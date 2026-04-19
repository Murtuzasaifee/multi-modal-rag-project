# Terraform Deployment Guide

Deploy the Multi-Modal RAG pipeline to AWS using Terraform.

## Prerequisites

- AWS CLI v2 installed and configured
- Terraform >= 1.5.0 installed
- Docker installed
- OpenAI API key

## Deployment Steps

### 1. Setup S3 Backend

```bash
cd infra
./setup-backend.sh
```

### 2. Configure Variables

Create your variables file from the example template:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Open terraform.tfvars in your editor and update the values
```

### 3. Initialize Terraform

```bash
terraform init -backend-config="bucket=doc-parser-terraform-state-{YOUR_ACCOUNT_ID}"
```

Get your account ID: `aws sts get-caller-identity --query Account --output text`

### 4. Review and Apply

```bash
terraform plan
terraform apply
```

> **Note:** Right after `terraform apply`, the newly created ECS service will attempt to start the `app` container but will stay in a `PENDING`/`FAILED` loop. This is expected! The ECR repository was just created and is currently empty. The ECS service will successfully start once you commit your code and the GitHub Actions CI/CD pipeline builds and pushes the Docker image.

### 5. Set OpenAI Secret

```bash
aws secretsmanager put-secret-value \
  --secret-id doc-parser/openai-api-key \
  --secret-string '{"openai_api_key":"sk-..."}'
```

### 6. Set Up GitHub Secrets for CI/CD

If you are using GitHub Actions for deployment, run this script to inject the Terraform outputs to your repository's secrets. Make sure you have the `gh` CLI installed.

```bash
cd ..
./setup-github-secrets.sh
```

### 7. Bootstrap Ollama Model (one-time)

```bash
cd ..
./bootstrap-ollama.sh glm-ocr:latest
```

## Verify Deployment

```bash
# Get ALB URL
terraform output alb_dns_name

# Health check
curl http://$(terraform output -raw alb_dns_name)/health
```

## Teardown

```bash
cd infra/terraform
terraform destroy
```

## Cost Saving

Pause the ECS service when not in use:

```bash
aws ecs update-service \
  --cluster doc-parser-cluster \
  --service doc-parser-app \
  --desired-count 0
```
