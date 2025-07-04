# CloudDrive with Audio Recording - Serverless Personal Cloud Platform

A modern, secure personal cloud platform built with AWS serverless technologies. Features both file management and audio recording capabilities with a beautiful responsive interface optimized for mobile devices.

## ✨ Key Features

### 🎤 **Audio Recording System**
- **Real-time Recording**: High-quality audio recording with MediaRecorder API
- **Chunked Upload**: Automatic chunking (5s-5min configurable) with S3 upload
- **Session Management**: Organized audio sessions with metadata
- **Mobile Optimized**: Touch-friendly interface designed for iPhone recording
- **Resumable Uploads**: Built-in retry logic for failed chunks

### 📁 **Complete File Management**
- **Secure Storage**: User-isolated S3 storage with JWT authentication
- **Full CRUD Operations**: Upload, download, rename, move, delete files
- **Folder Navigation**: Create and navigate nested folder structures
- **Drag & Drop**: Modern file upload with progress tracking

### 📱 **Mobile-First Design**
- **Responsive Dashboard**: Intuitive landing page with app selection
- **iOS Optimizations**: Native action sheets and touch targets
- **Compact UI**: Vertically optimized for maximum content visibility
- **Cross-Device**: Seamless experience across desktop, tablet, mobile

## 🚀 Quick Start

### Prerequisites
- AWS CLI installed and configured with sufficient permissions
- Node.js (v14+) and npm installed
- Git

### 1. Clone and Setup
```bash
git clone https://github.com/davidbmar/audio-ui-cf-s3-lambda-cognito.git
cd audio-ui-cf-s3-lambda-cognito
chmod +x step-*.sh
```

### 2. Deploy in Sequence
```bash
./step-10-setup.sh           # Initial AWS setup and configuration
./step-20-deploy-lambda.sh   # Deploy Lambda functions and infrastructure  
./step-25-update-web-files.sh # Deploy web interface with configuration
./step-45-validation.sh      # Validate deployment
./step-47-test-apis.sh       # Test API endpoints
```

### 3. Create Your First User
```bash
# Get your User Pool ID from the output or .env file
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

### 4. Access Your Applications
After deployment, you'll receive URLs for:
- **📁 File Manager**: `https://your-distribution.cloudfront.net`
- **🎤 Audio Recorder**: `https://your-distribution.cloudfront.net/audio.html`

## 🏗️ Architecture Overview

### Core Components
- **Frontend**: React-based SPA with in-browser Babel compilation
- **Authentication**: AWS Cognito User Pools + Identity Pools
- **API**: AWS Lambda functions via API Gateway
- **Storage**: S3 with user-scoped prefixes (`users/{userId}/`)
- **CDN**: CloudFront for global content delivery
- **Audio Storage**: Organized as `users/{userId}/audio/sessions/{date-sessionId}/`

### Audio Recording Flow
1. User authenticates via Cognito
2. MediaRecorder captures audio in configurable chunks
3. Each chunk gets pre-signed S3 URL from Lambda
4. Chunks upload directly to S3 with session metadata
5. Real-time UI updates show upload progress and playback

## 🎯 Use Cases

### Personal Use
- **Voice Memos**: Record thoughts, ideas, meeting notes
- **Audio Journaling**: Daily audio logs with organized storage
- **File Backup**: Secure personal cloud storage alternative

### Professional Use  
- **Interview Recording**: Journalist interviews with chunked backup
- **Training Material**: Educational content with reliable upload
- **Team Collaboration**: Shared audio notes and file storage

### Technical Use
- **Claude Memory Extension**: Audio storage for AI consciousness research
- **Transcription Pipeline**: Whisper-ready audio format and organization
- **Data Collection**: Structured audio data with metadata

## 🔧 Development

### Numbered Step System
The deployment uses a numbered step system for reliability:
- **step-10**: Initial setup and configuration
- **step-20**: Infrastructure deployment
- **step-25**: Web file deployment with environment substitution
- **step-45**: Audio-specific setup and validation
- **step-47**: Comprehensive API testing

### Template System
- **DO NOT** edit `web/app.js` or `web/audio.html` directly
- **ALWAYS** edit `.template` files in `web/` directory
- Run `./step-25-update-web-files.sh` to apply template changes

### Key Files
```
├── api/
│   ├── audio.js              # Audio recording Lambda functions
│   ├── s3.js                 # File management operations
│   └── data.js               # Basic API endpoints
├── web/
│   ├── index.html            # Dashboard and file manager
│   ├── audio.html.template   # Audio recorder interface  
│   ├── app.js.template       # Main application logic
│   └── audio-ui-styles.css   # Audio-specific styling
├── step-*.sh                 # Numbered deployment scripts
├── CLAUDE.md                 # Development guide for Claude
└── .env                      # Environment configuration
```

## 📱 Mobile Optimizations

### Audio Recording Mobile Features
- **Collapsible Panels**: Test panels hide for mobile recording
- **Touch Targets**: 36px+ buttons optimized for finger interaction
- **Compact Layout**: Vertical optimization for more visible recordings
- **Native Feel**: iOS action sheets for dropdown menus
- **Scroll Prevention**: Fixed scroll jumping during audio playback

### Responsive Design
- **Dashboard Cards**: Clean app selection with feature highlights
- **Adaptive Grid**: Single column on mobile, two columns on desktop
- **Breadcrumb Navigation**: Smart truncation and mobile-friendly sizing

## 🔐 Security Features

### Audio-Specific Security
- **User Isolation**: Audio files stored under `users/{userId}/audio/`
- **Session Management**: Secure session IDs with timestamp prefixing
- **Pre-signed URLs**: Time-limited (5min) upload/download access
- **Chunk Validation**: Server-side verification of audio uploads

### General Security
- **JWT Authentication**: All API calls require valid Cognito tokens
- **Input Sanitization**: File names and paths are sanitized
- **CORS Protection**: Proper CORS headers for web security
- **HTTPS Everywhere**: All traffic encrypted via CloudFront

## 🧹 Cleanup

To remove all AWS resources and avoid charges:
```bash
./step-99-cleanup.sh
```

This will safely delete:
- CloudFormation stack and all resources
- S3 buckets (after emptying)
- CloudFront distribution
- Cognito User and Identity Pools
- Lambda functions and log groups
- Serverless deployment artifacts

## 📊 Estimated Costs

For typical personal use:
- **S3 Storage**: ~$0.023/GB (audio files)
- **Lambda**: First 1M requests free
- **API Gateway**: First 1M requests free  
- **CloudFront**: First 1TB transfer free
- **Cognito**: First 50,000 MAUs free

Expected monthly cost: **$1-5** for personal use

## 🐛 Troubleshooting

### Common Audio Issues
1. **Microphone Access Denied**: Check browser permissions
2. **Upload Failures**: Verify network connection and retry logic
3. **Missing Icons**: Clear CloudFront cache, check CSS loading

### General Issues
1. **Authentication Failures**: Verify Cognito configuration in templates
2. **API Errors**: Check CloudWatch logs for Lambda functions
3. **Template Issues**: Ensure environment variables in `.env` are correct

### Debug Tools
- **Browser Console**: Check for JavaScript errors
- **CloudWatch Logs**: Monitor Lambda execution
- **Audio Debug Panel**: Built-in logging and export functionality

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch  
3. Edit `.template` files (not generated files)
4. Test on both desktop and mobile
5. Submit a pull request

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Built With

- **AWS Services**: Lambda, S3, Cognito, CloudFront, API Gateway
- **Frontend**: React 18, Babel (in-browser), MediaRecorder API
- **Infrastructure**: Serverless Framework, CloudFormation
- **Audio**: WebM/Opus encoding for Whisper compatibility

## 📚 Additional Documentation

- **[CLAUDE.md](CLAUDE.md)**: Comprehensive development guide
- **[AUDIO-RECORDING-SETUP.md](AUDIO-RECORDING-SETUP.md)**: Audio system documentation
- **AWS Documentation**: [Serverless](https://serverless.com/), [Cognito](https://docs.aws.amazon.com/cognito/), [S3](https://docs.aws.amazon.com/s3/)

---

**🎤 Ready to start recording?** Follow the Quick Start guide and you'll have a full-featured audio recording platform running in minutes!