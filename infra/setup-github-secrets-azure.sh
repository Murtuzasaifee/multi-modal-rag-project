#!/usr/bin/env bash
# Creates the Azure service principal and sets all required GitHub Actions secrets.
# Run this after `terraform apply` has completed successfully.
#
# Prerequisites:
#   - az CLI installed and logged in
#   - gh CLI installed and authenticated (`gh auth login`)
#   - terraform outputs available in infra/terraform-azure/
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
TF_DIR="$(dirname "$0")/terraform-azure"

echo "==> Reading Terraform outputs..."
RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name)
ACR_NAME=$(terraform -chdir="$TF_DIR" output -raw acr_name)
ACR_LOGIN_SERVER=$(terraform -chdir="$TF_DIR" output -raw acr_login_server)
CONTAINER_APP_NAME=$(terraform -chdir="$TF_DIR" output -raw container_app_name)

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

SP_NAME="doc-parser-cicd-${RESOURCE_GROUP}"

echo "==> Creating service principal: $SP_NAME"
SP_JSON=$(az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role "Contributor" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --output json)

CLIENT_ID=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['appId'])")
CLIENT_SECRET=$(echo "$SP_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])")

echo "==> Granting AcrPush role on ACR..."
ACR_ID=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query id -o tsv)
az role assignment create \
  --assignee "$CLIENT_ID" \
  --role "AcrPush" \
  --scope "$ACR_ID" \
  --output none

# Build the JSON credentials blob expected by azure/login@v2 creds parameter
AZURE_CREDENTIALS=$(cat <<EOF
{
  "clientId": "$CLIENT_ID",
  "clientSecret": "$CLIENT_SECRET",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "tenantId": "$TENANT_ID"
}
EOF
)

echo "==> Setting GitHub secrets on $REPO..."
gh secret set AZURE_CREDENTIALS       --repo "$REPO" --body "$AZURE_CREDENTIALS"
gh secret set ACR_LOGIN_SERVER        --repo "$REPO" --body "$ACR_LOGIN_SERVER"
gh secret set ACR_NAME                --repo "$REPO" --body "$ACR_NAME"
gh secret set AZURE_RESOURCE_GROUP    --repo "$REPO" --body "$RESOURCE_GROUP"
gh secret set CONTAINER_APP_NAME      --repo "$REPO" --body "$CONTAINER_APP_NAME"

echo ""
echo "✅ GitHub secrets set.  Next: set your API key in Key Vault:"
KV_NAME=$(terraform -chdir="$TF_DIR" output -raw key_vault_name)
echo "  az keyvault secret set --vault-name $KV_NAME --name openai-api-key --value sk-..."
echo ""
echo "Then trigger a deployment by pushing to the 'terraform' branch."
