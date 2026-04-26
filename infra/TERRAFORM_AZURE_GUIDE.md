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
- **Required Azure provider registration** (run once per subscription):

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Insights
# Wait for registrationState to return "Registered"
az provider show --namespace Microsoft.App --query registrationState -o tsv
```

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

> **Note**: The Container App creation will fail with `MANIFEST_UNKNOWN: manifest tagged by "latest" is not found`. This is **expected** — the Docker image doesn't exist in ACR yet. The app will transition to `Running` after step 7 when CI/CD pushes the image.

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

## 10. Destroy Infrastructure (Cleanup)

To remove all Azure resources created by Terraform:

```bash
cd infra/terraform-azure
terraform destroy
```

Follow prompts and type `yes` to confirm. This will destroy:
- Container App + Environment
- Key Vault (secrets are also deleted)
- Storage Account (File Shares are deleted with the account)
- Container Registry
- Log Analytics Workspace
- Managed Identity
- VNet + Subnet + NSG
- Resource Group (if empty after resource deletion)

> **Important**: The Terraform state backend (storage account created in step 1) is **not** destroyed. To remove it:

```bash
cd infra
az storage account delete --name <your-sa-name> --resource-group doc-parser-tfstate-rg
az group delete --name doc-parser-tfstate-rg --yes
```

## Common Issues & Expected Errors

<details>
<summary><strong>MissingSubscriptionRegistration: The subscription is not registered to use namespace 'Microsoft.App'</strong></summary>

This occurs if the Azure Container Apps provider isn't registered for your subscription.

```bash
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.Insights
# Wait until registrationState returns "Registered" (may take 2-5 minutes)
az provider show --namespace Microsoft.App --query registrationState -o tsv
```
</details>

<details>
<summary><strong>MANIFEST_UNKNOWN: manifest tagged by "latest" is not found</strong></summary>

**This is expected and not an error.** Terraform successfully creates the Container App infrastructure, but the Docker image hasn't been pushed to ACR yet (this happens in step 7 when you push to the `terraform` branch and trigger the CI/CD pipeline).

The Container App will show a `Failed` state initially. Once the CI/CD pipeline pushes the image to ACR and triggers a revision update, the app will transition to `Running`.

To verify after CI/CD completes:
```bash
az containerapp revision list \
  --name doc-parser-app \
  --resource-group doc-parser-dev-rg \
  --query "[].properties.runningState"
```
</details>

<details>
<summary><strong>Key Vault: Forbidden (403) during Terraform apply</strong></summary>

If Terraform fails creating a Key Vault secret with 403, but the access policy should exist, this is often a state file consistency issue. The access policy may have been created correctly, but Terraform state doesn't track it.

```bash
# Remove the failed secret resource from state and retry
terraform state rm 'module.container_apps.azurerm_key_vault_secret.openai_api_key'
terraform apply tfplan
```

Alternatively, verify the policy exists manually:
```bash
KV_NAME=$(terraform output -raw key_vault_name)
USER_OBJECT_ID=$(az ad signed-in-user show --query objectId -o tsv)
az keyvault show --name "$KV_NAME" --query "properties.accessPolicies[?objectId=='$USER_OBJECT_ID']"
```
</details>

<details>
<summary><strong>Key Vault name exceeds 24 characters</strong></summary>

Azure Key Vault names are globally unique and must be 3-24 alphanumeric characters plus hyphens. The Terraform code uses a shortened format to stay within limits:

```
${var.project_name}-${substr(var.environment, 0, 2)}kv${random_id.suffix.hex}
# Example: doc-parserdevkv90461d61 (22 chars)
```

If you encounter this error, you may have an older state file. Either:
- Destroy and re-apply: `terraform destroy && terraform apply tfplan`
- Or manually import the corrected resources if the Key Vault exists with a valid name.
</details>

<details>
<summary><strong>parsing the Workspace ID: the number of segments didn't match</strong></summary>

This error occurs if the Terraform code incorrectly passes the Log Analytics `workspace_id` (a UUID) instead of the full resource `id`. The correct Terraform code uses `module.log_analytics.id`.

If you encounter this with an older state or state inconsistency:
```bash
# Refresh state to sync with Azure
terraform refresh

# Or remove and re-apply the affected resource
terraform state rm 'module.container_apps.azurerm_container_app_environment.main'
terraform apply tfplan
```
</details>

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
