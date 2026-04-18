#!/bin/bash
# Setup GitHub Actions secrets from Terraform outputs

set -euo pipefail

echo "Retrieving Terraform outputs..."
cd terraform

ACCESS_KEY_ID=$(terraform output -raw cicd_user_access_key_id)
SECRET_KEY=$(terraform output -raw cicd_user_secret_key)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
ECR_REGISTRY=$(terraform output -json ecr_repository_urls | jq -r '.app')
CLUSTER_NAME=$(terraform output -raw cluster_name)

echo ""
echo "Setting GitHub secrets..."
echo ""

gh secret set AWS_ACCESS_KEY_ID --body "$ACCESS_KEY_ID"
echo "✓ AWS_ACCESS_KEY_ID set"

gh secret set AWS_SECRET_ACCESS_KEY --body "$SECRET_KEY"
echo "✓ AWS_SECRET_ACCESS_KEY set"

gh secret set AWS_REGION --body "$AWS_REGION"
echo "✓ AWS_REGION set"

gh secret set ECR_REGISTRY --body "$ECR_REGISTRY"
echo "✓ ECR_REGISTRY set"

gh secret set ECS_CLUSTER --body "$CLUSTER_NAME"
echo "✓ ECS_CLUSTER set"

gh secret set ECS_SERVICE_APP --body "doc-parser-app"
echo "✓ ECS_SERVICE_APP set"

echo ""
echo "GitHub secrets configured!"
echo ""
echo "These secrets will be used by the CI/CD pipeline."
