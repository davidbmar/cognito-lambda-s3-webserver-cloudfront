# Serverless Web Application with Cognito Authentication

This repository contains a serverless web application using AWS services including S3, CloudFront, Cognito, Lambda, and API Gateway. The application provides a static website with user authentication and a secure backend API.

## Architecture Overview

![Architecture Diagram](https://d1.awsstatic.com/architecture-diagrams/ArchitectureDiagrams/serverless-webapp-architecture-diagram.8ae3844048f8e76c95f66d7dfd4dd33c961ec91d.png)

- **Frontend Hosting**: Amazon S3 for storage + CloudFront for HTTPS delivery
- **Authentication**: Amazon Cognito User Pools and Identity Pools
- **Backend API**: AWS Lambda functions accessed via API Gateway
- **Deployment**: AWS Serverless Application Model (SAM) / Serverless Framework

## Prerequisites

1. AWS CLI installed and configured
2. Node.js installed (v14+)
3. Serverless Framework installed globally: `npm install -g serverless`
4. Required IAM permissions (see section below)

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

## Project Structure

```
.
├── api/
│   └── handler.js         # Lambda function for the API
├── functions/
│   └── setIdentityPoolRoles.js   # Utility Lambda for Cognito setup
├── web/
│   ├── index.html         # Main application page
│   ├── callback.html      # Authentication callback page
│   ├── app.js             # Frontend JavaScript
│   └── styles.css         # CSS styles
├── serverless.yml         # Serverless Framework configuration
├── deploy.sh              # Deployment script
└── README.md              # This documentation
```

## Setup Instructions

### 1. Clone the Repository

```bash
git clone [repository-url]
cd [repository-name]
```

### 2. Install Dependencies

```bash
npm install
```

### 3. Create/Update Configuration Files

The main configuration is in `serverless.yml`. Review and modify as needed:

- Update the AWS region if you want to deploy to a different region
- Update the S3 bucket name pattern if desired
- Review the Cognito settings and adjust as needed

### 4. Deploy the Application

```bash
./deploy.sh
```

The script will:
1. Deploy all AWS resources using the Serverless Framework
2. Extract outputs from the CloudFormation stack
3. Update the frontend configuration with the deployed resource identifiers
4. Upload the frontend files to the S3 bucket
5. Trigger the Lambda function to set Identity Pool roles

**Note**: The initial deployment can take 20-30 minutes, primarily due to CloudFront distribution creation.

### 5. Test the Application

After deployment, the script will output:
- Website URL (CloudFront URL)
- API endpoint URL
- User Pool ID
- User Pool Client ID
- Identity Pool ID

Visit the Website URL to test the application.

## Creating a User

Before you can log in, you'll need to create a user in the Cognito User Pool:

1. Go to the AWS Console > Cognito > User Pools
2. Select your User Pool (named something like "cloudfront-cognito-app-user-pool-dev")
3. Go to "Users and groups" > "Create user"
4. Enter the user details including email
5. Click "Create user"
6. Check your email for the temporary password

## Accessing the Application

1. Go to the CloudFront URL provided in the deployment output
2. Click "Sign In" and enter the credentials for the user you created
3. After authentication, you can click "Get Data from Lambda" to test the API call

## Customizing the Application

### Adding New API Endpoints

1. Add a new function to `api/handler.js`
2. Add the function to the `functions` section in `serverless.yml` with appropriate API Gateway configuration
3. Update the frontend code to call the new endpoint

### Modifying the Frontend

Edit the files in the `web/` directory, then re-deploy the frontend:

```bash
aws s3 cp web/ s3://[your-bucket-name]/ --recursive
```

### Changing the Bucket Name

The S3 bucket name is defined in the `custom` section of `serverless.yml`:

```yaml
custom:
  s3Bucket: ${self:service}-website-${sls:stage}-${aws:accountId}
```

If you want to change it, update this parameter and redeploy.

## Security Considerations

1. **S3 Bucket Access**: The S3 bucket is not publicly accessible. All content is served through CloudFront.

2. **CloudFront Security**: CloudFront uses Origin Access Identity to securely access the S3 bucket. The S3 bucket policy only allows access from your specific CloudFront distribution.

3. **API Security**: The API is protected by Cognito authentication. All requests require a valid JWT token.

4. **HTTPS**: CloudFront serves content over HTTPS with a default CloudFront certificate.

## Cleaning Up

To avoid incurring charges, delete the resources when you're done:

```bash
serverless remove
```

Or, in the AWS Console, delete the CloudFormation stack named "cloudfront-cognito-app-dev".

## Troubleshooting

### Deployment Fails

If deployment fails, check the CloudFormation stack events:

```bash
aws cloudformation describe-stack-events --stack-name cloudfront-cognito-app-dev
```

Common issues include:
- Insufficient IAM permissions
- Resource name conflicts
- Service quotas/limits

### Authentication Issues

If you can't log in, verify:
1. The user exists in Cognito User Pool
2. The callback URL in app.js matches the one configured in Cognito
3. The Cognito configuration in app.js is correct

### API Calls Failing

If the "Get Data" button doesn't work:
1. Check the browser console for errors
2. Verify the API Gateway endpoint is correct in app.js
3. Ensure the Cognito token is being sent correctly in the request header

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
