#!/bin/bash
# step-22-update-cognito-client.sh - Updates the Cognito User Pool Client to support implicit flow
# Run this script after step-20-deploy.sh

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "        Cognito Implicit Flow Configuration      "
echo "=================================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-20-deploy.sh first."
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ] || [ -z "$CLOUDFRONT_URL" ]; then
    echo "❌ Missing required variables in .env file. Please run step-20-deploy.sh first."
    exit 1
fi

echo "🔄 Updating Cognito User Pool Client to support implicit flow..."

aws cognito-idp update-user-pool-client \
  --user-pool-id "$USER_POOL_ID" \
  --client-id "$USER_POOL_CLIENT_ID" \
  --callback-urls "${CLOUDFRONT_URL}/callback.html" \
  --logout-urls "${CLOUDFRONT_URL}/index.html" \
  --allowed-o-auth-flows "implicit" "code" \
  --allowed-o-auth-scopes "email" "openid" "profile" \
  --allowed-o-auth-flows-user-pool-client \
  --supported-identity-providers "COGNITO"

echo "✅ Cognito User Pool Client updated successfully to use implicit flow!"
echo
echo "You can now test the authentication flow by visiting your CloudFront URL:"
echo "$CLOUDFRONT_URL"
echo
echo "Next steps:"
echo "1. Run './step-30-create-user.sh' to create a test user if you haven't already"
echo "2. Run './step-40-test.sh' to test your application"
echo "=================================================="
