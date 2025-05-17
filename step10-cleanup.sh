#!/bin/bash
# cleanup.sh - Removes all resources created by this application
# CAUTION: This will delete all resources created by the application!

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "              Cleanup Script                     "
echo "=================================================="
echo

# Display warning and confirmation
echo "⚠️ WARNING: This script will delete ALL resources created by this application!"
echo "⚠️ This includes S3 bucket, CloudFront distribution, Cognito User Pool, and more."
echo "⚠️ This operation CANNOT be undone!"
echo
read -p "Are you ABSOLUTELY sure you want to continue? (type 'yes' to confirm): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup aborted."
    exit 0
fi

echo
read -p "⚠️ Last chance! Type the name of your application to confirm deletion: " APP_NAME_CONFIRM

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Cannot determine resources to clean up."
    exit 1
fi

# Load environment variables
source .env

if [ "$APP_NAME_CONFIRM" != "$APP_NAME" ]; then
    echo "❌ App name doesn't match. Cleanup aborted."
    exit 1
fi

echo "🧹 Starting cleanup process..."

# Get the stack name
STACK_NAME="${APP_NAME}-${STAGE}"

# First, empty the S3 bucket (this is required before the bucket can be deleted)
if [ -n "$S3_BUCKET_NAME" ]; then
    echo "🗑️ Emptying S3 bucket: $S3_BUCKET_NAME"
    aws s3 rm s3://$S3_BUCKET_NAME --recursive || echo "⚠️ Failed to empty bucket, continuing anyway."
fi

# If there's a Cognito domain, delete it
if [ -n "$USER_POOL_ID" ] && [ -n "$COGNITO_DOMAIN" ]; then
    echo "🗑️ Deleting Cognito User Pool domain"
    aws cognito-idp delete-user-pool-domain \
        --user-pool-id $USER_POOL_ID \
        --domain $COGNITO_DOMAIN || echo "⚠️ Failed to delete Cognito domain, continuing anyway."
fi

# Delete the CloudFormation stack (this will delete all resources)
if [ -n "$STACK_NAME" ]; then
    echo "🗑️ Deleting CloudFormation stack: $STACK_NAME"
    aws cloudformation delete-stack --stack-name $STACK_NAME
    
    echo "⏳ Waiting for stack deletion to complete (this may take several minutes)..."
    aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME || echo "⚠️ Stack deletion wait failed, continuing anyway."
fi

# Remove local generated files
echo "🧹 Cleaning up local files..."
rm -f web/app.js web/app.js.bak
rm -f .env.bak

echo
echo "✅ Cleanup completed!"
echo
echo "The following resources should have been deleted:"
echo "- CloudFormation stack: $STACK_NAME"
echo "- S3 bucket: $S3_BUCKET_NAME"
echo "- CloudFront distribution"
echo "- Cognito User Pool and Identity Pool"
echo "- API Gateway endpoints"
echo "- Lambda functions"
echo
echo "Some resources may still be in the process of being deleted."
echo "You can check the status in the AWS Console."
echo
echo "To redeploy the application, run ./setup.sh followed by ./deploy.sh"
echo "=================================================="
