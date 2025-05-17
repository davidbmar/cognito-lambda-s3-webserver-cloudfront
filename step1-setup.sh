#!/bin/bash
# setup.sh - Initial setup script for the CloudFront Cognito Serverless Application
# This script should be run first after cloning the repository

set -e # Exit on any error

# Welcome banner
echo "=================================================="
echo "     CloudFront Cognito Serverless Application    "
echo "                 Setup Script                     "
echo "=================================================="
echo

# Check for AWS CLI installation
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install it first:"
    echo "   https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi

# Check for AWS CLI configuration
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured properly. Please run 'aws configure' first."
    exit 1
fi

# Check for Serverless Framework
if ! command -v serverless &> /dev/null; then
    echo "❌ Serverless Framework is not installed. Installing it now..."
    npm install -g serverless
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "❌ jq is not installed. This is required for JSON processing."
    echo "   Please install it before continuing:"
    echo "   - On macOS: brew install jq"
    echo "   - On Ubuntu/Debian: apt-get install jq"
    echo "   - On CentOS/RHEL: yum install jq"
    exit 1
fi

# Get AWS account ID for bucket naming
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-2"  # Default region
    echo "⚠️ AWS region not found in configuration, using default: $AWS_REGION"
fi

echo "🔍 Found AWS Account ID: $AWS_ACCOUNT_ID"
echo "🔍 Using AWS Region: $AWS_REGION"

# Generate unique bucket name
TIMESTAMP=$(date +%s)
DEFAULT_BUCKET_NAME="cloudfront-cognito-app-website-$TIMESTAMP-$AWS_ACCOUNT_ID"

# Ask for bucket name
echo
echo "⚠️ S3 bucket names must be globally unique across all of AWS."
echo "⚠️ Bucket names must only use lowercase letters, numbers, hyphens, and periods."
echo
read -p "Enter S3 bucket name (or press Enter for default '$DEFAULT_BUCKET_NAME'): " BUCKET_NAME
BUCKET_NAME=${BUCKET_NAME:-$DEFAULT_BUCKET_NAME}

# Validate bucket name
if [[ ! $BUCKET_NAME =~ ^[a-z0-9.-]+$ ]]; then
    echo "❌ Invalid bucket name. Please use only lowercase letters, numbers, hyphens, and periods."
    exit 1
fi

echo "✅ Using bucket name: $BUCKET_NAME"

# Generate unique Cognito domain name
DEFAULT_COGNITO_DOMAIN="cloudfront-cognito-app-$TIMESTAMP"
read -p "Enter Cognito domain prefix (or press Enter for default '$DEFAULT_COGNITO_DOMAIN'): " COGNITO_DOMAIN
COGNITO_DOMAIN=${COGNITO_DOMAIN:-$DEFAULT_COGNITO_DOMAIN}

# Validate domain name
if [[ ! $COGNITO_DOMAIN =~ ^[a-z0-9-]+$ ]]; then
    echo "❌ Invalid domain name. Please use only lowercase letters, numbers, and hyphens."
    exit 1
fi

echo "✅ Using Cognito domain: $COGNITO_DOMAIN"

# Generate application name for the CloudFormation stack
DEFAULT_APP_NAME="cloudfront-cognito-app"
read -p "Enter application name (or press Enter for default '$DEFAULT_APP_NAME'): " APP_NAME
APP_NAME=${APP_NAME:-$DEFAULT_APP_NAME}

# Validate app name
if [[ ! $APP_NAME =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "❌ Invalid application name. Please use only letters, numbers, and hyphens."
    exit 1
fi

echo "✅ Using application name: $APP_NAME"

# Generate application stage
DEFAULT_STAGE="dev"
read -p "Enter deployment stage (or press Enter for default '$DEFAULT_STAGE'): " STAGE
STAGE=${STAGE:-$DEFAULT_STAGE}

# Validate stage
if [[ ! $STAGE =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "❌ Invalid stage name. Please use only letters, numbers, and hyphens."
    exit 1
fi

echo "✅ Using deployment stage: $STAGE"

# Update serverless.yml with user preferences
echo "📝 Updating serverless.yml with your settings..."

if [ -f serverless.yml.template ]; then
    cp serverless.yml.template serverless.yml
else
    # If template doesn't exist, create a backup of the original
    cp serverless.yml serverless.yml.bak
fi

# Update serverless.yml
sed -i.bak "s/^service:.*$/service: $APP_NAME/" serverless.yml
sed -i.bak "s/custom:\n  s3Bucket:.*$/custom:\n  s3Bucket: $BUCKET_NAME/" serverless.yml 

# Create or update .env file to store configuration
echo "📝 Creating .env file with your settings..."
cat > .env << EOL
# CloudFront Cognito App Configuration
# Created by setup.sh - $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

# General Configuration
APP_NAME=$APP_NAME
STAGE=$STAGE
REGION=$AWS_REGION
ACCOUNT_ID=$AWS_ACCOUNT_ID

# Resource Configuration
S3_BUCKET_NAME=$BUCKET_NAME
COGNITO_DOMAIN=$COGNITO_DOMAIN

# Stack Information (will be populated after deployment)
API_ENDPOINT=
USER_POOL_ID=
USER_POOL_CLIENT_ID=
IDENTITY_POOL_ID=
CLOUDFRONT_URL=
EOL

# Create .gitignore if it doesn't exist, or update if it does
if [ ! -f .gitignore ]; then
    echo "📝 Creating .gitignore file..."
    cat > .gitignore << EOL
# Node.js
node_modules/
npm-debug.log
yarn-error.log
package-lock.json

# Serverless
.serverless/
.env

# Generated files
web/app.js
*.bak

# OS files
.DS_Store
.DS_Store?
._*
Thumbs.db
EOL
else
    # Make sure .env is in the .gitignore
    if ! grep -q "^.env" .gitignore; then
        echo ".env" >> .gitignore
    fi
    # Make sure web/app.js is in the .gitignore
    if ! grep -q "^web/app.js" .gitignore; then
        echo "web/app.js" >> .gitignore
    fi
fi

# Update app.js.template with the Cognito domain
echo "📝 Updating app.js.template with the Cognito domain..."
if [ -f web/app.js.template ]; then
    # Replace the auth URL line with the actual domain
    sed -i.bak "s|const authUrl = 'https://YOUR_COGNITO_DOMAIN_PREFIX.auth.us-east-2.amazoncognito.com/login';|const authUrl = 'https://$COGNITO_DOMAIN.auth.$AWS_REGION.amazoncognito.com/login';|g" web/app.js.template
    rm -f web/app.js.template.bak
fi

# Make deploy.sh executable
if [ -f deploy.sh ]; then
    chmod +x deploy.sh
fi

echo
echo "✅ Setup completed successfully!"
echo
echo "Your configuration has been saved to .env and updated in the project files."
echo
echo "Next steps:"
echo "1. Review the settings in .env if needed"
echo "2. Run './deploy.sh' to deploy your application"
echo "3. After deployment, use './create-user.sh' to create a test user"
echo
echo "⚠️ Important: .env contains sensitive information and should not be committed to version control"
echo "=================================================="
