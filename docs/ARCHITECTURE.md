# AWS Deployment Architecture

This document explains how every AWS service fits together when you deploy the MultiModal RAG pipeline. Read top to bottom — each diagram zooms into a different layer.

---

## 1. The Big Picture — End-to-End Flow

From a developer pushing code all the way to a user hitting the live URL.

```mermaid
flowchart TD
    DEV(["👩‍💻 Developer\npushes to main"])

    subgraph GHA["GitHub Actions (CI/CD)"]
        CI["CI workflow\nruff · mypy · pytest"]
        CD["CD workflow\ndocker build + push\necs force-deploy"]
    end

    subgraph ECR["Amazon ECR\n(Container Registry)"]
        IMG_APP["🐳 doc-parser/app\n:sha + :latest"]
        IMG_VIZ["🐳 doc-parser/visualizer\n:sha + :latest"]
    end

    subgraph AWS["AWS Cloud (VPC)"]
        subgraph ECS["Amazon ECS — Fargate"]
            TASK_APP["Task: doc-parser-app\n─────────────────\napp container  :8000\nqdrant sidecar :6333\nollama sidecar :11434"]
            TASK_VIZ["Task: doc-parser-visualizer\n────────────────────────\nstreamlit container :8501"]
        end

        ALB["Application Load Balancer\n────────────────────\n/ → visualizer :8501\n/api/* → app :8000"]

        subgraph STORAGE["Persistent Storage"]
            EFS["Amazon EFS\n(Network File System)\n─────────────────\n/qdrant/storage\n/root/.ollama"]
        end

        subgraph SECRETS["AWS Secrets Manager"]
            SM["Encrypted secrets\n─────────────────\nZ_AI_API_KEY\nOPENAI_API_KEY\n...injected at task start"]
        end

        CW["Amazon CloudWatch\nLogs\n─────────────────\n/ecs/doc-parser-app\n/ecs/doc-parser-visualizer"]
    end

    USER(["🌐 User\nbrowser / curl"])

    DEV -->|"git push main"| GHA
    CI -->|"must pass before CD runs"| CD
    CD -->|"docker push"| IMG_APP
    CD -->|"docker push"| IMG_VIZ
    IMG_APP -->|"pulled at task start"| TASK_APP
    IMG_VIZ -->|"pulled at task start"| TASK_VIZ
    EFS -->|"mounted volume"| TASK_APP
    SM  -->|"env var injection"| TASK_APP
    SM  -->|"env var injection"| TASK_VIZ
    TASK_APP -->|"logs"| CW
    TASK_VIZ -->|"logs"| CW
    TASK_APP --- ALB
    TASK_VIZ --- ALB
    USER -->|"HTTP request"| ALB
```

---

## 2. CI/CD Pipeline — GitHub Actions

What happens inside GitHub Actions on every push and on merge to `main`.

```mermaid
flowchart LR
    PUSH(["git push\n(any branch)"])
    MERGE(["git push main\n(PR merged)"])

    subgraph CI["CI workflow — runs on every push + PR"]
        direction TB
        LINT["lint job\n──────────\nruff check\nmypy src/"]
        UNIT["unit-tests job\n──────────────\npytest tests/unit/\n~30 seconds\nno API keys needed"]
    end

    subgraph CD["CD workflow — runs only on main"]
        direction TB
        BUILD["build-and-push job\n──────────────────\ndocker build app\ndocker build visualizer\ndocker push → ECR\ntag: git sha + latest"]
        DEPLOY["deploy job\n──────────\necs update-service\n--force-new-deployment\necs wait services-stable"]
    end

    PUSH --> CI
    MERGE --> CI
    MERGE --> CD
    CI -->|"branch protection\nmust pass"| CD
    BUILD -->|"needs: build-and-push"| DEPLOY
```

> **Why two separate jobs in CD?**
> `build-and-push` and `deploy` are separated so that if the image push fails, ECS is never asked to deploy a broken image. The `needs:` dependency enforces this order.

---

## 3. Amazon ECR — Container Registry

ECR stores your Docker images. Think of it as Docker Hub but private and inside your AWS account.

```mermaid
flowchart LR
    BUILD["GitHub Actions\ndocker build"]

    subgraph ECR["Amazon ECR"]
        REPO_APP["Repository\ndoc-parser/app\n─────────────\n:abc1234  ← new sha\n:abc0000  ← prev sha\n:latest   ← alias"]
        REPO_VIZ["Repository\ndoc-parser/visualizer\n─────────────────────\n:abc1234\n:abc0000\n:latest"]
    end

    ECS["ECS Fargate\n(pulls image at\ntask start)"]
    ROLLBACK["Rollback:\npoint task def\nto older sha tag"]

    BUILD -->|"docker push :sha + :latest"| REPO_APP
    BUILD -->|"docker push :sha + :latest"| REPO_VIZ
    REPO_APP -->|"image pull"| ECS
    REPO_VIZ -->|"image pull"| ECS
    REPO_APP -.->|"if deploy fails"| ROLLBACK
```

> **Why tag with both `:sha` and `:latest`?**
> `:sha` gives you a permanent, immutable tag for rollbacks. `:latest` is what ECS uses by default when it force-deploys — it always picks up the newest image.

---

## 4. Amazon ECS on Fargate — Running the Containers

ECS is the scheduler. Fargate is the serverless compute layer — you never touch a VM.

```mermaid
flowchart TD
    subgraph CLUSTER["ECS Cluster: doc-parser-cluster"]

        subgraph SERVICE_APP["ECS Service: doc-parser-app\n(desired count: 1)"]
            subgraph TASK_APP["Fargate Task (single network namespace)"]
                C_APP["Container: app\nFastAPI :8000\n──────────────\nParses PDFs\nEmbeds chunks\nServes /search /ingest"]
                C_QDRANT["Container: qdrant\nQdrant :6333\n──────────────\nVector database\nHybrid dense+sparse\nHNSW index"]
                C_OLLAMA["Container: ollama\nOllama :11434\n──────────────\nLocal LLM inference\nGLM-OCR model\n(optional sidecar)"]
            end
        end

        subgraph SERVICE_VIZ["ECS Service: doc-parser-visualizer\n(desired count: 1)"]
            subgraph TASK_VIZ["Fargate Task"]
                C_VIZ["Container: visualizer\nStreamlit :8501\n──────────────\nBbox overlays\nElement breakdown\nMarkdown preview"]
            end
        end
    end

    C_APP <-->|"localhost:6333\n(same task = same network)"| C_QDRANT
    C_APP <-->|"localhost:11434"| C_OLLAMA
    C_VIZ -->|"HTTP /api/*\nvia ALB"| C_APP
```

> **Key concept — sidecar pattern:**
> All containers inside a single Fargate task share the same `localhost`. That's why the `app` container can reach Qdrant at `http://localhost:6333` without any service discovery — they are co-located in the same task.

---

## 5. Amazon EFS — Persistent Storage

EFS is a network file system. It solves two problems: Qdrant data surviving a redeployment, and Ollama model weights not being re-downloaded every time.

```mermaid
flowchart LR
    subgraph EFS["Amazon EFS File System"]
        AP_QDRANT["Access Point\n/qdrant\n──────────\nOwner: uid 1000\nPermissions: 755"]
        AP_OLLAMA["Access Point\n/ollama\n──────────\nOwner: uid 0 (root)\nPermissions: 755"]
    end

    subgraph TASK["Fargate Task: doc-parser-app"]
        QDRANT["/qdrant/storage\nQdrant vector index\n(HNSW + BM25 data)"]
        OLLAMA["/root/.ollama\nGLM-OCR model weights\n~600 MB, pulled once"]
    end

    DEPLOY1["Deploy v1"]
    DEPLOY2["Deploy v2\n(new image)"]
    DEPLOY3["Deploy v3"]

    AP_QDRANT -->|"mounted at /qdrant/storage"| QDRANT
    AP_OLLAMA -->|"mounted at /root/.ollama"| OLLAMA

    DEPLOY1 -->|"writes vectors"| AP_QDRANT
    DEPLOY2 -->|"same data, no data loss"| AP_QDRANT
    DEPLOY3 -->|"same data, no data loss"| AP_QDRANT
```

> **Why Access Points and not just the raw file system?**
> Access Points enforce a specific root directory and POSIX owner per mount, so the `qdrant` container (uid 1000) and `ollama` container (root) each get their own isolated directory with correct permissions — even though they share one EFS file system.

---

## 6. AWS Secrets Manager — Secret Injection

API keys are never baked into Docker images or passed as plain environment variables. They live in Secrets Manager and are injected at task startup by the ECS agent.

```mermaid
sequenceDiagram
    participant DEV as Developer
    participant SM as AWS Secrets Manager
    participant ROLE as IAM Task Execution Role
    participant ECS as ECS Agent (Fargate)
    participant APP as App Container

    DEV->>SM: aws secretsmanager create-secret<br/>(Z_AI_API_KEY, OPENAI_API_KEY, ...)
    note over SM: Encrypted at rest (AES-256)<br/>Access controlled by IAM

    ECS->>ROLE: assume task execution role
    ROLE-->>ECS: temporary credentials

    ECS->>SM: GetSecretValue (doc-parser/openai-api-key)
    SM-->>ECS: plaintext value

    ECS->>APP: start container with<br/>OPENAI_API_KEY=sk-... (env var)
    note over APP: Secret lives only in<br/>container memory<br/>never written to disk
```

> **Why not just use `.env` on the server?**
> Secrets Manager gives you: audit logs of every access, automatic rotation, fine-grained IAM control over which task role can read which secret, and zero secrets in your git history or Docker layers.

---

## 7. Application Load Balancer — Traffic Routing

One public DNS name, two backend services, path-based routing.

```mermaid
flowchart TD
    USER(["🌐 User"])

    subgraph ALB["Application Load Balancer\ndoc-parser-alb.us-east-1.elb.amazonaws.com"]
        LISTENER["Listener :80\n(or :443 with ACM cert)"]
        RULE1["Rule: path /api/*\npriority 10"]
        RULE2["Default rule\n(everything else)"]
        TG_APP["Target Group\ndoc-parser-app-tg\nhealth: GET /health"]
        TG_VIZ["Target Group\ndoc-parser-viz-tg\nhealth: GET /_stcore/health"]
    end

    subgraph PRIVATE["Private Subnets (no public IP)"]
        APP["app container\n:8000"]
        VIZ["visualizer container\n:8501"]
    end

    USER -->|"HTTP GET /"| LISTENER
    USER -->|"HTTP POST /api/search"| LISTENER
    LISTENER --> RULE1
    LISTENER --> RULE2
    RULE1 -->|"forward"| TG_APP
    RULE2 -->|"forward"| TG_VIZ
    TG_APP -->|"health-checked"| APP
    TG_VIZ -->|"health-checked"| VIZ
```

> **Why are ECS tasks in private subnets?**
> The ALB sits in public subnets and is the only entry point. ECS tasks have no public IP — they can't be reached directly from the internet. This is standard AWS security practice (defence in depth).

---

## 8. IAM — Who Is Allowed to Do What

IAM is the permission system. Two principals matter here: the CI/CD bot and the ECS task itself.

```mermaid
flowchart LR
    subgraph GHA["GitHub Actions"]
        BOT["CI/CD IAM User\n(AWS_ACCESS_KEY_ID\nin GitHub Secrets)"]
    end

    subgraph ECS_ROLE["IAM Role\ndoc-parser-ecs-task-execution"]
        TRUST["Trust policy:\necs-tasks.amazonaws.com\ncan assume this role"]
        POLICY_ECS["AWS managed policy:\nAmazonECSTaskExecutionRolePolicy\n(ECR pull, CloudWatch logs)"]
        POLICY_SM["Inline policy:\nsecretsmanager:GetSecretValue\nfor doc-parser/* secrets"]
        POLICY_EFS["Inline policy:\nelasticfilesystem:ClientMount\nelasticfilesystem:ClientWrite"]
        POLICY_EXEC["Inline policy (optional):\nssmmessages:*\n(for ecs execute-command)"]
    end

    BOT -->|"ecr:GetAuthorizationToken\necr:PutImage\necs:UpdateService\necs:DescribeServices"| ECR["ECR + ECS"]
    TRUST --> ECS_ROLE
    POLICY_ECS --> ECS_ROLE
    POLICY_SM --> ECS_ROLE
    POLICY_EFS --> ECS_ROLE
    POLICY_EXEC --> ECS_ROLE
    ECS_ROLE -->|"assumed at task start"| FARGATE["Fargate Task\n(pulls secrets + images\nmounts EFS)"]
```

> **Principle of least privilege:**
> The CI/CD bot can only push images and trigger deployments — it cannot read secrets or access EFS. The ECS task role can read secrets and mount EFS — but it cannot push new images. Each principal has exactly the permissions it needs and nothing more.

---

## 9. CloudWatch Logs — Observability

Every container streams logs to CloudWatch. No SSH, no log files on disk.

```mermaid
flowchart LR
    subgraph TASK["Fargate Task"]
        C1["app\nstdout/stderr"]
        C2["qdrant\nstdout/stderr"]
        C3["ollama\nstdout/stderr"]
        C4["visualizer\nstdout/stderr"]
    end

    subgraph CW["Amazon CloudWatch Logs"]
        LG_APP["Log Group\n/ecs/doc-parser-app\n─────────────────\nStreams:\napp/app/<task-id>\nqdrant/qdrant/<task-id>\nollama/ollama/<task-id>"]
        LG_VIZ["Log Group\n/ecs/doc-parser-visualizer\n──────────────────────────\nStreams:\nvisualizer/visualizer/<task-id>"]
    end

    TAIL["aws logs tail\n/ecs/doc-parser-app\n--follow"]

    C1 -->|"awslogs driver"| LG_APP
    C2 -->|"awslogs driver"| LG_APP
    C3 -->|"awslogs driver"| LG_APP
    C4 -->|"awslogs driver"| LG_VIZ
    LG_APP --> TAIL
    LG_VIZ --> TAIL
```

> **The `awslogs` driver** is configured in the task definition under `logConfiguration`. The ECS agent collects stdout/stderr from each container and ships it directly to CloudWatch — no log agent or sidecar needed.

---

## 10. Rollback — What Happens When a Deploy Goes Wrong

Every `register-task-definition` call creates a new numbered revision. ECS never deletes old revisions.

```mermaid
flowchart LR
    subgraph ECR_TAGS["ECR Tags (immutable)"]
        SHA1[":abc1111\n(v1 image)"]
        SHA2[":abc2222\n(v2 image — broken)"]
    end

    subgraph TASK_DEFS["ECS Task Definition Revisions"]
        TD1["doc-parser-app:5\nimage: :abc1111"]
        TD2["doc-parser-app:6\nimage: :abc2222"]
    end

    subgraph SERVICE["ECS Service"]
        ACTIVE["Currently running\ntask def :6\n(broken)"]
    end

    ROLLBACK["aws ecs update-service\n--task-definition\ndoc-parser-app:5"]

    SHA1 --> TD1
    SHA2 --> TD2
    TD2 --> ACTIVE
    ROLLBACK -->|"point service\nback to rev 5"| TD1
    TD1 -->|"ECS drains rev 6\nstarts rev 5"| SERVICE
```

> **Rollback takes ~60 seconds** — ECS drains connections from the old task, starts a new task with the previous revision, waits for its health check to pass, then deregisters the broken task.

---

## Summary — All Services at a Glance

| AWS Service | Role in this project | Student analogy |
|-------------|----------------------|-----------------|
| **ECR** | Stores Docker images | Like Docker Hub, but private in your AWS account |
| **ECS + Fargate** | Runs containers without managing servers | Like Heroku — you give it a Docker image, it runs it |
| **EFS** | Persistent shared file system for containers | Like a USB drive that survives container restarts |
| **ALB** | Routes public traffic to the right container | Like nginx reverse proxy, but managed by AWS |
| **Secrets Manager** | Stores and injects API keys securely | Like a password manager your containers can query |
| **IAM** | Controls who can do what | Like Linux file permissions, but for AWS resources |
| **CloudWatch Logs** | Collects and stores container logs | Like `tail -f` but persistent and searchable |
| **GitHub Actions** | Automates build, test, and deploy | Like a robot that runs your scripts on every git push |
