#!/bin/bash

# CloudDrive Serverless Application - Preflight Check
# This script validates all system prerequisites before deployment
# Run this first to ensure your environment is ready for deployment

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-001-preflight-check"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Show step purpose
show_step_purpose "step-001-preflight-check.sh"

echo -e "${CYAN}=================================================="
echo -e "        CloudDrive Serverless Application"
echo -e "             PREFLIGHT CHECK"
echo -e "==================================================${NC}"
echo
log_info "Starting comprehensive preflight check" "$SCRIPT_NAME"
echo

# Track issues found
CRITICAL_ISSUES=0
WARNING_ISSUES=0

echo -e "${BLUE}🔧 CHECKING REQUIRED TOOLS${NC}"
echo "================================"

# Check AWS CLI
if check_command_exists "aws" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" "$SCRIPT_NAME"; then
    # Check AWS CLI version
    aws_version=$(aws --version 2>&1 | head -1 | cut -d' ' -f1 | cut -d'/' -f2)
    major_version=$(echo "$aws_version" | cut -d'.' -f1)
    
    if [ "$major_version" -ge 2 ]; then
        log_success "AWS CLI version $aws_version (recommended)" "$SCRIPT_NAME"
    else
        log_warning "AWS CLI version $aws_version is below recommended 2.x" "$SCRIPT_NAME"
        echo -e "${YELLOW}💡 Consider upgrading to AWS CLI v2 for better performance${NC}"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
else
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check Node.js
if check_command_exists "node" "https://nodejs.org/en/download/" "$SCRIPT_NAME"; then
    node_version=$(node --version 2>/dev/null | sed 's/v//')
    major_version=$(echo "$node_version" | cut -d'.' -f1)
    
    if [ "$major_version" -ge 14 ]; then
        log_success "Node.js version $node_version (compatible)" "$SCRIPT_NAME"
    else
        log_error "Node.js version $node_version is below minimum required 14.x" "$SCRIPT_NAME"
        echo -e "${YELLOW}💡 Please upgrade to Node.js 14.x or higher${NC}"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
else
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check npm
if check_command_exists "npm" "https://nodejs.org/en/download/" "$SCRIPT_NAME"; then
    npm_version=$(npm --version 2>/dev/null)
    log_info "npm version $npm_version" "$SCRIPT_NAME"
else
    log_error "npm not found (should come with Node.js)" "$SCRIPT_NAME"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check Git
if check_command_exists "git" "https://git-scm.com/downloads" "$SCRIPT_NAME"; then
    git_version=$(git --version 2>/dev/null | cut -d' ' -f3)
    log_info "Git version $git_version" "$SCRIPT_NAME"
else
    log_warning "Git not found (optional but recommended for version control)" "$SCRIPT_NAME"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

# Check jq (useful for JSON parsing)
if check_command_exists "jq" "https://stedolan.github.io/jq/download/" "$SCRIPT_NAME"; then
    jq_version=$(jq --version 2>/dev/null | sed 's/jq-//')
    log_info "jq version $jq_version" "$SCRIPT_NAME"
else
    log_warning "jq not found (recommended for JSON processing)" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Install with: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)${NC}"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

# Check curl
if check_command_exists "curl" "https://curl.se/download.html" "$SCRIPT_NAME"; then
    log_info "curl found" "$SCRIPT_NAME"
else
    log_warning "curl not found (useful for API testing)" "$SCRIPT_NAME"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

# Check bc (for calculations)
if check_command_exists "bc" "" "$SCRIPT_NAME"; then
    log_info "bc calculator found" "$SCRIPT_NAME"
else
    log_warning "bc calculator not found (used for disk space calculations)" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Install with: sudo apt-get install bc (Ubuntu) or brew install bc (macOS)${NC}"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

echo
echo -e "${BLUE}☁️ CHECKING AWS CONFIGURATION${NC}"
echo "==============================="

# Check AWS credentials
if check_aws_credentials "$SCRIPT_NAME"; then
    # Get AWS account information
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    user_arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)
    region=$(aws configure get region 2>/dev/null || echo "not-configured")
    
    log_success "AWS Account ID: $account_id" "$SCRIPT_NAME"
    log_info "AWS User ARN: $user_arn" "$SCRIPT_NAME"
    
    if [ "$region" != "not-configured" ]; then
        log_success "AWS Region: $region" "$SCRIPT_NAME"
    else
        log_warning "AWS region not configured, will use default" "$SCRIPT_NAME"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Check if region supports all services we need
    case "$region" in
        us-east-1|us-east-2|us-west-1|us-west-2|eu-west-1|eu-central-1|ap-southeast-1|ap-northeast-1)
            log_success "Region $region supports all required AWS services" "$SCRIPT_NAME"
            ;;
        *)
            log_warning "Region $region may have limited service availability" "$SCRIPT_NAME"
            echo -e "${YELLOW}💡 Consider using us-east-2, us-west-2, or eu-west-1 for full service support${NC}"
            WARNING_ISSUES=$((WARNING_ISSUES + 1))
            ;;
    esac
else
    log_error "AWS credentials not configured or invalid" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Run 'aws configure' to set up your credentials${NC}"
    echo -e "${YELLOW}💡 You need: Access Key ID, Secret Access Key, Region${NC}"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

echo
echo -e "${BLUE}🔐 CHECKING AWS PERMISSIONS${NC}"
echo "============================"

# Test basic AWS permissions (non-destructive checks only)
if aws sts get-caller-identity &> /dev/null; then
    log_info "Testing AWS service permissions (non-destructive)" "$SCRIPT_NAME"
    
    # Test S3 permissions
    if aws s3 ls > /dev/null 2>&1; then
        log_success "S3 list permissions OK" "$SCRIPT_NAME"
    else
        log_warning "S3 list permissions may be limited" "$SCRIPT_NAME"
        echo -e "${YELLOW}💡 Your user needs S3 permissions for bucket operations${NC}"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Test CloudFormation permissions
    if aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE > /dev/null 2>&1; then
        log_success "CloudFormation list permissions OK" "$SCRIPT_NAME"
    else
        log_warning "CloudFormation permissions may be limited" "$SCRIPT_NAME"
        echo -e "${YELLOW}💡 Your user needs CloudFormation permissions for deployment${NC}"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Test Lambda permissions
    if aws lambda list-functions > /dev/null 2>&1; then
        log_success "Lambda list permissions OK" "$SCRIPT_NAME"
    else
        log_warning "Lambda permissions may be limited" "$SCRIPT_NAME"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Test Cognito permissions
    if aws cognito-idp list-user-pools --max-results 1 > /dev/null 2>&1; then
        log_success "Cognito permissions OK" "$SCRIPT_NAME"
    else
        log_warning "Cognito permissions may be limited" "$SCRIPT_NAME"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Test CloudFront permissions
    if aws cloudfront list-distributions > /dev/null 2>&1; then
        log_success "CloudFront permissions OK" "$SCRIPT_NAME"
    else
        log_warning "CloudFront permissions may be limited" "$SCRIPT_NAME"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
    
    # Test API Gateway permissions
    if aws apigateway get-rest-apis > /dev/null 2>&1; then
        log_success "API Gateway permissions OK" "$SCRIPT_NAME"
    else
        log_warning "API Gateway permissions may be limited" "$SCRIPT_NAME"
        WARNING_ISSUES=$((WARNING_ISSUES + 1))
    fi
else
    log_error "Cannot test AWS permissions - credentials invalid" "$SCRIPT_NAME"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

echo
echo -e "${BLUE}💾 CHECKING SYSTEM RESOURCES${NC}"
echo "============================="

# Check disk space
if command -v bc &> /dev/null; then
    if check_disk_space "$SCRIPT_NAME" 2; then
        log_success "Sufficient disk space available" "$SCRIPT_NAME"
    else
        log_error "Insufficient disk space" "$SCRIPT_NAME"
        echo -e "${YELLOW}💡 Free up at least 2GB of disk space before deployment${NC}"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
else
    log_warning "Cannot check disk space (bc not available)" "$SCRIPT_NAME"
fi

# Check memory (if possible)
if [ -r /proc/meminfo ]; then
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' 2>/dev/null)
    
    if [ -n "$mem_available" ]; then
        mem_available_gb=$((mem_available / 1024 / 1024))
        if [ "$mem_available_gb" -ge 1 ]; then
            log_success "Available memory: ${mem_available_gb}GB" "$SCRIPT_NAME"
        else
            log_warning "Low available memory: ${mem_available_gb}GB" "$SCRIPT_NAME"
            WARNING_ISSUES=$((WARNING_ISSUES + 1))
        fi
    fi
fi

echo
echo -e "${BLUE}📁 CHECKING PROJECT STRUCTURE${NC}"
echo "=============================="

# Check if we're in a project directory
current_dir=$(basename "$(pwd)")
log_info "Current directory: $current_dir" "$SCRIPT_NAME"

# Check for required template files
required_files=(
    "serverless.yml.template"
    "web/app.js.template" 
    "web/audio.html.template"
    "api/handler.js"
    "api/s3.js"
    "api/audio.js"
)

missing_files=0
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        log_success "Found: $file" "$SCRIPT_NAME"
    else
        log_error "Missing: $file" "$SCRIPT_NAME"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    log_error "$missing_files required files missing" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Make sure you're in the correct project directory${NC}"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Check if .env already exists (from previous run)
if [ -f ".env" ]; then
    log_info "Found existing .env file from previous setup" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 You can run step-10-setup.sh to reconfigure or proceed with existing settings${NC}"
else
    log_info "No .env file found (expected for first run)" "$SCRIPT_NAME"
fi

echo
echo -e "${BLUE}🌐 CHECKING NETWORK CONNECTIVITY${NC}"
echo "================================"

# Test internet connectivity
if curl -s --max-time 10 https://aws.amazon.com > /dev/null 2>&1; then
    log_success "Internet connectivity OK" "$SCRIPT_NAME"
else
    log_warning "Internet connectivity test failed" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Check your internet connection and proxy settings${NC}"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

# Test AWS API connectivity
if aws sts get-caller-identity > /dev/null 2>&1; then
    log_success "AWS API connectivity OK" "$SCRIPT_NAME"
else
    log_warning "AWS API connectivity failed" "$SCRIPT_NAME"
    WARNING_ISSUES=$((WARNING_ISSUES + 1))
fi

echo
echo -e "${CYAN}=================================================="
echo -e "             PREFLIGHT CHECK RESULTS"
echo -e "==================================================${NC}"
echo

# Show summary
if [ $CRITICAL_ISSUES -eq 0 ] && [ $WARNING_ISSUES -eq 0 ]; then
    log_success "🎉 All checks passed! Your environment is ready for deployment." "$SCRIPT_NAME"
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
    
elif [ $CRITICAL_ISSUES -eq 0 ]; then
    log_warning "⚠️ Preflight check completed with $WARNING_ISSUES warnings" "$SCRIPT_NAME"
    echo -e "${YELLOW}Your environment should work, but some features may be limited.${NC}"
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
    
else
    log_error "❌ Preflight check failed with $CRITICAL_ISSUES critical issues" "$SCRIPT_NAME"
    echo -e "${RED}Please resolve critical issues before proceeding with deployment.${NC}"
    create_checkpoint "$SCRIPT_NAME" "failed" "$SCRIPT_NAME"
    
    echo
    echo -e "${YELLOW}🔧 COMMON SOLUTIONS:${NC}"
    echo -e "${BLUE}• Install missing tools using your package manager${NC}"
    echo -e "${BLUE}• Run 'aws configure' to set up AWS credentials${NC}"
    echo -e "${BLUE}• Ensure you have sufficient IAM permissions${NC}"
    echo -e "${BLUE}• Free up disk space if needed${NC}"
    echo -e "${BLUE}• Check your internet connection${NC}"
    
    echo
    exit 1
fi

echo
echo -e "${BLUE}📋 SUMMARY:${NC}"
echo -e "${GREEN}✅ Critical Issues: $CRITICAL_ISSUES${NC}"
if [ $WARNING_ISSUES -gt 0 ]; then
    echo -e "${YELLOW}⚠️ Warnings: $WARNING_ISSUES${NC}"
else
    echo -e "${GREEN}⚠️ Warnings: $WARNING_ISSUES${NC}"
fi

echo
echo -e "${BLUE}💡 RECOMMENDED NEXT STEPS:${NC}"
echo -e "${BLUE}1. Address any warnings if possible${NC}"
echo -e "${BLUE}2. Ensure you have sufficient AWS permissions${NC}"
echo -e "${BLUE}3. Review the AWS cost estimates in README.md${NC}"

echo

# Show next step
show_next_step "step-001-preflight-check.sh" "$(dirname "$0")"