#!/bin/bash
# step-15-validate.sh - Validates the completion of specific steps in the workflow
# Run this after each step to verify everything is ready for the next step

set -e # Exit on any error

print_header() {
  echo "=================================================="
  echo "   CloudFront Cognito Serverless Application     "
  echo "             Step Validation Tool                "
  echo "=================================================="
  echo
}

# Validate that step-10-setup.sh ran correctly
validate_step_10() {
  echo "🔍 Validating that step-10-setup.sh completed successfully..."
  
  # Check if .env exists
  if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run step-10-setup.sh first."
    return 1
  fi

  # Load environment variables
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
    return 1
  fi

  # Check that app.js.template exists
  if [ ! -f web/app.js.template ]; then
    echo "❌ web/app.js.template not found. Please run step-10-setup.sh again."
    return 1
  fi
  
  # Check that required directories exist
  for dir in web api functions; do
    if [ ! -d "$dir" ]; then
      echo "❌ Directory '$dir' not found. Please run step-10-setup.sh again."
      return 1
    fi
  done

  echo "🔍 Checking if app.js.template is using proper placeholders..."
  if grep -q "https://[^\.]*\.auth" web/app.js.template | grep -v "YOUR_COGNITO_DOMAIN_PREFIX"; then
      echo "⚠️ Warning: app.js.template contains hardcoded URLs that should be placeholders."
      echo "    Consider updating web/app.js.template to use placeholders like YOUR_COGNITO_DOMAIN_PREFIX."
      return 1
  fi
  
  echo "✅ step-10-setup.sh completed successfully!"
  echo "   - .env file created with all required variables"
  echo "   - All required directories and templates are in place"
  echo
  echo "You can now proceed to step-20-deploy.sh"
  return 0
}

# Validate that step-20-deploy.sh ran correctly
validate_step_20() {
  echo "🔍 Validating that step-20-deploy.sh completed successfully..."
  
  # First check if step-10 was completed
  if ! validate_step_10 > /dev/null; then
    echo "❌ step-10-setup.sh has not been completed successfully."
    echo "Please run step-10-setup.sh first, then validate with option 1."
    return 1
  fi
  
  # Load environment variables
  source .env
  
  # Check if stack exists
  STACK_NAME="${APP_NAME}-${STAGE}"
  if ! aws cloudformation describe-stacks --stack-name $STACK_NAME &> /dev/null; then
    echo "❌ CloudFormation stack '$STACK_NAME' not found."
    echo "Please run step-20-deploy.sh to deploy the application."
    return 1
  fi
  
  # Check if outputs were populated in .env
  if [ -z "$USER_POOL_ID" ] || [ -z "$CLOUDFRONT_URL" ]; then
    echo "❌ Missing deployment outputs in .env file."
    echo "Please run step-20-deploy.sh again to ensure all outputs are captured."
    return 1
  fi
  
  # Check if S3 bucket was created
  if ! aws s3api head-bucket --bucket $S3_BUCKET_NAME &> /dev/null; then
    echo "❌ S3 bucket '$S3_BUCKET_NAME' not found or not accessible."
    echo "Please run step-20-deploy.sh again."
    return 1
  fi
  
  # Check if Cognito domain was created and matches .env
  local domain_check
  domain_check=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID --query "UserPool.Domain" --output text 2>/dev/null || echo "")
  
  if [ -z "$domain_check" ] || [ "$domain_check" == "None" ]; then
    echo "❌ No Cognito domain found for User Pool."
    echo "Please run step-20-deploy.sh again."
    return 1
  fi
  
  if [ "$domain_check" != "$COGNITO_DOMAIN" ]; then
    echo "⚠️ Mismatch between Cognito domain in .env ($COGNITO_DOMAIN) and actual domain ($domain_check)."
    echo "Would you like to update your .env file to use the correct domain? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
      # Update .env file
      sed -i.bak "s|COGNITO_DOMAIN=.*$|COGNITO_DOMAIN=$domain_check|g" .env
      source .env
      echo "✅ Updated .env file with the correct domain: $domain_check"
      
      # Check if app.js needs updating
      if [ -f web/app.js ]; then
        if ! grep -q "$domain_check" web/app.js; then
          echo "⚠️ app.js is using an incorrect domain. Updating..."
          sed -i.bak "s|https://[^\.]*\.auth|https://$domain_check.auth|g" web/app.js
          
          # Upload to S3
          aws s3 cp web/app.js s3://$S3_BUCKET_NAME/app.js
          echo "✅ Updated app.js with the correct domain and uploaded to S3."
          
          # Create CloudFront invalidation
          DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text)
          if [ -n "$DISTRIBUTION_ID" ]; then
            aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/app.js"
            echo "✅ Created CloudFront invalidation for /app.js"
          fi
        fi
      fi
    else
      echo "⚠️ You should update the domain manually to continue."
    fi
    return 1
  fi
  
  # Check app.js
  if [ ! -f web/app.js ]; then
    echo "❌ web/app.js not found. It should have been created during deployment."
    echo "Please run step-20-deploy.sh again."
    return 1
  fi
  
  # Check if app.js has the correct domain
  if ! grep -q "$COGNITO_DOMAIN" web/app.js; then
    echo "❌ app.js does not contain the correct Cognito domain."
    echo "Please run step-20-deploy.sh again or manually update app.js."
    return 1
  fi
  
  echo "✅ step-20-deploy.sh completed successfully!"
  echo "   - CloudFormation stack created"
  echo "   - S3 bucket created"
  echo "   - Cognito resources created"
  echo "   - CloudFront distribution deployed"
  echo "   - app.js properly configured"
  echo
  echo "You can now proceed to step-30-create-user.sh"
  return 0
}

# Validate that step-30-create-user.sh ran correctly
validate_step_30() {
  echo "🔍 Validating that step-30-create-user.sh completed successfully..."
  
  # First check if step-20 was completed
  if ! validate_step_20 > /dev/null; then
    echo "❌ step-20-deploy.sh has not been completed successfully."
    echo "Please run step-20-deploy.sh first, then validate with option 2."
    return 1
  fi
  
  # Load environment variables
  source .env
  
  # Check if there are users in the Cognito User Pool
  if [ -z "$USER_POOL_ID" ]; then
    echo "❌ USER_POOL_ID not found in .env file."
    echo "Please run step-20-deploy.sh again."
    return 1
  fi
  
  local user_count
  user_count=$(aws cognito-idp list-users --user-pool-id $USER_POOL_ID --query "length(Users)" --output text)
  
  if [ "$user_count" -eq 0 ]; then
    echo "❌ No users found in the Cognito User Pool."
    echo "Please run step-30-create-user.sh to create a test user."
    return 1
  fi
  
  echo "✅ step-30-create-user.sh completed successfully!"
  echo "   - Found $user_count user(s) in the Cognito User Pool"
  echo
  echo "You can now check if DNS has propagated (option 4) or proceed to step-40-test.sh"
  return 0
}

# Check if DNS has propagated for the Cognito domain
check_dns_propagation() {
  echo "🔍 Checking if DNS has propagated for the Cognito domain..."
  
  # Load environment variables
  source .env
  
  if [ -z "$COGNITO_DOMAIN" ] || [ -z "$REGION" ]; then
    echo "❌ Missing Cognito domain or region in .env file."
    return 1
  fi
  
  local domain="${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com"
  
  # Try to resolve the domain
  if command -v dig &> /dev/null; then
    if dig +short "$domain" | grep -q .; then
      echo "✅ DNS resolution successful for $domain"
      echo
      echo "All prerequisites are met. You can now access your application at:"
      echo "   $CLOUDFRONT_URL"
      echo
      echo "You can now proceed to step-40-test.sh"
      return 0
    fi
  elif command -v nslookup &> /dev/null; then
    if nslookup "$domain" | grep -q "Address"; then
      echo "✅ DNS resolution successful for $domain"
      echo
      echo "All prerequisites are met. You can now access your application at:"
      echo "   $CLOUDFRONT_URL"
      echo
      echo "You can now proceed to step-40-test.sh"
      return 0
    fi
  else
    # Fallback to curl
    local status_code
    status_code=$(curl -s -o /dev/null -w "%{http_code}" "https://$domain" || echo "000")
    if [ "$status_code" != "000" ]; then
      echo "✅ DNS resolution appears to be working for $domain"
      echo
      echo "All prerequisites are met. You can now access your application at:"
      echo "   $CLOUDFRONT_URL"
      echo
      echo "You can now proceed to step-40-test.sh"
      return 0
    fi
  fi
  
  echo "⚠️ DNS for Cognito domain ($domain) has not fully propagated yet."
  echo "This can take 15-30 minutes. Please wait and try again."
  echo
  echo "You can still proceed to step-40-test.sh, but authentication may not work until DNS propagates."
  return 1
}

# Run all checks in sequence
run_all_checks() {
  local all_passed=true
  
  echo "🔍 Running all validation checks in sequence..."
  echo
  
  echo "Step 1: Validating setup (step-10-setup.sh)"
  echo "-------------------------------------------"
  if ! validate_step_10; then
    all_passed=false
    echo "❌ Setup validation failed. Please fix the issues before proceeding."
    return 1
  fi
  echo
  
  echo "Step 2: Validating deployment (step-20-deploy.sh)"
  echo "------------------------------------------------"
  if ! validate_step_20; then
    all_passed=false
    echo "❌ Deployment validation failed. Please fix the issues before proceeding."
    return 1
  fi
  echo
  
  echo "Step 3: Validating user creation (step-30-create-user.sh)"
  echo "--------------------------------------------------------"
  if ! validate_step_30; then
    all_passed=false
    echo "❌ User creation validation failed. Please fix the issues before proceeding."
    return 1
  fi
  echo
  
  echo "Step 4: Checking DNS propagation"
  echo "-------------------------------"
  if ! check_dns_propagation; then
    all_passed=false
    echo "⚠️ DNS propagation check failed, but this might just need more time."
  fi
  echo
  
  if [ "$all_passed" = true ]; then
    echo "✅ All validation checks passed successfully!"
    echo "You can now access your application at:"
    echo "   $CLOUDFRONT_URL"
    echo
    echo "Proceed to step-40-test.sh for final testing."
  else
    echo "⚠️ Some validation checks failed. Please address the issues before proceeding."
  fi
}

# Main execution
print_header
echo "This tool validates that each step in the deployment workflow completed successfully."
echo "Run it after each step to make sure you're ready to proceed to the next step."
echo

echo "Choose what to validate:"
echo "1. Validate step-10-setup.sh (Initial Setup)"
echo "2. Validate step-20-deploy.sh (Deployment)"
echo "3. Validate step-30-create-user.sh (User Creation)"
echo "4. Check DNS propagation (required for authentication)"
echo "5. Run all validation checks"
echo
read -p "Enter your choice (1-5): " choice

case $choice in
  1) validate_step_10 ;;
  2) validate_step_20 ;;
  3) validate_step_30 ;;
  4) check_dns_propagation ;;
  5) run_all_checks ;;
  *) 
    echo "Invalid choice. Please enter a number between 1 and 5."
    exit 1
    ;;
esac

echo "=================================================="
