#!/bin/bash

# Script Sequence Definition
# This file defines the order of scripts and their descriptions

declare -A SCRIPT_SEQUENCE=(
    ["step-10-setup.sh"]="step-15-validate.sh"
    ["step-15-validate.sh"]="step-20-deploy.sh"
    ["step-20-deploy.sh"]="step-22-update-cognito-client.sh"
    ["step-22-update-cognito-client.sh"]="step-25-update-web-files.sh"
    ["step-25-update-web-files.sh"]="step-30-create-user.sh"
    ["step-30-create-user.sh"]="step-40-test.sh"
    ["step-40-test.sh"]="complete"
)

declare -A SCRIPT_DESCRIPTIONS=(
    ["step-10-setup.sh"]="Initial AWS setup and configuration"
    ["step-15-validate.sh"]="Validate setup configuration"
    ["step-20-deploy.sh"]="Deploy Lambda functions and infrastructure (includes audio)"
    ["step-22-update-cognito-client.sh"]="Configure Cognito client for authentication"
    ["step-25-update-web-files.sh"]="Deploy web interface with configured endpoints"
    ["step-30-create-user.sh"]="Create test Cognito user"
    ["step-40-test.sh"]="Test application functionality"
    ["step-99-cleanup.sh"]="Clean up AWS resources"
)

# Function to display what current script does
print_script_purpose() {
    local current_script=$(get_current_script)
    local description="${SCRIPT_DESCRIPTIONS[$current_script]}"
    
    if [[ -n "$description" ]]; then
        echo "🎯 Purpose: $description"
        echo ""
    fi
}

# Function to get the current script name
get_current_script() {
    basename "$0"
}

# Function to get next step
get_next_step() {
    local current_script=$(get_current_script)
    echo "${SCRIPT_SEQUENCE[$current_script]}"
}

# Function to print next steps
print_next_steps() {
    local next_script=$(get_next_step)
    
    echo ""
    echo "===================================================="
    
    if [[ "$next_script" == "complete" ]]; then
        echo "✅ Setup Complete!"
        echo ""
        echo "Your application is ready at:"
        echo "🌐 ${CLOUDFRONT_URL}"
        echo ""
        echo "Optional next steps:"
        echo "- Create additional users with './step-30-create-user.sh'"
        echo "- Run tests with './step-40-test.sh'"
        echo "- Clean up resources with './step-99-cleanup.sh'"
    else
        echo "✅ Current step completed successfully!"
        echo ""
        echo "Next step:"
        echo "👉 Run './$next_script'"
        if [[ -n "${SCRIPT_DESCRIPTIONS[$next_script]}" ]]; then
            echo "   ${SCRIPT_DESCRIPTIONS[$next_script]}"
        fi
        echo ""
        echo "Your application URL:"
        echo "🌐 ${CLOUDFRONT_URL:-'Will be available after deployment'}"
    fi
    
    echo "===================================================="
}

# Function to check if all required env vars are set
check_env_vars() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "❌ Error: Missing required environment variables:"
        printf '%s\n' "${missing_vars[@]}"
        echo ""
        echo "Please run './step-10-setup.sh' first"
        return 1
    fi
    
    return 0
}

# Function to update setup status
update_setup_status() {
    local script_name=$(get_current_script)
    echo "${script_name}=$(date)" >> .setup-status
}

# Function to load configuration
load_config() {
    CONFIG_FILE=".env"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo "❌ Error: Configuration file not found."
        echo "Please run './step-10-setup.sh' first"
        return 1
    fi
}