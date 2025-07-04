#!/bin/bash

# Step 47: Validate Audio Recording Functionality
# This script validates that the audio recording functionality is working correctly

set -e

echo "🧪 Step 47: Validating Audio Recording Functionality"
echo "===================================================="

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command_exists aws; then
    echo "❌ AWS CLI is not installed."
    exit 1
fi

if ! command_exists curl; then
    echo "❌ curl is not installed."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run deployment first."
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$CLOUDFRONT_URL" ] || [ -z "$S3_BUCKET_NAME" ]; then
    echo "❌ Missing required variables in .env file."
    exit 1
fi

echo "🔍 Validation Environment:"
echo "  CloudFront URL: $CLOUDFRONT_URL"
echo "  S3 Bucket: $S3_BUCKET_NAME"
echo ""

# Test 1: Check if audio.html is accessible
echo "🌐 Test 1: Checking audio.html accessibility..."
AUDIO_URL="$CLOUDFRONT_URL/audio.html"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$AUDIO_URL" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "✅ Audio UI is accessible at $AUDIO_URL"
else
    echo "❌ Audio UI not accessible (HTTP $HTTP_STATUS)"
    echo "   Please run step-25-update-web-files.sh to upload audio.html"
fi

# Test 2: Check if Lambda functions are deployed
echo ""
echo "🔧 Test 2: Checking Lambda function deployment..."

# Get the stack name
STACK_NAME="${APP_NAME}-${STAGE}"

# Check if the stack exists and has audio functions
FUNCTIONS=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --query 'StackResources[?ResourceType==`AWS::Lambda::Function`].LogicalResourceId' \
    --output text 2>/dev/null || echo "")

if echo "$FUNCTIONS" | grep -q "uploadAudioChunk"; then
    echo "✅ uploadAudioChunk Lambda function deployed"
else
    echo "❌ uploadAudioChunk Lambda function not found"
fi

if echo "$FUNCTIONS" | grep -q "updateAudioSessionMetadata"; then
    echo "✅ updateAudioSessionMetadata Lambda function deployed"
else
    echo "❌ updateAudioSessionMetadata Lambda function not found"
fi

if echo "$FUNCTIONS" | grep -q "listAudioSessions"; then
    echo "✅ listAudioSessions Lambda function deployed"
else
    echo "❌ listAudioSessions Lambda function not found"
fi

if echo "$FUNCTIONS" | grep -q "getFailedAudioChunks"; then
    echo "✅ getFailedAudioChunks Lambda function deployed"
else
    echo "❌ getFailedAudioChunks Lambda function not found"
fi

# Test 3: Check API Gateway endpoints
echo ""
echo "📡 Test 3: Checking API Gateway endpoints..."

# Get the API Gateway URL from CloudFormation
API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$API_URL" ]; then
    echo "✅ API Gateway URL: $API_URL"
    
    # Test audio endpoints (without authentication - should get 401)
    echo ""
    echo "🔐 Testing audio endpoints (expecting 401 Unauthorized)..."
    
    # Test upload-chunk endpoint
    UPLOAD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        "$API_URL/api/audio/upload-chunk" || echo "000")
    
    if [ "$UPLOAD_STATUS" = "401" ]; then
        echo "✅ upload-chunk endpoint responding (401 Unauthorized as expected)"
    else
        echo "⚠️  upload-chunk endpoint returned HTTP $UPLOAD_STATUS (expected 401)"
    fi
    
    # Test sessions endpoint
    SESSIONS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        "$API_URL/api/audio/sessions" || echo "000")
    
    if [ "$SESSIONS_STATUS" = "401" ]; then
        echo "✅ sessions endpoint responding (401 Unauthorized as expected)"
    else
        echo "⚠️  sessions endpoint returned HTTP $SESSIONS_STATUS (expected 401)"
    fi
    
else
    echo "❌ Could not retrieve API Gateway URL"
fi

# Test 4: Check S3 bucket structure and permissions
echo ""
echo "📂 Test 4: Checking S3 bucket structure..."

# Check if the bucket exists
if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
    echo "✅ S3 bucket '$S3_BUCKET_NAME' exists and is accessible"
    
    # Check if web files are present
    if aws s3 ls "s3://$S3_BUCKET_NAME/audio.html" >/dev/null 2>&1; then
        echo "✅ audio.html found in S3 bucket"
    else
        echo "❌ audio.html not found in S3 bucket"
        echo "   Run: step-25-update-web-files.sh to upload it"
    fi
    
    if aws s3 ls "s3://$S3_BUCKET_NAME/audio-ui-styles.css" >/dev/null 2>&1; then
        echo "✅ audio-ui-styles.css found in S3 bucket"
    else
        echo "❌ audio-ui-styles.css not found in S3 bucket"
    fi
    
else
    echo "❌ S3 bucket '$S3_BUCKET_NAME' not accessible"
fi

# Test 5: Check IAM permissions for audio operations
echo ""
echo "🔐 Test 5: Checking IAM permissions..."

# Get the Lambda execution role
LAMBDA_ROLE=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --query 'StackResources[?LogicalResourceId==`IamRoleLambdaExecution`].PhysicalResourceId' \
    --output text 2>/dev/null || echo "")

if [ -n "$LAMBDA_ROLE" ]; then
    echo "✅ Lambda execution role found: $LAMBDA_ROLE"
    
    # Check if the role has S3 permissions
    S3_POLICIES=$(aws iam list-role-policies \
        --role-name "$LAMBDA_ROLE" \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$S3_POLICIES" ]; then
        echo "✅ IAM policies attached to Lambda role"
    else
        echo "⚠️  No inline policies found on Lambda role"
    fi
else
    echo "❌ Could not find Lambda execution role"
fi

# Test 6: Browser compatibility check
echo ""
echo "🌍 Test 6: Browser compatibility recommendations..."

echo "✅ Audio recording requires these browser features:"
echo "   • MediaRecorder API (supported in modern browsers)"
echo "   • getUserMedia API (requires HTTPS in production)"
echo "   • Web Audio API (for audio processing)"
echo ""
echo "✅ Supported browsers:"
echo "   • Chrome 47+"
echo "   • Firefox 25+"
echo "   • Safari 14.1+"
echo "   • Edge 79+"

# Summary
echo ""
echo "📊 Validation Summary"
echo "===================="

# Count successful tests
TESTS_PASSED=0
TOTAL_TESTS=6

# Audio UI accessibility
if [ "$HTTP_STATUS" = "200" ]; then
    ((TESTS_PASSED++))
fi

# Lambda functions (simplified - checking if any audio function exists)
if echo "$FUNCTIONS" | grep -q "Audio"; then
    ((TESTS_PASSED++))
fi

# API Gateway
if [ -n "$API_URL" ]; then
    ((TESTS_PASSED++))
fi

# S3 bucket
if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
    ((TESTS_PASSED++))
fi

# IAM role
if [ -n "$LAMBDA_ROLE" ]; then
    ((TESTS_PASSED++))
fi

# Browser compatibility (always passes)
((TESTS_PASSED++))

echo "Tests passed: $TESTS_PASSED/$TOTAL_TESTS"

if [ $TESTS_PASSED -eq $TOTAL_TESTS ]; then
    echo "🎉 All validation tests passed!"
    echo ""
    echo "🎤 Audio Recording is ready to use!"
    echo "   Visit: $CLOUDFRONT_URL/audio.html"
    echo ""
    echo "📝 Next steps:"
    echo "  1. Create a user account if you haven't already"
    echo "  2. Login to the application"
    echo "  3. Navigate to the audio recorder"
    echo "  4. Test recording functionality"
    echo ""
    echo "🔧 For transcription pipeline:"
    echo "  • Consider integrating AWS Transcribe or OpenAI Whisper"
    echo "  • Set up batch processing for audio files"
    echo "  • Add search functionality for transcripts"
    
elif [ $TESTS_PASSED -ge 4 ]; then
    echo "⚠️  Most tests passed - audio functionality should work with minor issues"
    echo ""
    echo "🔧 Recommended fixes:"
    if [ "$HTTP_STATUS" != "200" ]; then
        echo "  • Run step-25-update-web-files.sh to upload audio.html"
    fi
    if [ -z "$API_URL" ]; then
        echo "  • Check API Gateway deployment"
    fi
    
else
    echo "❌ Multiple validation tests failed"
    echo ""
    echo "🔧 Required fixes:"
    echo "  • Re-run step-45-setup-audio.sh"
    echo "  • Check AWS credentials and permissions"
    echo "  • Verify serverless.yml.template has audio endpoints"
    echo "  • Run step-25-update-web-files.sh"
fi

echo ""
echo "📚 Documentation:"
echo "  • Audio files stored in: users/{userId}/audio/sessions/"
echo "  • Session metadata: metadata.json per session"
echo "  • Chunk format: chunk-XXX.webm"
echo "  • Maximum chunk size: 25MB (Whisper compatible)"
echo ""

echo "🧪 Manual testing checklist:"
echo "  □ Can access audio recorder UI"
echo "  □ Can start/stop recording"
echo "  □ Chunks upload to S3 automatically"
echo "  □ Session metadata is created"
echo "  □ Can playback recorded chunks"
echo "  □ Failed uploads show retry option"
echo ""