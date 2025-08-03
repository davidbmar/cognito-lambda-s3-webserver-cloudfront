#!/bin/bash
# step-022-update-cognito-client.sh - Updates the Cognito User Pool Client to support implicit flow
# Prerequisites: step-020-deploy.sh
# Outputs: Updated Cognito client configuration for authentication

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-022-update-cognito-client"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-022-update-cognito-client.sh"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# Show step purpose
show_step_purpose "step-022-update-cognito-client.sh"

# Welcome banner
echo -e "${CYAN}=================================================="
echo -e "       CloudFront Cognito Serverless Application"
echo -e "        COGNITO AUTHENTICATION CONFIGURATION"
echo -e "==================================================${NC}"
echo
log_info "Starting Cognito client configuration" "$SCRIPT_NAME"

# Check if .env exists
if [ ! -f .env ]; then
    log_error ".env file not found. Please run step-020-deploy.sh first." "$SCRIPT_NAME"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$USER_POOL_ID" ] || [ -z "$USER_POOL_CLIENT_ID" ] || [ -z "$CLOUDFRONT_URL" ]; then
    log_error "Missing required variables in .env file. Please run step-020-deploy.sh first." "$SCRIPT_NAME"
    exit 1
fi
log_success "Environment variables validated" "$SCRIPT_NAME"

log_info "Updating Cognito User Pool Client to support implicit flow" "$SCRIPT_NAME"

if retry_command 3 5 "$SCRIPT_NAME" aws cognito-idp update-user-pool-client \
  --user-pool-id "$USER_POOL_ID" \
  --client-id "$USER_POOL_CLIENT_ID" \
  --callback-urls "${CLOUDFRONT_URL}/callback.html" \
  --logout-urls "${CLOUDFRONT_URL}/index.html" \
  --allowed-o-auth-flows "implicit" "code" \
  --allowed-o-auth-scopes "email" "openid" "profile" \
  --allowed-o-auth-flows-user-pool-client \
  --supported-identity-providers "COGNITO"; then
    log_success "Cognito User Pool Client configuration updated" "$SCRIPT_NAME"
else
    log_error "Failed to update Cognito User Pool Client" "$SCRIPT_NAME"
    exit 1
fi

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

log_success "Cognito User Pool Client updated successfully!" "$SCRIPT_NAME"
echo
echo -e "${BLUE}You can now test the authentication flow at:${NC}"
echo -e "${GREEN}$CLOUDFRONT_URL${NC}"

# Show next step
show_next_step "step-022-update-cognito-client.sh" "$(dirname "$0")"
