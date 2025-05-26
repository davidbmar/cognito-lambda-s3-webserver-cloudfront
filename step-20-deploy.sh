#!/bin/bash
# step-20-deploy.sh - Deploy the CloudFront Cognito Serverless Application with OAC
# Run this script after step-10-setup.sh

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "              Deployment Script                  "
echo "=================================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-10-setup.sh first."
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$APP_NAME" ] || [ -z "$STAGE" ] || [ -z "$S3_BUCKET_NAME" ] || [ -z "$COGNITO_DOMAIN" ]; then
    echo "❌ Missing required variables in .env file. Please run step-10-setup.sh again."
    exit 1
fi

# Check for AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured properly. Please run 'aws configure' first."
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

# Copy template to working file
cp serverless.yml.template serverless.yml

# Replace environment variable placeholders with actual values
sed -i.bak "s/\${env:APP_NAME, 'cloudfront-cognito-app'}/$APP_NAME/g" serverless.yml
sed -i.bak "s/\${env:REGION, 'us-east-2'}/$REGION/g" serverless.yml
sed -i.bak "s/\${env:S3_BUCKET_NAME, '\${self:service}-website-\${sls:stage}-\${aws:accountId}'}/$S3_BUCKET_NAME/g" serverless.yml

echo "✅ serverless.yml created from template"


# Now replace the placeholders with the actual values
sed -i.bak "s/APP_NAME_PLACEHOLDER/$APP_NAME/g" serverless.yml
sed -i.bak "s/REGION_PLACEHOLDER/$REGION/g" serverless.yml
sed -i.bak "s/S3_BUCKET_NAME_PLACEHOLDER/$S3_BUCKET_NAME/g" serverless.yml
sed -i.bak "s/STAGE_PLACEHOLDER/$STAGE/g" serverless.yml

# Deploy the serverless application
echo "🚀 Deploying serverless application..."
npx serverless deploy --stage $STAGE

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
echo "🔄 Setting up Cognito domain..."
# Check if the domain already exists
DOMAIN_CHECK=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID)
EXISTING_DOMAIN=$(echo "$DOMAIN_CHECK" | grep -A 3 "Domain" | grep ":" | cut -d'"' -f4)

if [ -z "$EXISTING_DOMAIN" ] || [ "$EXISTING_DOMAIN" == "null" ]; then
    echo "🆕 Creating new Cognito domain: $COGNITO_DOMAIN"
    aws cognito-idp create-user-pool-domain \
      --domain $COGNITO_DOMAIN \
      --user-pool-id $USER_POOL_ID
else
    echo "✅ Using existing Cognito domain: $EXISTING_DOMAIN"
    COGNITO_DOMAIN=$EXISTING_DOMAIN
fi


# Update .env file with the deployment outputs (add CloudFront API endpoint)
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

# Update the app.js replacement section to use CloudFront API:
echo "📝 Creating app.js from template..."
if [ -f web/app.js.template ]; then
    cp web/app.js.template web/app.js
    echo "✅ app.js created from template"
else
    echo "❌ ERROR: app.js.template not found!"
    exit 1
fi

echo "📝 Updating app.js with deployment values..."
if [ -f web/app.js ]; then
    sed -i.bak "s|YOUR_USER_POOL_ID|$USER_POOL_ID|g" web/app.js
    sed -i.bak "s|YOUR_USER_POOL_CLIENT_ID|$USER_POOL_CLIENT_ID|g" web/app.js
    sed -i.bak "s|YOUR_IDENTITY_POOL_ID|$IDENTITY_POOL_ID|g" web/app.js
    # Use CloudFront API endpoint instead of direct API Gateway
    sed -i.bak "s|YOUR_CLOUDFRONT_API_ENDPOINT|$CLOUDFRONT_API_ENDPOINT|g" web/app.js
    sed -i.bak "s|YOUR_CLOUDFRONT_S3_API_ENDPOINT|${CLOUDFRONT_URL}/api/s3/list|g" web/app.js
    sed -i.bak "s|YOUR_API_ENDPOINT|$CLOUDFRONT_API_ENDPOINT|g" web/app.js
    sed -i.bak "s|YOUR_APP_URL|$CLOUDFRONT_URL|g" web/app.js
    sed -i.bak "s|YOUR_COGNITO_DOMAIN_PREFIX|$COGNITO_DOMAIN|g" web/app.js

    # Add large warning to the top of app.js
    WARNING="// WARNING: THIS FILE IS AUTO-GENERATED BY THE DEPLOYMENT SCRIPT.\n// DO NOT EDIT DIRECTLY AS YOUR CHANGES WILL BE OVERWRITTEN.\n// EDIT app.js.template INSTEAD.\n"
    sed -i.bak "1s|^|$WARNING\n|" web/app.js
else
    echo "❌ ERROR: app.js file could not be created or found!"
    exit 1
fi

# Invoke the setIdentityPoolRoles function to ensure roles are properly set
echo "⚙️ Triggering the setIdentityPoolRoles Lambda function..."
FUNCTION_NAME="${APP_NAME}-${STAGE}-setIdentityPoolRoles"
aws lambda invoke --function-name $FUNCTION_NAME --invocation-type Event /dev/null || echo "Function invocation failed, but continuing deployment"

# Upload the website files to S3
echo "📤 Uploading website files to S3..."
aws s3 cp web/ s3://$S3_BUCKET_NAME/ --recursive

# Create a CloudFront invalidation
echo "🔄 Creating CloudFront invalidation..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?DomainName=='$(echo $CLOUDFRONT_URL | sed 's|https://||')'].Id" --output text)
if [ -n "$DISTRIBUTION_ID" ]; then
    aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
    echo "✅ Created CloudFront invalidation for all paths"
else
    echo "⚠️ Warning: Could not determine CloudFront distribution ID"
fi

echo
echo "✅ Deployment completed successfully!"
echo
echo "🔗 Website URLs:"
echo "   CloudFront: $CLOUDFRONT_URL"
echo "   S3 Website: $WEBSITE_URL"
echo
echo "📋 Your application details:"
echo "   API Endpoint: $API_ENDPOINT"
echo "   User Pool ID: $USER_POOL_ID"
echo "   User Pool Client ID: $USER_POOL_CLIENT_ID"
echo "   Identity Pool ID: $IDENTITY_POOL_ID"
echo "   Cognito Domain: ${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
echo
echo "⚠️ Note: It may take a few minutes for the CloudFront distribution to fully deploy."
echo "⚠️ You need to create a user in the Cognito User Pool to test the authentication."
echo "   Run './step-30-create-user.sh' to create a test user."
echo
echo "⚠️ IMPORTANT: Do not commit web/app.js to version control as it contains environment-specific values."
echo "   Only commit web/app.js.template and let the deployment script generate app.js during deployment."
echo "=================================================="
