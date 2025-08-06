#!/bin/bash

# Step 980: Cognito Domain and User Pool Cleanup Script
# This script handles Cognito resources that can block CloudFormation stack deletion
# Must be run before step-990-cleanup.sh to ensure clean stack deletion

# Source error handling and environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/error-handling.sh" ]; then
    source "$SCRIPT_DIR/error-handling.sh"
else
    echo "ERROR: error-handling.sh not found"
    exit 1
fi

# Initialize error handling
SCRIPT_NAME="step-980-cleanup-cognito"
setup_error_handling "$SCRIPT_NAME" 2>/dev/null || true
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME" 2>/dev/null || true

# Load environment variables
if [ -f .env ]; then
    source .env
    log_info "Loaded environment configuration" "$SCRIPT_NAME"
else
    log_error "No .env file found - cannot determine Cognito resources" "$SCRIPT_NAME"
    exit 1
fi

# Check required variables
if [ -z "$USER_POOL_ID" ] && [ -z "$COGNITO_DOMAIN" ]; then
    log_info "No Cognito resources configured - nothing to cleanup" "$SCRIPT_NAME"
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
    exit 0
fi

echo
echo "=================================================="
echo "        Cognito Resources Cleanup Script         "
echo "=================================================="
echo

# PHASE 1: Discovery
echo "📋 PHASE 1: COGNITO RESOURCE DISCOVERY"
echo "=================================================="

COGNITO_DOMAIN_EXISTS=false
USER_POOL_EXISTS=false
IDENTITY_POOL_EXISTS=false

# Check Cognito Domain
if [ -n "$COGNITO_DOMAIN" ]; then
    log_info "Checking Cognito domain: $COGNITO_DOMAIN" "$SCRIPT_NAME"
    DOMAIN_STATUS=$(aws cognito-idp describe-user-pool-domain --domain "$COGNITO_DOMAIN" --query 'DomainDescription.Status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$DOMAIN_STATUS" != "NOT_FOUND" ] && [ "$DOMAIN_STATUS" != "None" ]; then
        COGNITO_DOMAIN_EXISTS=true
        echo "   ✅ Domain: $COGNITO_DOMAIN (Status: $DOMAIN_STATUS)"
    else
        echo "   ❌ Domain: $COGNITO_DOMAIN (Not found or already deleted)"
    fi
fi

# Check User Pool
if [ -n "$USER_POOL_ID" ]; then
    log_info "Checking User Pool: $USER_POOL_ID" "$SCRIPT_NAME"
    USER_POOL_STATUS=$(aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --query 'UserPool.Status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$USER_POOL_STATUS" != "NOT_FOUND" ] && [ "$USER_POOL_STATUS" != "None" ]; then
        USER_POOL_EXISTS=true
        USER_COUNT=$(aws cognito-idp list-users --user-pool-id "$USER_POOL_ID" --query "length(Users)" --output text 2>/dev/null || echo "0")
        echo "   ✅ User Pool: $USER_POOL_ID (Status: $USER_POOL_STATUS)"
        echo "   👥 Users: $USER_COUNT"
    else
        echo "   ❌ User Pool: $USER_POOL_ID (Not found or already deleted)"
    fi
fi

# Check Identity Pool
if [ -n "$IDENTITY_POOL_ID" ]; then
    log_info "Checking Identity Pool: $IDENTITY_POOL_ID" "$SCRIPT_NAME"
    IDENTITY_POOL_NAME=$(aws cognito-identity describe-identity-pool --identity-pool-id "$IDENTITY_POOL_ID" --query 'IdentityPoolName' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$IDENTITY_POOL_NAME" != "NOT_FOUND" ] && [ "$IDENTITY_POOL_NAME" != "None" ]; then
        IDENTITY_POOL_EXISTS=true
        echo "   ✅ Identity Pool: $IDENTITY_POOL_ID ($IDENTITY_POOL_NAME)"
    else
        echo "   ❌ Identity Pool: $IDENTITY_POOL_ID (Not found or already deleted)"
    fi
fi

echo

# Check if anything needs cleanup
if [ "$COGNITO_DOMAIN_EXISTS" = false ] && [ "$USER_POOL_EXISTS" = false ] && [ "$IDENTITY_POOL_EXISTS" = false ]; then
    log_success "No Cognito resources found that need cleanup" "$SCRIPT_NAME"
    echo
    echo "All Cognito resources have already been cleaned up."
    echo "You can proceed directly to step-990-cleanup.sh"
    create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
    exit 0
fi

# PHASE 2: Deletion Plan
echo "📋 PHASE 2: COGNITO DELETION PLAN"
echo "=================================================="
echo
echo "🗑️ Resources that WILL BE DELETED:"
echo

if [ "$COGNITO_DOMAIN_EXISTS" = true ]; then
    echo "  ✓ Cognito Domain: $COGNITO_DOMAIN"
    echo "    ⚠️  This will remove the custom domain for Cognito authentication"
fi

if [ "$USER_POOL_EXISTS" = true ]; then
    echo "  ✓ Cognito User Pool: $USER_POOL_ID"
    if [ "$USER_COUNT" -gt 0 ]; then
        echo "    ⚠️  This will DELETE $USER_COUNT user(s) and all their data"
    fi
fi

if [ "$IDENTITY_POOL_EXISTS" = true ]; then
    echo "  ✓ Cognito Identity Pool: $IDENTITY_POOL_ID"
    echo "    ⚠️  This will remove federated identity access"
fi

echo
echo "=================================================="
echo "⚠️  IMPORTANT WARNINGS:"
echo "• User Pool deletion will permanently remove all users and their data"
echo "• Domain deletion will make the authentication URL unavailable"
echo "• Identity Pool deletion will revoke AWS resource access for users"
echo "• These deletions are IRREVERSIBLE"
echo "=================================================="
echo

# User confirmation
read -p "Do you want to proceed with Cognito cleanup? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    log_info "User cancelled Cognito cleanup" "$SCRIPT_NAME"
    echo "Operation cancelled. Cognito resources were not modified."
    echo "Note: You may need to clean these manually before running step-990-cleanup.sh"
    exit 1
fi

echo
read -p "Type 'DELETE' to confirm permanent removal of Cognito resources: " final_confirm
if [ "$final_confirm" != "DELETE" ]; then
    log_info "User cancelled at final confirmation" "$SCRIPT_NAME"
    echo "Operation cancelled. Cognito resources were not modified."
    exit 1
fi

# PHASE 3: Execution
echo
echo "=================================================="
echo "📋 PHASE 3: EXECUTING COGNITO CLEANUP"
echo "=================================================="
echo

# Delete in proper order: Domain → User Pool → Identity Pool

# 1. Delete Cognito Domain (must be first)
if [ "$COGNITO_DOMAIN_EXISTS" = true ]; then
    log_info "Deleting Cognito domain: $COGNITO_DOMAIN" "$SCRIPT_NAME"
    echo "🌐 Deleting Cognito domain..."
    
    if aws cognito-idp delete-user-pool-domain --domain "$COGNITO_DOMAIN" --user-pool-id "$USER_POOL_ID" 2>/dev/null; then
        log_success "Cognito domain deletion initiated" "$SCRIPT_NAME"
        echo "   ✅ Domain deletion initiated (may take 1-2 minutes)"
        
        # Wait for domain deletion to complete
        echo "   ⏳ Waiting for domain deletion to complete..."
        sleep 5
        
        # Check if deletion completed
        for i in {1..12}; do # Wait up to 60 seconds
            DOMAIN_CHECK=$(aws cognito-idp describe-user-pool-domain --domain "$COGNITO_DOMAIN" --query 'DomainDescription.Status' --output text 2>/dev/null || echo "DELETED")
            if [ "$DOMAIN_CHECK" = "DELETED" ] || [ "$DOMAIN_CHECK" = "NOT_FOUND" ]; then
                log_success "Cognito domain successfully deleted" "$SCRIPT_NAME"
                echo "   ✅ Domain deletion confirmed"
                break
            else
                echo "   ⏳ Domain status: $DOMAIN_CHECK (waiting...)"
                sleep 5
            fi
        done
    else
        log_warning "Failed to delete Cognito domain" "$SCRIPT_NAME"
        echo "   ⚠️  Domain deletion failed - will try to continue"
    fi
    echo
fi

# 2. Delete User Pool (after domain is gone)
if [ "$USER_POOL_EXISTS" = true ]; then
    log_info "Deleting User Pool: $USER_POOL_ID" "$SCRIPT_NAME"
    echo "👥 Deleting User Pool..."
    
    if aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID" 2>/dev/null; then
        log_success "User Pool deleted successfully" "$SCRIPT_NAME"
        echo "   ✅ User Pool deleted"
    else
        log_warning "Failed to delete User Pool" "$SCRIPT_NAME"
        echo "   ⚠️  User Pool deletion failed"
    fi
    echo
fi

# 3. Delete Identity Pool
if [ "$IDENTITY_POOL_EXISTS" = true ]; then
    log_info "Deleting Identity Pool: $IDENTITY_POOL_ID" "$SCRIPT_NAME"
    echo "🆔 Deleting Identity Pool..."
    
    if aws cognito-identity delete-identity-pool --identity-pool-id "$IDENTITY_POOL_ID" 2>/dev/null; then
        log_success "Identity Pool deleted successfully" "$SCRIPT_NAME"
        echo "   ✅ Identity Pool deleted"
    else
        log_warning "Failed to delete Identity Pool" "$SCRIPT_NAME"
        echo "   ⚠️  Identity Pool deletion failed"
    fi
    echo
fi

# Final verification
echo "=================================================="
echo "🔍 FINAL VERIFICATION"
echo "=================================================="

ALL_CLEAN=true

if [ "$COGNITO_DOMAIN_EXISTS" = true ]; then
    FINAL_DOMAIN_CHECK=$(aws cognito-idp describe-user-pool-domain --domain "$COGNITO_DOMAIN" --query 'DomainDescription.Status' --output text 2>/dev/null || echo "DELETED")
    if [ "$FINAL_DOMAIN_CHECK" = "DELETED" ] || [ "$FINAL_DOMAIN_CHECK" = "NOT_FOUND" ]; then
        echo "✅ Cognito Domain: Deleted"
    else
        echo "⚠️  Cognito Domain: Still exists (Status: $FINAL_DOMAIN_CHECK)"
        ALL_CLEAN=false
    fi
fi

if [ "$USER_POOL_EXISTS" = true ]; then
    FINAL_POOL_CHECK=$(aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --query 'UserPool.Status' --output text 2>/dev/null || echo "DELETED")
    if [ "$FINAL_POOL_CHECK" = "DELETED" ] || [ "$FINAL_POOL_CHECK" = "NOT_FOUND" ]; then
        echo "✅ User Pool: Deleted"
    else
        echo "⚠️  User Pool: Still exists (Status: $FINAL_POOL_CHECK)"
        ALL_CLEAN=false
    fi
fi

if [ "$IDENTITY_POOL_EXISTS" = true ]; then
    FINAL_IDENTITY_CHECK=$(aws cognito-identity describe-identity-pool --identity-pool-id "$IDENTITY_POOL_ID" --query 'IdentityPoolName' --output text 2>/dev/null || echo "DELETED")
    if [ "$FINAL_IDENTITY_CHECK" = "DELETED" ] || [ "$FINAL_IDENTITY_CHECK" = "NOT_FOUND" ]; then
        echo "✅ Identity Pool: Deleted"
    else
        echo "⚠️  Identity Pool: Still exists"
        ALL_CLEAN=false
    fi
fi

echo

if [ "$ALL_CLEAN" = true ]; then
    log_success "All Cognito resources successfully cleaned up" "$SCRIPT_NAME"
    echo "🎉 Cognito cleanup completed successfully!"
    echo
    echo "Next steps:"
    echo "  • Run ./step-990-cleanup.sh to complete full cleanup"
    echo "  • CloudFormation stack deletion should now succeed"
else
    log_warning "Some Cognito resources may still exist" "$SCRIPT_NAME"
    echo "⚠️  Some resources may still exist - manual cleanup might be needed"
    echo
    echo "You can still proceed to step-990-cleanup.sh"
    echo "The cleanup script will handle any remaining resources"
fi

echo "=================================================="

# Mark as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME" 2>/dev/null || true
log_success "Cognito cleanup script completed" "$SCRIPT_NAME"