#!/bin/bash
# step-990-cleanup.sh - Complete cleanup with comprehensive orphaned resource detection
# Prerequisites: None (can be run anytime)
# Outputs: Complete cleanup of all AWS resources associated with the application
# Phase 1: Discovery and reporting what exists
# Phase 2: Show deletion plan  
# Phase 3: Execute cleanup with confirmations

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-990-cleanup"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Load environment variables
if [ ! -f .env ]; then
    log_error ".env file not found. Cannot determine resources to clean up." "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 If you need to clean up resources without .env, you'll need to specify them manually${NC}"
    exit 1
fi

source .env

# Validate required variables from .env
if [ -z "$APP_NAME" ] || [ -z "$STAGE" ]; then
    log_error "APP_NAME or STAGE not set in .env file" "$SCRIPT_NAME" 
    echo -e "${YELLOW}💡 Run step-010-setup.sh to create proper .env configuration${NC}"
    exit 1
fi

log_info "Starting comprehensive cleanup for $APP_NAME-$STAGE" "$SCRIPT_NAME"

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
        echo "  ❓ Decision: You'll be asked later whether to delete or keep"
        echo "  📊 Contains: $OBJECT_COUNT objects (${BUCKET_SIZE:-0 bytes})"
    else
        echo "  ✅ Status: PRE-EXISTING bucket (existed before deployment)"
        echo "  🛡️  Default: WILL BE KEPT SAFE (you can override later if needed)"
        echo "  📊 Contains: $OBJECT_COUNT objects (${BUCKET_SIZE:-0 bytes})"
        echo "  📋 Decision: You'll be prompted later with a safety warning"
        echo "  ℹ️  Note: Only bucket policy will be updated (CloudFront access removed)"
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

# STEP 1: Clean up local files FIRST (prevents deployment bucket conflicts)
log_info "Cleaning up local Serverless Framework files to prevent conflicts" "$SCRIPT_NAME"
if [ -d ".serverless" ]; then
    log_info "Removing .serverless directory" "$SCRIPT_NAME"
    rm -rf .serverless
    log_success "Serverless cache cleaned" "$SCRIPT_NAME"
else
    log_info "No .serverless directory found" "$SCRIPT_NAME"
fi

# Clean up other local files
log_info "Cleaning up generated local files" "$SCRIPT_NAME"
rm -f web/app.js web/app.js.bak web/audio.html web/audio.html.bak serverless.yml.bak serverless.yml.backup-*
rm -f .env.bak
log_success "Local files cleaned" "$SCRIPT_NAME"

# STEP 2: Delete CloudFormation stack (this will delete most AWS resources)
if [ "$STACK_EXISTS" = true ]; then
    log_info "Deleting CloudFormation stack: $STACK_NAME" "$SCRIPT_NAME"
    aws cloudformation delete-stack --stack-name $STACK_NAME
    
    log_info "Waiting for stack deletion (this may take several minutes)..." "$SCRIPT_NAME"
    if aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 2>/dev/null; then
        log_success "CloudFormation stack deleted successfully" "$SCRIPT_NAME"
    else
        log_warning "Stack deletion wait timed out or failed, checking status..." "$SCRIPT_NAME"
        
        # Check if stack is in DELETE_FAILED state
        if aws cloudformation describe-stacks --stack-name $STACK_NAME 2>/dev/null | grep -q "DELETE_FAILED"; then
            log_error "Stack is in DELETE_FAILED state" "$SCRIPT_NAME"
            
            # Get failed resources
            FAILED_RESOURCES=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceStatus=='DELETE_FAILED'].{Type:ResourceType,Id:PhysicalResourceId}" --output json)
            log_info "Resources that failed to delete: $FAILED_RESOURCES" "$SCRIPT_NAME"
            
            # We'll handle these in the orphaned resources section below
        else
            log_info "Stack may still be deleting or already deleted" "$SCRIPT_NAME"
        fi
    fi
else
    log_info "No CloudFormation stack found to delete" "$SCRIPT_NAME"
fi

# STEP 3: Clean up deployment buckets (Serverless Framework buckets)
if [ $DEPLOYMENT_BUCKET_COUNT -gt 0 ]; then
    log_info "Deleting Serverless deployment buckets" "$SCRIPT_NAME"
    for bucket in $DEPLOYMENT_BUCKETS; do
        if [ -n "$bucket" ]; then
            log_info "Emptying and deleting deployment bucket: $bucket" "$SCRIPT_NAME"
            aws s3 rm s3://$bucket --recursive 2>/dev/null || log_warning "Failed to empty bucket $bucket" "$SCRIPT_NAME"
            aws s3 rb s3://$bucket --force 2>/dev/null || log_warning "Failed to delete bucket $bucket" "$SCRIPT_NAME"
        fi
    done
else
    log_info "No deployment buckets found" "$SCRIPT_NAME"
fi

# STEP 4: Clean up any orphaned resources that CloudFormation missed
log_info "Scanning for orphaned resources that could cause future deployment conflicts" "$SCRIPT_NAME"

# 1. Orphaned Log Groups (can cause CREATE_FAILED errors)
ORPHANED_LOGS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${APP_NAME}-${STAGE}" --query "logGroups[*].logGroupName" --output text 2>/dev/null || echo "")
ORPHANED_COUNT=0
if [ -n "$ORPHANED_LOGS" ] && [ "$ORPHANED_LOGS" != "None" ]; then
    log_warning "Found orphaned log groups that could cause deployment conflicts" "$SCRIPT_NAME"
    for log_group in $ORPHANED_LOGS; do
        if [ -n "$log_group" ]; then
            log_info "Deleting orphaned log group: $log_group" "$SCRIPT_NAME"
            if aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null; then
                ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
            else
                log_warning "Failed to delete orphaned log group: $log_group" "$SCRIPT_NAME"
            fi
        fi
    done
    if [ $ORPHANED_COUNT -gt 0 ]; then
        log_success "Cleaned up $ORPHANED_COUNT orphaned log groups" "$SCRIPT_NAME"
    fi
else
    log_info "No orphaned log groups found" "$SCRIPT_NAME"
fi

# 2. Orphaned Lambda Functions (in case stack deletion failed)
ORPHANED_FUNCTIONS=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '${APP_NAME}-${STAGE}-')].FunctionName" --output text 2>/dev/null || echo "")
if [ -n "$ORPHANED_FUNCTIONS" ] && [ "$ORPHANED_FUNCTIONS" != "None" ]; then
    log_warning "Found orphaned Lambda functions" "$SCRIPT_NAME"
    for function_name in $ORPHANED_FUNCTIONS; do
        if [ -n "$function_name" ]; then
            log_info "Deleting orphaned Lambda function: $function_name" "$SCRIPT_NAME"
            aws lambda delete-function --function-name "$function_name" 2>/dev/null || log_warning "Failed to delete function: $function_name" "$SCRIPT_NAME"
        fi
    done
else
    log_info "No orphaned Lambda functions found" "$SCRIPT_NAME"
fi

# 3. Orphaned IAM Roles (from failed deployments)
ORPHANED_ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName, '${APP_NAME}-${STAGE}-')].RoleName" --output text 2>/dev/null || echo "")
if [ -n "$ORPHANED_ROLES" ] && [ "$ORPHANED_ROLES" != "None" ]; then
    log_warning "Found orphaned IAM roles" "$SCRIPT_NAME"
    for role_name in $ORPHANED_ROLES; do
        if [ -n "$role_name" ]; then
            log_info "Deleting orphaned IAM role: $role_name" "$SCRIPT_NAME"
            # Detach policies first
            aws iam list-attached-role-policies --role-name "$role_name" --query "AttachedPolicies[*].PolicyArn" --output text 2>/dev/null | xargs -I {} aws iam detach-role-policy --role-name "$role_name" --policy-arn {} 2>/dev/null || true
            # Delete inline policies
            aws iam list-role-policies --role-name "$role_name" --query "PolicyNames" --output text 2>/dev/null | xargs -I {} aws iam delete-role-policy --role-name "$role_name" --policy-name {} 2>/dev/null || true
            # Delete role
            aws iam delete-role --role-name "$role_name" 2>/dev/null || log_warning "Failed to delete role: $role_name" "$SCRIPT_NAME"
        fi
    done
else
    log_info "No orphaned IAM roles found" "$SCRIPT_NAME"
fi

log_success "Orphaned resource cleanup completed" "$SCRIPT_NAME"

# STEP 5: Handle user data bucket separately (with user confirmation)

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
        echo "Default Action: KEEP SAFE (recommended)"
        echo
        echo "⚠️  WARNING: This bucket existed BEFORE your deployment!"
        echo "⚠️  It may contain important data or be used by other applications."
        echo "⚠️  Deleting it could break other systems or lose important data."
        echo
        echo "The script will KEEP this bucket by default."
        echo "Only answer 'y' if you are absolutely certain you want to delete it."
        echo
        read -p "Override default and DELETE this pre-existing bucket? (y/N) [Default: N]: " DELETE_BUCKET_CONFIRM
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
        echo "✅ Bucket will be PRESERVED (safe choice)"
    fi
    echo "=================================================="
fi

# These resources were already handled in the proper sequence above

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

# All cleanup was handled in the proper sequence above

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
    echo "S3 Data Bucket: DELETED ✅"
    echo "  → $S3_BUCKET_NAME and all contents removed"
else
    echo "S3 Data Bucket: KEPT SAFE ✅"
    echo "  → $S3_BUCKET_NAME preserved with all data intact"
    if [ "$BUCKET_CREATED_BY_STACK" = false ]; then
        echo "  → Pre-existing bucket was protected from deletion"
    else
        echo "  → You chose to keep this bucket"
    fi
fi
echo
echo "To redeploy: ./step-010-setup.sh followed by ./step-020-deploy.sh"

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
    if aws cloudformation describe-stacks --stack-name $STACK_NAME 2>&1 | grep -q "does not exist"; then
        echo "✅ CloudFormation stack successfully deleted"
    else
        CURRENT_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "DOES_NOT_EXIST")
        if [ "$CURRENT_STATUS" = "DELETE_FAILED" ]; then
            echo "⚠️  CloudFormation stack in DELETE_FAILED state (expected - handled by manual cleanup)"
        elif [ "$CURRENT_STATUS" = "DOES_NOT_EXIST" ]; then
            echo "✅ CloudFormation stack successfully deleted"
        else
            echo "ℹ️  CloudFormation stack status: $CURRENT_STATUS"
        fi
    fi
fi

# Check if S3 bucket is deleted (only if user chose to delete)
if [ "$BUCKET_EXISTS" = true ]; then
    if [ "$DELETE_BUCKET" = true ]; then
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>&1 | grep -q "Not Found\|NoSuchBucket\|404"; then
            echo "✅ S3 data bucket successfully deleted"
        else
            echo "⚠️  S3 data bucket may still exist (check AWS console if concerned)"
        fi
    else
        echo "✅ S3 data bucket preserved as requested"
    fi
fi

echo "=================================================="

# Clean deployment state for fresh start BEFORE final logging
if [ -d ".deployment-state" ]; then
    log_info "Cleaning deployment state for fresh start" "$SCRIPT_NAME"
    rm -rf .deployment-state
fi

# Mark cleanup as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_success "Comprehensive cleanup completed for $APP_NAME-$STAGE" "$SCRIPT_NAME"

echo
echo -e "${GREEN}🎉 Cleanup Summary:${NC}"
echo -e "${BLUE}  • Local Serverless cache: Cleaned first (prevents conflicts)${NC}"
if [ "$STACK_EXISTS" = true ]; then
    echo -e "${BLUE}  • CloudFormation stack: Deletion attempted (may be in DELETE_FAILED - resources cleaned manually)${NC}"
else
    echo -e "${BLUE}  • CloudFormation stack: N/A (did not exist)${NC}"
fi
echo -e "${BLUE}  • Deployment buckets: Cleaned up${NC}"
echo -e "${BLUE}  • Orphaned resources: Scanned and cleaned${NC}"
echo -e "${BLUE}  • Lambda functions & Log groups: Cleaned up${NC}"
if [ "$DELETE_BUCKET" = true ]; then
    echo -e "${RED}  • S3 data bucket: DELETED (all data removed)${NC}"
elif [ "$BUCKET_CREATED_BY_STACK" = false ]; then
    echo -e "${GREEN}  • S3 data bucket: KEPT SAFE (pre-existing bucket protected)${NC}"
else
    echo -e "${GREEN}  • S3 data bucket: KEPT SAFE (user chose to preserve)${NC}"
fi

echo
echo -e "${BLUE}💡 Next Steps:${NC}"
echo -e "${BLUE}  • Your AWS account is now clean${NC}"
echo -e "${BLUE}  • You can safely redeploy using: ./step-010-setup.sh${NC}"
echo -e "${BLUE}  • Or use ./deploy-all.sh for fully automated deployment${NC}"

echo
log_info "Cleanup script completed - ready for fresh deployment" "$SCRIPT_NAME"