#!/usr/bin/env bash
# Creates the Azure Storage Account used as the Terraform remote backend.
# Run this once before your first `terraform init`.
#
# Prerequisites: az CLI installed and logged in (`az login`).
set -euo pipefail

# ── Fetch active subscription explicitly to avoid SubscriptionNotFound errors ──
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
echo "==> Using subscription: $SUBSCRIPTION_ID (tenant: $TENANT_ID)"

# ── Configuration ──────────────────────────────────────────────────────────────
LOCATION="${LOCATION:-eastus}"
TF_STATE_RG="${TF_STATE_RG:-doc-parser-tfstate-rg}"
# Storage account name: 3-24 chars, lowercase alphanumeric, globally unique
TF_STATE_SA="${TF_STATE_SA:-docparsertfstate$(echo $SUBSCRIPTION_ID | tr -d '-' | cut -c1-8)}"
TF_STATE_CONTAINER="${TF_STATE_CONTAINER:-tfstate}"
TF_STATE_KEY="${TF_STATE_KEY:-doc-parser.tfstate}"

echo "==> Creating resource group for Terraform state: $TF_STATE_RG"
az group create \
  --name "$TF_STATE_RG" \
  --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  --output none

echo "==> Creating storage account: $TF_STATE_SA"
az storage account create \
  --name "$TF_STATE_SA" \
  --resource-group "$TF_STATE_RG" \
  --location "$LOCATION" \
  --subscription "$SUBSCRIPTION_ID" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --allow-blob-public-access false \
  --output none

echo "==> Creating blob container: $TF_STATE_CONTAINER"
az storage container create \
  --name "$TF_STATE_CONTAINER" \
  --account-name "$TF_STATE_SA" \
  --subscription "$SUBSCRIPTION_ID" \
  --auth-mode login \
  --output none

echo ""
echo "✅ Terraform backend ready.  Run the following to initialise:"
echo ""
echo "  cd infra/terraform-azure"
echo "  terraform init \\"
echo "    -backend-config=\"resource_group_name=$TF_STATE_RG\" \\"
echo "    -backend-config=\"storage_account_name=$TF_STATE_SA\" \\"
echo "    -backend-config=\"container_name=$TF_STATE_CONTAINER\" \\"
echo "    -backend-config=\"key=$TF_STATE_KEY\""
echo ""
echo "Or export these environment variables before running terraform init:"
echo "  export ARM_SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "  export ARM_TENANT_ID=$TENANT_ID"
echo "  export ARM_RESOURCE_GROUP_NAME=$TF_STATE_RG"
echo "  export ARM_STORAGE_ACCOUNT_NAME=$TF_STATE_SA"
echo "  export ARM_CONTAINER_NAME=$TF_STATE_CONTAINER"
echo "  export ARM_KEY=$TF_STATE_KEY"
