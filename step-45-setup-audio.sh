#!/bin/bash

# Step 45: Setup Audio Recording Functionality
# This script adds audio recording capabilities to the existing CloudDrive application

set -e

echo "🎤 Step 45: Setting up Audio Recording Functionality"
echo "=================================================="

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command_exists aws; then
    echo "❌ AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command_exists serverless; then
    echo "❌ Serverless Framework is not installed. Please install it first."
    exit 1
fi

if ! command_exists node; then
    echo "❌ Node.js is not installed. Please install it first."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Check if we're in the right directory
if [ ! -f "serverless.yml" ] && [ ! -f "serverless.yml.template" ]; then
    echo "❌ Not in the correct directory. Please run this from the project root."
    exit 1
fi

# Backup existing files
echo "📂 Creating backups..."
if [ -f "serverless.yml" ]; then
    cp serverless.yml serverless.yml.backup-$(date +%Y%m%d-%H%M%S)
    echo "✅ Backed up serverless.yml"
fi

# Check if audio.js already exists
if [ -f "api/audio.js" ]; then
    echo "✅ Audio API handler already exists"
else
    echo "❌ Audio API handler (api/audio.js) not found. Please ensure it was created."
    exit 1
fi

# Check if audio.html already exists
if [ -f "web/audio.html" ]; then
    echo "✅ Audio UI already exists"
else
    echo "❌ Audio UI (web/audio.html) not found. Please ensure it was created."
    exit 1
fi

# Check if serverless.yml.template has audio endpoints
if grep -q "uploadAudioChunk" serverless.yml.template; then
    echo "✅ Audio endpoints already configured in serverless.yml.template"
else
    echo "❌ Audio endpoints not found in serverless.yml.template. Please add them first."
    exit 1
fi

# Install additional dependencies if needed
echo "📦 Checking dependencies..."
if [ -f "package.json" ]; then
    # Check if we need any additional packages
    echo "✅ Package.json exists, dependencies should be handled by existing setup"
else
    echo "ℹ️  No package.json found, assuming dependencies are managed globally"
fi

# Deploy the audio functionality
echo "🚀 Deploying audio functionality..."

# Check if serverless.yml exists or if we need to use template
if [ -f "serverless.yml" ]; then
    echo "📝 Using existing serverless.yml"
    SERVERLESS_FILE="serverless.yml"
else
    echo "📝 Using serverless.yml.template"
    SERVERLESS_FILE="serverless.yml.template"
fi

# Deploy using serverless
echo "🔧 Deploying Lambda functions..."
if serverless deploy --config $SERVERLESS_FILE; then
    echo "✅ Lambda functions deployed successfully"
else
    echo "❌ Failed to deploy Lambda functions"
    exit 1
fi

# Get the API Gateway URL
API_URL=$(aws cloudformation describe-stacks \
    --stack-name $(grep "service:" $SERVERLESS_FILE | cut -d: -f2 | xargs)-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`ServiceEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$API_URL" ]; then
    echo "✅ API Gateway URL: $API_URL"
    echo "🎤 Audio API endpoints available at:"
    echo "   - POST $API_URL/api/audio/upload-chunk"
    echo "   - POST $API_URL/api/audio/session-metadata"
    echo "   - GET  $API_URL/api/audio/sessions"
    echo "   - GET  $API_URL/api/audio/failed-chunks"
else
    echo "⚠️  Could not retrieve API Gateway URL automatically"
fi

# Update web files with correct API endpoints
echo "🌐 Setting up web configuration..."

# Check if we have CloudFront distribution
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name $(grep "service:" $SERVERLESS_FILE | cut -d: -f2 | xargs)-dev \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionURL`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "$CLOUDFRONT_URL" ]; then
    echo "✅ CloudFront URL: $CLOUDFRONT_URL"
    echo "🎤 Audio UI will be available at: $CLOUDFRONT_URL/audio.html"
else
    echo "⚠️  Could not retrieve CloudFront URL automatically"
fi

# Check S3 bucket for web hosting
BUCKET_NAME=$(grep "s3Bucket:" $SERVERLESS_FILE | cut -d: -f2 | xargs | sed 's/\${self:service}-website-\${sls:stage}-\${aws:accountId}//' || echo "")

if [ -n "$BUCKET_NAME" ]; then
    echo "📂 S3 bucket pattern found in configuration"
else
    echo "⚠️  Could not determine S3 bucket name pattern"
fi

# Create a simple test script
cat > test-audio-upload.sh << 'EOF'
#!/bin/bash

# Simple test script for audio upload functionality
# Usage: ./test-audio-upload.sh [API_URL]

API_URL=${1:-"https://your-api-url.execute-api.region.amazonaws.com/dev"}
TOKEN=${2:-"your-jwt-token"}

echo "🧪 Testing Audio Upload Functionality"
echo "======================================"

if [ "$TOKEN" = "your-jwt-token" ]; then
    echo "❌ Please provide a valid JWT token as the second argument"
    echo "Usage: $0 <API_URL> <JWT_TOKEN>"
    exit 1
fi

# Test audio upload endpoint
echo "📡 Testing upload-chunk endpoint..."
curl -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"sessionId":"test-session-123","chunkNumber":1,"contentType":"audio/webm"}' \
    "$API_URL/api/audio/upload-chunk"

echo -e "\n\n📡 Testing sessions endpoint..."
curl -X GET \
    -H "Authorization: Bearer $TOKEN" \
    "$API_URL/api/audio/sessions"

echo -e "\n\n✅ Audio upload test completed"
EOF

chmod +x test-audio-upload.sh

echo ""
echo "🎉 Audio Recording Setup Complete!"
echo "=================================="
echo ""
echo "📋 Summary:"
echo "  • Audio API endpoints deployed to Lambda"
echo "  • Audio UI created at web/audio.html"
echo "  • S3 storage configured for audio chunks"
echo "  • User isolation and authentication integrated"
echo ""
echo "🔧 Next Steps:"
echo "  1. Run step-25-update-web-files.sh to upload audio.html to S3"
echo "  2. Visit your CloudFront URL + /audio.html to test"
echo "  3. Ensure users are logged in to access audio functionality"
echo ""
echo "🧪 Testing:"
echo "  • Use the test panel in the audio UI for quick tests"
echo "  • Run ./test-audio-upload.sh with your API URL and JWT token"
echo "  • Check S3 bucket for uploaded audio chunks"
echo ""
echo "🔐 Security Features:"
echo "  • User-scoped audio storage (users/{userId}/audio/)"
echo "  • JWT token authentication for all endpoints"
echo "  • Pre-signed URLs for secure uploads"
echo "  • Automatic session metadata tracking"
echo ""
echo "📈 Future Enhancements:"
echo "  • Add transcription pipeline (Whisper integration)"
echo "  • Implement search functionality"
echo "  • Add batch upload for failed chunks"
echo "  • Create session management UI"
echo ""

if [ -n "$CLOUDFRONT_URL" ]; then
    echo "🎤 Ready to record! Visit: $CLOUDFRONT_URL/audio.html"
else
    echo "🎤 Ready to record! Upload audio.html to your S3 bucket and visit via CloudFront"
fi

echo ""