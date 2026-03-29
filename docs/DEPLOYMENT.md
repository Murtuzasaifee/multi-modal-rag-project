# Deployment Runbook

This document covers local Docker Compose development, one-time AWS infrastructure setup, and the CI/CD pipeline.

---

## Architecture

```
GitHub Push (main)
       │
       ▼
GitHub Actions CD
  ├── docker build (app)        → ECR: doc-parser/app:<sha>
  └── docker build (visualizer) → ECR: doc-parser/visualizer:<sha>
       │
       ▼
ECS Fargate (force-new-deployment)
  ├── doc-parser-app          (FastAPI + Qdrant + Ollama sidecar)
  └── doc-parser-visualizer   (Streamlit)
       │
       ▼
Application Load Balancer
  ├── /          → visualizer (port 8501)
  └── /api/*     → app        (port 8000)
```

**Storage:**
- EFS volume mounted at `/qdrant/storage` (Qdrant vector data — persistent across deployments)
- EFS volume mounted at `/root/.ollama` (Ollama model weights — download once)

**Secrets:** All API keys stored in AWS Secrets Manager and injected as environment variables at task startup.

---

## Prerequisites

```bash
# AWS CLI v2
aws --version   # must be 2.x

# Docker
docker --version

# jq (for JSON processing in setup scripts)
brew install jq   # macOS
# or: apt-get install jq

# Verify AWS credentials
aws sts get-caller-identity
```

Set these shell variables before running any AWS CLI commands below:

```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export CLUSTER_NAME=doc-parser-cluster
export VPC_ID=<your-vpc-id>
export SUBNET_IDS=<subnet-id-1>,<subnet-id-2>   # comma-separated, private subnets
export ALB_SECURITY_GROUP=<your-alb-sg-id>
export ECS_SECURITY_GROUP=<your-ecs-sg-id>
```

---

## Local Docker Compose Quickstart

```bash
# 1. Copy and fill in the env file
cp .env.example .env
# Edit .env — set Z_AI_API_KEY, OPENAI_API_KEY, etc.

# 2. Start all services (Qdrant + app + visualizer)
docker compose up --build

# 3. Verify
curl http://localhost:8000/health      # FastAPI
open http://localhost:8501             # Streamlit visualizer
open http://localhost:6333/dashboard   # Qdrant dashboard

# 4. Stop
docker compose down

# 5. Stop and delete volumes (full reset)
docker compose down -v
```

---

## One-Time AWS Infrastructure Setup

Run these commands **once** when provisioning a new environment. They are idempotent — running twice is safe.

### 1. ECR Repositories

```bash
aws ecr create-repository \
  --repository-name doc-parser/app \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true

aws ecr create-repository \
  --repository-name doc-parser/visualizer \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true
```

### 2. ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name $CLUSTER_NAME \
  --capacity-providers FARGATE FARGATE_SPOT \
  --region $AWS_REGION
```

### 3. EFS File System + Access Points

```bash
# Create file system
FS_ID=$(aws efs create-file-system \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --region $AWS_REGION \
  --query 'FileSystemId' --output text)
echo "EFS File System: $FS_ID"

# Wait for available state
aws efs describe-file-systems \
  --file-system-id $FS_ID \
  --query 'FileSystems[0].LifeCycleState'

# Create mount target in each subnet (repeat per subnet)
aws efs create-mount-target \
  --file-system-id $FS_ID \
  --subnet-id <subnet-id-1> \
  --security-groups $ECS_SECURITY_GROUP

# Access point for Qdrant data
QDRANT_AP=$(aws efs create-access-point \
  --file-system-id $FS_ID \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory "Path=/qdrant,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
  --query 'AccessPointId' --output text)
echo "Qdrant access point: $QDRANT_AP"

# Access point for Ollama models
OLLAMA_AP=$(aws efs create-access-point \
  --file-system-id $FS_ID \
  --posix-user Uid=0,Gid=0 \
  --root-directory "Path=/ollama,CreationInfo={OwnerUid=0,OwnerGid=0,Permissions=755}" \
  --query 'AccessPointId' --output text)
echo "Ollama access point: $OLLAMA_AP"
```

### 4. Secrets Manager

Store each secret individually so tasks can fetch only what they need:

```bash
aws secretsmanager create-secret \
  --name doc-parser/z-ai-api-key \
  --secret-string '{"Z_AI_API_KEY":"<your-key>"}' \
  --region $AWS_REGION

aws secretsmanager create-secret \
  --name doc-parser/openai-api-key \
  --secret-string '{"OPENAI_API_KEY":"<your-key>"}' \
  --region $AWS_REGION

# Update an existing secret
aws secretsmanager put-secret-value \
  --secret-id doc-parser/openai-api-key \
  --secret-string '{"OPENAI_API_KEY":"<new-key>"}'
```

### 5. IAM — Users, Roles, and Permissions

There are **three distinct IAM principals** in this project. Create all three before proceeding.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Principal                │  Type       │  Used by                  │
├───────────────────────────┼─────────────┼───────────────────────────┤
│  doc-parser-cicd          │  IAM User   │  GitHub Actions (CD bot)  │
│  doc-parser-admin         │  IAM User   │  You (manual AWS CLI ops) │
│  doc-parser-ecs-task-exec │  IAM Role   │  Fargate tasks at runtime │
└─────────────────────────────────────────────────────────────────────┘
```

---

#### 5a. CI/CD Bot User (`doc-parser-cicd`)

This is the machine user whose credentials go into GitHub Secrets. It can **push images to ECR** and **trigger ECS deployments** — nothing else.

```bash
# Create the user
aws iam create-user --user-name doc-parser-cicd

# Create an access key (save the output — you only see the secret once)
aws iam create-access-key --user-name doc-parser-cicd
# → copy AccessKeyId and SecretAccessKey into scripts/set_github_secrets.sh

# Create the policy document
cat > /tmp/cicd-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Sid": "ECRPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": [
        "arn:aws:ecr:*:*:repository/doc-parser/app",
        "arn:aws:ecr:*:*:repository/doc-parser/visualizer"
      ]
    },
    {
      "Sid": "ECSDeployServices",
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSWaitForStable",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeTaskDefinition",
        "ecs:ListTasks",
        "ecs:DescribeTasks"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach as an inline policy
aws iam put-user-policy \
  --user-name doc-parser-cicd \
  --policy-name doc-parser-cicd-policy \
  --policy-document file:///tmp/cicd-policy.json
```

> **Why restrict ECR to specific repository ARNs?**
> The `GetAuthorizationToken` call must be `Resource: *` (AWS requirement), but the actual push actions are scoped to only the two repositories this project uses. If the key is ever leaked, it cannot push to any other ECR repo in your account.

---

#### 5b. Admin / Developer User (`doc-parser-admin`)

This is your personal IAM user for running the one-time setup commands in this runbook. It has broader permissions than the CI/CD bot, scoped to only `doc-parser*` resources.

```bash
# Create the user
aws iam create-user --user-name doc-parser-admin

# Create access key for local AWS CLI use
aws iam create-access-key --user-name doc-parser-admin
# → add to your local ~/.aws/credentials or export as env vars

cat > /tmp/admin-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRFullAccess",
      "Effect": "Allow",
      "Action": ["ecr:*"],
      "Resource": [
        "arn:aws:ecr:*:*:repository/doc-parser/*"
      ]
    },
    {
      "Sid": "ECRAuth",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Sid": "ECSFullAccess",
      "Effect": "Allow",
      "Action": ["ecs:*"],
      "Resource": "*"
    },
    {
      "Sid": "EFSFullAccess",
      "Effect": "Allow",
      "Action": ["elasticfilesystem:*"],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerDocParser",
      "Effect": "Allow",
      "Action": ["secretsmanager:*"],
      "Resource": "arn:aws:secretsmanager:*:*:secret:doc-parser/*"
    },
    {
      "Sid": "IAMDocParserRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:AttachRolePolicy",
        "iam:PutRolePolicy",
        "iam:PassRole",
        "iam:GetRole",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy"
      ],
      "Resource": "arn:aws:iam::*:role/doc-parser-*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DescribeLogGroups",
        "logs:DeleteLogGroup",
        "logs:TagLogGroup"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/ecs/doc-parser*"
    },
    {
      "Sid": "ALBSetup",
      "Effect": "Allow",
      "Action": ["elasticloadbalancing:*"],
      "Resource": "*"
    },
    {
      "Sid": "ECSExec",
      "Effect": "Allow",
      "Action": ["ssmmessages:*"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name doc-parser-admin \
  --policy-name doc-parser-admin-policy \
  --policy-document file:///tmp/admin-policy.json
```

> **Why a separate admin user instead of using root?**
> AWS root credentials should never be used for day-to-day operations. The admin user is scoped to `doc-parser*` resources — it cannot accidentally delete unrelated infrastructure in your account.

---

#### 5c. ECS Task Execution Role (`doc-parser-ecs-task-execution`)

This is an **IAM Role** (not a user) assumed automatically by Fargate when it starts a task. It allows the task to: pull images from ECR, write logs to CloudWatch, read secrets from Secrets Manager, and mount EFS volumes.

```bash
# Create the role with ECS trust policy
aws iam create-role \
  --role-name doc-parser-ecs-task-execution \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach AWS-managed policy (ECR pull + CloudWatch logs)
aws iam attach-role-policy \
  --role-name doc-parser-ecs-task-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Inline policy: Secrets Manager read for doc-parser/* secrets
aws iam put-role-policy \
  --role-name doc-parser-ecs-task-execution \
  --policy-name secrets-manager-read \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"ReadDocParserSecrets\",
      \"Effect\": \"Allow\",
      \"Action\": [\"secretsmanager:GetSecretValue\"],
      \"Resource\": \"arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:doc-parser/*\"
    }]
  }"

# Inline policy: EFS mount for Qdrant + Ollama volumes
aws iam put-role-policy \
  --role-name doc-parser-ecs-task-execution \
  --policy-name efs-mount \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"EFSMount\",
      \"Effect\": \"Allow\",
      \"Action\": [
        \"elasticfilesystem:ClientMount\",
        \"elasticfilesystem:ClientWrite\",
        \"elasticfilesystem:DescribeMountTargets\"
      ],
      \"Resource\": \"arn:aws:elasticfilesystem:${AWS_REGION}:${AWS_ACCOUNT_ID}:file-system/${FS_ID}\"
    }]
  }"

# Inline policy: ECS Exec (needed for ollama model bootstrap — optional)
aws iam put-role-policy \
  --role-name doc-parser-ecs-task-execution \
  --policy-name ecs-exec \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "ECSExec",
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    }]
  }'

export EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/doc-parser-ecs-task-execution"
```

---

#### 5d. Permission Summary

| Permission | CI/CD Bot | Admin User | Task Exec Role |
|---|---|---|---|
| ECR push images | ✅ (scoped repos) | ✅ | — |
| ECR pull images | ✅ | ✅ | ✅ (via managed policy) |
| ECS update/deploy services | ✅ | ✅ | — |
| ECS describe/list tasks | ✅ | ✅ | — |
| EFS mount volumes | — | ✅ (setup only) | ✅ (at runtime) |
| Secrets Manager read | — | ✅ (setup only) | ✅ (at runtime) |
| Secrets Manager write/create | — | ✅ | — |
| IAM role creation | — | ✅ (doc-parser-* only) | — |
| CloudWatch log write | — | — | ✅ (via managed policy) |
| CloudWatch log group create | — | ✅ | — |
| ALB create/manage | — | ✅ | — |
| ECS Exec (shell into task) | — | — | ✅ (optional) |

### 6. CloudWatch Log Groups

```bash
aws logs create-log-group --log-group-name /ecs/doc-parser-app --region $AWS_REGION
aws logs create-log-group --log-group-name /ecs/doc-parser-visualizer --region $AWS_REGION
```

---

## ECS Task Definitions

### App Task Definition

Save as `/tmp/app-task-def.json`, then register:

```json
{
  "family": "doc-parser-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "2048",
  "memory": "8192",
  "executionRoleArn": "<EXECUTION_ROLE_ARN>",
  "taskRoleArn": "<EXECUTION_ROLE_ARN>",
  "volumes": [
    {
      "name": "qdrant-data",
      "efsVolumeConfiguration": {
        "fileSystemId": "<FS_ID>",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "<QDRANT_AP>",
          "iam": "ENABLED"
        }
      }
    },
    {
      "name": "ollama-models",
      "efsVolumeConfiguration": {
        "fileSystemId": "<FS_ID>",
        "transitEncryption": "ENABLED",
        "authorizationConfig": {
          "accessPointId": "<OLLAMA_AP>",
          "iam": "ENABLED"
        }
      }
    }
  ],
  "containerDefinitions": [
    {
      "name": "app",
      "image": "<ECR_REGISTRY>/doc-parser/app:latest",
      "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
      "essential": true,
      "environment": [
        {"name": "EMBEDDING_PROVIDER", "value": "openai"},
        {"name": "RERANKER_BACKEND", "value": "openai"},
        {"name": "QDRANT_URL", "value": "http://localhost:6333"},
        {"name": "PARSER_BACKEND", "value": "cloud"}
      ],
      "secrets": [
        {
          "name": "Z_AI_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:<REGION>:<ACCOUNT>:secret:doc-parser/z-ai-api-key:Z_AI_API_KEY::"
        },
        {
          "name": "OPENAI_API_KEY",
          "valueFrom": "arn:aws:secretsmanager:<REGION>:<ACCOUNT>:secret:doc-parser/openai-api-key:OPENAI_API_KEY::"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/doc-parser-app",
          "awslogs-region": "<AWS_REGION>",
          "awslogs-stream-prefix": "app"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    },
    {
      "name": "qdrant",
      "image": "qdrant/qdrant:v1.13.3",
      "portMappings": [{"containerPort": 6333, "protocol": "tcp"}],
      "essential": true,
      "mountPoints": [
        {
          "sourceVolume": "qdrant-data",
          "containerPath": "/qdrant/storage",
          "readOnly": false
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/doc-parser-app",
          "awslogs-region": "<AWS_REGION>",
          "awslogs-stream-prefix": "qdrant"
        }
      }
    },
    {
      "name": "ollama",
      "image": "ollama/ollama:latest",
      "portMappings": [{"containerPort": 11434, "protocol": "tcp"}],
      "essential": false,
      "mountPoints": [
        {
          "sourceVolume": "ollama-models",
          "containerPath": "/root/.ollama",
          "readOnly": false
        }
      ],
      "environment": [
        {"name": "OLLAMA_HOST", "value": "0.0.0.0"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/doc-parser-app",
          "awslogs-region": "<AWS_REGION>",
          "awslogs-stream-prefix": "ollama"
        }
      }
    }
  ]
}
```

```bash
# Fill in placeholders, then register
sed -i \
  -e "s|<EXECUTION_ROLE_ARN>|${EXECUTION_ROLE_ARN}|g" \
  -e "s|<FS_ID>|${FS_ID}|g" \
  -e "s|<QDRANT_AP>|${QDRANT_AP}|g" \
  -e "s|<OLLAMA_AP>|${OLLAMA_AP}|g" \
  -e "s|<ECR_REGISTRY>|${ECR_REGISTRY}|g" \
  -e "s|<REGION>|${AWS_REGION}|g" \
  -e "s|<ACCOUNT>|${AWS_ACCOUNT_ID}|g" \
  -e "s|<AWS_REGION>|${AWS_REGION}|g" \
  /tmp/app-task-def.json

aws ecs register-task-definition \
  --cli-input-json file:///tmp/app-task-def.json \
  --region $AWS_REGION
```

### Visualizer Task Definition

Save as `/tmp/viz-task-def.json`:

```json
{
  "family": "doc-parser-visualizer",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "<EXECUTION_ROLE_ARN>",
  "containerDefinitions": [
    {
      "name": "visualizer",
      "image": "<ECR_REGISTRY>/doc-parser/visualizer:latest",
      "portMappings": [{"containerPort": 8501, "protocol": "tcp"}],
      "essential": true,
      "environment": [
        {"name": "API_BASE_URL", "value": "http://doc-parser-app.local:8000"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/doc-parser-visualizer",
          "awslogs-region": "<AWS_REGION>",
          "awslogs-stream-prefix": "visualizer"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8501/_stcore/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 30
      }
    }
  ]
}
```

```bash
sed -i \
  -e "s|<EXECUTION_ROLE_ARN>|${EXECUTION_ROLE_ARN}|g" \
  -e "s|<ECR_REGISTRY>|${ECR_REGISTRY}|g" \
  -e "s|<AWS_REGION>|${AWS_REGION}|g" \
  /tmp/viz-task-def.json

aws ecs register-task-definition \
  --cli-input-json file:///tmp/viz-task-def.json \
  --region $AWS_REGION
```

---

## ECS Services

### Create Application Load Balancer

```bash
# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name doc-parser-alb \
  --subnets $(echo $SUBNET_IDS | tr ',' ' ') \
  --security-groups $ALB_SECURITY_GROUP \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Target groups
APP_TG_ARN=$(aws elbv2 create-target-group \
  --name doc-parser-app-tg \
  --protocol HTTP \
  --port 8000 \
  --target-type ip \
  --vpc-id $VPC_ID \
  --health-check-path /health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

VIZ_TG_ARN=$(aws elbv2 create-target-group \
  --name doc-parser-viz-tg \
  --protocol HTTP \
  --port 8501 \
  --target-type ip \
  --vpc-id $VPC_ID \
  --health-check-path /_stcore/health \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Listener: / → visualizer, /api/* → app
LISTENER_ARN=$(aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$VIZ_TG_ARN \
  --query 'Listeners[0].ListenerArn' --output text)

aws elbv2 create-rule \
  --listener-arn $LISTENER_ARN \
  --priority 10 \
  --conditions Field=path-pattern,Values='/api/*' \
  --actions Type=forward,TargetGroupArn=$APP_TG_ARN
```

### Create ECS Services

```bash
# App service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name doc-parser-app \
  --task-definition doc-parser-app \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$(echo $SUBNET_IDS | tr ',' ',')],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$APP_TG_ARN,containerName=app,containerPort=8000" \
  --region $AWS_REGION

# Visualizer service
aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name doc-parser-visualizer \
  --task-definition doc-parser-visualizer \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$(echo $SUBNET_IDS | tr ',' ',')],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=$VIZ_TG_ARN,containerName=visualizer,containerPort=8501" \
  --region $AWS_REGION
```

---

## Ollama Model Bootstrap (One-Time)

After the app service is running, pull the required model into the EFS-backed Ollama container:

```bash
# Find a running task
TASK_ARN=$(aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name doc-parser-app \
  --query 'taskArns[0]' --output text)

# Exec into the Ollama container and pull the model
aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container ollama \
  --interactive \
  --command "ollama pull glm4v:9b"
```

The model is stored on EFS and persists across deployments — you only need to run this once.

Note: ECS Exec requires the task role to have `ssmmessages:*` permissions. Add this to the task execution role if not already present:

```bash
aws iam put-role-policy \
  --role-name doc-parser-ecs-task-execution \
  --policy-name ecs-exec \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "*"
    }]
  }'
```

---

## GitHub Actions Secrets

Set these in your GitHub repository under **Settings → Secrets and variables → Actions**:

```bash
# Using GitHub CLI
gh secret set AWS_ACCESS_KEY_ID      --body "<iam-access-key>"
gh secret set AWS_SECRET_ACCESS_KEY  --body "<iam-secret-key>"
gh secret set AWS_REGION             --body "us-east-1"
gh secret set ECR_REGISTRY           --body "${ECR_REGISTRY}"
gh secret set ECS_CLUSTER            --body "doc-parser-cluster"
gh secret set ECS_SERVICE_APP        --body "doc-parser-app"
gh secret set ECS_SERVICE_VISUALIZER --body "doc-parser-visualizer"
```

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user key with ECR push + ECS deploy permissions |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret |
| `AWS_REGION` | AWS region (e.g. `us-east-1`) |
| `ECR_REGISTRY` | `<account>.dkr.ecr.<region>.amazonaws.com` |
| `ECS_CLUSTER` | ECS cluster name |
| `ECS_SERVICE_APP` | ECS service name for the FastAPI app |
| `ECS_SERVICE_VISUALIZER` | ECS service name for the Streamlit visualizer |

> The `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` here are from the **`doc-parser-cicd`** user created in Section 5a — not your personal admin credentials.

---

## CI/CD Flow

```
Push to any branch / PR opened
        │
        ▼
CI workflow (ci.yml)
  ├── lint (parallel)
  │     ├── ruff check src/ tests/ scripts/
  │     └── mypy src/
  └── unit-tests (parallel)
        └── pytest tests/unit/ -v
              (no API keys, no Docker, ~30s)

Push to main (after PR merge)
        │
        ▼
CD workflow (cd.yml)
  ├── build-and-push
  │     ├── docker build + push app    → ECR :<sha> + :latest
  │     └── docker build + push viz    → ECR :<sha> + :latest
  └── deploy (needs: build-and-push)
        ├── aws ecs update-service --force-new-deployment (app)
        ├── aws ecs update-service --force-new-deployment (visualizer)
        └── aws ecs wait services-stable
```

**Branch protection recommendation:** Require CI checks to pass before merging to `main`. This ensures CD only runs on green code.

---

## Health Checks and Monitoring

```bash
# Check service status
aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services doc-parser-app doc-parser-visualizer \
  --query 'services[*].{name:serviceName,running:runningCount,desired:desiredCount,status:status}' \
  --output table

# Tail logs (last 100 lines)
aws logs tail /ecs/doc-parser-app --follow
aws logs tail /ecs/doc-parser-visualizer --follow

# Health check endpoints
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names doc-parser-alb \
  --query 'LoadBalancers[0].DNSName' --output text)

curl http://${ALB_DNS}/health           # FastAPI
curl http://${ALB_DNS}/_stcore/health   # Streamlit
```

---

## Rollback Procedure

Every deployment registers a new ECS task definition revision. To roll back:

```bash
# List recent revisions
aws ecs list-task-definitions \
  --family-prefix doc-parser-app \
  --sort DESC \
  --query 'taskDefinitionArns[:5]' \
  --output table

# Roll back to a specific revision (e.g., revision 7)
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service doc-parser-app \
  --task-definition doc-parser-app:7

aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service doc-parser-visualizer \
  --task-definition doc-parser-visualizer:7

# Wait for stable
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services doc-parser-app doc-parser-visualizer
```

---

## Pre-Push Verification

Run locally before pushing to ensure CI will pass:

```bash
uv pip install -e ".[dev]"
ruff check src/ tests/ scripts/
mypy src/
pytest tests/unit/ -v
```
