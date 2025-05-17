#!/bin/bash
# create-user.sh - Creates a test user in the Cognito User Pool
# Run this script after deploy.sh

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "   CloudFront Cognito Serverless Application     "
echo "              User Creation Script               "
echo "=================================================="
echo

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please run setup.sh and deploy.sh first."
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$USER_POOL_ID" ]; then
    echo "❌ USER_POOL_ID not found in .env file. Please run deploy.sh first."
    exit 1
fi

# Get user information
read -p "Enter email for the test user: " USER_EMAIL
if [ -z "$USER_EMAIL" ]; then
    echo "❌ Email cannot be empty."
    exit 1
fi

# Validate email format (basic validation)
if [[ ! $USER_EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "❌ Invalid email format."
    exit 1
fi

# Generate a random password that meets Cognito requirements
RANDOM_PASSWORD="Test$(date +%s)!"

# Create the user in Cognito
echo "👤 Creating user in Cognito User Pool..."
aws cognito-idp admin-create-user \
  --user-pool-id $USER_POOL_ID \
  --username $USER_EMAIL \
  --temporary-password "$RANDOM_PASSWORD" \
  --user-attributes Name=email,Value=$USER_EMAIL Name=email_verified,Value=true

# Set a permanent password
echo "🔒 Setting permanent password for the user..."
read -s -p "Enter a permanent password for the user (min 8 chars, with upper, lower, number): " USER_PASSWORD
echo
if [ -z "$USER_PASSWORD" ]; then
    echo "❌ Password cannot be empty."
    exit 1
fi

# Password must be at least 8 characters and contain upper, lower, and number
if [[ ${#USER_PASSWORD} -lt 8 ]] || [[ ! $USER_PASSWORD =~ [A-Z] ]] || [[ ! $USER_PASSWORD =~ [a-z] ]] || [[ ! $USER_PASSWORD =~ [0-9] ]]; then
    echo "❌ Password must be at least 8 characters and contain uppercase, lowercase, and numbers."
    exit 1
fi

aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username $USER_EMAIL \
  --password "$USER_PASSWORD" \
  --permanent

echo
echo "✅ User created successfully!"
echo
echo "👤 Test User Details:"
echo "   Email: $USER_EMAIL"
echo "   Password: (the password you entered)"
echo
echo "🔗 Login URL:"
echo "   $CLOUDFRONT_URL"
echo
echo "✨ You can now test the application by visiting the CloudFront URL and signing in with these credentials."
echo "=================================================="
