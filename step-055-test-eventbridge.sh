#!/bin/bash
# step-055-test-eventbridge.sh - Test EventBridge Integration
# Prerequisites: step-050-configure-eventbridge.sh (required)
# Outputs: EventBridge integration test results and monitoring guidance

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-055-test-eventbridge"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-055-test-eventbridge.sh"; then
    log_error "Prerequisites not met" "$SCRIPT_NAME"
    exit 1
fi

# Show step purpose
show_step_purpose "step-055-test-eventbridge.sh"

echo -e "${CYAN}=================================================="
echo -e "       CloudFront Cognito Serverless Application"
echo -e "            EVENTBRIDGE INTEGRATION TESTING"
echo -e "==================================================${NC}"
echo
log_info "Starting EventBridge integration testing" "$SCRIPT_NAME"

# Load configuration
if [ ! -f .env ]; then
    log_error ".env file not found. Please run step-050-configure-eventbridge.sh first." "$SCRIPT_NAME"
    exit 1
fi

source .env

# Validate EventBridge configuration
if [ -z "$EVENT_BUS_NAME" ]; then
    log_error "EVENT_BUS_NAME not set in .env. Please run step-050-configure-eventbridge.sh first." "$SCRIPT_NAME"
    exit 1
fi

log_info "Testing EventBridge integration for: $APP_NAME-$STAGE" "$SCRIPT_NAME"
echo "📋 Event Bus: $EVENT_BUS_NAME"
echo "📋 Application: $APP_NAME-$STAGE"
echo

# Test 1: Check if EventBridge bus exists
log_info "Testing EventBridge bus connectivity" "$SCRIPT_NAME"
if aws events describe-event-bus --name "$EVENT_BUS_NAME" &>/dev/null; then
    log_success "EventBridge bus '$EVENT_BUS_NAME' is accessible" "$SCRIPT_NAME"
else
    log_error "EventBridge bus '$EVENT_BUS_NAME' not found" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Make sure the eventbridge-orchestrator is deployed first${NC}"
    exit 1
fi

# Test 2: Check Lambda function environment
log_info "Testing Lambda function configuration" "$SCRIPT_NAME"
FUNCTION_NAME="${APP_NAME}-${STAGE}-uploadAudioChunk"
EVENT_BUS_CONFIG=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --query 'Environment.Variables.EVENT_BUS_NAME' --output text 2>/dev/null)

if [ "$EVENT_BUS_CONFIG" = "$EVENT_BUS_NAME" ]; then
    log_success "Lambda function has correct EVENT_BUS_NAME: $EVENT_BUS_CONFIG" "$SCRIPT_NAME"
else
    log_error "Lambda function EVENT_BUS_NAME mismatch: expected '$EVENT_BUS_NAME', got '$EVENT_BUS_CONFIG'" "$SCRIPT_NAME"
    exit 1
fi

# Test 3: Send test event directly to EventBridge
log_info "Testing direct EventBridge event publishing" "$SCRIPT_NAME"

TEST_EVENT='{
  "Source": "custom.upload-service",
  "DetailType": "Audio Uploaded",
  "Detail": "{\"userId\":\"test-user\",\"fileId\":\"test-'$(date +%s)'\",\"s3Location\":{\"bucket\":\"'$S3_BUCKET_NAME'\",\"key\":\"users/test-user/test-audio.webm\"},\"metadata\":{\"contentType\":\"audio/webm\",\"size\":1024,\"uploadTimestamp\":\"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"},\"userEmail\":\"test@example.com\",\"fileName\":\"test-audio.webm\"}",
  "EventBusName": "'$EVENT_BUS_NAME'"
}'

if aws events put-events --entries "$TEST_EVENT" &>/dev/null; then
    log_success "Successfully published test event to EventBridge" "$SCRIPT_NAME"
else
    log_error "Failed to publish test event to EventBridge" "$SCRIPT_NAME"
    exit 1
fi

# Test 4: Check for rules that would process these events
log_info "Checking EventBridge rules" "$SCRIPT_NAME"
RULES=$(aws events list-rules --event-bus-name "$EVENT_BUS_NAME" --query "Rules[].Name" --output text 2>/dev/null)

if [ -n "$RULES" ] && [ "$RULES" != "None" ]; then
    log_success "Found EventBridge rules:" "$SCRIPT_NAME"
    for rule in $RULES; do
        if [ -n "$rule" ] && [ "$rule" != "None" ]; then
            echo "   ✓ $rule"
        fi
    done
    
    # Get rule details
    echo
    log_info "Rule details:" "$SCRIPT_NAME"
    for rule in $RULES; do
        if [ -n "$rule" ] && [ "$rule" != "None" ]; then
            RULE_DETAILS=$(aws events describe-rule --name "$rule" --event-bus-name "$EVENT_BUS_NAME" 2>/dev/null)
            if [ $? -eq 0 ]; then
                echo "   📋 $rule:"
                echo "      State: $(echo "$RULE_DETAILS" | grep -o '"State":"[^"]*' | cut -d'"' -f4)"
                echo "      Pattern: $(echo "$RULE_DETAILS" | grep -o '"EventPattern":"[^"]*' | cut -d'"' -f4 | head -c 50)..."
            fi
        fi
    done
else
    log_warning "No rules found for event bus '$EVENT_BUS_NAME'" "$SCRIPT_NAME"
    echo "   ⚠️  Events will be published but not processed"
    echo "   💡 Deploy eventbridge-orchestrator rules to process events"
fi

# Test 5: Check recent CloudWatch logs for event processing
log_info "Checking recent EventBridge activity" "$SCRIPT_NAME"
if [ -n "$RULES" ] && [ "$RULES" != "None" ]; then
    RULE_NAME=$(echo "$RULES" | head -1 | xargs)
    if [ -n "$RULE_NAME" ] && [ "$RULE_NAME" != "None" ]; then
        # Check for Lambda targets of the rule
        TARGETS=$(aws events list-targets-by-rule --rule "$RULE_NAME" --event-bus-name "$EVENT_BUS_NAME" --query "Targets[?starts_with(Arn, 'arn:aws:lambda')].Arn" --output text 2>/dev/null)
        
        if [ -n "$TARGETS" ] && [ "$TARGETS" != "None" ]; then
            log_success "Found Lambda targets for rule: $RULE_NAME" "$SCRIPT_NAME"
            for target in $TARGETS; do
                FUNCTION_NAME=$(echo "$target" | cut -d':' -f7)
                echo "   🎯 Target: $FUNCTION_NAME"
                
                # Check recent logs
                LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
                if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" &>/dev/null; then
                    echo "   📋 Recent activity (last 5 minutes):"
                    RECENT_LOGS=$(aws logs filter-log-events --log-group-name "$LOG_GROUP" --start-time $(($(date +%s)*1000 - 300000)) --query "events[].message" --output text 2>/dev/null | head -3)
                    if [ -n "$RECENT_LOGS" ]; then
                        echo "$RECENT_LOGS" | while read line; do
                            if [ -n "$line" ]; then
                                echo "      $(echo "$line" | head -c 80)..."
                            fi
                        done
                    else
                        echo "      No recent activity"
                    fi
                fi
            done
        else
            log_info "No Lambda targets found for EventBridge rules" "$SCRIPT_NAME"
        fi
    fi
fi

# Test 6: Verify EventBridge permissions
log_info "Testing EventBridge permissions" "$SCRIPT_NAME"
if aws events put-events --entries '{"Source":"test","DetailType":"Permission Test","Detail":"{}","EventBusName":"'$EVENT_BUS_NAME'"}' &>/dev/null; then
    log_success "EventBridge permissions are correctly configured" "$SCRIPT_NAME"
else
    log_warning "EventBridge permissions may need adjustment" "$SCRIPT_NAME"
fi

# Mark step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

echo
log_success "EventBridge integration testing completed!" "$SCRIPT_NAME"
echo

# Provide testing guidance
echo -e "${BLUE}🎯 How to trigger real EventBridge events:${NC}"
echo
echo -e "${GREEN}1. Audio Recording Test:${NC}"
echo -e "   Visit: ${CYAN}$CLOUDFRONT_URL/audio.html${NC}"
echo -e "   - Login with Cognito"
echo -e "   - Record audio (each chunk publishes an event)"
echo -e "   - Event Type: ${YELLOW}Audio Uploaded${NC}"
echo
echo -e "${GREEN}2. File Upload Test:${NC}"
echo -e "   Visit: ${CYAN}$CLOUDFRONT_URL/files.html${NC}"
echo -e "   - Login and upload any file"
echo -e "   - Event Types: ${YELLOW}Document Uploaded, Audio Uploaded, etc.${NC}"
echo
echo -e "${GREEN}3. File Operations Test:${NC}"
echo -e "   - Delete files: ${YELLOW}Document Deleted${NC}"
echo -e "   - Rename files: ${YELLOW}Document Moved${NC}"
echo -e "   - Move files: ${YELLOW}Document Moved${NC}"
echo

echo -e "${BLUE}🔍 Monitor EventBridge events:${NC}"
echo
echo -e "${CYAN}# Watch EventBridge orchestrator logs:${NC}"
echo -e "aws logs tail /aws/lambda/dev-event-logger --since 5m --follow"
echo
echo -e "${CYAN}# Watch your app's upload function logs:${NC}"
echo -e "aws logs tail /aws/lambda/$FUNCTION_NAME --since 5m --follow"
echo
echo -e "${CYAN}# Check EventBridge metrics:${NC}"
echo -e "aws cloudwatch get-metric-statistics \\"
echo -e "  --namespace AWS/Events \\"
echo -e "  --metric-name MatchedEvents \\"
echo -e "  --start-time \$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \\"
echo -e "  --end-time \$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo -e "  --period 300 --statistics Sum"
echo

echo -e "${BLUE}📊 Event Schema Example:${NC}"
cat << 'EOF'
{
  "userId": "user-123",
  "fileId": "unique-file-id",
  "s3Location": {
    "bucket": "your-bucket",
    "key": "users/user-123/filename.webm"
  },
  "metadata": {
    "contentType": "audio/webm",
    "size": 1024,
    "uploadTimestamp": "2025-01-27T12:00:00Z"
  },
  "userEmail": "user@example.com",
  "fileName": "filename.webm"
}
EOF

echo
echo -e "${YELLOW}💡 Next Steps:${NC}"
echo -e "   1. Test audio recording to verify events are published"
echo -e "   2. Check eventbridge-orchestrator logs for event processing"
echo -e "   3. Verify transcription pipeline receives audio events"
echo

# Show next step
show_next_step "step-055-test-eventbridge.sh" "$(dirname "$0")"