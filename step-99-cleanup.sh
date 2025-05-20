#!/bin/bash
# step-99-cleanup.sh - Removes all resources created by this application
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
echo "⚠️ This includes S3 bucket, CloudFront distribution, Cognito User Pool, Lambda functions, and more."
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

# Delete Lambda log groups (these aren't automatically removed by CloudFormation)
echo "🗑️ Deleting Lambda log groups..."
# List log groups with our app name prefix and delete them
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-${STAGE}" --query "logGroups[*].logGroupName" --output text | xargs -r -n1 aws logs delete-log-group --log-group-name || echo "⚠️ Failed to delete some log groups, continuing anyway."

# First, empty the S3 bucket (this is required before the bucket can be deleted)
if [ -n "$S3_BUCKET_NAME" ]; then
    echo "🗑️ Emptying S3 bucket: $S3_BUCKET_NAME"
    # Check if bucket exists before trying to empty it
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        aws s3 rm s3://$S3_BUCKET_NAME --recursive || echo "⚠️ Failed to empty bucket, continuing anyway."
    else
        echo "ℹ️ S3 bucket $S3_BUCKET_NAME does not exist or is not accessible."
    fi
fi

# Check for Serverless deployment bucket and empty it
DEPLOYMENT_BUCKET="${APP_NAME}-serverlessdeploymentbucket-"
echo "🔍 Looking for Serverless deployment buckets..."
DEPLOYMENT_BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${DEPLOYMENT_BUCKET}')].Name" --output text)

if [ -n "$DEPLOYMENT_BUCKETS" ]; then
    echo "🗑️ Found deployment buckets to clean up: $DEPLOYMENT_BUCKETS"
    for bucket in $DEPLOYMENT_BUCKETS; do
        echo "🗑️ Emptying deployment bucket: $bucket"
        aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty deployment bucket $bucket, continuing anyway."
    done
fi

# If there's a Cognito domain, delete it (must be done before stack deletion)
if [ -n "$USER_POOL_ID" ] && [ -n "$COGNITO_DOMAIN" ]; then
    echo "🗑️ Deleting Cognito User Pool domain"
    aws cognito-idp delete-user-pool-domain \
        --user-pool-id $USER_POOL_ID \
        --domain $COGNITO_DOMAIN || echo "⚠️ Failed to delete Cognito domain, continuing anyway."
fi

# Check for any CloudFront invalidations in progress
if [ -n "$CLOUDFRONT_URL" ]; then
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text)
    
    if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
        echo "🔍 Found CloudFront distribution: $DISTRIBUTION_ID"
        echo "⏳ Checking for invalidations in progress..."
        
        # Wait for any invalidations to complete
        INVALIDATIONS=$(aws cloudfront list-invalidations --distribution-id $DISTRIBUTION_ID --query "InvalidationList.Items[?Status=='InProgress'].Id" --output text)
        if [ -n "$INVALIDATIONS" ]; then
            echo "⏳ Waiting for CloudFront invalidations to complete..."
            for invalidation_id in $INVALIDATIONS; do
                echo "  Waiting for invalidation $invalidation_id..."
                aws cloudfront wait invalidation-completed --distribution-id $DISTRIBUTION_ID --id $invalidation_id || echo "⚠️ Wait failed for invalidation, continuing anyway."
            done
        fi
        
        echo "✅ CloudFront distribution ready for deletion"
    fi
fi

# Delete the CloudFormation stack (this will delete most resources)
if [ -n "$STACK_NAME" ]; then
    echo "🗑️ Deleting CloudFormation stack: $STACK_NAME"
    
    # Check if stack exists before trying to delete it
    if aws cloudformation describe-stacks --stack-name $STACK_NAME >/dev/null 2>&1; then
        aws cloudformation delete-stack --stack-name $STACK_NAME
        
        echo "⏳ Waiting for stack deletion to complete (this may take several minutes)..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME || echo "⚠️ Stack deletion wait failed, continuing anyway."
    else
        echo "ℹ️ CloudFormation stack $STACK_NAME does not exist or is not accessible."
    fi
fi

# Clean up any remaining deployment bucket after stack deletion
if [ -n "$DEPLOYMENT_BUCKETS" ]; then
    echo "🔍 Checking if deployment buckets still exist after stack deletion..."
    for bucket in $DEPLOYMENT_BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            echo "🗑️ Manually deleting deployment bucket: $bucket"
            aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete deployment bucket $bucket, continuing anyway."
        fi
    done
fi

# Remove local generated files
echo "🧹 Cleaning up local files..."
rm -f web/app.js web/app.js.bak serverless.yml.bak
rm -f .env.bak
rm -rf .serverless

# Clean up serverless state files
if [ -d ".serverless" ]; then
    echo "🧹 Cleaning up Serverless Framework state files..."
    rm -rf .serverless
fi

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
echo "- Lambda log groups"
echo "- Serverless deployment bucket(s)"
echo
echo "Some resources may still be in the process of being deleted."
echo "You can check the status in the AWS Console."
echo
echo "To redeploy the application, run ./step-10-setup.sh followed by ./step-20-deploy.sh"
echo "=================================================="
