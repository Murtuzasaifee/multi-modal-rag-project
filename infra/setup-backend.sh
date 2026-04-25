#!/bin/bash
# Setup S3 backend for Terraform state

set -euo pipefail

# Get AWS account ID (makes bucket unique per account)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)

# Unique bucket name with account ID suffix
BUCKET_NAME="doc-parser-terraform-state-${AWS_ACCOUNT_ID}"
REGION="us-east-1"

echo "Setting up Terraform S3 backend..."
echo "Bucket name: ${BUCKET_NAME}"
echo "Account ID: ${AWS_ACCOUNT_ID}"
echo ""

# Check if bucket exists
if aws s3 ls "s3://${BUCKET_NAME}" --region "$REGION" 2>/dev/null; then
    echo "✓ S3 bucket already exists: ${BUCKET_NAME}"
else
    echo "Creating S3 bucket: ${BUCKET_NAME}"
    aws s3 mb "s3://${BUCKET_NAME}" --region "$REGION"

    echo "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --region "$REGION"

    echo "Enabling server-side encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration \
        '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }' \
        --region "$REGION"

    echo "✓ S3 bucket created and configured"
fi

echo ""
echo "Backend setup complete!"
echo ""
echo "Initialize Terraform with:"
echo "  cd infra/terraform"
echo "  terraform init -backend-config=\"bucket=${BUCKET_NAME}\""
