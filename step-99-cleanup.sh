#!/bin/bash
# step-99-cleanup.sh - Removes all resources created by this application
# CAUTION: This will delete ALL resources created by the application!

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
aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-${STAGE}" --query "logGroups[*].logGroupName" --output text | xargs -I {} aws logs delete-log-group --log-group-name {} 2>/dev/null || echo "⚠️ Failed to delete some log groups, continuing anyway."

# Find deployment buckets from CloudFormation resources if stack exists
echo "🔍 Checking for ServerlessDeploymentBucket in CloudFormation stack..."
DEPLOYMENT_BUCKETS=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceType=='AWS::S3::Bucket' && contains(LogicalResourceId, 'ServerlessDeployment')].PhysicalResourceId" --output text 2>/dev/null || echo "")

# Also look for deployment buckets with naming pattern if stack query didn't work
if [ -z "$DEPLOYMENT_BUCKETS" ]; then
    echo "🔍 Looking for Serverless deployment buckets by name pattern..."
    DEPLOYMENT_BUCKETS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${APP_NAME}-${STAGE}-serverlessdeployment') || starts_with(Name, '${APP_NAME}-serverlessdeploymentbucket')].Name" --output text)
fi

# Empty and delete any deployment buckets found
if [ -n "$DEPLOYMENT_BUCKETS" ]; then
    echo "🗑️ Found deployment buckets to clean up: $DEPLOYMENT_BUCKETS"
    for bucket in $DEPLOYMENT_BUCKETS; do
        echo "🗑️ Emptying deployment bucket: $bucket"
        aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty bucket $bucket, continuing anyway."
        echo "🗑️ Deleting deployment bucket: $bucket"
        aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete bucket $bucket, continuing anyway."
    done
fi

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

# If there's a Cognito domain, delete it (must be done before stack deletion)
if [ -n "$USER_POOL_ID" ] && [ -n "$COGNITO_DOMAIN" ]; then
    echo "🗑️ Deleting Cognito User Pool domain"
    aws cognito-idp delete-user-pool-domain \
        --user-pool-id $USER_POOL_ID \
        --domain $COGNITO_DOMAIN 2>/dev/null || echo "⚠️ Failed to delete Cognito domain, continuing anyway."
fi

# Check for any CloudFront invalidations in progress
if [ -n "$CLOUDFRONT_URL" ]; then
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text 2>/dev/null)
    
    if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
        echo "🔍 Found CloudFront distribution: $DISTRIBUTION_ID"
        echo "⏳ Checking for invalidations in progress..."
        
        # Wait for any invalidations to complete
        INVALIDATIONS=$(aws cloudfront list-invalidations --distribution-id $DISTRIBUTION_ID --query "InvalidationList.Items[?Status=='InProgress'].Id" --output text 2>/dev/null)
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
    
    # Check if stack is in DELETE_FAILED state
    echo "🔍 Checking if stack is in DELETE_FAILED state..."
    if aws cloudformation describe-stacks --stack-name $STACK_NAME 2>/dev/null | grep -q "DELETE_FAILED"; then
        echo "⚠️ Stack is in DELETE_FAILED state. Finding resources that failed to delete..."
        
        FAILED_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceStatus=='DELETE_FAILED']" --output json)
        
        echo "Resources that failed to delete: $FAILED_RESOURCES"
        
        # Handle each type of resource specifically
        echo "🗑️ Attempting to delete failed resources directly..."
        
        # Extract and handle S3 buckets from the failed resources
        S3_BUCKETS=$(echo "$FAILED_RESOURCES" | grep -o '"PhysicalResourceId":[[:space:]]*"[^"]*"' | grep -i "bucket" | sed 's/"PhysicalResourceId":[[:space:]]*"\(.*\)"/\1/')
        
        for bucket in $S3_BUCKETS; do
            echo "🗑️ Emptying and deleting S3 bucket: $bucket"
            aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty bucket, continuing anyway."
            aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete bucket, continuing anyway."
        done
        
        # Try deleting the stack one more time
        echo "🔄 Attempting to delete the stack again..."
        aws cloudformation delete-stack --stack-name $STACK_NAME
        
        echo "⚠️ If the stack still fails to delete, use a different STAGE value for your next deployment."
    fi
fi

# Clean up any remaining deployment bucket after stack deletion
if [ -n "$DEPLOYMENT_BUCKETS" ]; then
    echo "🔍 Checking if deployment buckets still exist after stack deletion..."
    for bucket in $DEPLOYMENT_BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            echo "🗑️ Manually deleting deployment bucket: $bucket"
            aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty bucket $bucket, continuing anyway."
            aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete bucket $bucket, continuing anyway."
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

# Recommend using a different stage name if there were issues
echo "💡 If you encountered any issues with deletion, consider changing your STAGE in the .env file for your next deployment."
echo "   Current application name: $APP_NAME"
echo "   Current stage: $STAGE"
echo "   You can change these in the .env file or during the setup process."

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
