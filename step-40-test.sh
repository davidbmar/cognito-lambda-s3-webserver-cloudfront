#!/bin/bash
# step-40-test.sh - Tests the deployed application
# Run this script after step-20-deploy.sh and step-30-create-user.sh

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "                 Test Script                     "
echo "=================================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-10-setup.sh and step-20-deploy.sh first."
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$CLOUDFRONT_URL" ] || [ -z "$USER_POOL_ID" ]; then
    echo "❌ Missing required variables in .env file. Please run step-20-deploy.sh first."
    exit 1
fi

echo "🔍 Testing application components..."

# Function to perform a URL check
check_url() {
    local url=$1
    local description=$2
    
    echo -n "  🔗 Testing $description ($url)... "
    
    # Use curl to check if the URL is accessible
    if curl -s --head "$url" | grep "200 OK\|200\|301\|302" > /dev/null; then
        echo "✅ Success!"
        return 0
    else
        echo "❌ Failed!"
        return 1
    fi
}

# Test CloudFront URL
if check_url "$CLOUDFRONT_URL" "CloudFront Distribution"; then
    CLOUDFRONT_OK=true
else
    CLOUDFRONT_OK=false
    echo "    ⚠️ CloudFront distribution may not be fully deployed yet. It can take 5-10 minutes."
fi

# Test S3 bucket website URL
if [ -n "$WEBSITE_URL" ]; then
    if check_url "$WEBSITE_URL" "S3 Website"; then
        S3_OK=true
    else
        S3_OK=false
        echo "    ⚠️ S3 website may not be properly configured."
    fi
else
    S3_OK=false
    echo "    ⚠️ S3 website URL not found in .env file."
fi

# Test API endpoint
if [ -n "$API_ENDPOINT" ]; then
    if check_url "${API_ENDPOINT%/data}" "API Gateway"; then
        API_OK=true
    else
        API_OK=false
        echo "    ⚠️ API Gateway may not be properly configured or requires authentication."
    fi
else
    API_OK=false
    echo "    ⚠️ API endpoint not found in .env file."
fi

# Test Cognito domain
if [ -n "$COGNITO_DOMAIN" ] && [ -n "$REGION" ]; then
    COGNITO_URL="https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
    if check_url "$COGNITO_URL" "Cognito Domain"; then
        COGNITO_OK=true
    else
        COGNITO_OK=false
        echo "    ⚠️ Cognito domain may not be properly configured."
    fi
else
    COGNITO_OK=false
    echo "    ⚠️ Cognito domain or region not found in .env file."
fi

# Check if users exist in the Cognito User Pool
echo -n "  👤 Checking for users in Cognito User Pool... "
if [ -n "$USER_POOL_ID" ]; then
    USER_COUNT=$(aws cognito-idp list-users --user-pool-id $USER_POOL_ID --query "length(Users)" --output text)
    
    if [ "$USER_COUNT" -gt 0 ]; then
        echo "✅ Found $USER_COUNT user(s)!"
        USERS_OK=true
    else
        echo "⚠️ No users found. Run ./step-30-create-user.sh to create a test user."
        USERS_OK=false
    fi
else
    echo "❌ User Pool ID not found in .env file."
    USERS_OK=false
fi

# Test CloudFront error responses for SPA routing
if [ "$CLOUDFRONT_OK" = true ]; then
    echo -n "  🌐 Testing CloudFront SPA routing... "
    
    # Use curl to check if a deep link returns index.html
    if curl -s "$CLOUDFRONT_URL/non-existent-page" | grep "<title>" > /dev/null; then
        echo "✅ Success!"
        SPA_OK=true
    else
        echo "❌ Failed! SPA routing may not be configured correctly."
        SPA_OK=false
    fi
else
    SPA_OK=false
fi

# Calculate overall status
if [ "$CLOUDFRONT_OK" = true ] && [ "$API_OK" = true ] && [ "$COGNITO_OK" = true ] && [ "$USERS_OK" = true ] && [ "$SPA_OK" = true ]; then
    OVERALL_STATUS="✅ PASSED"
    HELP_MESSAGE="You can now use the application by visiting: $CLOUDFRONT_URL"
else
    OVERALL_STATUS="⚠️ PARTIAL"
    HELP_MESSAGE="Some components may need attention. See details above."
fi

# Print summary
echo
echo "📋 Test Summary:"
echo "   CloudFront Distribution: $([ "$CLOUDFRONT_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo "   S3 Website: $([ "$S3_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo "   API Gateway: $([ "$API_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo "   Cognito Domain: $([ "$COGNITO_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo "   Users in Cognito: $([ "$USERS_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo "   SPA Routing: $([ "$SPA_OK" = true ] && echo "✅ OK" || echo "❌ Issue")"
echo
echo "🏁 Overall Status: $OVERALL_STATUS"
echo
echo "💡 $HELP_MESSAGE"
echo
echo "👉 For the best experience, test the application in a web browser: $CLOUDFRONT_URL"
echo "=================================================="
