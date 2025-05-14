#!/bin/bash
set -e

# Deploy the serverless application
echo "Deploying serverless application..."
serverless deploy

# Get the outputs from the deployment
export AWS_PAGER=""
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)
IDENTITY_POOL_ID=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Outputs[?OutputKey=='IdentityPoolId'].OutputValue" --output text)
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text)
WEBSITE_URL=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" --output text)

# Update the app.js file with the correct values
echo "Updating app.js with deployment values..."
sed -i.bak "s|YOUR_USER_POOL_ID|$USER_POOL_ID|g" web/app.js
sed -i.bak "s|YOUR_USER_POOL_CLIENT_ID|$USER_POOL_CLIENT_ID|g" web/app.js
sed -i.bak "s|YOUR_IDENTITY_POOL_ID|$IDENTITY_POOL_ID|g" web/app.js
sed -i.bak "s|YOUR_API_ENDPOINT|$API_ENDPOINT|g" web/app.js

# Get the S3 bucket name
BUCKET_NAME=$(aws cloudformation describe-stacks --stack-name cognito-serverless-app-dev --query "Stacks[0].Resources[?LogicalResourceId=='WebsiteBucket'].PhysicalResourceId" --output text)
if [ -z "$BUCKET_NAME" ]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    BUCKET_NAME="cognito-serverless-app-website-dev-$ACCOUNT_ID"
fi

# Upload the website files to S3
echo "Uploading website files to S3..."
aws s3 cp web/ s3://$BUCKET_NAME/ --recursive

echo "Deployment complete!"
echo "Website URL: $WEBSITE_URL"
