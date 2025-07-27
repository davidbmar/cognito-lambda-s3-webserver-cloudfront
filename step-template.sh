#!/bin/bash
# step-XX-description.sh - Brief description of what this script does
# This is a template for creating consistent step scripts

set -e # Exit on any error

# Source the common sequence functions
source ./script-sequence.sh

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "           Script Purpose Goes Here              "
echo "=================================================="
echo

# Display what this script does
print_script_purpose

# Load configuration using common function
if ! load_config; then
    exit 1
fi

# Check required environment variables for this script
required_vars=(
    "APP_NAME"
    "S3_BUCKET_NAME"
    # Add other required vars here
)

if ! check_env_vars "${required_vars[@]}"; then
    exit 1
fi

# Main script logic goes here
echo "🔄 Starting main process..."

# Do the actual work
# ...

echo "✅ Process completed successfully!"

# Update setup status
update_setup_status

# Print next steps using common function
print_next_steps