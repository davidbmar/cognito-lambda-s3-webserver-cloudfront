#!/bin/bash
# step-10-setup.sh - Initial setup script for the CloudDrive Serverless Application
# This script configures AWS resources and generates environment settings
# Prerequisites: step-001-preflight-check.sh (recommended)
# Outputs: .env file with all deployment configuration

# Source framework libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/error-handling.sh" || { echo "Error handling library not found"; exit 1; }
source "$SCRIPT_DIR/step-navigation.sh" || { echo "Navigation library not found"; exit 1; }

SCRIPT_NAME="step-10-setup"
setup_error_handling "$SCRIPT_NAME"
create_checkpoint "$SCRIPT_NAME" "in_progress" "$SCRIPT_NAME"

# Validate prerequisites
if ! validate_prerequisites "step-10-setup.sh"; then
    log_error "Prerequisites not met - run preflight check first" "$SCRIPT_NAME"
    echo -e "${YELLOW}💡 Run: ./step-001-preflight-check.sh${NC}"
    exit 1
fi

# Show step purpose
show_step_purpose "step-10-setup.sh"

# Welcome banner
echo -e "${CYAN}=================================================="
echo -e "       CloudDrive Serverless Application"
echo -e "              INITIAL SETUP"
echo -e "==================================================${NC}"
echo
log_info "Starting initial setup and configuration" "$SCRIPT_NAME"

# Check AWS CLI and credentials using framework functions
if ! check_command_exists "aws" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" "$SCRIPT_NAME"; then
    exit 1
fi

if ! check_aws_credentials "$SCRIPT_NAME"; then
    exit 1
fi

# Get AWS account information with error handling
log_info "Retrieving AWS account information" "$SCRIPT_NAME"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    log_error "Failed to get AWS account ID" "$SCRIPT_NAME"
    exit 1
}

AWS_REGION=$(aws configure get region 2>/dev/null)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-2"  # Default region
    log_warning "AWS region not found in configuration, using default: $AWS_REGION" "$SCRIPT_NAME"
else
    log_success "Using configured AWS region: $AWS_REGION" "$SCRIPT_NAME"
fi

log_success "AWS Account ID: $AWS_ACCOUNT_ID" "$SCRIPT_NAME"

# Generate unique app name with username prefix
DEFAULT_USERNAME=$(whoami | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')
if [ -z "$DEFAULT_USERNAME" ]; then
    DEFAULT_USERNAME="user"
fi
DEFAULT_APP_NAME="${DEFAULT_USERNAME}-cloudfront-app"

# Ask for application name
echo
echo "⚠️ The application name will be used for the CloudFormation stack and resource naming."
echo
read -p "Enter application name (or press Enter for default '$DEFAULT_APP_NAME'): " APP_NAME
APP_NAME=${APP_NAME:-$DEFAULT_APP_NAME}

# Validate app name
if [[ ! $APP_NAME =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "❌ Invalid application name. Please use only letters, numbers, and hyphens."
    exit 1
fi

echo "✅ Using application name: $APP_NAME"

# Generate unique bucket name
TIMESTAMP=$(date +%s)
DEFAULT_BUCKET_NAME="${APP_NAME}-website-${TIMESTAMP}-${AWS_ACCOUNT_ID}"

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
DEFAULT_COGNITO_DOMAIN="${APP_NAME}-${TIMESTAMP}"

echo
echo "⚠️ Cognito domain naming restrictions:"
echo "  - Must use only lowercase letters, numbers, and hyphens"
echo "  - Cannot contain the word 'cognito' or 'aws' (reserved words)"
echo "  - Between 1-63 characters"
echo

# Loop until we get a valid domain name
while true; do
    read -p "Enter Cognito domain prefix (or press Enter for default '$DEFAULT_COGNITO_DOMAIN'): " COGNITO_DOMAIN
    COGNITO_DOMAIN=${COGNITO_DOMAIN:-$DEFAULT_COGNITO_DOMAIN}
    
    # Validate domain name
    if [[ ! $COGNITO_DOMAIN =~ ^[a-z0-9-]+$ ]]; then
        echo "❌ Invalid domain name. Please use only lowercase letters, numbers, and hyphens."
        continue
    fi
    
    # Check for reserved words
    if [[ $COGNITO_DOMAIN == *cognito* || $COGNITO_DOMAIN == *aws* ]]; then
        echo "❌ Domain name cannot contain reserved words 'cognito' or 'aws'. Please choose another name."
        continue
    fi
    
    # Check length
    if [ ${#COGNITO_DOMAIN} -gt 63 ]; then
        echo "❌ Domain name is too long. Maximum length is 63 characters."
        continue
    fi
    
    # Valid domain
    break
done

echo "✅ Using Cognito domain: $COGNITO_DOMAIN"

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

# Create package.json if it doesn't exist
if [ ! -f package.json ]; then
    echo "📝 Creating package.json..."
    cat > package.json << EOL
{
  "name": "${APP_NAME}",
  "version": "1.0.0",
  "description": "CloudFront Cognito Serverless Application",
  "main": "index.js",
  "scripts": {
    "deploy": "serverless deploy",
    "remove": "serverless remove"
  },
  "devDependencies": {
    "serverless": "^3.30.1"
  },
  "dependencies": {
    "aws-sdk": "^2.1423.0"
  }
}
EOL
fi

# Create or update serverless.yml
echo "📝 Creating serverless.yml..."
cat > serverless.yml << EOL
service: ${APP_NAME}

provider:
  name: aws
  runtime: nodejs18.x
  region: ${AWS_REGION}
  iam:
    role:
      statements:
        - Effect: Allow
          Action:
            - s3:GetObject
          Resource: "arn:aws:s3:::#{WebsiteBucket}/*"
        - Effect: Allow
          Action:
            - cognito-identity:SetIdentityPoolRoles
          Resource: "*"
        - Effect: Allow
          Action:
            - iam:PassRole
          Resource: !GetAtt AuthenticatedRole.Arn

custom:
  s3Bucket: ${BUCKET_NAME}
  
functions:
  api:
    handler: api/handler.getData
    events:
      - http:
          path: data
          method: get
          cors: true
          authorizer:
            type: COGNITO_USER_POOLS
            authorizerId:
              Ref: ApiGatewayAuthorizer

  # Custom resource function to set identity pool roles
  setIdentityPoolRoles:
    handler: functions/setIdentityPoolRoles.handler
    environment:
      IDENTITY_POOL_ID: !Ref IdentityPool
      AUTHENTICATED_ROLE_ARN: !GetAtt AuthenticatedRole.Arn

resources:
  Resources:
    # API Gateway Authorizer
    ApiGatewayAuthorizer:
      Type: AWS::ApiGateway::Authorizer
      Properties:
        Name: cognito-authorizer
        IdentitySource: method.request.header.Authorization
        RestApiId:
          Ref: ApiGatewayRestApi
        Type: COGNITO_USER_POOLS
        ProviderARNs:
          - !GetAtt UserPool.Arn

    # S3 bucket for website hosting with public access
    WebsiteBucket:
      Type: AWS::S3::Bucket
      Properties:
        BucketName: ${BUCKET_NAME}
        WebsiteConfiguration:
          IndexDocument: index.html
          ErrorDocument: error.html
        PublicAccessBlockConfiguration:
          BlockPublicAcls: false
          BlockPublicPolicy: false
          IgnorePublicAcls: false
          RestrictPublicBuckets: false
        CorsConfiguration:
          CorsRules:
            - AllowedHeaders: ['*']
              AllowedMethods: [GET, HEAD, PUT]
              AllowedOrigins: ['*']
              MaxAge: 3000

    # Cognito user pool
    UserPool:
      Type: AWS::Cognito::UserPool
      Properties:
        UserPoolName: ${APP_NAME}-user-pool-${STAGE}
        AutoVerifiedAttributes:
          - email
        UsernameAttributes:
          - email
        Policies:
          PasswordPolicy:
            MinimumLength: 8
            RequireLowercase: true
            RequireNumbers: true
            RequireSymbols: false
            RequireUppercase: true

    # Cognito user pool client
    UserPoolClient:
      Type: AWS::Cognito::UserPoolClient
      Properties:
        ClientName: ${APP_NAME}-app-client-${STAGE}
        UserPoolId: !Ref UserPool
        GenerateSecret: false
        ExplicitAuthFlows:
          - ALLOW_USER_SRP_AUTH
          - ALLOW_REFRESH_TOKEN_AUTH
        AllowedOAuthFlowsUserPoolClient: true
        AllowedOAuthFlows:
          - implicit
          - code
        AllowedOAuthScopes:
          - email
          - openid
          - profile
        CallbackURLs:
          - 'http://localhost:8080/callback.html'
        LogoutURLs:
          - 'http://localhost:8080/index.html'
        SupportedIdentityProviders:
          - COGNITO

    # Cognito identity pool
    IdentityPool:
      Type: AWS::Cognito::IdentityPool
      Properties:
        IdentityPoolName: ${APP_NAME}-identity-pool-${STAGE}
        AllowUnauthenticatedIdentities: false
        CognitoIdentityProviders:
          - ClientId: !Ref UserPoolClient
            ProviderName: !GetAtt UserPool.ProviderName

    # IAM roles for authenticated users
    AuthenticatedRole:
      Type: AWS::IAM::Role
      Properties:
        AssumeRolePolicyDocument:
          Version: '2012-10-17'
          Statement:
            - Effect: Allow
              Principal:
                Federated: cognito-identity.amazonaws.com
              Action: sts:AssumeRoleWithWebIdentity
              Condition:
                StringEquals:
                  cognito-identity.amazonaws.com:aud: !Ref IdentityPool
                ForAnyValue:StringLike:
                  cognito-identity.amazonaws.com:amr: authenticated
        ManagedPolicyArns:
          - arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

    # Custom resource to set identity pool roles after creation
    SetRolesCustomResource:
      Type: Custom::SetIdentityPoolRoles
      DependsOn: 
        - IdentityPool
        - AuthenticatedRole
      Properties:
        ServiceToken: !GetAtt SetIdentityPoolRolesLambdaFunction.Arn
        IdentityPoolId: !Ref IdentityPool
        Roles:
          authenticated: !GetAtt AuthenticatedRole.Arn
    
    CloudFrontDistribution:
      Type: AWS::CloudFront::Distribution
      Properties:
        DistributionConfig:
          Origins:
            - DomainName: !GetAtt WebsiteBucket.DomainName
              Id: S3Origin
              S3OriginConfig:
                OriginAccessIdentity: !Sub "origin-access-identity/cloudfront/\${CloudFrontOriginAccessIdentity}"
          Enabled: true
          DefaultRootObject: index.html
          DefaultCacheBehavior:
            AllowedMethods:
              - GET
              - HEAD
            TargetOriginId: S3Origin
            ForwardedValues:
              QueryString: false
              Cookies:
                Forward: none
            ViewerProtocolPolicy: redirect-to-https
          CustomErrorResponses:
            - ErrorCode: 403
              ResponsePagePath: /index.html
              ResponseCode: 200
              ErrorCachingMinTTL: 10
            - ErrorCode: 404
              ResponsePagePath: /index.html
              ResponseCode: 200
              ErrorCachingMinTTL: 10
          ViewerCertificate:
            CloudFrontDefaultCertificate: true
    
    CloudFrontOriginAccessIdentity:
      Type: AWS::CloudFront::CloudFrontOriginAccessIdentity
      Properties:
        CloudFrontOriginAccessIdentityConfig:
          Comment: "Access identity for S3 bucket"
    
    # Update the bucket policy to grant CloudFront access
    WebsiteBucketPolicy:
      Type: AWS::S3::BucketPolicy
      Properties:
        Bucket: !Ref WebsiteBucket
        PolicyDocument:
          Version: '2012-10-17'
          Statement:
            - Effect: Allow
              Principal:
                CanonicalUser: !GetAtt CloudFrontOriginAccessIdentity.S3CanonicalUserId
              Action: 's3:GetObject'
              Resource: !Join ['', ['arn:aws:s3:::', !Ref WebsiteBucket, '/*']]

  Outputs:
    WebsiteURL:
      Description: S3 Website URL
      Value: !GetAtt WebsiteBucket.WebsiteURL
    WebsiteBucketName:
      Description: Name of the S3 bucket for website hosting
      Value: !Ref WebsiteBucket
    ApiEndpoint:
      Description: URL of the API Gateway endpoint
      Value: !Sub "https://\${ApiGatewayRestApi}.execute-api.\${AWS::Region}.amazonaws.com/\${sls:stage}/data"
    UserPoolId:
      Description: ID of the Cognito User Pool
      Value: !Ref UserPool
    UserPoolClientId:
      Description: ID of the Cognito User Pool Client
      Value: !Ref UserPoolClient
    IdentityPoolId:
      Description: ID of the Cognito Identity Pool
      Value: !Ref IdentityPool
    CloudFrontURL:
      Description: URL of the CloudFront distribution
      Value: !Sub "https://\${CloudFrontDistribution.DomainName}"
EOL

# Update app.js.template with the Cognito domain
echo "📝 Updating app.js.template with the Cognito domain..."

# Create web directory if it doesn't exist
mkdir -p web

# Create other necessary web files if they don't exist
if [ ! -f web/index.html ]; then
    echo "📝 Creating index.html..."
    cat > web/index.html << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cognito Serverless App</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Cognito Serverless Demo</h1>
        <div id="login-section">
            <button id="login-button">Sign In</button>
        </div>
        <div id="authenticated-section" style="display: none;">
            <h2>Welcome, <span id="user-email"></span>!</h2>
            <button id="get-data-button">Get Data from Lambda</button>
            <div id="data-output"></div>
            <button id="logout-button">Sign Out</button>
        </div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/amazon-cognito-identity-js/dist/amazon-cognito-identity.min.js"></script>
    <script src="https://sdk.amazonaws.com/js/aws-sdk-2.1000.0.min.js"></script>
    <script src="app.js"></script>
</body>
</html>
EOL
fi

if [ ! -f web/callback.html ]; then
    echo "📝 Creating callback.html..."
    cat > web/callback.html << EOL
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Authentication Callback</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <div class="container">
        <h1>Processing Authentication...</h1>
        <p>Please wait while we process your sign-in.</p>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/amazon-cognito-identity-js/dist/amazon-cognito-identity.min.js"></script>
    <script src="https://sdk.amazonaws.com/js/aws-sdk-2.1000.0.min.js"></script>
    <script>
        // Parse the URL fragment
        const fragment = window.location.hash.substring(1);
        const params = new URLSearchParams(fragment);
        
        // If we have a code in the query string instead of fragment
        const urlParams = new URLSearchParams(window.location.search);
        const code = urlParams.get('code');
        
        if (code) {
            // For authorization code flow
            console.log("Authorization code received:", code);
            // In a real app, you would exchange this for tokens
            // For simplicity, we'll just redirect back to the main page
            window.location.href = 'index.html';
        } else {
            // For implicit flow
            // Store the tokens in localStorage
            const idToken = params.get('id_token');
            const accessToken = params.get('access_token');
            
            if (idToken) {
                localStorage.setItem('id_token', idToken);
            }
            
            if (accessToken) {
                localStorage.setItem('access_token', accessToken);
            }
            
            // Redirect back to the main page
            window.location.href = 'index.html';
        }
    </script>
</body>
</html>
EOL
fi

if [ ! -f web/styles.css ]; then
    echo "📝 Creating styles.css..."
    cat > web/styles.css << EOL
body {
    font-family: Arial, sans-serif;
    margin: 0;
    padding: 0;
    background-color: #f5f5f5;
}

.container {
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    background-color: white;
    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
    border-radius: 5px;
    margin-top: 50px;
}

h1 {
    color: #333;
}

button {
    background-color: #4CAF50;
    border: none;
    color: white;
    padding: 10px 20px;
    text-align: center;
    text-decoration: none;
    display: inline-block;
    font-size: 16px;
    margin: 10px 2px;
    cursor: pointer;
    border-radius: 5px;
}

button:hover {
    background-color: #45a049;
}

#logout-button {
    background-color: #f44336;
}

#logout-button:hover {
    background-color: #d32f2f;
}

#data-output {
    background-color: #f8f8f8;
    border: 1px solid #ddd;
    padding: 10px;
    border-radius: 5px;
    margin-top: 20px;
    white-space: pre-wrap;
    font-family: monospace;
    min-height: 100px;
}
EOL
fi

# Make sure the api directory exists with the handler.js file
mkdir -p api
if [ ! -f api/handler.js ]; then
    echo "📝 Creating api/handler.js..."
    cat > api/handler.js << EOL
'use strict';

module.exports.getData = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify(
        {
          message: 'Hello from Lambda!',
          user: email
        },
        null,
        2
      ),
    };
  } catch (error) {
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({ error: error.message }),
    };
  }
};
EOL
fi

# Make sure the functions directory exists with the setIdentityPoolRoles.js file
mkdir -p functions
if [ ! -f functions/setIdentityPoolRoles.js ]; then
    echo "📝 Creating functions/setIdentityPoolRoles.js..."
    cat > functions/setIdentityPoolRoles.js << EOL
'use strict';

exports.handler = async (event, context) => {
  console.log('REQUEST RECEIVED:', JSON.stringify(event));
  console.log('CONTEXT:', JSON.stringify(context));
  console.log('ENV VARS:', JSON.stringify(process.env));
  
  // For Delete operations, just succeed
  if (event.RequestType === 'Delete') {
    return;
  }
  
  try {
    const AWS = require('aws-sdk');
    const cognitoidentity = new AWS.CognitoIdentity({ region: process.env.AWS_REGION || '${AWS_REGION}' });
    
    // Get values from environment variables
    const identityPoolId = process.env.IDENTITY_POOL_ID;
    const authenticatedRoleArn = process.env.AUTHENTICATED_ROLE_ARN;
    
    if (!identityPoolId) {
      throw new Error('IdentityPoolId is not defined in environment variables');
    }
    
    if (!authenticatedRoleArn) {
      throw new Error('authenticatedRoleArn is not defined in environment variables');
    }
    
    console.log(\`Setting roles for identity pool \${identityPoolId}\`);
    console.log(\`Authenticated role: \${authenticatedRoleArn}\`);
    
    const params = {
      IdentityPoolId: identityPoolId,
      Roles: {
        authenticated: authenticatedRoleArn
      }
    };
    
    console.log('SetIdentityPoolRoles params:', JSON.stringify(params));
    
    const result = await cognitoidentity.setIdentityPoolRoles(params).promise();
    console.log('SetIdentityPoolRoles result:', JSON.stringify(result));
    
    console.log('Successfully set identity pool roles');
  } catch (error) {
    console.error('Error setting identity pool roles:', error);
    throw error;
  }
};
EOL
fi

# Create .env file to store configuration
echo "📝 Creating .env file with your settings..."
cat > .env << EOL
# CloudFront Cognito App Configuration
# Created by step1-setup.sh - $(date)
# DO NOT COMMIT THIS FILE TO VERSION CONTROL

# General Configuration
APP_NAME=${APP_NAME}
STAGE=${STAGE}
REGION=${AWS_REGION}
ACCOUNT_ID=${AWS_ACCOUNT_ID}

# Resource Configuration
S3_BUCKET_NAME=${BUCKET_NAME}
COGNITO_DOMAIN=${COGNITO_DOMAIN}

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

# Make deploy.sh executable
for script in step2-deploy.sh step3-create-user.sh test.sh cleanup.sh; do
    if [ -f "$script" ]; then
        echo "📝 Making $script executable..."
        chmod +x "$script"
    fi
done

# Mark this step as completed
create_checkpoint "$SCRIPT_NAME" "completed" "$SCRIPT_NAME"

echo
log_success "Initial setup completed successfully!" "$SCRIPT_NAME"
echo
log_info "Configuration saved to .env file" "$SCRIPT_NAME"
log_info "Project files updated with settings" "$SCRIPT_NAME"

echo
echo -e "${YELLOW}⚠️ Important Security Note:${NC}"
echo -e "${YELLOW}.env contains sensitive information and should not be committed to version control${NC}"

# Show next step using navigation system
show_next_step "step-10-setup.sh" "$(dirname "$0")"
