#!/bin/bash
set -e

# Deploy the serverless application
echo "Deploying serverless application..."
serverless deploy

# Get the outputs from the deployment
export AWS_PAGER=""
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name cloudfront-cognito-app-dev --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name cloudfront-cognito-app-dev --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)
IDENTITY_POOL_ID=$(aws cloudformation describe-stacks --stack-name cloudfront-cognito-app-dev --query "Stacks[0].Outputs[?OutputKey=='IdentityPoolId'].OutputValue" --output text)
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name cloudfront-cognito-app-dev --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text)
WEBSITE_URL=$(aws cloudformation describe-stacks --stack-name cloudfront-cognito-app-dev --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" --output text)

# Update the app.js file with the correct values
echo "Updating app.js with deployment values..."
sed -i.bak "s|YOUR_USER_POOL_ID|$USER_POOL_ID|g" web/app.js
sed -i.bak "s|YOUR_USER_POOL_CLIENT_ID|$USER_POOL_CLIENT_ID|g" web/app.js
sed -i.bak "s|YOUR_IDENTITY_POOL_ID|$IDENTITY_POOL_ID|g" web/app.js
sed -i.bak "s|YOUR_API_ENDPOINT|$API_ENDPOINT|g" web/app.js
sed -i.bak "s|http://localhost:8080|$WEBSITE_URL|g" web/app.js

# Get the S3 bucket name
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="cloudfront-cognito-app-website-dev-$ACCOUNT_ID"

# Invoke the setIdentityPoolRoles function to ensure roles are properly set
echo "Triggering the setIdentityPoolRoles Lambda function..."
FUNCTION_NAME="cloudfront-cognito-app-dev-setIdentityPoolRoles"
aws lambda invoke --function-name $FUNCTION_NAME --invocation-type Event /dev/null || echo "Function invocation failed, but continuing deployment"

# Upload the website files to S3
echo "Uploading website files to S3..."
aws s3 cp web/ s3://$BUCKET_NAME/ --recursive

echo "Deployment complete!"
echo "Website URL: $WEBSITE_URL"
echo "API Endpoint: $API_ENDPOINT"
echo "User Pool ID: $USER_POOL_ID"
echo "User Pool Client ID: $USER_POOL_CLIENT_ID"
echo "Identity Pool ID: $IDENTITY_POOL_ID"

echo "⚠️ Note: It may take a few minutes for the CloudFront distribution to deploy."
echo "⚠️ Once deployed, you may need to create a user in the Cognito User Pool to test the authentication."
