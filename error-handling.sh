#!/bin/bash

# Error Handling Library for CloudDrive Serverless Application
# Based on Script-Based Sequential Deployment Framework
# Provides centralized error handling, logging, and retry logic

# Color definitions for consistent output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables for error tracking
ERROR_COUNT=0
WARNING_COUNT=0
# Use absolute path to handle directory changes (like cd terraform)
DEPLOYMENT_STATE_DIR="$(pwd)/.deployment-state"

# Ensure deployment state directory and log files exist immediately
if [ ! -d "$DEPLOYMENT_STATE_DIR" ]; then
    mkdir -p "$DEPLOYMENT_STATE_DIR" 2>/dev/null || {
        echo "Warning: Could not create deployment state directory"
        # Fallback to current directory for logs
        DEPLOYMENT_STATE_DIR="."
    }
fi

# Initialize log files if they don't exist
touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
touch "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true

# Function to log error messages with timestamps
log_error() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    ERROR_COUNT=$((ERROR_COUNT + 1))
    
    # Display to console with color
    echo -e "${RED}❌ ERROR [${script_name}]: ${message}${NC}" >&2
    
    # Log to files with error handling
    echo "${timestamp} ERROR [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
    echo "${timestamp} ERROR [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log warning messages with timestamps
log_warning() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    WARNING_COUNT=$((WARNING_COUNT + 1))
    
    # Display to console with color
    echo -e "${YELLOW}⚠️ WARNING [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} WARNING [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
    echo "${timestamp} WARNING [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log informational messages with timestamps
log_info() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Display to console with color
    echo -e "${BLUE}ℹ️ INFO [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} INFO [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to log success messages with timestamps
log_success() {
    local message="$1"
    local script_name="${2:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Display to console with color
    echo -e "${GREEN}✅ SUCCESS [${script_name}]: ${message}${NC}"
    
    # Log to files with error handling
    echo "${timestamp} SUCCESS [${script_name}]: ${message}" >> "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
}

# Function to check if a command exists
check_command_exists() {
    local command="$1"
    local install_url="${2:-}"
    local script_name="${3:-unknown}"
    
    if ! command -v "$command" &> /dev/null; then
        log_error "Required command '$command' not found" "$script_name"
        if [ -n "$install_url" ]; then
            echo -e "${YELLOW}💡 Installation guide: $install_url${NC}"
        fi
        return 1
    else
        log_info "Command '$command' found" "$script_name"
        return 0
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    local script_name="${1:-unknown}"
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured properly" "$script_name"
        echo -e "${YELLOW}💡 Run 'aws configure' to set up your credentials${NC}"
        return 1
    else
        local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        local region=$(aws configure get region 2>/dev/null || echo "not-set")
        log_info "AWS credentials valid (Account: $account_id, Region: $region)" "$script_name"
        return 0
    fi
}

# Function to retry commands with exponential backoff
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local script_name="$3"
    shift 3
    local cmd=("$@")
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: ${cmd[*]}" "$script_name"
        
        if "${cmd[@]}"; then
            log_success "Command succeeded on attempt $attempt" "$script_name"
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_warning "Command failed, retrying in ${delay}s..." "$script_name"
            sleep "$delay"
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        ((attempt++))
    done
    
    log_error "Command failed after $max_attempts attempts: ${cmd[*]}" "$script_name"
    return 1
}

# Function to create checkpoints for state tracking
create_checkpoint() {
    local step_name="$1"
    local status="$2"  # pending, in_progress, completed, failed
    local script_name="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use absolute path and handle failures gracefully
    local state_dir="$(pwd)/.deployment-state"
    mkdir -p "$state_dir" 2>/dev/null || return 0
    
    echo "${timestamp} ${step_name} ${status}" >> "${state_dir}/checkpoints.log" 2>/dev/null || true
    echo "${status}" > "${state_dir}/${step_name}.status" 2>/dev/null || true
    
    log_info "Checkpoint: ${step_name} -> ${status}" "$script_name"
}

# Function to check if a step was completed
is_step_completed() {
    local step_name="$1"
    local status_file="${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    
    if [ -f "$status_file" ]; then
        local status=$(cat "$status_file" 2>/dev/null)
        [ "$status" = "completed" ]
    else
        return 1
    fi
}

# Function to show deployment summary
show_deployment_summary() {
    local script_name="${1:-deployment}"
    
    echo
    echo -e "${CYAN}=================================================="
    echo -e "             DEPLOYMENT SUMMARY"
    echo -e "==================================================${NC}"
    echo
    
    # Show error and warning counts
    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${RED}❌ Errors: $ERROR_COUNT${NC}"
    else
        echo -e "${GREEN}✅ Errors: 0${NC}"
    fi
    
    if [ $WARNING_COUNT -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Warnings: $WARNING_COUNT${NC}"
    else
        echo -e "${GREEN}✅ Warnings: 0${NC}"
    fi
    
    echo
    
    # Show completed steps
    if [ -f "${DEPLOYMENT_STATE_DIR}/checkpoints.log" ]; then
        echo -e "${BLUE}Completed Steps:${NC}"
        grep "completed" "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null | while read -r line; do
            local step=$(echo "$line" | cut -d' ' -f2)
            echo -e "${GREEN}  ✅ $step${NC}"
        done
        echo
    fi
    
    # Show log file locations
    echo -e "${BLUE}Log Files:${NC}"
    echo -e "  📋 Main Log: ${DEPLOYMENT_STATE_DIR}/deployment.log"
    echo -e "  ❌ Errors: ${DEPLOYMENT_STATE_DIR}/errors.log"
    echo -e "  ⚠️ Warnings: ${DEPLOYMENT_STATE_DIR}/warnings.log"
    echo -e "  📊 Checkpoints: ${DEPLOYMENT_STATE_DIR}/checkpoints.log"
    echo
}

# Function to clean deployment state for fresh start
clean_deployment_state() {
    local script_name="${1:-cleanup}"
    
    if [ -d "$DEPLOYMENT_STATE_DIR" ]; then
        log_info "Cleaning deployment state directory" "$script_name"
        rm -rf "$DEPLOYMENT_STATE_DIR"
        mkdir -p "$DEPLOYMENT_STATE_DIR"
        
        # Re-initialize log files
        touch "${DEPLOYMENT_STATE_DIR}/deployment.log" 2>/dev/null || true
        touch "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || true
        touch "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || true
        touch "${DEPLOYMENT_STATE_DIR}/checkpoints.log" 2>/dev/null || true
        
        ERROR_COUNT=0
        WARNING_COUNT=0
        
        log_success "Deployment state cleaned for fresh start" "$script_name"
    fi
}

# Function to setup error handling for scripts
setup_error_handling() {
    local script_name="$1"
    
    # Enable basic error handling without problematic traps
    set -e
    set -o pipefail
    
    # Don't set error traps - they cause false positives
    # Scripts should handle their own error checking
    
    log_info "Error handling initialized for $script_name" "$script_name"
}

# Function to handle non-critical errors with user choice
handle_non_critical_error() {
    local error_description="$1"
    local script_name="$2"
    local continue_anyway="${3:-false}"
    
    log_warning "$error_description (non-critical)" "$script_name"
    
    if [ "$continue_anyway" = "true" ]; then
        log_info "Continuing deployment despite non-critical error" "$script_name"
        return 0
    else
        echo -e "${YELLOW}Continue anyway? (y/N): ${NC}"
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                log_info "User chose to continue despite error" "$script_name"
                return 0
                ;;
            *)
                log_info "User chose to abort due to error" "$script_name"
                return 1
                ;;
        esac
    fi
}

# Function to check disk space
check_disk_space() {
    local script_name="${1:-preflight}"
    local min_gb="${2:-1}"
    
    local available_gb=$(df . | tail -1 | awk '{print $4}' | xargs -I {} echo "scale=2; {}/1024/1024" | bc 2>/dev/null || echo "0")
    
    if (( $(echo "$available_gb < $min_gb" | bc -l) )); then
        log_error "Insufficient disk space: ${available_gb}GB available, ${min_gb}GB required" "$script_name"
        return 1
    else
        log_info "Disk space OK: ${available_gb}GB available" "$script_name"
        return 0
    fi
}

# Function to validate tool versions
validate_tool_versions() {
    local script_name="${1:-preflight}"
    local warnings=0
    
    # Check Node.js version if available
    if command -v node &> /dev/null; then
        local node_version=$(node --version 2>/dev/null | sed 's/v//')
        local major_version=$(echo "$node_version" | cut -d'.' -f1)
        
        if [ "$major_version" -lt 14 ]; then
            log_warning "Node.js version $node_version is below recommended 14.x" "$script_name"
            warnings=$((warnings + 1))
        else
            log_info "Node.js version $node_version OK" "$script_name"
        fi
    fi
    
    # Check AWS CLI version
    if command -v aws &> /dev/null; then
        local aws_version=$(aws --version 2>&1 | head -1 | cut -d' ' -f1 | cut -d'/' -f2)
        local major_version=$(echo "$aws_version" | cut -d'.' -f1)
        
        if [ "$major_version" -lt 2 ]; then
            log_warning "AWS CLI version $aws_version is below recommended 2.x" "$script_name"
            warnings=$((warnings + 1))
        else
            log_info "AWS CLI version $aws_version OK" "$script_name"
        fi
    fi
    
    return $warnings
}

# Function to show recent errors (for debugging)
show_recent_errors() {
    local count="${1:-5}"
    
    if [ -f "${DEPLOYMENT_STATE_DIR}/errors.log" ]; then
        echo -e "${RED}Recent Errors (last $count):${NC}"
        tail -n "$count" "${DEPLOYMENT_STATE_DIR}/errors.log" 2>/dev/null || echo "No errors logged"
    else
        echo -e "${GREEN}No error log found${NC}"
    fi
}

# Function to show recent warnings (for debugging)
show_recent_warnings() {
    local count="${1:-5}"
    
    if [ -f "${DEPLOYMENT_STATE_DIR}/warnings.log" ]; then
        echo -e "${YELLOW}Recent Warnings (last $count):${NC}"
        tail -n "$count" "${DEPLOYMENT_STATE_DIR}/warnings.log" 2>/dev/null || echo "No warnings logged"
    else
        echo -e "${GREEN}No warning log found${NC}"
    fi
}

# Export functions for use in other scripts
export -f log_error log_warning log_info log_success
export -f check_command_exists check_aws_credentials
export -f retry_command create_checkpoint is_step_completed
export -f show_deployment_summary clean_deployment_state
export -f setup_error_handling handle_non_critical_error
export -f check_disk_space validate_tool_versions
export -f show_recent_errors show_recent_warnings

# Export variables
export DEPLOYMENT_STATE_DIR ERROR_COUNT WARNING_COUNT
export RED GREEN BLUE YELLOW CYAN BOLD NC