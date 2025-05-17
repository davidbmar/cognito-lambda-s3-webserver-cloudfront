#!/bin/bash
# validate-env.sh - Validates environment configuration and resource status
# Use this script between deployment steps to verify everything is ready to proceed

set -e # Exit on any error

print_header() {
  echo "=================================================="
  echo "   CloudFront Cognito Serverless Application     "
  echo "          Environment Validation Tool            "
  echo "=================================================="
  echo
}

check_env_file() {
  echo "🔍 Checking environment configuration..."
  if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-10-setup.sh first."
    exit 1
  fi

  source .env
  
  # Check required variables
  local required_vars=("APP_NAME" "STAGE" "REGION" "S3_BUCKET_NAME" "COGNITO_DOMAIN")
  local missing_vars=()
  
  for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
      missing_vars+=("$var")
    fi
  done
  
  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "❌ Missing required variables in .env file: ${missing_vars[*]}"
    echo "Please run step-10-setup.sh again."
    exit 1
  fi
  
  echo "✅ Environment configuration looks good."
}

check_deployment_status() {
  echo "🔍 Checking deployment status..."
  source .env
  
  # Check if stack exists
  STACK_NAME="${APP_NAME}-${STAGE}"
  if ! aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null; then
    echo "❌ CloudFormation stack '$STACK_NAME' not found."
    echo "Please run step-20-deploy.sh to deploy the application."
    return 1
  fi
  
  echo "✅ CloudFormation stack exists."
  
  # Check S3 bucket
  if ! aws s3api head-bucket --bucket $S3_BUCKET_NAME &> /dev/null; then
    echo "❌ S3 bucket '$S3_BUCKET_NAME' not found or not accessible."
    echo "Please run step-20-deploy.sh to deploy the application."
    return 1
  fi
  echo "✅ S3 bucket exists and is accessible."
  
  # Check CloudFront distribution
  if [ -z "$CLOUDFRONT_URL" ]; then
    echo "⚠️ CloudFront URL not found in .env file."
    echo "The deployment might not be complete. Please run step-20-deploy.sh."
    return 1
  fi
  
  # Check Cognito User Pool
  if [ -z "$USER_POOL_ID" ]; then
    echo "⚠️ User Pool ID not found in .env file."
    echo "The deployment might not be complete. Please run step-20-deploy.sh."
    return 1
  fi
  
  echo "✅ All required resources exist."
  return 0
}

check_cognito_domain() {
  echo "🔍 Checking Cognito domain..."
  source .env
  
  if [ -z "$COGNITO_DOMAIN" ] || [ -z "$USER_POOL_ID" ]; then
    echo "❌ Missing Cognito domain or User Pool ID in .env file."
    echo "Please run step-20-deploy.sh to deploy Cognito resources."
    return 1
  fi
  
  # Check if domain exists in Cognito
  local domain_status
  domain_status=$(aws cognito-idp describe-user-pool-domain --domain $COGNITO_DOMAIN --query "DomainDescription.Status" --output text 2>/dev/null || echo "NOT_FOUND")
  
  if [ "$domain_status" = "ACTIVE" ]; then
    echo "✅ Cognito domain is active: $COGNITO_DOMAIN.auth.$REGION.amazoncognito.com"
    
    # Validate that app.js is using the correct domain
    if [ -f web/app.js ]; then
      if grep -q "$COGNITO_DOMAIN" web/app.js; then
        echo "✅ App.js appears to be using the correct Cognito domain."
      else
        echo "❌ App.js might be using an incorrect Cognito domain."
        echo "Please update app.js with the correct domain or re-run step-20-deploy.sh."
        return 1
      fi
    fi
    
    return 0
  elif [ "$domain_status" = "CREATING" ]; then
    echo "⚠️ Cognito domain is still being created. Please wait a few minutes and try again."
    return 1
  else
    echo "❌ Cognito domain '$COGNITO_DOMAIN' not found or not active."
    
    # Check if there's another active domain for this user pool
    local active_domains
    active_domains=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID --query "UserPool.Domain" --output text 2>/dev/null || echo "")
    
    if [ -n "$active_domains" ] && [ "$active_domains" != "None" ]; then
      echo "⚠️ Found another active domain for this User Pool: $active_domains"
      echo "Would you like to update your .env file to use this domain? (y/n)"
      read -r response
      if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        # Update .env file
        sed -i.bak "s|COGNITO_DOMAIN=.*$|COGNITO_DOMAIN=$active_domains|g" .env
        source .env
        echo "✅ Updated .env file with the active domain: $active_domains"
        
        # Update app.js
        if [ -f web/app.js ]; then
          sed -i.bak "s|YOUR_COGNITO_DOMAIN_PREFIX|$active_domains|g" web/app.js
          echo "✅ Updated app.js with the active domain."
          
          # Upload to S3
          aws s3 cp web/app.js s3://$S3_BUCKET_NAME/app.js
          echo "✅ Uploaded updated app.js to S3."
          
          # Create CloudFront invalidation
          DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text)
          if [ -n "$DISTRIBUTION_ID" ]; then
            aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/app.js"
            echo "✅ Created CloudFront invalidation for /app.js"
          fi
        fi
        
        return 0
      fi
    fi
    
    echo "Please run step-20-deploy.sh to deploy Cognito resources with the correct domain."
    return 1
  fi
}

check_cognito_users() {
  echo "🔍 Checking for Cognito users..."
  source .env
  
  if [ -z "$USER_POOL_ID" ]; then
    echo "❌ User Pool ID not found in .env file."
    echo "Please run step-20-deploy.sh to deploy Cognito resources."
    return 1
  fi
  
  local user_count
  user_count=$(aws cognito-idp list-users --user-pool-id $USER_POOL_ID --query "length(Users)" --output text)
  
  if [ "$user_count" -gt 0 ]; then
    echo "✅ Found $user_count user(s) in the Cognito User Pool."
    return 0
  else
    echo "⚠️ No users found in the Cognito User Pool."
    echo "Please run step-30-create-user.sh to create a test user."
    return 1
  fi
}

check_dns_propagation() {
  echo "🔍 Checking DNS propagation for Cognito domain..."
  source .env
  
  if [ -z "$COGNITO_DOMAIN" ] || [ -z "$REGION" ]; then
    echo "❌ Missing Cognito domain or region in .env file."
    return 1
  fi
  
  local domain="${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
  
  # Try to resolve the domain using dig or nslookup
  if command -v dig &> /dev/null; then
    if dig +short "$domain" | grep -q .; then
      echo "✅ DNS resolution successful for $domain"
      return 0
    fi
  elif command -v nslookup &> /dev/null; then
    if nslookup "$domain" | grep -q "Address"; then
      echo "✅ DNS resolution successful for $domain"
      return 0
    fi
  else
    # Fallback to curl
    if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q -v "000"; then
      echo "✅ DNS resolution appears to be working for $domain"
      return 0
    fi
  fi
  
  echo "⚠️ DNS for Cognito domain ($domain) has not fully propagated yet."
  echo "This can take 15-30 minutes. Please wait and try again."
  return 1
}

print_next_steps() {
  echo
  echo "Next steps:"
  
  if ! check_deployment_status &>/dev/null; then
    echo "1. Run './step-20-deploy.sh' to deploy your application"
    exit 0
  fi
  
  if ! check_cognito_domain &>/dev/null; then
    echo "1. Wait for the Cognito domain to become active or fix domain configuration issues"
    echo "2. Run this validation script again to verify"
    exit 0
  fi
  
  if ! check_cognito_users &>/dev/null; then
    echo "1. Run './step-30-create-user.sh' to create a test user"
    exit 0
  fi
  
  if ! check_dns_propagation &>/dev/null; then
    echo "1. Wait for DNS propagation (15-30 minutes)"
    echo "2. Run this validation script again to verify"
    exit 0
  fi
  
  echo "✅ All checks passed! You can now test your application at:"
  echo "   $CLOUDFRONT_URL"
  echo
  echo "Run './step-40-test.sh' to perform comprehensive testing of all components."
}

# Main execution
print_header
check_env_file

echo
echo "Choose what to check:"
echo "1. Check deployment status (pre-step-20)"
echo "2. Check Cognito domain (pre-step-30)"
echo "3. Check Cognito users (pre-step-40)"
echo "4. Check DNS propagation (post-step-30)"
echo "5. Run all checks (comprehensive validation)"
echo
read -p "Enter your choice (1-5): " choice

case $choice in
  1) check_deployment_status ;;
  2) check_cognito_domain ;;
  3) check_cognito_users ;;
  4) check_dns_propagation ;;
  5) 
    check_deployment_status
    check_cognito_domain
    check_cognito_users
    check_dns_propagation
    ;;
  *) 
    echo "Invalid choice. Please enter a number between 1 and 5."
    exit 1
    ;;
esac

print_next_steps

echo "=================================================="
