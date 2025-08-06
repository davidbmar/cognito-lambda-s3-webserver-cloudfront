#!/bin/bash

# Step Navigation System for CloudDrive Serverless Application
# Based on Script-Based Sequential Deployment Framework
# Provides smart step progression and user guidance

# Source error handling functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/error-handling.sh" ]; then
    source "$SCRIPT_DIR/error-handling.sh"
else
    # Fallback if error handling not available
    log_info() { echo "INFO: $1"; }
    log_warning() { echo "WARNING: $1"; }
    log_error() { echo "ERROR: $1"; }
fi

# Define the deployment sequence with descriptions
declare -A STEP_SEQUENCE=(
    ["step-001-preflight-check.sh"]="step-010-setup.sh"
    ["step-010-setup.sh"]="step-015-validate.sh" 
    ["step-015-validate.sh"]="step-020-deploy.sh"
    ["step-020-deploy.sh"]="step-022-update-cognito-client.sh"
    ["step-022-update-cognito-client.sh"]="step-025-update-web-files.sh"
    ["step-025-update-web-files.sh"]="step-030-create-user.sh"
    ["step-030-create-user.sh"]="step-040-test.sh"
    ["step-040-test.sh"]="step-050-configure-eventbridge.sh"
    ["step-050-configure-eventbridge.sh"]="step-055-test-eventbridge.sh"
    ["step-055-test-eventbridge.sh"]="complete"
)

declare -A STEP_DESCRIPTIONS=(
    ["step-001-preflight-check.sh"]="Validate system prerequisites and dependencies"
    ["step-010-setup.sh"]="Initial AWS setup and configuration"
    ["step-015-validate.sh"]="Validate setup configuration and AWS connectivity"
    ["step-020-deploy.sh"]="Deploy Lambda functions and infrastructure (smart bucket handling)"
    ["step-022-update-cognito-client.sh"]="Configure Cognito client for authentication"
    ["step-025-update-web-files.sh"]="Deploy web interface with configured endpoints"
    ["step-030-create-user.sh"]="Create test Cognito user (optional)"
    ["step-040-test.sh"]="Test application functionality and API endpoints"
    ["step-050-configure-eventbridge.sh"]="Configure EventBridge integration for event publishing"
    ["step-055-test-eventbridge.sh"]="Test EventBridge integration with monitoring guidance"
    ["step-980-cleanup-cognito.sh"]="Clean up Cognito resources (domains and user pools)"
    ["step-990-cleanup.sh"]="Clean up AWS resources (intelligent bucket preservation)"
)

declare -A STEP_PREREQUISITES=(
    ["step-001-preflight-check.sh"]=""
    ["step-010-setup.sh"]="step-001-preflight-check.sh"
    ["step-015-validate.sh"]="step-010-setup.sh"
    ["step-020-deploy.sh"]="step-015-validate.sh"
    ["step-022-update-cognito-client.sh"]="step-020-deploy.sh"
    ["step-025-update-web-files.sh"]="step-022-update-cognito-client.sh"
    ["step-030-create-user.sh"]="step-025-update-web-files.sh"
    ["step-040-test.sh"]="step-025-update-web-files.sh"  # Can test without user creation
    ["step-050-configure-eventbridge.sh"]="step-025-update-web-files.sh"
    ["step-055-test-eventbridge.sh"]="step-050-configure-eventbridge.sh"
    ["step-980-cleanup-cognito.sh"]=""  # Can run anytime for pre-cleanup
    ["step-990-cleanup.sh"]=""  # Can run anytime
)

# Function to get current script name
get_current_script() {
    basename "$0"
}

# Function to detect next step based on current script
detect_next_step() {
    local current_script="$1"
    
    if [ -z "$current_script" ]; then
        current_script=$(get_current_script)
    fi
    
    echo "${STEP_SEQUENCE[$current_script]}"
}

# Function to show next step with description
show_next_step() {
    local current_script="$1"
    local script_dir="${2:-.}"
    
    if [ -z "$current_script" ]; then
        current_script=$(get_current_script)
    fi
    
    local next_script=$(detect_next_step "$current_script")
    local script_name="${current_script:-unknown}"
    
    echo
    echo -e "${CYAN}=================================================="
    echo -e "               NEXT STEPS"
    echo -e "==================================================${NC}"
    
    if [[ "$next_script" == "complete" ]]; then
        log_success "Deployment sequence completed!" "$script_name"
        echo
        echo -e "${GREEN}🎉 Your CloudDrive application is ready!${NC}"
        
        # Show application URLs if available
        if [ -f ".env" ]; then
            source .env 2>/dev/null || true
            if [ -n "$CLOUDFRONT_URL" ]; then
                echo -e "${BLUE}🌐 Application URL: $CLOUDFRONT_URL${NC}"
                echo -e "${BLUE}📁 File Manager: $CLOUDFRONT_URL/files.html${NC}"
                echo -e "${BLUE}🎤 Audio Recorder: $CLOUDFRONT_URL/audio.html${NC}"
            fi
        fi
        
        echo
        echo -e "${BLUE}Optional next steps:${NC}"
        if [ ! -f "${script_dir}/step-030-create-user.sh" ] || ! is_step_completed "step-030-create-user"; then
            echo -e "${BLUE}  👤 Create test user: ./step-030-create-user.sh${NC}"
        fi
        echo -e "${BLUE}  🧪 Run comprehensive tests: ./step-040-test.sh${NC}"
        echo -e "${BLUE}  🔗 Configure EventBridge: ./step-050-configure-eventbridge.sh${NC}"
        echo -e "${BLUE}  🧹 Clean up resources: ./step-990-cleanup.sh${NC}"
        
        # Show deployment summary
        show_deployment_summary "$script_name"
        
    elif [ -n "$next_script" ]; then
        echo -e "${GREEN}✅ Current step completed successfully!${NC}"
        echo
        echo -e "${CYAN}👉 Next step: ${BOLD}$next_script${NC}"
        
        if [[ -n "${STEP_DESCRIPTIONS[$next_script]}" ]]; then
            echo -e "${BLUE}   📋 ${STEP_DESCRIPTIONS[$next_script]}${NC}"
        fi
        
        # Check if next script exists
        local next_path="${script_dir}/${next_script}"
        if [ -f "$next_path" ]; then
            echo -e "${BLUE}   🚀 Run: ./$next_script${NC}"
            
            # Make sure it's executable
            if [ ! -x "$next_path" ]; then
                log_warning "Next script is not executable, fixing permissions" "$script_name"
                chmod +x "$next_path" 2>/dev/null || log_warning "Could not make script executable" "$script_name"
            fi
        else
            log_warning "Next script not found: $next_path" "$script_name"
            echo -e "${YELLOW}   ⚠️ Script file missing, you may need to create it${NC}"
        fi
        
        # Show application URL if available
        if [ -f ".env" ]; then
            source .env 2>/dev/null || true
            if [ -n "$CLOUDFRONT_URL" ]; then
                echo
                echo -e "${BLUE}🌐 Current application URL: $CLOUDFRONT_URL${NC}"
            fi
        fi
        
    else
        log_warning "No next step defined for current script: $current_script" "$script_name"
        echo -e "${YELLOW}⚠️ Unknown next step. Check your deployment sequence.${NC}"
    fi
    
    echo -e "${CYAN}==================================================${NC}"
    echo
}

# Function to validate prerequisites for current step
validate_prerequisites() {
    local current_script="$1"
    local script_name="${current_script:-unknown}"
    
    if [ -z "$current_script" ]; then
        current_script=$(get_current_script)
    fi
    
    local required_step="${STEP_PREREQUISITES[$current_script]}"
    
    if [ -z "$required_step" ]; then
        log_info "No prerequisites required for $current_script" "$script_name"
        return 0
    fi
    
    log_info "Checking prerequisites for $current_script" "$script_name"
    
    # Check if required step was completed
    local step_base=$(basename "$required_step" .sh)
    if is_step_completed "$step_base"; then
        log_success "Prerequisite satisfied: $required_step completed" "$script_name"
        return 0
    else
        log_error "Prerequisite not met: $required_step must be completed first" "$script_name"
        echo -e "${YELLOW}💡 Run ./$required_step first${NC}"
        return 1
    fi
}

# Function to show current step purpose
show_step_purpose() {
    local current_script="$1"
    
    if [ -z "$current_script" ]; then
        current_script=$(get_current_script)
    fi
    
    local description="${STEP_DESCRIPTIONS[$current_script]}"
    
    if [[ -n "$description" ]]; then
        echo -e "${CYAN}🎯 Purpose: $description${NC}"
        echo
    fi
}

# Function to show deployment progress
show_deployment_progress() {
    local script_name="${1:-navigation}"
    
    echo -e "${CYAN}📊 DEPLOYMENT PROGRESS${NC}"
    echo -e "${CYAN}=====================${NC}"
    
    local completed_count=0
    local total_count=0
    
    # Count all steps except cleanup
    for step in "${!STEP_DESCRIPTIONS[@]}"; do
        if [[ "$step" != "step-990-cleanup.sh" ]]; then
            total_count=$((total_count + 1))
            
            local step_base=$(basename "$step" .sh)
            if is_step_completed "$step_base"; then
                echo -e "${GREEN}✅ $step${NC} - ${STEP_DESCRIPTIONS[$step]}"
                completed_count=$((completed_count + 1))
            else
                echo -e "${YELLOW}⭕ $step${NC} - ${STEP_DESCRIPTIONS[$step]}"
            fi
        fi
    done
    
    echo
    echo -e "${BLUE}Progress: $completed_count/$total_count steps completed${NC}"
    
    # Calculate and show percentage
    if [ $total_count -gt 0 ]; then
        local percentage=$((completed_count * 100 / total_count))
        echo -e "${BLUE}Completion: ${percentage}%${NC}"
    fi
    
    echo
}

# Function to show all available steps
show_all_steps() {
    echo -e "${CYAN}📋 AVAILABLE DEPLOYMENT STEPS${NC}"
    echo -e "${CYAN}==============================${NC}"
    
    # Show steps in order
    local current_step="step-001-preflight-check.sh"
    local step_number=1
    
    while [ "$current_step" != "complete" ] && [ $step_number -lt 20 ]; do
        if [[ -n "${STEP_DESCRIPTIONS[$current_step]}" ]]; then
            local step_base=$(basename "$current_step" .sh)
            local status_icon="⭕"
            
            if is_step_completed "$step_base"; then
                status_icon="✅"
            fi
            
            echo -e "${status_icon} ${BOLD}$current_step${NC}"
            echo -e "   ${STEP_DESCRIPTIONS[$current_step]}"
            echo
        fi
        
        current_step="${STEP_SEQUENCE[$current_step]}"
        step_number=$((step_number + 1))
    done
    
    # Show cleanup step separately
    echo -e "${YELLOW}🧹 ${BOLD}step-990-cleanup.sh${NC}"
    echo -e "   ${STEP_DESCRIPTIONS['step-990-cleanup.sh']}"
    echo
}

# Function to validate step execution environment
validate_step_environment() {
    local current_script="$1"
    local script_name="${current_script:-unknown}"
    
    # Check if we're in the right directory (contains .env or serverless.yml)
    if [ ! -f ".env" ] && [ ! -f "serverless.yml" ] && [ ! -f "serverless.yml.template" ]; then
        log_warning "Not in deployment directory (missing .env or serverless.yml)" "$script_name"
        echo -e "${YELLOW}💡 Make sure you're in the correct project directory${NC}"
        return 1
    fi
    
    # Load environment if available
    if [ -f ".env" ]; then
        source .env 2>/dev/null || log_warning "Could not load .env file" "$script_name"
    fi
    
    return 0
}

# Function to estimate remaining time
estimate_remaining_time() {
    local script_name="${1:-navigation}"
    
    # Simple time estimates in minutes for each step
    declare -A STEP_TIME_ESTIMATES=(
        ["step-001-preflight-check.sh"]=1
        ["step-010-setup.sh"]=2
        ["step-015-validate.sh"]=1
        ["step-020-deploy.sh"]=8
        ["step-022-update-cognito-client.sh"]=2
        ["step-025-update-web-files.sh"]=3
        ["step-030-create-user.sh"]=1
        ["step-040-test.sh"]=2
        ["step-050-configure-eventbridge.sh"]=3
    )
    
    local remaining_time=0
    
    for step in "${!STEP_TIME_ESTIMATES[@]}"; do
        local step_base=$(basename "$step" .sh)
        if ! is_step_completed "$step_base"; then
            remaining_time=$((remaining_time + STEP_TIME_ESTIMATES[$step]))
        fi
    done
    
    if [ $remaining_time -gt 0 ]; then
        echo -e "${BLUE}⏱️ Estimated remaining time: ~${remaining_time} minutes${NC}"
    else
        echo -e "${GREEN}🎉 All major steps completed!${NC}"
    fi
}

# Export functions for use in other scripts
export -f get_current_script detect_next_step show_next_step
export -f validate_prerequisites show_step_purpose
export -f show_deployment_progress show_all_steps
export -f validate_step_environment estimate_remaining_time