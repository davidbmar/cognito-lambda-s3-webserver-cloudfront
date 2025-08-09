#!/bin/bash
# step-050-configure-eventbridge.sh - IMPROVED VERSION
# Purpose: Configure EventBridge integration with smart bus discovery

set -e

# Source error handling
source ./error-handling.sh || { echo "Error handling not found"; exit 1; }
source ./step-navigation.sh || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-050-configure-eventbridge"
setup_error_handling "$SCRIPT_NAME"

echo "🎯 Purpose: Configure EventBridge integration with smart discovery"
echo
echo "=================================================="
echo "       CloudFront Cognito Serverless Application"
echo "            EVENTBRIDGE CONFIGURATION"
echo "=================================================="
echo

# Load existing .env
source .env

# Function to discover EventBridge buses
discover_event_bus() {
    echo "🔍 Discovering EventBridge buses..."
    
    # First, check if EVENT_BUS_NAME is already in local .env
    if [ -n "$EVENT_BUS_NAME" ]; then
        echo "📋 Found EVENT_BUS_NAME in local .env: $EVENT_BUS_NAME"
        if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
            echo "✅ Bus '$EVENT_BUS_NAME' exists in AWS"
            return 0
        else
            echo "⚠️  Bus '$EVENT_BUS_NAME' in .env doesn't exist in AWS"
        fi
    fi
    
    # Try common bus names
    local common_buses=("dev-application-events" "dbm-eventbridgebus" "${APP_NAME}-events" "default")
    
    for bus in "${common_buses[@]}"; do
        if aws events describe-event-bus --name "$bus" &>/dev/null; then
            echo "✅ Found existing EventBridge bus: $bus"
            EVENT_BUS_NAME="$bus"
            
            # Add to .env if not present
            if ! grep -q "^EVENT_BUS_NAME=" .env 2>/dev/null; then
                echo "" >> .env
                echo "# EventBridge Configuration" >> .env
                echo "EVENT_BUS_NAME=$EVENT_BUS_NAME" >> .env
                echo "📝 Added EVENT_BUS_NAME to .env"
            fi
            return 0
        fi
    done
    
    # If orchestrator directory exists, check its configuration
    local EVENTBRIDGE_DIR="../eventbridge-orchestrator"
    if [ -f "$EVENTBRIDGE_DIR/.env" ]; then
        local orchestrator_bus=$(grep "^EVENT_BUS_NAME=" "$EVENTBRIDGE_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        if [ -n "$orchestrator_bus" ] && aws events describe-event-bus --name "$orchestrator_bus" &>/dev/null; then
            echo "✅ Found bus from orchestrator config: $orchestrator_bus"
            EVENT_BUS_NAME="$orchestrator_bus"
            
            # Add to local .env
            if ! grep -q "^EVENT_BUS_NAME=" .env 2>/dev/null; then
                echo "" >> .env
                echo "# EventBridge Configuration" >> .env
                echo "EVENT_BUS_NAME=$EVENT_BUS_NAME" >> .env
                echo "📝 Added EVENT_BUS_NAME to .env"
            fi
            return 0
        fi
    fi
    
    # List all custom event buses
    echo "📋 Available EventBridge buses:"
    aws events list-event-buses --query 'EventBuses[?Name!=`default`].Name' --output text
    
    echo
    echo "❌ Could not automatically determine EventBridge bus"
    read -p "Enter EventBridge bus name: " EVENT_BUS_NAME
    
    if [ -z "$EVENT_BUS_NAME" ]; then
        echo "❌ EventBridge bus name is required"
        exit 1
    fi
    
    # Verify and add to .env
    if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
        echo "✅ Verified bus '$EVENT_BUS_NAME' exists"
        if ! grep -q "^EVENT_BUS_NAME=" .env 2>/dev/null; then
            echo "" >> .env
            echo "# EventBridge Configuration" >> .env
            echo "EVENT_BUS_NAME=$EVENT_BUS_NAME" >> .env
            echo "📝 Added EVENT_BUS_NAME to .env"
        fi
    else
        echo "❌ Bus '$EVENT_BUS_NAME' not found"
        exit 1
    fi
}

# Main execution
discover_event_bus

echo
echo "🚀 Deploying Lambda functions with EventBridge configuration..."
echo

# Export for serverless
export EVENT_BUS_NAME

# Deploy with serverless
npx serverless deploy --verbose

echo
echo "✅ EventBridge integration configured successfully!"
echo
echo "📋 Configuration Summary:"
echo "   Event Bus: $EVENT_BUS_NAME"
echo "   Region: $REGION"
echo "   Stack: ${APP_NAME}-${STAGE}"
echo
echo "🎯 Next steps:"
echo "   1. Test file upload at https://${CLOUDFRONT_URL}"
echo "   2. Monitor events: aws logs tail /aws/lambda/dev-event-logger --follow"
echo "   3. Run: ./step-055-test-eventbridge.sh"

create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"
show_next_step "$SCRIPT_NAME" "scripts"