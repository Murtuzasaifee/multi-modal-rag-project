# Azure Deployment Guide

This guide covers deploying the doc-parser stack on Azure using Terraform.

## AWS → Azure Service Mapping

| AWS | Azure | Notes |
|---|---|---|
| ECR | Azure Container Registry (ACR) | Image registry |
| ECS Fargate (multi-container task) | Azure Container Apps (multi-container sidecar) | All three containers share `localhost` — no URL changes needed |
| Application Load Balancer | Container Apps built-in HTTPS ingress | TLS terminated at ingress edge |
| EFS | Azure File Shares (SMB) | Persistent volumes for qdrant and ollama |
| Secrets Manager | Azure Key Vault | API key storage |
| CloudWatch Logs | Log Analytics Workspace | Centralised logging |
| IAM Roles + Users | Managed Identity + Service Principal | Identity for containers and CI/CD |
| S3 (TF state) | Azure Blob Storage (TF state) | Remote backend |

## Architecture

```
Internet
   │  HTTPS
   ▼
Container Apps Environment (VNet-integrated)
   │
   └─ Container App: doc-parser-app
        ├─ container: app        (port 8000, external ingress)
        ├─ container: qdrant     (localhost:6333, sidecar)
        └─ container: ollama     (localhost:11434, sidecar)
              │                        │
         Azure File Share         Azure File Share
         qdrant-data              ollama-models
```

The three containers share one network namespace (identical to the ECS task approach), so `QDRANT_URL=http://localhost:6333` and `OLLAMA_BASE_URL=http://localhost:11434` require **no changes**.

## Prerequisites

- Azure CLI: `az --version` ≥ 2.55
- Terraform: `terraform --version` ≥ 1.5
- GitHub CLI: `gh --version` (for secret setup)

## 1. Provision Terraform State Backend

```bash
cd infra
bash setup-backend-azure.sh
```

Note the `terraform init` command printed at the end; you'll need it in the next step.

## 2. Configure Variables

```bash
cd infra/terraform-azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum verify location and environment.
```

## 3. Initialise Terraform

```bash
terraform init \
  -backend-config="resource_group_name=doc-parser-tfstate-rg" \
  -backend-config="storage_account_name=<your-sa-name>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=doc-parser.tfstate"
```

## 4. Plan and Apply

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform will create:
- Resource group
- VNet + delegated subnet + NSG
- Azure Container Registry
- Storage Account + File Shares (qdrant-data, ollama-models)
- Key Vault + placeholder secret
- Log Analytics Workspace
- User-Assigned Managed Identity
- Container Apps Environment + Container App

## 5. Set the OpenAI API Key

```bash
KV_NAME=$(terraform output -raw key_vault_name)
az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name openai-api-key \
  --value "sk-..."
```

The Container App reads this value at runtime via the managed identity — no restart required once the secret is updated.

## 6. Configure GitHub Secrets for CI/CD

```bash
cd infra
bash setup-github-secrets-azure.sh
```

This script:
1. Creates an Azure service principal with `Contributor` on the resource group and `AcrPush` on ACR.
2. Sets the following GitHub Actions secrets:
   - `AZURE_CREDENTIALS` — JSON blob for `azure/login@v2`
   - `ACR_LOGIN_SERVER` — e.g. `docparserdevacr.azurecr.io`
   - `ACR_NAME` — e.g. `docparserdevacr`
   - `AZURE_RESOURCE_GROUP` — resource group name
   - `CONTAINER_APP_NAME` — e.g. `doc-parser-app`

## 7. Trigger the CD Pipeline

Push a commit to the `terraform` branch:

```bash
git push origin HEAD:terraform
```

The CD pipeline will:
1. Build and push the app image to ACR.
2. Update the `app` container in the Container App (qdrant and ollama keep running — zero restart).
3. Wait up to 15 minutes for the new revision to reach `Running` state.
4. Run a smoke test against `https://<fqdn>/health`.

## 8. Bootstrap Ollama (ollama backend only)

If you set `parser_backend = "ollama"`, pull the model into the ollama sidecar:

```bash
cd infra
bash bootstrap-ollama-azure.sh glm-ocr:latest
# Inside the shell: ollama pull glm-ocr:latest && exit
```

## 9. Verify

```bash
APP_URL=$(terraform -chdir=infra/terraform-azure output -raw container_app_url)
curl "$APP_URL/health"
```

## Useful Commands

```bash
# View live logs (all containers in the app)
az containerapp logs show \
  --name doc-parser-app \
  --resource-group doc-parser-dev-rg \
  --follow

# Exec into a running container for debugging
az containerapp exec \
  --name doc-parser-app \
  --resource-group doc-parser-dev-rg \
  --container app \
  --command /bin/sh

# Force a new revision (equivalent to ECS force-new-deployment)
az containerapp update \
  --name doc-parser-app \
  --resource-group doc-parser-dev-rg \
  --container-name app \
  --image <acr-login-server>/doc-parser/app:latest
```

## Notes

- **Resource limits**: The Consumption plan allows max 4 vCPU / 8 Gi per Container App. The default `terraform.tfvars.example` allocates 3.5 vCPU / 7 Gi across the three containers, leaving headroom.
- **Cold starts**: Set `app_min_replicas = 0` to scale to zero when idle (saves cost; adds ~30 s cold-start latency on first request).
- **Persistent storage**: Azure File Shares (SMB) replace EFS. Performance is similar for the access patterns used by qdrant and ollama model storage.
- **TLS**: Azure Container Apps provisions and renews TLS certificates automatically — no ACM certificate management needed.
- **NSG**: The default NSG allows inbound 80/443 from Internet. For production, restrict to your IP ranges or place an Azure Front Door / Application Gateway in front.
