#!/bin/bash
# Bootstrap Ollama model into EFS

set -euo pipefail

CLUSTER_NAME="doc-parser-cluster"
SERVICE_NAME="doc-parser-app"
MODEL_NAME="${1:-glm-ocr:latest}"

echo "Finding a running task..."
TASK_ARN=$(aws ecs list-tasks \
    --cluster "$CLUSTER_NAME" \
    --service-name "$SERVICE_NAME" \
    --query 'taskArns[0]' \
    --output text)

if [ -z "$TASK_ARN" ]; then
    echo "Error: No running task found for service $SERVICE_NAME"
    exit 1
fi

echo "Task found: $TASK_ARN"
echo ""
echo "This will pull the model: $MODEL_NAME"
echo "This can take 5-10 minutes depending on network speed."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

echo ""
echo "Executing ollama pull command..."
aws ecs execute-command \
    --cluster "$CLUSTER_NAME" \
    --task "$TASK_ARN" \
    --container ollama \
    --interactive \
    --command "ollama pull $MODEL_NAME"

echo ""
echo "Model pull complete!"
echo "The model is now stored on EFS and will persist across deployments."
