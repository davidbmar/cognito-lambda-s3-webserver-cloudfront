# Test API endpoint
if check_url "${API_ENDPOINT%/data}" "API Gateway"; then
    API_OK=true
else
    API_OK=false
    echo "    ⚠️ API Gateway may not be properly configured or requires authentication."
fi

# Test Cognito domain
COGNITO_URL="https://${COGNITO_DOMAIN}.auth.${AWS_REGION}.amazoncognito.com"
if check_url "$COGNITO_URL" "Cognito Domain"; then
    COGNITO_OK=true
else
    COGNITO_OK=false
    echo "    ⚠️ Cognito domain may not be properly configured."
fi

# Check if users exist in the Cognito User Pool
echo -n "  👤 Checking for users in Cognito User Pool... "
USER_COUNT=$(aws cognito-idp list-users --user-pool-id $USER_POOL_ID --query "length(Users)" --output text)

if [ "$USER_COUNT" -gt 0 ]; then
    echo "✅ Found $USER_COUNT user(s)!"
    USERS_OK=true
else
    echo "⚠️ No users found. Run ./create-user.sh to create a test user."
    USERS_OK=false
fi

# Test CloudFront error responses for SPA routing
if [ "$CLOUDFRONT_OK" = true ]; then
    echo -n "  🌐 Testing CloudFront SPA routing... "
    
    # Use curl to check if a deep link returns index.html
    if curl -s "$CLOUDFRONT_URL/non-existent-page" | grep "<title>Cognito Serverless App</title>" > /dev/null; then
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
