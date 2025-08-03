#!/bin/bash

# Automated Deployment Script for CloudDrive Serverless Application
# Fully automated deployment with user control and comprehensive error handling
# Based on Script-Based Sequential Deployment Framework

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="deploy-all"
setup_error_handling "$SCRIPT_NAME"

# Command line options
AUTO_APPROVE=false
FRESH_START=false
SKIP_PREFLIGHT=false
SKIP_TESTS=false
SKIP_USER_CREATION=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --fresh-start)
            FRESH_START=true
            shift
            ;;
        --skip-preflight)
            SKIP_PREFLIGHT=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --skip-user-creation)
            SKIP_USER_CREATION=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Automated deployment for CloudDrive Serverless Application"
            echo ""
            echo "Options:"
            echo "  --auto-approve         Non-interactive mode (skip confirmations)"
            echo "  --fresh-start          Clean state directory and restart deployment"
            echo "  --skip-preflight       Skip prerequisite checks (not recommended)"
            echo "  --skip-tests           Skip application testing after deployment"
            echo "  --skip-user-creation   Skip test user creation"
            echo "  --verbose, -v          Enable verbose logging"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     Interactive deployment with all steps"
            echo "  $0 --auto-approve      Fully automated deployment"
            echo "  $0 --fresh-start       Clean deployment from scratch"
            echo "  $0 --skip-tests        Deploy without running tests"
            echo ""
            echo "Environment Variables:"
            echo "  DEPLOYMENT_TIMEOUT     Maximum time to wait for each step (default: 600s)"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1" "$SCRIPT_NAME"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration
DEPLOYMENT_TIMEOUT=${DEPLOYMENT_TIMEOUT:-600}  # 10 minutes per step
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Welcome banner
echo -e "${CYAN}=================================================="
echo -e "       CloudDrive Serverless Application"
echo -e "           AUTOMATED DEPLOYMENT"
echo -e "==================================================${NC}"
echo
log_info "Starting automated deployment process" "$SCRIPT_NAME"

# Show deployment options
echo -e "${BLUE}Deployment Configuration:${NC}"
echo -e "${BLUE}  Auto-approve: ${AUTO_APPROVE}${NC}"
echo -e "${BLUE}  Fresh start: ${FRESH_START}${NC}"
echo -e "${BLUE}  Skip preflight: ${SKIP_PREFLIGHT}${NC}"
echo -e "${BLUE}  Skip tests: ${SKIP_TESTS}${NC}"
echo -e "${BLUE}  Skip user creation: ${SKIP_USER_CREATION}${NC}"
echo -e "${BLUE}  Verbose mode: ${VERBOSE}${NC}"
echo

# Function to prompt user for continuation
prompt_continue() {
    local step_name="$1"
    local description="$2"
    
    if [ "$AUTO_APPROVE" = true ]; then
        log_info "Auto-approving: $step_name" "$SCRIPT_NAME"
        return 0
    fi
    
    echo -e "${CYAN}About to run: ${BOLD}$step_name${NC}"
    echo -e "${BLUE}$description${NC}"
    echo
    
    while true; do
        echo -e "${YELLOW}Continue with this step? (y/n/q): ${NC}"
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                return 0
                ;;
            [nN]|[nN][oO])
                log_info "User chose to skip: $step_name" "$SCRIPT_NAME"
                return 1
                ;;
            [qQ]|[qQ][uU][iI][tT])
                log_info "User chose to quit deployment" "$SCRIPT_NAME"
                exit 0
                ;;
            *)
                echo -e "${RED}Please answer y (yes), n (no), or q (quit)${NC}"
                ;;
        esac
    done
}

# Function to handle deployment failures
can_continue_after_failure() {
    local step_name="$1"
    local exit_code="$2"
    
    log_error "Step failed: $step_name (exit code: $exit_code)" "$SCRIPT_NAME"
    
    if [ "$AUTO_APPROVE" = true ]; then
        log_error "Auto-approve mode: stopping deployment due to failure" "$SCRIPT_NAME"
        return 1
    fi
    
    echo -e "${RED}Step '$step_name' failed with exit code $exit_code${NC}"
    echo
    echo -e "${YELLOW}Options:${NC}"
    echo -e "${BLUE}  r) Retry this step${NC}"
    echo -e "${BLUE}  c) Continue anyway (may cause issues)${NC}"
    echo -e "${BLUE}  s) Skip this step${NC}"
    echo -e "${BLUE}  q) Quit deployment${NC}"
    echo
    
    while true; do
        echo -e "${YELLOW}What would you like to do? (r/c/s/q): ${NC}"
        read -r response
        case "$response" in
            [rR]|[rR][eE][tT][rR][yY])
                return 2  # Retry
                ;;
            [cC]|[cC][oO][nN][tT][iI][nN][uU][eE])
                log_warning "Continuing despite failure (may cause issues)" "$SCRIPT_NAME"
                return 0  # Continue
                ;;
            [sS]|[sS][kK][iI][pP])
                log_warning "Skipping failed step" "$SCRIPT_NAME"
                return 1  # Skip
                ;;
            [qQ]|[qQ][uU][iI][tT])
                log_info "User chose to quit after failure" "$SCRIPT_NAME"
                exit 1
                ;;
            *)
                echo -e "${RED}Please answer r (retry), c (continue), s (skip), or q (quit)${NC}"
                ;;
        esac
    done
}

# Function to run a deployment step with error handling
run_step() {
    local step_script="$1"
    local step_description="$2"
    local is_optional="${3:-false}"
    
    # Check if step exists
    if [ ! -f "$step_script" ]; then
        if [ "$is_optional" = true ]; then
            log_warning "Optional step not found: $step_script" "$SCRIPT_NAME"
            return 0
        else
            log_error "Required step not found: $step_script" "$SCRIPT_NAME"
            return 1
        fi
    fi
    
    # Make sure script is executable
    if [ ! -x "$step_script" ]; then
        log_info "Making script executable: $step_script" "$SCRIPT_NAME"
        chmod +x "$step_script" 2>/dev/null || {
            log_error "Could not make script executable: $step_script" "$SCRIPT_NAME"
            return 1
        }
    fi
    
    # Check if step was already completed (for resume capability)
    local step_base=$(basename "$step_script" .sh)
    if is_step_completed "$step_base"; then
        log_info "$step_description already completed, skipping" "$SCRIPT_NAME"
        return 0
    fi
    
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        log_info "Running: $step_script (attempt $((retry_count + 1))/$max_retries)" "$SCRIPT_NAME"
        
        # Run the step with timeout
        if [ "$VERBOSE" = true ]; then
            timeout "$DEPLOYMENT_TIMEOUT" "./$step_script"
        else
            timeout "$DEPLOYMENT_TIMEOUT" "./$step_script" > /tmp/${step_base}.log 2>&1
        fi
        
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_success "$step_description completed successfully" "$SCRIPT_NAME"
            return 0
        elif [ $exit_code -eq 124 ]; then
            log_error "$step_description timed out after ${DEPLOYMENT_TIMEOUT}s" "$SCRIPT_NAME"
            retry_count=$((retry_count + 1))
        else
            # Show recent output if not in verbose mode
            if [ "$VERBOSE" = false ] && [ -f "/tmp/${step_base}.log" ]; then
                echo -e "${YELLOW}Recent output from $step_script:${NC}"
                tail -n 10 "/tmp/${step_base}.log" | while read -r line; do
                    echo -e "${YELLOW}  $line${NC}"
                done
                echo
            fi
            
            local action=$(can_continue_after_failure "$step_script" $exit_code)
            local action_code=$?
            
            case $action_code in
                0)  # Continue anyway
                    return 0
                    ;;
                1)  # Skip or quit
                    return 1
                    ;;
                2)  # Retry
                    retry_count=$((retry_count + 1))
                    if [ $retry_count -lt $max_retries ]; then
                        log_info "Retrying step: $step_script" "$SCRIPT_NAME"
                        sleep 5
                        continue
                    else
                        log_error "Maximum retries exceeded for: $step_script" "$SCRIPT_NAME"
                        return 1
                    fi
                    ;;
            esac
        fi
    done
    
    log_error "Step failed after $max_retries attempts: $step_script" "$SCRIPT_NAME"
    return 1
}

# Clean state if requested
if [ "$FRESH_START" = true ]; then
    log_info "Fresh start requested - cleaning deployment state" "$SCRIPT_NAME"
    clean_deployment_state "$SCRIPT_NAME"
fi

# Estimate total time
echo -e "${BLUE}⏱️ Estimated total deployment time: 15-25 minutes${NC}"
echo

# Step 1: Preflight Check
if [ "$SKIP_PREFLIGHT" = false ]; then
    if prompt_continue "step-001-preflight-check.sh" "Validate system prerequisites and dependencies"; then
        if ! run_step "step-001-preflight-check.sh" "Preflight Check"; then
            log_error "Preflight check failed - deployment cannot continue" "$SCRIPT_NAME"
            exit 1
        fi
    else
        log_warning "Skipping preflight check (not recommended)" "$SCRIPT_NAME"
    fi
else
    log_warning "Preflight check skipped by user request" "$SCRIPT_NAME"
fi

# Step 2: Initial Setup
if prompt_continue "step-010-setup.sh" "Configure AWS resources and generate environment settings"; then
    if ! run_step "step-010-setup.sh" "Initial Setup"; then
        log_error "Initial setup failed - deployment cannot continue" "$SCRIPT_NAME"
        exit 1
    fi
else
    log_error "Initial setup is required for deployment" "$SCRIPT_NAME"
    exit 1
fi

# Step 3: Validation
if prompt_continue "step-015-validate.sh" "Validate configuration and AWS connectivity"; then
    run_step "step-015-validate.sh" "Configuration Validation" true
fi

# Step 4: Infrastructure Deployment (Critical)
if prompt_continue "step-020-deploy.sh" "Deploy Lambda functions and AWS infrastructure"; then
    if ! run_step "step-020-deploy.sh" "Infrastructure Deployment"; then
        log_error "Infrastructure deployment failed - deployment cannot continue" "$SCRIPT_NAME"
        exit 1
    fi
else
    log_error "Infrastructure deployment is required" "$SCRIPT_NAME"
    exit 1
fi

# Step 5: Cognito Configuration
if prompt_continue "step-022-update-cognito-client.sh" "Configure Cognito authentication settings"; then
    run_step "step-022-update-cognito-client.sh" "Cognito Configuration" true
fi

# Step 6: Web Files Deployment (Critical)
if prompt_continue "step-025-update-web-files.sh" "Deploy web interface with configured endpoints"; then
    if ! run_step "step-025-update-web-files.sh" "Web Files Deployment"; then
        log_error "Web files deployment failed - application may not work correctly" "$SCRIPT_NAME"
        if [ "$AUTO_APPROVE" = true ]; then
            log_error "Auto-approve mode: stopping due to critical failure" "$SCRIPT_NAME"
            exit 1
        fi
    fi
else
    log_error "Web files deployment is required for application to work" "$SCRIPT_NAME"
    exit 1
fi

# Step 7: Test User Creation (Optional)
if [ "$SKIP_USER_CREATION" = false ]; then
    if prompt_continue "step-030-create-user.sh" "Create a test user for application testing"; then
        run_step "step-030-create-user.sh" "Test User Creation" true
    fi
else
    log_info "Test user creation skipped by user request" "$SCRIPT_NAME"
fi

# Step 8: Application Testing (Optional)
if [ "$SKIP_TESTS" = false ]; then
    if prompt_continue "step-040-test.sh" "Test deployed application functionality"; then
        run_step "step-040-test.sh" "Application Testing" true
    fi
else
    log_info "Application testing skipped by user request" "$SCRIPT_NAME"
fi

# Step 9: EventBridge Configuration (Optional)
if prompt_continue "step-050-configure-eventbridge.sh" "Configure EventBridge for event publishing"; then
    run_step "step-050-configure-eventbridge.sh" "EventBridge Configuration" true
fi

# Clean up temporary files
rm -f /tmp/step-*.log 2>/dev/null

# Final status and summary
echo
echo -e "${CYAN}=================================================="
echo -e "           DEPLOYMENT COMPLETED"
echo -e "==================================================${NC}"

# Load environment to show final URLs
if [ -f ".env" ]; then
    source .env 2>/dev/null || true
fi

create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
log_success "Automated deployment completed successfully!" "$SCRIPT_NAME"

echo
echo -e "${GREEN}🎉 Your CloudDrive application is ready!${NC}"
echo

if [ -n "$CLOUDFRONT_URL" ]; then
    echo -e "${BLUE}📱 Access your applications:${NC}"
    echo -e "${GREEN}  🏠 Dashboard: $CLOUDFRONT_URL${NC}"
    echo -e "${GREEN}  📁 File Manager: $CLOUDFRONT_URL/files.html${NC}"
    echo -e "${GREEN}  🎤 Audio Recorder: $CLOUDFRONT_URL/audio.html${NC}"
    echo
fi

echo -e "${BLUE}📋 Application Configuration:${NC}"
if [ -n "$USER_POOL_ID" ]; then
    echo -e "${BLUE}  👤 User Pool ID: $USER_POOL_ID${NC}"
fi
if [ -n "$S3_BUCKET_NAME" ]; then
    echo -e "${BLUE}  📦 S3 Bucket: $S3_BUCKET_NAME${NC}"
fi
if [ -n "$COGNITO_DOMAIN" ]; then
    echo -e "${BLUE}  🔐 Cognito Domain: $COGNITO_DOMAIN${NC}"
fi

echo
echo -e "${BLUE}🛠️ Management Commands:${NC}"
echo -e "${BLUE}  📊 Check status: ./deployment-status.sh${NC}"
echo -e "${BLUE}  👤 Create users: ./step-030-create-user.sh${NC}"
echo -e "${BLUE}  🧪 Run tests: ./step-040-test.sh${NC}"
echo -e "${BLUE}  🧹 Cleanup: ./step-990-cleanup.sh${NC}"

echo
echo -e "${YELLOW}⚠️ Important Notes:${NC}"
echo -e "${YELLOW}  • CloudFront may take 5-15 minutes to fully propagate${NC}"
echo -e "${YELLOW}  • Create users in Cognito to test authentication${NC}"
echo -e "${YELLOW}  • Check logs in .deployment-state/ for troubleshooting${NC}"

# Show deployment summary
echo
show_deployment_summary "$SCRIPT_NAME"

echo -e "${CYAN}==================================================${NC}"
log_info "Deployment script completed" "$SCRIPT_NAME"