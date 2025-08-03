#!/bin/bash

# Deployment Status Monitoring Script for CloudDrive Serverless Application
# Real-time deployment progress and health monitoring
# Based on Script-Based Sequential Deployment Framework

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" 2>/dev/null || {
    # Fallback functions if error handling not available
    log_info() { echo -e "\033[0;34mINFO:\033[0m $1"; }
    log_warning() { echo -e "\033[1;33mWARNING:\033[0m $1"; }
    log_error() { echo -e "\033[0;31mERROR:\033[0m $1"; }
    log_success() { echo -e "\033[0;32mSUCCESS:\033[0m $1"; }
}

source "$SCRIPT_DIR/step-navigation.sh" 2>/dev/null || {
    # Fallback if navigation not available
    show_deployment_progress() { echo "Navigation system not available"; }
}

SCRIPT_NAME="deployment-status"

# Command line options
REFRESH_INTERVAL=0
CONTINUOUS_MODE=false
SHOW_LOGS=false
SHOW_RESOURCES=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh|-r)
            REFRESH_INTERVAL="$2"
            CONTINUOUS_MODE=true
            shift 2
            ;;
        --logs|-l)
            SHOW_LOGS=true
            shift
            ;;
        --no-resources)
            SHOW_RESOURCES=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Real-time deployment status monitoring for CloudDrive application"
            echo ""
            echo "Options:"
            echo "  --refresh, -r SECONDS    Continuous monitoring with refresh interval"
            echo "  --logs, -l              Show recent log entries"
            echo "  --no-resources          Skip AWS resource health check"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      One-time status check"
            echo "  $0 --refresh 30         Monitor with 30-second refresh"
            echo "  $0 --logs               Show status with recent logs"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to display step status
display_status() {
    local step_name="$1"
    local display_name="${2:-$step_name}"
    local status_file="${DEPLOYMENT_STATE_DIR}/${step_name}.status"
    
    if [ -f "$status_file" ]; then
        local status=$(cat "$status_file" 2>/dev/null)
        case "$status" in
            "completed")
                echo -e "${GREEN}✅ $display_name${NC}"
                ;;
            "in_progress")
                echo -e "${BLUE}🔄 $display_name${NC} (in progress)"
                ;;
            "failed")
                echo -e "${RED}❌ $display_name${NC} (failed)"
                ;;
            *)
                echo -e "${YELLOW}⭕ $display_name${NC} (unknown status)"
                ;;
        esac
    else
        echo -e "${YELLOW}⭕ $display_name${NC} (not started)"
    fi
}

# Function to check AWS CloudFormation stack status
check_cloudformation_status() {
    if [ ! -f ".env" ]; then
        log_warning "No .env file found - cannot check CloudFormation status" "$SCRIPT_NAME"
        return 1
    fi
    
    source .env 2>/dev/null || return 1
    
    if [ -z "$APP_NAME" ] || [ -z "$STAGE" ]; then
        log_warning "APP_NAME or STAGE not set in .env" "$SCRIPT_NAME"
        return 1
    fi
    
    local stack_name="${APP_NAME}-${STAGE}"
    
    echo -e "${BLUE}☁️ CloudFormation Stack Status:${NC}"
    
    if aws sts get-caller-identity > /dev/null 2>&1; then
        local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].StackStatus" --output text 2>/dev/null)
        
        if [ -n "$stack_status" ] && [ "$stack_status" != "None" ]; then
            case "$stack_status" in
                "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                    echo -e "${GREEN}  ✅ Stack: $stack_name ($stack_status)${NC}"
                    ;;
                "CREATE_IN_PROGRESS"|"UPDATE_IN_PROGRESS")
                    echo -e "${BLUE}  🔄 Stack: $stack_name ($stack_status)${NC}"
                    ;;
                "CREATE_FAILED"|"UPDATE_FAILED"|"DELETE_FAILED")
                    echo -e "${RED}  ❌ Stack: $stack_name ($stack_status)${NC}"
                    ;;
                "DELETE_COMPLETE")
                    echo -e "${YELLOW}  🗑️ Stack: $stack_name (deleted)${NC}"
                    ;;
                *)
                    echo -e "${YELLOW}  ⚠️ Stack: $stack_name ($stack_status)${NC}"
                    ;;
            esac
            
            # Show stack creation time
            local creation_time=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].CreationTime" --output text 2>/dev/null)
            if [ -n "$creation_time" ]; then
                echo -e "${BLUE}  🕐 Created: $creation_time${NC}"
            fi
        else
            echo -e "${YELLOW}  ⭕ Stack: $stack_name (not found)${NC}"
        fi
    else
        echo -e "${RED}  ❌ Cannot check stack status (AWS credentials invalid)${NC}"
    fi
    
    echo
}

# Function to check AWS resource health
check_aws_resources() {
    if [ ! -f ".env" ] || [ "$SHOW_RESOURCES" = false ]; then
        return 0
    fi
    
    source .env 2>/dev/null || return 1
    
    echo -e "${BLUE}🌐 AWS Resource Health:${NC}"
    
    # Check S3 bucket
    if [ -n "$S3_BUCKET_NAME" ]; then
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
            local object_count=$(aws s3 ls s3://$S3_BUCKET_NAME --recursive --summarize 2>/dev/null | grep "Total Objects:" | cut -d: -f2 | xargs || echo "0")
            echo -e "${GREEN}  ✅ S3 Bucket: $S3_BUCKET_NAME ($object_count objects)${NC}"
        else
            echo -e "${RED}  ❌ S3 Bucket: $S3_BUCKET_NAME (not accessible)${NC}"
        fi
    fi
    
    # Check CloudFront distribution
    if [ -n "$CLOUDFRONT_URL" ]; then
        local distribution_id=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(DomainName, '$(echo $CLOUDFRONT_URL | sed 's|https://||')')]|[0].Id" --output text 2>/dev/null)
        if [ -n "$distribution_id" ] && [ "$distribution_id" != "None" ]; then
            local dist_status=$(aws cloudfront get-distribution --id "$distribution_id" --query "Distribution.Status" --output text 2>/dev/null)
            echo -e "${GREEN}  ✅ CloudFront: $distribution_id ($dist_status)${NC}"
        else
            echo -e "${YELLOW}  ⭕ CloudFront: Not found${NC}"
        fi
    fi
    
    # Check Cognito User Pool
    if [ -n "$USER_POOL_ID" ]; then
        if aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" > /dev/null 2>&1; then
            local user_count=$(aws cognito-idp list-users --user-pool-id "$USER_POOL_ID" --query "length(Users)" --output text 2>/dev/null || echo "0")
            echo -e "${GREEN}  ✅ Cognito User Pool: $USER_POOL_ID ($user_count users)${NC}"
        else
            echo -e "${RED}  ❌ Cognito User Pool: $USER_POOL_ID (not accessible)${NC}"
        fi
    fi
    
    # Check Lambda functions
    if [ -n "$APP_NAME" ] && [ -n "$STAGE" ]; then
        local lambda_count=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, '${APP_NAME}-${STAGE}')]" --output json 2>/dev/null | jq length 2>/dev/null || echo "0")
        if [ "$lambda_count" -gt 0 ]; then
            echo -e "${GREEN}  ✅ Lambda Functions: $lambda_count deployed${NC}"
        else
            echo -e "${YELLOW}  ⭕ Lambda Functions: None found${NC}"
        fi
    fi
    
    # Check API Gateway
    if [ -n "$API_ENDPOINT" ]; then
        local api_id=$(echo "$API_ENDPOINT" | grep -o 'https://[^.]*' | sed 's|https://||')
        if aws apigateway get-rest-api --rest-api-id "$api_id" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ API Gateway: $api_id${NC}"
        else
            echo -e "${RED}  ❌ API Gateway: $api_id (not accessible)${NC}"
        fi
    fi
    
    echo
}

# Function to check service endpoints
check_service_endpoints() {
    if [ ! -f ".env" ]; then
        return 0
    fi
    
    source .env 2>/dev/null || return 1
    
    echo -e "${BLUE}🔗 Service Endpoints:${NC}"
    
    # Check CloudFront URL
    if [ -n "$CLOUDFRONT_URL" ]; then
        if curl -s --max-time 10 "$CLOUDFRONT_URL" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Web Application: $CLOUDFRONT_URL${NC}"
        else
            echo -e "${YELLOW}  ⚠️ Web Application: $CLOUDFRONT_URL (not responding)${NC}"
        fi
    fi
    
    # Check API endpoints
    if [ -n "$CLOUDFRONT_API_ENDPOINT" ]; then
        # Note: API endpoints require authentication, so we can't test them directly
        echo -e "${BLUE}  ℹ️ API Endpoint: $CLOUDFRONT_API_ENDPOINT (requires auth)${NC}"
    fi
    
    if [ -n "$AUDIO_API_ENDPOINT" ]; then
        echo -e "${BLUE}  ℹ️ Audio API: $AUDIO_API_ENDPOINT (requires auth)${NC}"
    fi
    
    echo
}

# Function to show error summary
show_error_summary() {
    local error_file="${DEPLOYMENT_STATE_DIR}/errors.log"
    local warning_file="${DEPLOYMENT_STATE_DIR}/warnings.log"
    
    if [ -f "$error_file" ] && [ -s "$error_file" ]; then
        local error_count=$(wc -l < "$error_file" 2>/dev/null || echo "0")
        echo -e "${RED}❌ Recent Errors ($error_count total):${NC}"
        tail -n 5 "$error_file" 2>/dev/null | while read -r line; do
            echo -e "${RED}    $line${NC}"
        done
        echo
    fi
    
    if [ -f "$warning_file" ] && [ -s "$warning_file" ]; then
        local warning_count=$(wc -l < "$warning_file" 2>/dev/null || echo "0")
        echo -e "${YELLOW}⚠️ Recent Warnings ($warning_count total):${NC}"
        tail -n 3 "$warning_file" 2>/dev/null | while read -r line; do
            echo -e "${YELLOW}    $line${NC}"
        done
        echo
    fi
}

# Function to show recent deployment logs
show_recent_logs() {
    local log_file="${DEPLOYMENT_STATE_DIR}/deployment.log"
    
    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        echo -e "${BLUE}📋 Recent Activity (last 10 entries):${NC}"
        tail -n 10 "$log_file" 2>/dev/null | while read -r line; do
            if echo "$line" | grep -q "ERROR"; then
                echo -e "${RED}    $line${NC}"
            elif echo "$line" | grep -q "WARNING"; then
                echo -e "${YELLOW}    $line${NC}"
            elif echo "$line" | grep -q "SUCCESS"; then
                echo -e "${GREEN}    $line${NC}"
            else
                echo -e "${BLUE}    $line${NC}"
            fi
        done
        echo
    else
        echo -e "${YELLOW}📋 No recent activity logged${NC}"
        echo
    fi
}

# Function to show next recommended actions
show_next_actions() {
    echo -e "${CYAN}💡 Next Recommended Actions:${NC}"
    
    # Check what steps are completed and suggest next steps
    if ! is_step_completed "step-001-preflight-check"; then
        echo -e "${BLUE}  1. Run preflight check: ./step-001-preflight-check.sh${NC}"
    elif ! is_step_completed "step-010-setup"; then
        echo -e "${BLUE}  1. Run initial setup: ./step-010-setup.sh${NC}"
    elif ! is_step_completed "step-020-deploy"; then
        echo -e "${BLUE}  1. Deploy infrastructure: ./step-020-deploy.sh${NC}"
    elif ! is_step_completed "step-025-update-web-files"; then
        echo -e "${BLUE}  1. Deploy web files: ./step-025-update-web-files.sh${NC}"
    elif ! is_step_completed "step-030-create-user"; then
        echo -e "${BLUE}  1. Create test user: ./step-030-create-user.sh${NC}"
        echo -e "${BLUE}  2. Run tests: ./step-040-test.sh${NC}"
    else
        echo -e "${GREEN}  ✅ Core deployment completed!${NC}"
        echo -e "${BLUE}  • Test your application: ./step-040-test.sh${NC}"
        echo -e "${BLUE}  • Configure EventBridge: ./step-050-configure-eventbridge.sh${NC}"
        
        if [ -n "$CLOUDFRONT_URL" ]; then
            echo -e "${BLUE}  • Access your app: $CLOUDFRONT_URL${NC}"
        fi
    fi
    
    echo
}

# Main status display function
display_deployment_status() {
    clear
    
    echo -e "${CYAN}=================================================="
    echo -e "       CloudDrive Deployment Status Monitor"
    echo -e "==================================================${NC}"
    echo -e "${BLUE}Last Updated: $(date)${NC}"
    echo
    
    # Show step progress
    echo -e "${BLUE}📋 Deployment Progress:${NC}"
    display_status "step-001-preflight-check" "Preflight Check"
    display_status "step-010-setup" "Initial Setup"
    display_status "step-015-validate" "Configuration Validation"
    display_status "step-020-deploy" "Infrastructure Deployment"
    display_status "step-022-update-cognito-client" "Cognito Configuration"
    display_status "step-025-update-web-files" "Web Files Deployment"
    display_status "step-030-create-user" "Test User Creation"
    display_status "step-040-test" "Application Testing"
    display_status "step-050-configure-eventbridge" "EventBridge Configuration"
    echo
    
    # Show overall progress percentage
    if declare -f show_deployment_progress > /dev/null 2>&1; then
        show_deployment_progress "$SCRIPT_NAME"
    fi
    
    # Check CloudFormation status
    if [ "$SHOW_RESOURCES" = true ]; then
        check_cloudformation_status
        check_aws_resources
        check_service_endpoints
    fi
    
    # Show errors and warnings
    show_error_summary
    
    # Show recent logs if requested
    if [ "$SHOW_LOGS" = true ]; then
        show_recent_logs
    fi
    
    # Show next actions
    show_next_actions
    
    # Show refresh info for continuous mode
    if [ "$CONTINUOUS_MODE" = true ]; then
        echo -e "${BLUE}🔄 Refreshing every ${REFRESH_INTERVAL} seconds (Press Ctrl+C to stop)${NC}"
        echo
    fi
}

# Main execution
if [ "$CONTINUOUS_MODE" = true ]; then
    log_info "Starting continuous monitoring (refresh: ${REFRESH_INTERVAL}s)" "$SCRIPT_NAME"
    
    # Trap Ctrl+C to exit gracefully
    trap 'echo -e "\n${BLUE}Monitoring stopped.${NC}"; exit 0' INT
    
    while true; do
        display_deployment_status
        sleep "$REFRESH_INTERVAL"
    done
else
    display_deployment_status
fi