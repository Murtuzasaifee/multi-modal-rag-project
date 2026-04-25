#!/usr/bin/env bash
# Creates the Azure Storage Account used as the Terraform remote backend.
# Run this once before your first `terraform init`.
#
# Prerequisites: az CLI installed and logged in (`az login`).
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
LOCATION="${LOCATION:-eastus}"
TF_STATE_RG="${TF_STATE_RG:-doc-parser-tfstate-rg}"
TF_STATE_SA="${TF_STATE_SA:-docparsertfstate$RANDOM}"   # must be globally unique
TF_STATE_CONTAINER="${TF_STATE_CONTAINER:-tfstate}"
TF_STATE_KEY="${TF_STATE_KEY:-doc-parser.tfstate}"

echo "==> Creating resource group for Terraform state: $TF_STATE_RG"
az group create --name "$TF_STATE_RG" --location "$LOCATION" --output none

echo "==> Creating storage account: $TF_STATE_SA"
az storage account create \
  --name "$TF_STATE_SA" \
  --resource-group "$TF_STATE_RG" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --output none

echo "==> Creating blob container: $TF_STATE_CONTAINER"
az storage container create \
  --name "$TF_STATE_CONTAINER" \
  --account-name "$TF_STATE_SA" \
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
echo "  export ARM_RESOURCE_GROUP_NAME=$TF_STATE_RG"
echo "  export ARM_STORAGE_ACCOUNT_NAME=$TF_STATE_SA"
echo "  export ARM_CONTAINER_NAME=$TF_STATE_CONTAINER"
echo "  export ARM_KEY=$TF_STATE_KEY"
