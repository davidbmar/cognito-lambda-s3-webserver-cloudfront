#!/bin/bash
# step-020-deploy.sh - Deploy the CloudFront Cognito Serverless Application with OAC
# Prerequisites: step-015-validate.sh (recommended)
# Outputs: Deployed AWS infrastructure with CloudFormation stack

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-020-deploy"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-020-deploy.sh"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# Show step purpose
show_step_purpose "step-020-deploy.sh"

# Welcome banner
echo -e "${CYAN}=================================================="
echo -e "       CloudFront Cognito Serverless Application"
echo -e "              INFRASTRUCTURE DEPLOYMENT"
echo -e "==================================================${NC}"
echo
log_info "Starting infrastructure deployment" "$SCRIPT_NAME"

# Check if .env exists
if [ ! -f .env ]; then
    log_error ".env file not found. Please run step-010-setup.sh first." "$SCRIPT_NAME"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$APP_NAME" ] || [ -z "$STAGE" ] || [ -z "$S3_BUCKET_NAME" ] || [ -z "$COGNITO_DOMAIN" ]; then
    log_error "Missing required variables in .env file. Please run step-010-setup.sh again." "$SCRIPT_NAME"
    exit 1
fi
log_success "Environment variables validated" "$SCRIPT_NAME"

# Check for AWS CLI configuration
if ! check_aws_credentials "$SCRIPT_NAME"; then
    exit 1
fi

# Check if we need to install dependencies
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    
    # Create or update package.json if it doesn't exist or lacks required dependencies
    if [ ! -f "package.json" ]; then
        echo "Creating package.json..."
        cat > package.json << EOL
{
  "name": "${APP_NAME}",
  "version": "1.0.0",
  "description": "CloudFront Cognito Serverless Application",
  "main": "index.js",
  "scripts": {
    "deploy": "serverless deploy",
    "remove": "serverless remove"
  },
  "devDependencies": {
    "serverless": "^3.30.1"
  },
  "dependencies": {
    "aws-sdk": "^2.1423.0"
  }
}
EOL
    else
        # Update package.json to fix dependency issues
        echo "Updating package.json to fix dependency conflicts..."
        # This ensures serverless-offline is compatible with serverless
        if grep -q "serverless-offline" package.json; then
            if grep -q "serverless.*4" package.json; then
                # If serverless v4, ensure offline is compatible
                sed -i.bak 's/"serverless-offline": "[^"]*"/"serverless-offline": "^14.0.0"/g' package.json
            else
                # If serverless v3, ensure offline is compatible
                sed -i.bak 's/"serverless-offline": "[^"]*"/"serverless-offline": "^12.0.4"/g' package.json
            fi
        fi
    fi
    
    # Install dependencies with legacy peer deps to avoid conflicts
    npm install --legacy-peer-deps
fi

# Create or update serverless.yml to use Origin Access Control
# Create serverless.yml from template with proper substitutions
echo "📝 Creating serverless.yml from template..."
if [ ! -f serverless.yml.template ]; then
    echo "❌ serverless.yml.template not found!"
    exit 1
fi

# Check if S3 bucket already exists
echo "🔍 Checking if S3 bucket $S3_BUCKET_NAME already exists..."
BUCKET_EXISTS=false
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
    echo "✅ S3 bucket $S3_BUCKET_NAME already exists"
    BUCKET_EXISTS=true
else
    echo "🆕 S3 bucket $S3_BUCKET_NAME does not exist - will be created"
fi

# Copy template to working file
cp serverless.yml.template serverless.yml

# Replace environment variable placeholders with actual values
sed -i.bak "s/\${env:APP_NAME, 'cloudfront-cognito-app'}/$APP_NAME/g" serverless.yml
sed -i.bak "s/\${env:REGION, 'us-east-2'}/$REGION/g" serverless.yml
sed -i.bak "s/\${env:S3_BUCKET_NAME, '\${self:service}-website-\${sls:stage}-\${aws:accountId}'}/$S3_BUCKET_NAME/g" serverless.yml

# If bucket exists, handle references differently
if [ "$BUCKET_EXISTS" = true ]; then
    echo "📝 Modifying serverless.yml to use existing bucket..."
    
    # Remove the WebsiteBucket resource section
    sed -i.bak2 '/# S3 bucket for website hosting with public access/,/# Cognito user pool/{/# Cognito user pool/!d;}' serverless.yml
    
    # Also remove the WebsiteBucketPolicy since it depends on WebsiteBucket
    sed -i.bak8 '/# Bucket policy for CloudFront OAC access/,/Outputs:/{/Outputs:/!d;}' serverless.yml
    
    # Replace all references to !Ref WebsiteBucket with the actual bucket name
    sed -i.bak3 "s/!Ref WebsiteBucket/$S3_BUCKET_NAME/g" serverless.yml
    
    # Replace all references to !GetAtt WebsiteBucket with appropriate values
    sed -i.bak4 "s/!GetAtt WebsiteBucket\.RegionalDomainName/${S3_BUCKET_NAME}.s3.${REGION}.amazonaws.com/g" serverless.yml
    sed -i.bak5 "s/!GetAtt WebsiteBucket\.WebsiteURL/http:\/\/${S3_BUCKET_NAME}.s3-website-${REGION}.amazonaws.com/g" serverless.yml
    
    # Replace references to #{WebsiteBucket} in IAM policies
    sed -i.bak6 "s/#{WebsiteBucket}/$S3_BUCKET_NAME/g" serverless.yml
    
    # Replace ${WebsiteBucket} references
    sed -i.bak7 "s/\${WebsiteBucket}/$S3_BUCKET_NAME/g" serverless.yml
fi

echo "✅ serverless.yml created from template"


# Now replace the placeholders with the actual values
sed -i.bak "s/APP_NAME_PLACEHOLDER/$APP_NAME/g" serverless.yml
sed -i.bak "s/REGION_PLACEHOLDER/$REGION/g" serverless.yml
sed -i.bak "s/S3_BUCKET_NAME_PLACEHOLDER/$S3_BUCKET_NAME/g" serverless.yml
sed -i.bak "s/STAGE_PLACEHOLDER/$STAGE/g" serverless.yml

# Deploy the serverless application with error handling
echo "🚀 Deploying serverless application..."
if ! npx serverless deploy --stage $STAGE 2>&1 | tee /tmp/deploy-output.log; then
    log_error "Deployment failed" "$SCRIPT_NAME"
    
    # Check for specific deployment bucket error
    if grep -q "Deployment bucket has been removed manually" /tmp/deploy-output.log; then
        log_warning "Detected deployment bucket conflict - attempting automatic recovery" "$SCRIPT_NAME"
        
        # Try to remove the service first
        log_info "Running serverless remove to clean up state" "$SCRIPT_NAME"
        npx serverless remove --stage $STAGE 2>/dev/null || true
        
        # Clean up .serverless directory
        log_info "Cleaning .serverless directory" "$SCRIPT_NAME"
        rm -rf .serverless
        
        # Retry deployment
        log_info "Retrying deployment with clean state" "$SCRIPT_NAME"
        if ! npx serverless deploy --stage $STAGE; then
            log_error "Deployment failed after automatic recovery attempt" "$SCRIPT_NAME"
            echo -e "${YELLOW}💡 Try running: ./step-990-cleanup.sh for complete cleanup${NC}"
            exit 1
        fi
        log_success "Deployment succeeded after automatic recovery" "$SCRIPT_NAME"
    else
        # Show last few lines of error for other failures
        echo -e "${RED}Deployment failed with error:${NC}"
        tail -20 /tmp/deploy-output.log
        exit 1
    fi
fi

# Clean up temp file
rm -f /tmp/deploy-output.log

# If bucket already existed, we need to manually add the bucket policy for CloudFront
if [ "$BUCKET_EXISTS" = true ]; then
    echo "📝 Adding bucket policy for CloudFront access..."
    
    # Get the CloudFront distribution ID from the stack outputs
    STACK_NAME="${APP_NAME}-${STAGE}"
    CF_DISTRIBUTION_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" --output text 2>/dev/null || echo "")
    
    if [ -z "$CF_DISTRIBUTION_ID" ]; then
        # Try to get it from the CloudFront distribution list
        CF_DISTRIBUTION_ID=$(aws cloudformation describe-stack-resources --stack-name $STACK_NAME --query "StackResources[?ResourceType=='AWS::CloudFront::Distribution'].PhysicalResourceId" --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$CF_DISTRIBUTION_ID" ] && [ "$CF_DISTRIBUTION_ID" != "None" ]; then
        # Create bucket policy JSON
        cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/${CF_DISTRIBUTION_ID}"
                }
            }
        }
    ]
}
EOF
        
        # Apply the bucket policy
        aws s3api put-bucket-policy --bucket $S3_BUCKET_NAME --policy file:///tmp/bucket-policy.json
        echo "✅ Bucket policy added for CloudFront access"
        
        # Clean up
        rm -f /tmp/bucket-policy.json
        
        echo "✅ S3 permissions for authenticated users handled by CloudFormation"
    else
        echo "⚠️ Could not determine CloudFront distribution ID. You may need to manually add the bucket policy."
    fi
fi

# Get the outputs from the deployment (add this section around line 200)
echo "📊 Retrieving deployment outputs..."
export AWS_PAGER=""
STACK_NAME="${APP_NAME}-${STAGE}"

USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)
IDENTITY_POOL_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='IdentityPoolId'].OutputValue" --output text)
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text)
CLOUDFRONT_API_ENDPOINT="${CLOUDFRONT_URL}/api/data"
WEBSITE_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" --output text)
CLOUDFRONT_URL=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='CloudFrontURL'].OutputValue" --output text)

echo "📝 Updating Cognito User Pool Client..."
aws cognito-idp update-user-pool-client \
  --user-pool-id $USER_POOL_ID \
  --client-id $USER_POOL_CLIENT_ID \
  --callback-urls "${CLOUDFRONT_URL}/callback.html" \
  --logout-urls "${CLOUDFRONT_URL}/index.html" \
  --allowed-o-auth-flows "code" "implicit" \
  --allowed-o-auth-scopes "email" "openid" "profile" \
  --supported-identity-providers "COGNITO" \
  --allowed-o-auth-flows-user-pool-client

# Check and configure Cognito domain
log_info "Setting up Cognito domain" "$SCRIPT_NAME"
echo "🔄 Setting up Cognito domain..."

# Check if required variables are set
if [ -z "$USER_POOL_ID" ] || [ -z "$COGNITO_DOMAIN" ]; then
    log_error "Missing required variables: USER_POOL_ID or COGNITO_DOMAIN" "$SCRIPT_NAME"
    exit 1
fi

# Check if the domain already exists
log_info "Checking existing Cognito domain for User Pool: $USER_POOL_ID" "$SCRIPT_NAME"
echo "🔍 Checking if Cognito domain already exists for user pool..."

DOMAIN_CHECK=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID 2>/dev/null)
if [ $? -ne 0 ]; then
    log_error "Failed to describe user pool $USER_POOL_ID" "$SCRIPT_NAME"
    echo "💡 Check that the user pool exists and you have permissions"
    exit 1
fi
log_success "Successfully retrieved user pool details" "$SCRIPT_NAME"

# Use jq for more reliable JSON parsing instead of grep
if command -v jq >/dev/null 2>&1; then
    EXISTING_DOMAIN=$(echo "$DOMAIN_CHECK" | jq -r '.UserPool.Domain // empty' 2>/dev/null)
    log_info "Using jq to parse domain: '$EXISTING_DOMAIN'" "$SCRIPT_NAME"
else
    # Fallback to grep method with timeout
    log_info "jq not available, using grep fallback" "$SCRIPT_NAME"
    EXISTING_DOMAIN=$(echo "$DOMAIN_CHECK" | timeout 10s grep -A 3 "Domain" | grep ":" | cut -d'"' -f4 2>/dev/null || echo "")
fi

log_info "Parsed existing domain result: '$EXISTING_DOMAIN'" "$SCRIPT_NAME"

if [ -z "$EXISTING_DOMAIN" ] || [ "$EXISTING_DOMAIN" == "null" ] || [ "$EXISTING_DOMAIN" == "None" ]; then
    log_info "No existing domain found, creating new Cognito domain: $COGNITO_DOMAIN" "$SCRIPT_NAME"
    echo "🆕 Creating new Cognito domain: $COGNITO_DOMAIN"
    
    # Create domain with timeout and better error handling
    DOMAIN_CREATE_OUTPUT=$(timeout 30s aws cognito-idp create-user-pool-domain \
      --domain $COGNITO_DOMAIN \
      --user-pool-id $USER_POOL_ID 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create Cognito domain '$COGNITO_DOMAIN'" "$SCRIPT_NAME"
        echo "Error details: $DOMAIN_CREATE_OUTPUT"
        if echo "$DOMAIN_CREATE_OUTPUT" | grep -q "InvalidParameterException"; then
            echo "💡 Domain name '$COGNITO_DOMAIN' may be invalid or already taken globally"
            echo "💡 Try using a different COGNITO_DOMAIN in your .env file"
        elif echo "$DOMAIN_CREATE_OUTPUT" | grep -q "LimitExceededException"; then
            echo "💡 Domain limit exceeded. Delete unused domains or use a different AWS account"
        else
            echo "💡 Check AWS permissions and domain name requirements"
        fi
        exit 1
    fi
    log_success "Successfully created Cognito domain: $COGNITO_DOMAIN" "$SCRIPT_NAME"
    echo "✅ Cognito domain created successfully: $COGNITO_DOMAIN"
else
    log_info "Using existing Cognito domain: $EXISTING_DOMAIN" "$SCRIPT_NAME"
    echo "✅ Using existing Cognito domain: $EXISTING_DOMAIN"
    COGNITO_DOMAIN=$EXISTING_DOMAIN
fi

# Verify .env file exists before updating
if [ ! -f .env ]; then
    log_error ".env file not found. Cannot update deployment outputs." "$SCRIPT_NAME"
    echo "💡 Run step-010-setup.sh to create the .env file"
    exit 1
fi

# Update .env file with the deployment outputs (add CloudFront API endpoint)
log_info "Updating .env file with deployment outputs" "$SCRIPT_NAME"
echo "📝 Updating .env file with deployment outputs..."
sed -i.bak "s|API_ENDPOINT=.*$|API_ENDPOINT=$API_ENDPOINT|g" .env
sed -i.bak "s|USER_POOL_ID=.*$|USER_POOL_ID=$USER_POOL_ID|g" .env
sed -i.bak "s|USER_POOL_CLIENT_ID=.*$|USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID|g" .env
sed -i.bak "s|IDENTITY_POOL_ID=.*$|IDENTITY_POOL_ID=$IDENTITY_POOL_ID|g" .env
sed -i.bak "s|CLOUDFRONT_URL=.*$|CLOUDFRONT_URL=$CLOUDFRONT_URL|g" .env
sed -i.bak "s|COGNITO_DOMAIN=.*$|COGNITO_DOMAIN=$COGNITO_DOMAIN|g" .env
sed -i.bak "s|WEBSITE_URL=.*$|WEBSITE_URL=$WEBSITE_URL|g" .env

# Add CloudFront API endpoint to .env if it doesn't exist
if ! grep -q "CLOUDFRONT_API_ENDPOINT" .env; then
    echo "CLOUDFRONT_API_ENDPOINT=$CLOUDFRONT_API_ENDPOINT" >> .env
else
    sed -i.bak "s|CLOUDFRONT_API_ENDPOINT=.*$|CLOUDFRONT_API_ENDPOINT=$CLOUDFRONT_API_ENDPOINT|g" .env
fi

# Add Audio API endpoint to .env if it doesn't exist
AUDIO_API_ENDPOINT="${CLOUDFRONT_URL}/api/audio"
if ! grep -q "AUDIO_API_ENDPOINT" .env; then
    echo "AUDIO_API_ENDPOINT=$AUDIO_API_ENDPOINT" >> .env
else
    sed -i.bak "s|AUDIO_API_ENDPOINT=.*$|AUDIO_API_ENDPOINT=$AUDIO_API_ENDPOINT|g" .env
fi

# Update the app.js replacement section to use CloudFront API:
log_info "Creating app.js from template" "$SCRIPT_NAME"
echo "📝 Creating app.js from template..."

if [ ! -f web/app.js.template ]; then
    log_error "web/app.js.template not found!" "$SCRIPT_NAME"
    echo "❌ ERROR: app.js.template not found!"
    echo "💡 Make sure you're running this script from the project root directory"
    exit 1
fi

if ! cp web/app.js.template web/app.js; then
    log_error "Failed to create app.js from template" "$SCRIPT_NAME"
    exit 1
fi
log_success "app.js created from template" "$SCRIPT_NAME"
echo "✅ app.js created from template"

log_info "Updating app.js with deployment values" "$SCRIPT_NAME"
echo "📝 Updating app.js with deployment values..."

# Validate required variables before substitution
if [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ] || [ -z "$IDENTITY_POOL_ID" ] || [ -z "$CLOUDFRONT_URL" ] || [ -z "$COGNITO_DOMAIN" ]; then
    log_error "Missing required variables for app.js template substitution" "$SCRIPT_NAME"
    echo "USER_POOL_ID: $USER_POOL_ID"
    echo "USER_POOL_CLIENT_ID: $USER_POOL_CLIENT_ID"
    echo "IDENTITY_POOL_ID: $IDENTITY_POOL_ID"
    echo "CLOUDFRONT_URL: $CLOUDFRONT_URL"
    echo "COGNITO_DOMAIN: $COGNITO_DOMAIN"
    exit 1
fi

if [ -f web/app.js ]; then
    if ! sed -i.bak "s|YOUR_USER_POOL_ID|$USER_POOL_ID|g" web/app.js; then
        log_error "Failed to update USER_POOL_ID in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_USER_POOL_CLIENT_ID|$USER_POOL_CLIENT_ID|g" web/app.js; then
        log_error "Failed to update USER_POOL_CLIENT_ID in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_IDENTITY_POOL_ID|$IDENTITY_POOL_ID|g" web/app.js; then
        log_error "Failed to update IDENTITY_POOL_ID in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    # Use CloudFront API endpoint instead of direct API Gateway
    if ! sed -i.bak "s|YOUR_CLOUDFRONT_API_ENDPOINT|$CLOUDFRONT_API_ENDPOINT|g" web/app.js; then
        log_error "Failed to update CLOUDFRONT_API_ENDPOINT in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_CLOUDFRONT_S3_API_ENDPOINT|${CLOUDFRONT_URL}/api/s3/list|g" web/app.js; then
        log_error "Failed to update CLOUDFRONT_S3_API_ENDPOINT in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_API_ENDPOINT|$CLOUDFRONT_API_ENDPOINT|g" web/app.js; then
        log_error "Failed to update API_ENDPOINT in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_APP_URL|$CLOUDFRONT_URL|g" web/app.js; then
        log_error "Failed to update APP_URL in app.js" "$SCRIPT_NAME"
        exit 1
    fi
    if ! sed -i.bak "s|YOUR_COGNITO_DOMAIN_PREFIX|$COGNITO_DOMAIN|g" web/app.js; then
        log_error "Failed to update COGNITO_DOMAIN in app.js" "$SCRIPT_NAME"
        exit 1
    fi

    # Add large warning to the top of app.js
    WARNING="// WARNING: THIS FILE IS AUTO-GENERATED BY THE DEPLOYMENT SCRIPT.\n// DO NOT EDIT DIRECTLY AS YOUR CHANGES WILL BE OVERWRITTEN.\n// EDIT app.js.template INSTEAD.\n"
    if ! sed -i.bak "1s|^|$WARNING\n|" web/app.js; then
        log_error "Failed to add warning header to app.js" "$SCRIPT_NAME"
        exit 1
    fi
    log_success "app.js updated with deployment values" "$SCRIPT_NAME"
else
    log_error "app.js file could not be created or found!" "$SCRIPT_NAME"
    exit 1
fi

# Invoke the setIdentityPoolRoles function to ensure roles are properly set
log_info "Triggering setIdentityPoolRoles Lambda function" "$SCRIPT_NAME"
echo "⚙️ Triggering the setIdentityPoolRoles Lambda function..."
FUNCTION_NAME="${APP_NAME}-${STAGE}-setIdentityPoolRoles"

if aws lambda invoke --function-name $FUNCTION_NAME --invocation-type Event /dev/null 2>/dev/null; then
    log_success "setIdentityPoolRoles function invoked successfully" "$SCRIPT_NAME"
else
    log_warning "setIdentityPoolRoles function invocation failed, but continuing deployment" "$SCRIPT_NAME"
    echo "Function invocation failed, but continuing deployment"
fi

# Upload the website files to S3
log_info "Starting website files upload to S3" "$SCRIPT_NAME"
echo "📤 Uploading website files to S3..."

if ! aws s3 cp web/ s3://$S3_BUCKET_NAME/ --recursive; then
    log_error "Failed to upload website files to S3 bucket: $S3_BUCKET_NAME" "$SCRIPT_NAME"
    echo "💡 Check that the S3 bucket exists and you have write permissions"
    exit 1
fi
log_success "Website files uploaded successfully to S3" "$SCRIPT_NAME"

# Create a CloudFront invalidation
log_info "Creating CloudFront invalidation" "$SCRIPT_NAME"
echo "🔄 Creating CloudFront invalidation..."

if [ -z "$CLOUDFRONT_URL" ]; then
    log_error "CLOUDFRONT_URL is not set - cannot create invalidation" "$SCRIPT_NAME"
    exit 1
fi

DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$(echo $CLOUDFRONT_URL | sed 's|https://||')'].Id" --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    log_error "Failed to list CloudFront distributions" "$SCRIPT_NAME"
    exit 1
fi

if [ -n "$DISTRIBUTION_ID" ] && [ "$DISTRIBUTION_ID" != "None" ]; then
    if aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*" >/dev/null 2>&1; then
        log_success "Created CloudFront invalidation for all paths" "$SCRIPT_NAME"
        echo "✅ Created CloudFront invalidation for all paths"
    else
        log_warning "Failed to create CloudFront invalidation, but continuing" "$SCRIPT_NAME"
        echo "⚠️ Warning: Failed to create CloudFront invalidation"
    fi
else
    log_warning "Could not determine CloudFront distribution ID" "$SCRIPT_NAME"
    echo "⚠️ Warning: Could not determine CloudFront distribution ID"
fi

# Mark deployment as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

echo
log_success "Infrastructure deployment completed successfully!" "$SCRIPT_NAME"
echo
echo -e "${BLUE}🔗 Website URLs:${NC}"
echo -e "${GREEN}   CloudFront: $CLOUDFRONT_URL${NC}"
echo -e "${BLUE}   S3 Website: $WEBSITE_URL${NC}"
echo
echo -e "${BLUE}📋 Your application details:${NC}"
echo -e "${BLUE}   API Endpoint: $API_ENDPOINT${NC}"
echo -e "${BLUE}   User Pool ID: $USER_POOL_ID${NC}"
echo -e "${BLUE}   User Pool Client ID: $USER_POOL_CLIENT_ID${NC}"
echo -e "${BLUE}   Identity Pool ID: $IDENTITY_POOL_ID${NC}"
echo -e "${BLUE}   Cognito Domain: ${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com${NC}"
echo
echo -e "${YELLOW}⚠️ Note: It may take a few minutes for the CloudFront distribution to fully deploy.${NC}"
echo -e "${YELLOW}⚠️ IMPORTANT: Do not commit web/app.js to version control as it contains environment-specific values.${NC}"
echo -e "${YELLOW}   Only commit web/app.js.template and let the deployment script generate app.js during deployment.${NC}"

# Show next step
show_next_step "step-020-deploy.sh" "$(dirname "$0")"
