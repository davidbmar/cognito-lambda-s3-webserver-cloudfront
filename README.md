# CloudDrive - Serverless Personal File Manager

A modern, secure personal file manager built with AWS serverless technologies. Upload, organize, and manage your files with a beautiful responsive interface that works seamlessly across all devices.

<img width="1478" alt="CloudDrive Desktop Interface" src="https://github.com/user-attachments/assets/a6a5ecf4-49c8-4b7a-9444-9e19c8e838bf" />
<img width="1386" alt="CloudDrive File Management" src="https://github.com/user-attachments/assets/b386a9ab-55e6-4d5e-bb6e-ebcaf64adf66" />

## ✨ Features

### 📁 Complete File Management
- **Upload Files**: Drag-and-drop or click to upload files up to 100MB
- **Folder Navigation**: Create and navigate through nested folder structures
- **Rename**: Rename files and folders with validation
- **Move**: Intuitive tree-view selector for moving files between folders
- **Delete**: Safe deletion with confirmation prompts
- **Download**: Secure pre-signed URL downloads

### 📱 Mobile-First Design
- **Responsive UI**: Beautiful interface that adapts to any screen size
- **iOS Action Sheets**: Native-feeling dropdown menus on iPhone/iPad
- **Touch-Optimized**: Large touch targets and gesture-friendly interactions
- **Mobile Navigation**: Compact breadcrumbs and optimized layout

### 🔐 Enterprise-Grade Security
- **AWS Cognito Authentication**: Secure user management with JWT tokens
- **User Isolation**: Each user can only access their own files
- **Pre-signed URLs**: Secure, time-limited download links
- **HTTPS Everywhere**: All traffic encrypted via CloudFront

### 🚀 Modern Architecture
- **Serverless**: Zero-maintenance infrastructure that scales automatically
- **Fast Performance**: CloudFront CDN for global content delivery
- **Real-time Updates**: Instant UI updates after file operations

## 🏗️ Architecture Overview

![Architecture Diagram](https://d1.awsstatic.com/architecture-diagrams/ArchitectureDiagrams/serverless-webapp-architecture-diagram.8ae3844048f8e76c95f66d7dfd4dd33c961ec91d.png)

- **Frontend Hosting**: Amazon S3 for storage + CloudFront for HTTPS delivery
- **Authentication**: Amazon Cognito User Pools and Identity Pools
- **Backend API**: AWS Lambda functions accessed via API Gateway
- **File Storage**: S3 with user-scoped prefixes for security
- **Deployment**: Serverless Framework with automated configuration

## 🚀 Quick Start

### Prerequisites

- AWS CLI installed and configured
- Node.js (v14+) and npm installed
- Serverless Framework installed: `npm install -g serverless`
- Git

### 1. Clone and Deploy

```bash
git clone https://github.com/davidbmar/cognito-lambda-s3-webserver-cloudfront.git
cd cognito-lambda-s3-webserver-cloudfront
chmod +x deploy.sh
./deploy.sh
```

### 2. Create Your First User

```bash
aws cognito-idp admin-create-user \
  --user-pool-id [YOUR_USER_POOL_ID] \
  --username your-email@example.com \
  --temporary-password TempPass123! \
  --message-action SUPPRESS

aws cognito-idp admin-set-user-password \
  --user-pool-id [YOUR_USER_POOL_ID] \
  --username your-email@example.com \
  --password YourPassword123! \
  --permanent
```

### 3. Access Your App

After deployment, you'll get a CloudFront URL. Visit it and sign in with your credentials!

## 🛠️ Technical Details

### Required IAM Permissions

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

### API Endpoints

The backend provides several secure API endpoints:

- **GET /api/s3/list** - List user's files and folders
- **POST /api/s3/upload-url** - Generate pre-signed upload URLs
- **GET /api/s3/download/{key}** - Generate secure download URLs
- **DELETE /api/s3/delete/{key}** - Delete files/folders
- **POST /api/s3/rename** - Rename files/folders
- **POST /api/s3/move** - Move files between folders

### File Structure

```
├── web/
│   ├── index.html          # Main application UI
│   ├── app.js.template     # Frontend JavaScript (template)
│   └── callback.html       # OAuth callback handler
├── api/
│   ├── handler.js          # Main API endpoints
│   └── s3.js              # S3 file operations
├── serverless.yml.template # Infrastructure configuration
└── deploy.sh              # Automated deployment script
```

### Security Features

1. **User Isolation**: Files are stored with `users/{userId}/` prefixes
2. **Authentication**: All API calls require valid Cognito JWT tokens
3. **Input Validation**: File names and paths are sanitized
4. **Pre-signed URLs**: Secure, time-limited access to S3 objects
5. **CORS Protection**: Proper CORS headers for web security

## 📱 Mobile Optimizations

### iOS Action Sheets
On iPhone and iPad, dropdown menus use native-style action sheets that slide up from the bottom, providing a familiar iOS experience.

### Responsive Design
- Breadcrumb navigation automatically adapts to screen size
- Touch targets are optimized for mobile interaction
- Dropdowns and modals are repositioned to avoid viewport clipping

### Performance
- Lazy loading for large file lists
- Optimized image handling for mobile networks
- Minimal JavaScript bundle size

## 🔧 Configuration

The deployment script automatically configures all necessary settings:

1. **Backend Deployment**: Creates all AWS resources via CloudFormation
2. **Configuration Update**: Updates frontend with actual resource IDs
3. **S3 Upload**: Deploys website files to S3
4. **Cognito Setup**: Configures authentication URLs and policies

## 🎯 Use Cases

- **Personal Cloud Storage**: Secure alternative to public cloud services
- **Team File Sharing**: Private file sharing within organizations
- **Document Management**: Organize and access documents from anywhere
- **Media Storage**: Store and organize photos, videos, and other media
- **Backup Solution**: Secure cloud backup for important files

## 🔄 Development Workflow

### Making Changes

1. Edit `web/app.js.template` for frontend changes
2. Edit `api/*.js` files for backend changes
3. Run `./deploy.sh` to deploy updates
4. The script automatically handles configuration updates

### Local Testing

For backend development:
```bash
serverless offline
```

For frontend development, serve the `web/` directory with any static server.

## 🧹 Cleanup

To avoid AWS charges, remove all resources when done:

```bash
serverless remove
```

This will delete all CloudFormation resources including S3 buckets (with all files), Lambda functions, API Gateway, Cognito pools, and CloudFront distribution.

## 📊 Costs

Typical monthly costs for light usage:
- **S3 Storage**: $0.023/GB
- **Lambda**: First 1M requests free
- **API Gateway**: First 1M requests free
- **CloudFront**: First 1TB transfer free
- **Cognito**: First 50,000 MAUs free

For most personal use cases, this will cost less than $5/month.

## 🐛 Troubleshooting

### Common Issues

1. **"Client does not exist" error**: 
   - Verify the User Pool Client ID matches in app.js
   - Check if CloudFront URL is set in Cognito User Pool Client

2. **Upload failures**:
   - Check file size (100MB limit)
   - Verify S3 bucket permissions
   - Check browser console for detailed errors

3. **Authentication fails**:
   - Ensure user exists in Cognito User Pool
   - Check password meets complexity requirements
   - Verify callback URLs in Cognito configuration

4. **Mobile dropdown issues**:
   - Clear browser cache
   - Try different mobile browsers
   - Check for JavaScript errors in console

### Debug Tools

- **CloudWatch Logs**: Monitor Lambda function execution
- **Browser DevTools**: Inspect network requests and console errors
- **Serverless Logs**: `serverless logs -f functionName`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on both desktop and mobile
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

Built with:
- [AWS Serverless Framework](https://www.serverless.com/)
- [Amazon Cognito](https://aws.amazon.com/cognito/)
- [AWS Lambda](https://aws.amazon.com/lambda/)
- [Amazon CloudFront](https://aws.amazon.com/cloudfront/)
- [Amazon S3](https://aws.amazon.com/s3/)

## 📚 Reference Documentation

- [Serverless Framework Documentation](https://www.serverless.com/framework/docs/)
- [Amazon Cognito Documentation](https://docs.aws.amazon.com/cognito/latest/developerguide/what-is-amazon-cognito.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html)
- [Amazon CloudFront Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html)
- [Amazon S3 Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html)