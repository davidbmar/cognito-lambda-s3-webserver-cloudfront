#!/bin/bash
# step-050-configure-eventbridge.sh - Configure EventBridge Integration
# Prerequisites: step-040-test.sh (recommended) or step-025-update-web-files.sh
# Outputs: EventBridge configuration for event publishing

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-050-configure-eventbridge"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-050-configure-eventbridge.sh"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# Show step purpose
show_step_purpose "step-050-configure-eventbridge.sh"

echo -e "${CYAN}=================================================="
echo -e "       CloudFront Cognito Serverless Application"
echo -e "            EVENTBRIDGE CONFIGURATION"
echo -e "==================================================${NC}"
echo
log_info "Starting EventBridge configuration" "$SCRIPT_NAME"

# Load configuration
if [ ! -f .env ]; then
    log_error ".env file not found. Please run step-020-deploy.sh first." "$SCRIPT_NAME"
    exit 1
fi

source .env

# Check prerequisites
log_info "Checking prerequisites" "$SCRIPT_NAME"

if ! check_command_exists "aws" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" "$SCRIPT_NAME"; then
    exit 1
fi

echo "✅ Prerequisites check passed"
echo

# Get EventBridge configuration
echo "🔍 Configuring EventBridge integration..."
echo

# Try to find eventbridge-orchestrator directory
EVENTBRIDGE_DIR=""
if [ -d "../eventbridge-orchestrator" ]; then
    EVENTBRIDGE_DIR="../eventbridge-orchestrator"
elif [ -d "../../eventbridge-orchestrator" ]; then
    EVENTBRIDGE_DIR="../../eventbridge-orchestrator"
fi

# Try to get EVENT_BUS_NAME from eventbridge-orchestrator .env
if [ -n "$EVENTBRIDGE_DIR" ] && [ -f "$EVENTBRIDGE_DIR/.env" ]; then
    echo "📁 Found eventbridge-orchestrator at: $EVENTBRIDGE_DIR"
    EVENT_BUS_NAME=$(grep "^EVENT_BUS_NAME=" "$EVENTBRIDGE_DIR/.env" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
fi

# If not found, ask user
if [ -z "$EVENT_BUS_NAME" ]; then
    echo "Please provide EventBridge configuration:"
    echo
    read -p "Enter EventBridge bus name (e.g., dev-application-events): " EVENT_BUS_NAME
    
    if [ -z "$EVENT_BUS_NAME" ]; then
        echo "❌ EventBridge bus name is required"
        exit 1
    fi
fi

echo "📋 Using EventBridge bus: $EVENT_BUS_NAME"

# Verify the bus exists
if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
    echo "✅ EventBridge bus '$EVENT_BUS_NAME' exists"
else
    echo "❌ EventBridge bus '$EVENT_BUS_NAME' not found"
    echo "   Please deploy the eventbridge-orchestrator first"
    exit 1
fi

# Add EVENT_BUS_NAME to .env if not present
echo
echo "📝 Updating .env configuration..."

if grep -q "EVENT_BUS_NAME=" .env 2>/dev/null; then
    echo "✅ EVENT_BUS_NAME already in .env"
else
    echo "" >> .env
    echo "# EventBridge Configuration" >> .env
    echo "EVENT_BUS_NAME=$EVENT_BUS_NAME" >> .env
    echo "✅ Added EVENT_BUS_NAME to .env"
fi

# Check if serverless.yml needs updating
echo
echo "🔧 Checking serverless.yml configuration..."

if grep -q "EVENT_BUS_NAME:" serverless.yml && grep -q "events:PutEvents" serverless.yml; then
    echo "✅ EventBridge configuration already in serverless.yml"
else
    echo "⚠️  Updating serverless.yml with EventBridge configuration..."
    
    # Backup serverless.yml
    cp serverless.yml serverless.yml.bak-eventbridge
    
    # Add global environment variable if not present
    if ! grep -q "EVENT_BUS_NAME:" serverless.yml; then
        sed -i "/^provider:/,/^[^ ]/ s/  region: .*/&\n  environment:\n    EVENT_BUS_NAME: $EVENT_BUS_NAME/" serverless.yml
    fi
    
    # Add EventBridge permissions if not present
    if ! grep -q "events:PutEvents" serverless.yml; then
        sed -i "/- iam:PassRole/a\        - Effect: Allow\n          Action:\n            - events:PutEvents\n          Resource: \"arn:aws:events:\${self:provider.region}:\${aws:accountId}:event-bus/$EVENT_BUS_NAME\"" serverless.yml
    fi
    
    echo "✅ Updated serverless.yml"
fi

# Update audio.js to publish events
echo
echo "📄 Updating audio.js to publish EventBridge events..."

AUDIO_JS="api/audio.js"
if grep -q "createUploadEvent" "$AUDIO_JS"; then
    echo "✅ audio.js already has EventBridge integration"
else
    echo "⚠️  Adding EventBridge integration to audio.js..."
    
    # Backup audio.js
    cp "$AUDIO_JS" "$AUDIO_JS.bak-eventbridge"
    
    # Add the require statement at the top
    sed -i "/'use strict';/a const { createUploadEvent } = require('./eventbridge-utils');" "$AUDIO_JS"
    
    # Add event publishing after the upload URL generation
    # Look for the line with "Generated upload URL for" and add the event publishing code after it
    
    # Create a temporary file with the EventBridge integration
    cat > /tmp/audio-eventbridge-addition.txt << 'EOF'

    // Publish EventBridge event for audio upload
    try {
      const fileSize = body.fileSize || 0;
      const fileName = \`chunk-\${paddedChunkNumber}.webm\`;
      const eventId = await createUploadEvent(userId, email, fileName, s3Key, 'audio/webm', fileSize);
      console.log(\`Published audio upload event with ID: \${eventId}\`);
    } catch (eventError) {
      // Don't fail the upload if event publishing fails
      console.warn('Failed to publish audio upload event:', eventError.message);
    }
EOF
    
    # Use sed to insert the EventBridge code after the "Generated upload URL" log
    sed -i '/console.log(`Generated upload URL for ${s3Key}`);/r /tmp/audio-eventbridge-addition.txt' "$AUDIO_JS"
    
    # Clean up temp file
    rm -f /tmp/audio-eventbridge-addition.txt
    
    echo "✅ Updated audio.js with EventBridge integration"
fi

echo
echo "🚀 Deploying Lambda functions with EventBridge configuration..."

# Export EVENT_BUS_NAME for serverless deployment
export EVENT_BUS_NAME="$EVENT_BUS_NAME"

# Deploy with force to ensure environment variables are updated
npx serverless deploy --stage "$STAGE" --force

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

echo
log_success "EventBridge integration configured successfully!" "$SCRIPT_NAME"
echo

# Verify deployment
log_info "Verifying deployment" "$SCRIPT_NAME"
FUNCTION_NAME="${APP_NAME}-${STAGE}-uploadAudioChunk"

if aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query 'Environment.Variables.EVENT_BUS_NAME' --output text | grep -q "$EVENT_BUS_NAME"; then
    log_success "EVENT_BUS_NAME is properly configured in Lambda" "$SCRIPT_NAME"
else
    log_warning "EVENT_BUS_NAME may not be set correctly" "$SCRIPT_NAME"
fi

echo
echo -e "${BLUE}🎯 Next steps:${NC}"
echo -e "${BLUE}   1. Test audio recording at ${GREEN}$CLOUDFRONT_URL/audio.html${NC}"
echo -e "${BLUE}   2. Check EventBridge logs with:${NC}"
echo -e "${CYAN}      aws logs tail /aws/lambda/dev-event-logger --since 5m${NC}"
echo -e "${BLUE}   3. Set up the transcription service to process audio events${NC}"
echo

# Show next step
show_next_step "step-050-configure-eventbridge.sh" "$(dirname "$0")"