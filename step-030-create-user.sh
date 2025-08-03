#!/bin/bash
# step-030-create-user.sh - Creates a test user in the Cognito User Pool
# Prerequisites: step-025-update-web-files.sh
# Outputs: Test user account in Cognito for application testing

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-030-create-user"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-030-create-user.sh"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# Show step purpose
show_step_purpose "step-030-create-user.sh"

# Welcome banner
echo -e "${CYAN}=================================================="
echo -e "       CloudFront Cognito Serverless Application"
echo -e "              TEST USER CREATION"
echo -e "==================================================${NC}"
echo
log_info "Starting test user creation" "$SCRIPT_NAME"

# Check if .env exists
if [ ! -f .env ]; then
    log_error ".env file not found. Please run step-025-update-web-files.sh first." "$SCRIPT_NAME"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$USER_POOL_ID" ]; then
    log_error "USER_POOL_ID not found in .env file. Please run step-020-deploy.sh first." "$SCRIPT_NAME"
    exit 1
fi
log_success "Environment variables validated" "$SCRIPT_NAME"

# Get user information
read -p "Enter email for the test user: " USER_EMAIL
if [ -z "$USER_EMAIL" ]; then
    log_error "Email cannot be empty." "$SCRIPT_NAME"
    exit 1
fi

# Validate email format (basic validation)
if [[ ! $USER_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    log_error "Invalid email format." "$SCRIPT_NAME"
    exit 1
fi
log_success "Email format validated: $USER_EMAIL" "$SCRIPT_NAME"

# Generate a random password that meets Cognito requirements
RANDOM_PASSWORD="Test$(date +%s)!"

# Create the user in Cognito
log_info "Creating user in Cognito User Pool" "$SCRIPT_NAME"
if retry_command 3 5 "$SCRIPT_NAME" aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username $USER_EMAIL \
  --temporary-password "$RANDOM_PASSWORD" \
  --user-attributes Name=email,Value=$USER_EMAIL Name=email_verified,Value=true; then
    log_success "User created in Cognito" "$SCRIPT_NAME"
else
    log_error "Failed to create user in Cognito" "$SCRIPT_NAME"
    exit 1
fi

# Set a permanent password
echo "🔒 Setting permanent password for the user..."
read -s -p "Enter a permanent password for the user (min 8 chars, with upper, lower, number): " USER_PASSWORD
echo
if [ -z "$USER_PASSWORD" ]; then
    log_error "Password cannot be empty." "$SCRIPT_NAME"
    exit 1
fi

# Password must be at least 8 characters and contain upper, lower, and number
if [[ ${#USER_PASSWORD} -lt 8 ]] || [[ ! $USER_PASSWORD =~ [A-Z] ]] || [[ ! $USER_PASSWORD =~ [a-z] ]] || [[ ! $USER_PASSWORD =~ [0-9] ]]; then
    log_error "Password must be at least 8 characters and contain uppercase, lowercase, and numbers." "$SCRIPT_NAME"
    exit 1
fi
log_success "Password format validated" "$SCRIPT_NAME"

log_info "Setting permanent password" "$SCRIPT_NAME"
if retry_command 3 5 "$SCRIPT_NAME" aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username $USER_EMAIL \
  --password "$USER_PASSWORD" \
  --permanent; then
    log_success "Permanent password set" "$SCRIPT_NAME"
else
    log_error "Failed to set permanent password" "$SCRIPT_NAME"
    exit 1
fi

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

echo
log_success "Test user created successfully!" "$SCRIPT_NAME"
echo
echo -e "${BLUE}👤 Test User Details:${NC}"
echo -e "${GREEN}   Email: $USER_EMAIL${NC}"
echo -e "${BLUE}   Password: (the password you entered)${NC}"
echo
echo -e "${BLUE}🔗 Login URL:${NC}"
echo -e "${GREEN}   $CLOUDFRONT_URL${NC}"
echo
echo -e "${CYAN}✨ You can now test the application by visiting the CloudFront URL and signing in with these credentials.${NC}"

# Show next step
show_next_step "step-030-create-user.sh" "$(dirname "$0")"
