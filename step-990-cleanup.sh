#!/bin/bash
# step-99-cleanup.sh - Complete cleanup with all safety features
# Phase 1: Discovery and reporting what exists
# Phase 2: Show deletion plan
# Phase 3: Execute cleanup with confirmations

set -e # Exit on any error

# Load environment variables
if [ ! -f .env ]; then
    echo "❌ .env file not found. Cannot determine resources to clean up."
    exit 1
fi

source .env

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "      Complete Resource Cleanup Script           "
echo "=================================================="
echo

# Get the stack name
STACK_NAME="${APP_NAME}-${STAGE}"

echo "📋 PHASE 1: RESOURCE DISCOVERY"
echo "=================================================="
echo "Scanning AWS for all resources associated with:"
echo "  Application: $APP_NAME"
echo "  Stage: $STAGE"
echo "  Stack: $STACK_NAME"
echo "=================================================="
echo

# 1. Check CloudFormation Stack
echo "1️⃣ CloudFormation Stack:"
STACK_EXISTS=false
STACK_STATUS=""
if aws cloudformation describe-stacks --stack-name $STACK_NAME >/dev/null 2>&1; then
    STACK_EXISTS=true
    echo "   ✅ Found: $STACK_NAME"
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --output text)
    echo "   📊 Status: $STACK_STATUS"
    
    # Get stack creation time
    STACK_CREATED=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].CreationTime" --output text)
    echo "   🕐 Created: $STACK_CREATED"
else
    echo "   ❌ Not found: $STACK_NAME"
fi
echo

# 2. Check S3 Data Bucket
echo "2️⃣ S3 Data Bucket:"
BUCKET_EXISTS=false
BUCKET_CREATED_BY_STACK=false
OBJECT_COUNT=0
if [ -n "$S3_BUCKET_NAME" ]; then
    echo "   Name: $S3_BUCKET_NAME"
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        BUCKET_EXISTS=true
        echo "   ✅ Exists: Yes"
        
        # Get bucket creation date
        BUCKET_CREATED=$(aws s3api list-buckets --query "Buckets[?Name=='$S3_BUCKET_NAME'].CreationDate" --output text)
        echo "   🕐 Created: $BUCKET_CREATED"
        
        # Check if created by stack
        if [ "$STACK_EXISTS" = true ]; then
            BUCKET_IN_STACK=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceType=='AWS::S3::Bucket' && PhysicalResourceId=='$S3_BUCKET_NAME'].LogicalResourceId" --output text 2>/dev/null || echo "")
            
            if [ -n "$BUCKET_IN_STACK" ] && [ "$BUCKET_IN_STACK" != "None" ]; then
                echo "   📌 Origin: Created by this CloudFormation stack"
                BUCKET_CREATED_BY_STACK=true
            else
                echo "   📌 Origin: PRE-EXISTING (not created by this stack)"
                echo "   ⚠️  Note: Bucket existed before stack creation"
                BUCKET_CREATED_BY_STACK=false
            fi
        else
            echo "   📌 Origin: Cannot determine (no stack found)"
        fi
        
        # Count objects
        echo "   ⏳ Counting objects..."
        OBJECT_COUNT=$(aws s3 ls s3://$S3_BUCKET_NAME --recursive --summarize | grep "Total Objects:" | cut -d: -f2 | xargs || echo "0")
        BUCKET_SIZE=$(aws s3 ls s3://$S3_BUCKET_NAME --recursive --summarize | grep "Total Size:" | cut -d: -f2 | xargs || echo "0")
        echo "   📊 Objects: ${OBJECT_COUNT:-0}"
        echo "   💾 Total Size: ${BUCKET_SIZE:-0 bytes}"
    else
        echo "   ❌ Does not exist"
    fi
else
    echo "   ❌ No bucket configured"
fi
echo

# 3. Check CloudFront Distribution
echo "3️⃣ CloudFront Distribution:"
DISTRIBUTION_EXISTS=false
DISTRIBUTION_ID=""
if [ -n "$CLOUDFRONT_URL" ]; then
    DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text 2>/dev/null)
    if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
        DISTRIBUTION_EXISTS=true
        echo "   ✅ Found: $DISTRIBUTION_ID"
        echo "   🌐 URL: $CLOUDFRONT_URL"
        
        # Get distribution status
        DIST_STATUS=$(aws cloudfront get-distribution --id $DISTRIBUTION_ID --query "Distribution.Status" --output text 2>/dev/null || echo "Unknown")
        echo "   📊 Status: $DIST_STATUS"
    else
        echo "   ❌ Not found"
    fi
else
    echo "   ❌ No CloudFront URL configured"
fi
echo

# 4. Check Cognito Resources
echo "4️⃣ Cognito Resources:"
USER_POOL_EXISTS=false
USER_COUNT=0
if [ -n "$USER_POOL_ID" ]; then
    if aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID >/dev/null 2>&1; then
        USER_POOL_EXISTS=true
        echo "   ✅ User Pool: $USER_POOL_ID"
        USER_COUNT=$(aws cognito-idp list-users --user-pool-id $USER_POOL_ID --query "length(Users)" --output text 2>/dev/null || echo "0")
        echo "   👥 Users: $USER_COUNT"
        
        # Check domain
        if [ -n "$COGNITO_DOMAIN" ]; then
            echo "   🌐 Domain: $COGNITO_DOMAIN"
        fi
    else
        echo "   ❌ User Pool not found"
    fi
else
    echo "   ❌ No User Pool configured"
fi

IDENTITY_POOL_EXISTS=false
if [ -n "$IDENTITY_POOL_ID" ]; then
    IDENTITY_POOL_EXISTS=true
    echo "   ✅ Identity Pool: $IDENTITY_POOL_ID"
fi
echo

# 5. Check Lambda Functions
echo "5️⃣ Lambda Functions:"
LAMBDA_FUNCTIONS=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '${APP_NAME}-${STAGE}')].FunctionName" --output text 2>/dev/null)
LAMBDA_COUNT=0
if [ -n "$LAMBDA_FUNCTIONS" ]; then
    for func in $LAMBDA_FUNCTIONS; do
        echo "   ✅ $func"
        LAMBDA_COUNT=$((LAMBDA_COUNT + 1))
    done
    echo "   📊 Total: $LAMBDA_COUNT functions"
else
    echo "   ❌ No Lambda functions found"
fi
echo

# 6. Check API Gateway
echo "6️⃣ API Gateway:"
if [ -n "$API_ENDPOINT" ]; then
    # Extract API ID from endpoint
    API_ID=$(echo $API_ENDPOINT | sed 's|https://||' | cut -d'.' -f1)
    if aws apigateway get-rest-api --rest-api-id $API_ID >/dev/null 2>&1; then
        echo "   ✅ Found: $API_ID"
        echo "   🌐 Endpoint: $API_ENDPOINT"
    else
        echo "   ❌ Not found"
    fi
else
    echo "   ❌ No API endpoint configured"
fi
echo

# 7. Check Lambda Log Groups
echo "7️⃣ Lambda Log Groups:"
LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-${STAGE}" --query "logGroups[*].logGroupName" --output text 2>/dev/null)
LOG_GROUP_COUNT=0
if [ -n "$LOG_GROUPS" ]; then
    for log_group in $LOG_GROUPS; do
        echo "   ✅ $log_group"
        LOG_GROUP_COUNT=$((LOG_GROUP_COUNT + 1))
    done
    echo "   📊 Total: $LOG_GROUP_COUNT log groups"
else
    echo "   ❌ No Lambda log groups found"
fi
echo

# 8. Check Deployment Buckets
echo "8️⃣ Serverless Deployment Buckets:"
# First check CloudFormation stack for deployment buckets
DEPLOYMENT_BUCKETS_CF=""
if [ "$STACK_EXISTS" = true ]; then
    DEPLOYMENT_BUCKETS_CF=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceType=='AWS::S3::Bucket' && contains(LogicalResourceId, 'ServerlessDeployment')].PhysicalResourceId" --output text 2>/dev/null || echo "")
fi
# Also check by naming pattern
DEPLOYMENT_BUCKETS_PATTERN=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${APP_NAME}-${STAGE}-serverlessdeployment') || starts_with(Name, '${APP_NAME}-serverlessdeploymentbucket')].Name" --output text)
# Combine both lists and remove duplicates
DEPLOYMENT_BUCKETS=$(echo "$DEPLOYMENT_BUCKETS_CF $DEPLOYMENT_BUCKETS_PATTERN" | tr ' ' '\n' | sort -u | grep -v '^$' | tr '\n' ' ')
DEPLOYMENT_BUCKET_COUNT=0
if [ -n "$(echo $DEPLOYMENT_BUCKETS | xargs)" ]; then
    for bucket in $DEPLOYMENT_BUCKETS; do
        if [ -n "$bucket" ]; then
            echo "   ✅ $bucket"
            DEPLOYMENT_BUCKET_COUNT=$((DEPLOYMENT_BUCKET_COUNT + 1))
        fi
    done
    echo "   📊 Total: $DEPLOYMENT_BUCKET_COUNT deployment buckets"
else
    echo "   ❌ No deployment buckets found"
fi

echo
echo "=================================================="
echo "📋 PHASE 2: DELETION PLAN"
echo "=================================================="
echo

echo "🗑️ Resources that WILL BE DELETED:"
echo
if [ "$STACK_EXISTS" = true ]; then
    echo "  ✓ CloudFormation stack: $STACK_NAME"
fi
if [ "$DISTRIBUTION_EXISTS" = true ]; then
    echo "  ✓ CloudFront distribution: $DISTRIBUTION_ID"
fi
if [ "$USER_POOL_EXISTS" = true ]; then
    echo "  ✓ Cognito User Pool: $USER_POOL_ID ($USER_COUNT users)"
fi
if [ "$IDENTITY_POOL_EXISTS" = true ]; then
    echo "  ✓ Cognito Identity Pool: $IDENTITY_POOL_ID"
fi
if [ -n "$API_ENDPOINT" ]; then
    echo "  ✓ API Gateway: $API_ID"
fi
if [ $LAMBDA_COUNT -gt 0 ]; then
    echo "  ✓ Lambda functions: $LAMBDA_COUNT functions"
fi
if [ $LOG_GROUP_COUNT -gt 0 ]; then
    echo "  ✓ Lambda log groups: $LOG_GROUP_COUNT log groups"
fi
if [ $DEPLOYMENT_BUCKET_COUNT -gt 0 ]; then
    echo "  ✓ Deployment buckets: $DEPLOYMENT_BUCKET_COUNT buckets"
fi
echo

echo "📦 S3 Data Bucket ($S3_BUCKET_NAME):"
if [ "$BUCKET_EXISTS" = true ]; then
    if [ "$BUCKET_CREATED_BY_STACK" = true ]; then
        echo "  ⚠️  Status: Created by this stack"
        echo "  ⚠️  Decision: You'll be asked whether to delete"
        echo "  📊 Contains: $OBJECT_COUNT objects (${BUCKET_SIZE:-0 bytes})"
    else
        echo "  ✅ Status: PRE-EXISTING bucket"
        echo "  💡 Recommendation: KEEP (existed before deployment)"
        echo "  📊 Contains: $OBJECT_COUNT objects (${BUCKET_SIZE:-0 bytes})"
        echo "  ⚠️  Note: Bucket policy may be updated to remove CloudFront access"
    fi
else
    echo "  ❌ Bucket does not exist"
fi

echo
echo "=================================================="
echo

# Now ask for confirmation to proceed
read -p "Do you want to proceed with cleanup? (type 'yes' to confirm): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Cleanup aborted."
    exit 0
fi

echo
read -p "Type the name of your application to confirm: " APP_NAME_CONFIRM

if [ "$APP_NAME_CONFIRM" != "$APP_NAME" ]; then
    echo "❌ App name doesn't match. Cleanup aborted."
    exit 1
fi

echo
echo "=================================================="
echo "📋 PHASE 3: EXECUTING CLEANUP"
echo "=================================================="
echo

# Delete Lambda log groups
if [ $LOG_GROUP_COUNT -gt 0 ]; then
    echo "🗑️ Deleting Lambda log groups..."
    aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-${STAGE}" --query "logGroups[*].logGroupName" --output text | xargs -I {} aws logs delete-log-group --log-group-name {} 2>/dev/null || echo "⚠️ Failed to delete some log groups, continuing anyway."
fi

# Delete deployment buckets found during discovery
if [ $DEPLOYMENT_BUCKET_COUNT -gt 0 ]; then
    for bucket in $DEPLOYMENT_BUCKETS; do
        if [ -n "$bucket" ]; then
            echo "🗑️ Deleting deployment bucket: $bucket"
            aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty bucket $bucket, continuing anyway."
            aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete bucket $bucket, continuing anyway."
        fi
    done
fi

# Ask about S3 data bucket
DELETE_BUCKET=false
if [ "$BUCKET_EXISTS" = true ]; then
    echo
    echo "=================================================="
    echo "📦 S3 DATA BUCKET DECISION REQUIRED"
    echo "=================================================="
    echo "Bucket: $S3_BUCKET_NAME"
    echo "Objects: $OBJECT_COUNT"
    echo "Size: ${BUCKET_SIZE:-0 bytes}"
    
    if [ "$BUCKET_CREATED_BY_STACK" = true ]; then
        echo "Status: Created by this CloudFormation stack"
        echo
        read -p "Delete this bucket and ALL its contents? (y/N): " DELETE_BUCKET_CONFIRM
    else
        echo "Status: PRE-EXISTING bucket (existed before this deployment)"
        echo
        echo "⚠️  WARNING: This bucket existed BEFORE your deployment!"
        echo "⚠️  It may contain important data or be used by other applications."
        echo
        read -p "Are you SURE you want to delete this pre-existing bucket? (y/N): " DELETE_BUCKET_CONFIRM
    fi
    
    if [ "$DELETE_BUCKET_CONFIRM" = "y" ] || [ "$DELETE_BUCKET_CONFIRM" = "Y" ]; then
        DELETE_BUCKET=true
        echo
        echo "⚠️  FINAL CONFIRMATION REQUIRED"
        read -p "Type the bucket name '$S3_BUCKET_NAME' to confirm deletion: " BUCKET_CONFIRM
        if [ "$BUCKET_CONFIRM" != "$S3_BUCKET_NAME" ]; then
            DELETE_BUCKET=false
            echo "❌ Bucket name doesn't match. Bucket will be PRESERVED."
        else
            echo "⚠️  Bucket WILL BE DELETED!"
        fi
    else
        echo "✅ Bucket will be PRESERVED"
    fi
    echo "=================================================="
fi

# Delete Cognito domain
if [ "$USER_POOL_EXISTS" = true ] && [ -n "$COGNITO_DOMAIN" ]; then
    echo "🗑️ Deleting Cognito User Pool domain"
    aws cognito-idp delete-user-pool-domain \
        --user-pool-id $USER_POOL_ID \
        --domain $COGNITO_DOMAIN 2>/dev/null || echo "⚠️ Failed to delete Cognito domain, continuing anyway."
fi

# Wait for CloudFront invalidations
if [ "$DISTRIBUTION_EXISTS" = true ]; then
    INVALIDATIONS=$(aws cloudfront list-invalidations --distribution-id $DISTRIBUTION_ID --query "InvalidationList.Items[?Status=='InProgress'].Id" --output text 2>/dev/null)
    if [ -n "$INVALIDATIONS" ]; then
        echo "⏳ Waiting for CloudFront invalidations to complete..."
        for invalidation_id in $INVALIDATIONS; do
            aws cloudfront wait invalidation-completed --distribution-id $DISTRIBUTION_ID --id $invalidation_id || true
        done
    fi
fi

# Delete CloudFormation stack with DELETE_FAILED handling
if [ "$STACK_EXISTS" = true ]; then
    echo "🗑️ Deleting CloudFormation stack: $STACK_NAME"
    aws cloudformation delete-stack --stack-name $STACK_NAME
    echo "⏳ Waiting for stack deletion (this may take several minutes)..."
    aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME || echo "⚠️ Stack deletion wait failed, continuing anyway."
    
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

# Handle S3 bucket based on decision
if [ "$DELETE_BUCKET" = true ] && [ "$BUCKET_EXISTS" = true ]; then
    echo "🗑️ Deleting S3 bucket: $S3_BUCKET_NAME"
    aws s3 rm s3://$S3_BUCKET_NAME --recursive || echo "⚠️ Failed to empty bucket, continuing anyway."
    aws s3 rb s3://$S3_BUCKET_NAME --force || echo "⚠️ Failed to delete bucket, continuing anyway."
elif [ "$DELETE_BUCKET" = false ] && [ "$BUCKET_EXISTS" = true ]; then
    echo "🔒 S3 bucket PRESERVED: $S3_BUCKET_NAME"
    if [ "$BUCKET_CREATED_BY_STACK" = false ]; then
        echo "⚠️ Note: The bucket policy may have been updated to remove CloudFront access"
    fi
fi

# Clean up any remaining deployment buckets after stack deletion
if [ -n "$(echo $DEPLOYMENT_BUCKETS | xargs)" ]; then
    echo "🔍 Checking if deployment buckets still exist after stack deletion..."
    for bucket in $DEPLOYMENT_BUCKETS; do
        if [ -n "$bucket" ] && aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            echo "🗑️ Manually deleting deployment bucket: $bucket"
            aws s3 rm s3://$bucket --recursive || echo "⚠️ Failed to empty bucket $bucket, continuing anyway."
            aws s3 rb s3://$bucket --force || echo "⚠️ Failed to delete bucket $bucket, continuing anyway."
        fi
    done
fi

# Clean up local files
echo "🧹 Cleaning up local files..."
rm -f web/app.js web/app.js.bak web/audio.html web/audio.html.bak serverless.yml.bak serverless.yml.backup-*
rm -f .env.bak
rm -rf .serverless

echo
echo "=================================================="
echo "               CLEANUP COMPLETE                   "
echo "=================================================="
echo
echo "Deleted:"
if [ "$STACK_EXISTS" = true ]; then
    echo "  ✓ CloudFormation stack"
fi
if [ "$DISTRIBUTION_EXISTS" = true ]; then
    echo "  ✓ CloudFront distribution"
fi
if [ "$USER_POOL_EXISTS" = true ]; then
    echo "  ✓ Cognito resources"
fi
if [ $LAMBDA_COUNT -gt 0 ]; then
    echo "  ✓ Lambda functions"
fi
if [ -n "$API_ENDPOINT" ]; then
    echo "  ✓ API Gateway"
fi
if [ $DEPLOYMENT_BUCKET_COUNT -gt 0 ]; then
    echo "  ✓ Deployment buckets"
fi
echo
if [ "$DELETE_BUCKET" = true ]; then
    echo "S3 Data Bucket: DELETED ❌"
else
    echo "S3 Data Bucket: PRESERVED ✅"
    echo "  → $S3_BUCKET_NAME"
fi
echo
echo "To redeploy: ./step-10-setup.sh followed by ./step-20-deploy.sh"

# Recommend using a different stage name if there were issues
if [ "$STACK_EXISTS" = true ] && aws cloudformation describe-stacks --stack-name $STACK_NAME 2>/dev/null | grep -q "DELETE_FAILED"; then
    echo
    echo "💡 Stack deletion failed. Consider changing your STAGE in the .env file for your next deployment."
    echo "   Current application name: $APP_NAME"
    echo "   Current stage: $STAGE"
    echo "   You can change these in the .env file or during the setup process."
fi

echo
echo "🔍 Final Verification:"
# Check if CloudFormation stack is deleted
if [ "$STACK_EXISTS" = true ]; then
    aws cloudformation describe-stacks --stack-name $STACK_NAME 2>&1 | grep -q "does not exist" && echo "✅ Stack deleted" || echo "❌ Stack still exists"
fi

# Check if S3 bucket is deleted (only if user chose to delete)
if [ "$BUCKET_EXISTS" = true ]; then
    if [ "$DELETE_BUCKET" = true ]; then
        aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>&1 | grep -q "Not Found\|NoSuchBucket\|404" && echo "✅ Bucket deleted" || echo "❌ Bucket still exists"
    else
        echo "✅ Bucket preserved as requested"
    fi
fi

echo "=================================================="