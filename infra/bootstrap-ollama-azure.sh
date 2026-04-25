#!/usr/bin/env bash
# Pulls the GLM-OCR model into the ollama sidecar container running in Azure.
# Equivalent to bootstrap-ollama.sh for the AWS ECS setup.
#
# Prerequisites: az CLI logged in; jq installed.
set -euo pipefail

MODEL="${1:-glm-ocr:latest}"
TF_DIR="$(dirname "$0")/terraform-azure"

RESOURCE_GROUP=$(terraform -chdir="$TF_DIR" output -raw resource_group_name)
CONTAINER_APP=$(terraform -chdir="$TF_DIR" output -raw container_app_name)

echo "==> Pulling model '$MODEL' into the ollama container..."
echo "    Container App: $CONTAINER_APP"
echo "    Resource Group: $RESOURCE_GROUP"
echo ""
echo "    This will open an interactive exec session.  Run:"
echo "      ollama pull $MODEL"
echo "    then exit when the download completes."
echo ""

az containerapp exec \
  --name "$CONTAINER_APP" \
  --resource-group "$RESOURCE_GROUP" \
  --container ollama \
  --command "/bin/sh"
