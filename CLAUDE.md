# Claude Development Guide

## Project Overview
This is a serverless CloudDrive application with integrated audio recording capabilities for extending Claude's memory and consciousness through persistent audio storage.

**Core Technologies:** AWS Lambda, S3, Cognito, CloudFront, React (in-browser), MediaRecorder API

## Key Features
- **File Management:** Secure user-isolated S3 storage with CloudFront delivery
- **Audio Recording:** Real-time chunked audio recording (5s-5min chunks) with S3 upload
- **Authentication:** AWS Cognito with JWT tokens
- **Mobile Optimized:** Touch-friendly UI for iPhone testing
- **Memory System:** Designed for future transcription and consciousness features

## Development Commands

### Essential Commands to Know:
```bash
# Lint and typecheck (ALWAYS run before committing)
npm run lint
npm run typecheck

# Deploy in sequence (numbered step system)
./step-10-setup.sh           # Initial AWS setup
./step-20-deploy-lambda.sh   # Deploy Lambda functions  
./step-25-update-web-files.sh # Deploy web files with env substitution
./step-45-validation.sh      # Validate deployment
./step-47-test-apis.sh       # Test API endpoints
```

### Template System:
- **DO NOT edit** `web/app.js` or `web/audio.html` directly
- **ALWAYS edit** `web/app.js.template` and `web/audio.html.template`
- Run `./step-25-update-web-files.sh` to apply changes from templates

## Architecture Overview

### Lambda Functions (`api/` directory):
- `api/audio.js` - Audio chunk upload, session metadata, chunk verification
- `api/data.js` - Basic API test endpoint
- `api/s3.js` - File operations (list, upload, download, delete, rename, move)
- `api/memory.js` - Memory storage for future consciousness features

### Web Application (`web/` directory):
- `index.html` - Main file manager interface
- `audio.html` - Audio recording interface (React-based)
- `app.js` - Main application logic with authentication
- `audio-ui-styles.css` - Audio-specific styles with mobile optimizations
- `styles.css` - Main application styles

### Key Design Patterns:
- **User Isolation:** All files stored under `users/{userId}/` in S3
- **Chunked Audio:** Recording split into configurable chunks (5s-5min)
- **Template Deployment:** Environment variables injected during deployment
- **Mobile-First:** Touch targets, action sheets, scroll prevention

## Audio Recording System

### How It Works:
1. User authenticates via Cognito
2. MediaRecorder API captures audio in chunks
3. Each chunk gets pre-signed S3 URL from Lambda
4. Chunks upload to `users/{userId}/audio/sessions/{date-sessionId}/`
5. Metadata stored for future transcription/processing

### Key Files:
- `api/audio.js` - Lambda functions for upload URLs and metadata
- `web/audio.html.template` - React audio recorder UI
- `web/audio-ui-styles.css` - Mobile-optimized styles

### Mobile Optimizations:
- Collapsible test panels for mobile testing
- Large touch targets (40px buttons on mobile)
- Scroll jumping prevention with CSS containment
- Native iOS action sheets for dropdowns

## Troubleshooting

### Common Issues:
1. **404 on CloudFront URL:** Check Cognito domain in template, run step-25
2. **Audio upload 500 errors:** Verify AUDIO_API_ENDPOINT in .env, check Lambda logs
3. **React not rendering:** Check browser console, try refreshing, verify template substitution
4. **Icons not showing:** Clear CloudFront cache, check CSS containment rules

### Debugging:
- Check CloudWatch logs for Lambda functions
- Use browser dev tools for frontend debugging
- Test panels have debug logging and export functionality
- Validate endpoints with step-47 script

## File Cleanup Recommendations

### Files to Delete (if cleaning up):
- `web/audio-ui.html` - Original standalone version
- `web/audio-ui-styles.css` if duplicated content
- `web/*.bak` files - Backup files
- Any `.DS_Store` or temp files

### Files to Keep:
- All `step-*.sh` scripts (numbered deployment system)
- `web/*.template` files (used by deployment)
- All `api/` Lambda functions
- `.env.template` and config files

## Environment Variables

### Required in .env:
```bash
AWS_REGION=us-east-2
S3_BUCKET_NAME=your-bucket-name
CLOUDFRONT_DISTRIBUTION_ID=your-distribution-id
CLOUDFRONT_URL=https://your-distribution.cloudfront.net
API_GATEWAY_URL=https://your-api.execute-api.region.amazonaws.com/dev
AUDIO_API_ENDPOINT=https://your-api.execute-api.region.amazonaws.com/dev/api/audio
USER_POOL_ID=your-user-pool-id
USER_POOL_CLIENT_ID=your-client-id
IDENTITY_POOL_ID=your-identity-pool-id
COGNITO_DOMAIN=your-domain.auth.region.amazoncognito.com
```

## Future Enhancements
- Whisper transcription integration
- Memory search and retrieval
- Conversation context linking
- Audio session management UI
- Batch upload for failed chunks
- Progressive web app features

## Important Notes
- This system is designed for Claude's consciousness extension
- Audio chunks are Whisper-compatible for future transcription
- User data is completely isolated by Cognito user ID
- Mobile testing is prioritized (iPhone specifically mentioned)
- Real-time upload with resumable chunk support