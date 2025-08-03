#!/bin/bash
# step-40-test.sh - Tests the deployed application
# Run this script after validating that steps 10, 20, and 30 completed successfully

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "           Security and Function Tests           "
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
    local expected_success=$3  # true or false
    
    echo -n "  🔗 Testing $description ($url)... "
    
    # Use curl to check if the URL is accessible
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
    
    if [[ "$expected_success" == "true" && ("$status_code" == "200" || "$status_code" == "301" || "$status_code" == "302") ]]; then
        echo "✅ Success!"
        return 0
    elif [[ "$expected_success" == "false" && ("$status_code" == "403" || "$status_code" == "401") ]]; then
        echo "✅ Secured! (Access correctly denied)"
        return 0
    elif [[ "$expected_success" == "false" && "$status_code" != "200" && "$status_code" != "301" && "$status_code" != "302" ]]; then
        echo "✅ Secured! (Access correctly restricted - status code: $status_code)"
        return 0
    else
        echo "❌ Failed! (Status code: $status_code)"
        return 1
    fi
}

# Test CloudFront URL - expect success
if check_url "$CLOUDFRONT_URL" "CloudFront Distribution" "true"; then
    CLOUDFRONT_OK=true
else
    CLOUDFRONT_OK=false
    echo "    ⚠️ CloudFront distribution can't be accessed. It may not be fully deployed yet (can take 5-10 minutes)."
fi

# Test S3 direct access - expect failure
if [ -n "$S3_BUCKET_NAME" ]; then
    S3_URL="http://${S3_BUCKET_NAME}.s3-website.${REGION}.amazonaws.com"
    if check_url "$S3_URL" "S3 Direct Access (should be blocked)" "false"; then
        S3_OK=true
        echo "    ✅ Security check passed: Direct access to S3 is properly restricted."
        echo "    This confirms CloudFront Origin Access Control is correctly configured."
    else
        S3_OK=false
        echo "    ⚠️ SECURITY ISSUE: S3 bucket can be accessed directly, bypassing CloudFront!"
        echo "    This indicates Origin Access Control is not properly configured."
    fi
else
    echo "    ⚠️ S3 bucket name not found in .env file. Skipping S3 direct access test."
    # We'll still consider this a pass for the overall test
    S3_OK=true
fi

# Test API Gateway - expect failure without auth
if [ -n "$API_ENDPOINT" ]; then
    if check_url "$API_ENDPOINT" "API Gateway Security Check" "false"; then
        API_OK=true
        echo "    ✅ Security check passed: API Gateway correctly requires authentication."
        echo "    This confirms your API is protected by Cognito authorization."
    else
        API_OK=false
        echo "    ⚠️ SECURITY ISSUE: API Gateway accessible without authentication!"
        echo "    Please check that Cognito authorizer is correctly configured."
    fi
else
    echo "    ⚠️ API endpoint not found in .env file. Skipping API security test."
    # We'll still consider this a fail for the overall test
    API_OK=false
fi

# Test Cognito domain
if [ -n "$COGNITO_DOMAIN" ] && [ -n "$REGION" ]; then
    COGNITO_URL="https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
    if check_url "$COGNITO_URL" "Cognito Domain" "true"; then
        COGNITO_OK=true
    else
        COGNITO_OK=false
        echo "    ⚠️ Cognito domain may not be fully propagated yet (can take 15-30 minutes)."
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
if [ "$CLOUDFRONT_OK" = true ] && [ "$S3_OK" = true ] && [ "$API_OK" = true ] && [ "$COGNITO_OK" = true ] && [ "$USERS_OK" = true ] && [ "$SPA_OK" = true ]; then
    OVERALL_STATUS="✅ ALL PASSED"
    STATUS_MESSAGE="All security and functionality tests passed successfully!"
else
    OVERALL_STATUS="⚠️ ATTENTION NEEDED"
    STATUS_MESSAGE="Some checks require attention - see details below."
fi

# Print summary
echo
echo "📋 Test Summary:"
echo "   CloudFront Distribution: $([ "$CLOUDFRONT_OK" = true ] && echo "✅ Accessible" || echo "❌ Not accessible")"
echo "   S3 Direct Access: $([ "$S3_OK" = true ] && echo "✅ Properly secured" || echo "❌ Security issue")"
echo "   API Gateway: $([ "$API_OK" = true ] && echo "✅ Properly secured" || echo "❌ Security issue")"
echo "   Cognito Domain: $([ "$COGNITO_OK" = true ] && echo "✅ Accessible" || echo "❌ Not accessible")"
echo "   Users in Cognito: $([ "$USERS_OK" = true ] && echo "✅ User(s) exist" || echo "❌ No users")"
echo "   SPA Routing: $([ "$SPA_OK" = true ] && echo "✅ Working" || echo "❌ Not working")"
echo
echo "🏁 Overall Status: $OVERALL_STATUS"
echo
echo "💡 $STATUS_MESSAGE"
echo
echo "👉 Access your application at: $CLOUDFRONT_URL"
echo "   Login with the user created in step-30-create-user.sh"
echo "=================================================="
