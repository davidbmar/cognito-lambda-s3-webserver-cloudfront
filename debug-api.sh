#!/bin/bash
# debug-api.sh - Check if your API is working correctly

set -e

echo "🔍 API Debugging Script"
echo "======================="

# Load environment variables
if [ ! -f .env ]; then
    echo "❌ .env file not found"
    exit 1
fi

source .env

echo "📋 Current Configuration:"
echo "  App Name: $APP_NAME"
echo "  Stage: $STAGE"
echo "  CloudFront URL: $CLOUDFRONT_URL"
echo "  API Endpoint: $API_ENDPOINT"
echo

# Test 1: Check if CloudFormation stack was updated
echo "🔍 Test 1: Checking CloudFormation stack..."
STACK_NAME="${APP_NAME}-${STAGE}"
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].StackStatus" --output text)
echo "  Stack Status: $STACK_STATUS"

# Test 2: Get the actual API Gateway endpoint
echo
echo "🔍 Test 2: Getting actual API Gateway endpoints..."
API_ID=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text | cut -d'/' -f3 | cut -d'.' -f1)
echo "  API Gateway ID: $API_ID"

# List all paths in API Gateway
echo "  Available API paths:"
aws apigateway get-resources --rest-api-id $API_ID --query "items[*].{Path:pathPart,Methods:resourceMethods}" --output table

# Test 3: Test direct API Gateway call (without CloudFront)
echo
echo "🔍 Test 3: Testing direct API Gateway call..."
DIRECT_API_URL="https://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE}/api/data"
echo "  Direct API URL: $DIRECT_API_URL"

# Test without auth first to see what error we get
echo "  Testing without auth (expect 401):"
curl -s -w "Status: %{http_code}\n" "$DIRECT_API_URL" | head -3

# Test 4: Test CloudFront API call
echo
echo "🔍 Test 4: Testing CloudFront API call..."
CLOUDFRONT_API_URL="${CLOUDFRONT_URL}/api/data"
echo "  CloudFront API URL: $CLOUDFRONT_API_URL"
echo "  Testing without auth (should get same result as direct API):"
curl -s -w "Status: %{http_code}\n" "$CLOUDFRONT_API_URL" | head -3

# Test 5: Check CloudFront cache behaviors
echo
echo "🔍 Test 5: Checking CloudFront configuration..."
DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text)
echo "  Distribution ID: $DISTRIBUTION_ID"

if [ "$DISTRIBUTION_ID" != "None" ] && [ -n "$DISTRIBUTION_ID" ]; then
    echo "  Cache behaviors:"
    aws cloudfront get-distribution --id $DISTRIBUTION_ID --query "Distribution.DistributionConfig.CacheBehaviors.Items[*].{PathPattern:PathPattern,TargetOrigin:TargetOriginId}" --output table
else
    echo "  ❌ Could not find CloudFront distribution"
fi

echo
echo "📝 Recommendations:"
echo "1. If Test 3 shows API working but Test 4 doesn't, it's a CloudFront routing issue"
echo "2. If both tests fail with 404, the API path wasn't updated correctly"
echo "3. If you get 401 errors, the API is working but needs authentication"
echo "4. If you get HTML responses, CloudFront is serving error pages"
echo
echo "💡 If you're still getting HTML, try creating a CloudFront invalidation:"
echo "   aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths '/api/*'"
