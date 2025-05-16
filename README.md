# AWS Serverless Application with Cognito Authentication and CloudFront

This guide walks through setting up a complete serverless application on AWS with Cognito authentication, API Gateway, Lambda, S3 for web hosting, and CloudFront for secure HTTPS access.

## Architecture Overview

![Architecture Diagram](https://d1.awsstatic.com/architecture-diagrams/ArchitectureDiagrams/serverless-webapp-architecture-diagram.8ae3844048f8e76c95f66d7dfd4dd33c961ec91d.png)

- **Frontend Hosting**: Amazon S3 for storage + CloudFront for HTTPS delivery
- **Authentication**: Amazon Cognito User Pools and Identity Pools
- **Backend API**: AWS Lambda functions accessed via API Gateway
- **Deployment**: Serverless Framework

## Prerequisites

- AWS CLI installed and configured
- Node.js (v14+) and npm installed
- Serverless Framework installed: `npm install -g serverless`
- Git

## Required IAM Permissions

The following AWS IAM permissions are needed to deploy this application:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*",
                "cloudformation:*",
                "cloudfront:*",
                "cognito-idp:*",
                "cognito-identity:*",
                "lambda:*",
                "apigateway:*",
                "iam:GetRole",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:PutRolePolicy",
                "iam:AttachRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PassRole"
            ],
            "Resource": "*"
        }
    ]
}
```

You can create a policy with these permissions and attach it to your IAM user or role.

### 3. Setup Configuration

The main configuration is in `serverless.yml`. Review and modify as needed:

- Update the AWS region if you want to deploy to a different region
- Update the S3 bucket name pattern if desired
- Review the Cognito settings and adjust as needed

The `app.js` file in the web directory contains frontend configuration that will be automatically updated during deployment:

```javascript
// Configuration - to be updated after deployment
const config = {
    userPoolId: 'YOUR_USER_POOL_ID',
    userPoolClientId: 'YOUR_USER_POOL_CLIENT_ID',
    identityPoolId: 'YOUR_IDENTITY_POOL_ID',
    region: 'us-east-2',
    apiUrl: 'YOUR_API_ENDPOINT',
    appUrl: 'http://localhost:8080'
};
```

These placeholders will be automatically replaced during deployment.

### 4. Configure Serverless Framework

The `serverless.yml` file defines all the AWS resources:

- Lambda functions
- API Gateway endpoints
- Cognito User and Identity Pools
- S3 bucket for web hosting
- CloudFront distribution
- IAM roles and permissions

Key configurations to review:

- **Region**: Defaults to `us-east-2` but can be changed
- **S3 Bucket Name**: Generated using your account ID
- **Cognito Settings**: User pool, client, and identity pool configurations

### 5. Prepare the Web Application

The frontend is pre-configured, but the `app.js` file has placeholders that will be automatically updated during deployment:

```javascript
// Configuration - to be updated after deployment
const config = {
    userPoolId: 'YOUR_USER_POOL_ID',
    userPoolClientId: 'YOUR_USER_POOL_CLIENT_ID',
    identityPoolId: 'YOUR_IDENTITY_POOL_ID',
    region: 'us-east-2',
    apiUrl: 'YOUR_API_ENDPOINT',
    appUrl: 'http://localhost:8080'
};
```

These placeholders will be automatically replaced during deployment.

## Deployment

### 1. Make the Deployment Script Executable

```bash
chmod +x deploy.sh
```

### 2. Run the Deployment

```bash
./deploy.sh
```

This script will:

1. Deploy the serverless application using CloudFormation
2. Get configuration outputs from the CloudFormation stack
3. Update the web app configuration with actual AWS resource IDs
4. Set up the Cognito Identity Pool roles
5. Upload the website files to S3
6. Configure the Cognito User Pool Client to use the CloudFront URL

### 3. Expected Output

After a successful deployment (which takes 3-5 minutes), you'll see output like:

```
Deployment complete!
Website URL: http://[your-bucket-name].s3-website.us-east-2.amazonaws.com
CloudFront URL: https://[cloudfront-id].cloudfront.net
API Endpoint: https://[api-id].execute-api.us-east-2.amazonaws.com/dev/data
User Pool ID: us-east-2_[id]
User Pool Client ID: [client-id]
Identity Pool ID: us-east-2:[id]
```

**Note**: The CloudFront distribution takes 10-15 minutes to fully deploy.

## Creating a User

Before you can log in, you'll need to create a user in the Cognito User Pool:

```bash
aws cognito-idp admin-create-user \
  --user-pool-id [YOUR_USER_POOL_ID] \
  --username test@example.com \
  --temporary-password Test123! \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id [YOUR_USER_POOL_ID] \
  --username test@example.com \
  --password Test123! \
  --permanent
```

Replace `[YOUR_USER_POOL_ID]` with the User Pool ID from the deployment output.

Alternatively, you can create a user through the AWS Console:

1. Go to the AWS Console > Cognito > User Pools
2. Select your User Pool (named something like "cloudfront-cognito-app-user-pool-dev")
3. Go to "Users and groups" > "Create user"
4. Enter the user details including email
5. Click "Create user"
6. Check your email for the temporary password (if you don't use `--message-action SUPPRESS`)

## How Authentication Works

1. User clicks "Sign In" button
2. They're redirected to the Cognito Hosted UI
3. After successful login, Cognito redirects to the callback URL
4. The callback page extracts tokens and stores them locally
5. The tokens are used to authenticate API requests

## Cleanup

To avoid incurring AWS charges, remove all resources when not needed:

```bash
serverless remove
```

This will delete all resources created by the CloudFormation stack.

## Troubleshooting

### Common Issues:

1. **"Client does not exist" error**: 
   - Verify the User Pool Client ID in app.js matches the actual client ID
   - Check if the CloudFront URL is correctly set in the Cognito User Pool Client

2. **S3 bucket upload failures**:
   - Check if the S3 bucket exists in your AWS account
   - Verify the bucket name is correctly formatted in serverless.yml and deploy.sh

3. **Authentication fails**:
   - Ensure the Cognito User Pool Client has the correct callback URLs
   - Check that your user was created successfully

4. **API access denied**:
   - Verify the API Gateway authorizer is correctly configured
   - Check that the ID token is being passed in the Authorization header

For detailed logs and debugging:
- Check CloudWatch Logs for Lambda function logs
- Use browser developer tools to inspect network requests
- Run `serverless logs -f [function-name]` to see specific function logs

## Security Considerations

1. **S3 Bucket Access**: The S3 bucket is not publicly accessible. All content is served through CloudFront.

2. **CloudFront Security**: CloudFront uses Origin Access Identity to securely access the S3 bucket. The S3 bucket policy only allows access from your specific CloudFront distribution.

3. **API Security**: The API is protected by Cognito authentication. All requests require a valid JWT token.

4. **HTTPS**: CloudFront serves content over HTTPS with a default CloudFront certificate.

## Next Steps and Improvements

1. **Custom Domain**: Add a custom domain for your CloudFront distribution
2. **Enhanced Authentication**: Add social login providers or multi-factor authentication
3. **Database Integration**: Add DynamoDB to store user data
4. **CI/CD Pipeline**: Set up automated deployment with AWS CodePipeline
5. **Monitoring**: Add AWS CloudWatch Alarms and Logs for monitoring

## Reference Documentation

- [Serverless Framework Documentation](https://www.serverless.com/framework/docs/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/what-is-amazon-cognito.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Amazon CloudFront Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html)
- [Amazon S3 Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html)

## License

[MIT License](LICENSE)
