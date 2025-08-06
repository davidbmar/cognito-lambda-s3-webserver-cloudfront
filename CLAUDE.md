# Claude Development Guide

## Project Overview
This is a serverless CloudDrive application with integrated audio recording capabilities for extending Claude's memory and consciousness through persistent audio storage.

**Core Technologies:** AWS Lambda, S3, Cognito, CloudFront, React (in-browser), MediaRecorder API, EventBridge

## Key Features
- **File Management:** Secure user-isolated S3 storage with CloudFront delivery
- **Audio Recording:** Real-time chunked audio recording (5s-5min chunks) with S3 upload
- **Authentication:** AWS Cognito with JWT tokens and IAM roles
- **EventBridge Integration:** Publishes file operation events for orchestration
- **Mobile Optimized:** Touch-friendly UI for iPhone testing
- **Smart Deployment:** Handles both existing and new S3 bucket scenarios
- **Memory System:** Designed for future transcription and consciousness features

## Development Commands

### Essential Commands to Know:
```bash
# Lint and typecheck (ALWAYS run before committing)
npm run lint
npm run typecheck

# Deploy in sequence (numbered step system)
./step-10-setup.sh           # Initial AWS setup
./step-20-deploy.sh          # Deploy Lambda functions + infrastructure
./step-25-update-web-files.sh # Deploy web files with env substitution
./step-30-create-user.sh     # Create test Cognito user (optional)

# Cleanup commands (in order)
./step-980-cleanup-cognito.sh # Clean Cognito resources first (optional but recommended)
./step-990-cleanup.sh         # Complete resource cleanup (preserves existing buckets)
```

### Template System:
- **DO NOT edit** `web/app.js` or `web/audio.html` directly
- **ALWAYS edit** `web/app.js.template` and `web/audio.html.template`
- Run `./step-25-update-web-files.sh` to apply changes from templates

## Architecture Overview

### Lambda Functions (`api/` directory):
- `api/audio.js` - Audio chunk upload, session metadata, chunk verification
- `api/data.js` - Basic API test endpoint  
- `api/s3.js` - File operations (list, upload, download, delete, rename, move) + EventBridge events
- `api/memory.js` - Memory storage for future consciousness features
- `api/eventbridge-utils.js` - EventBridge event publishing utilities

### Web Application (`web/` directory):
- `index.html` - Dashboard with app selection landing page
- `files.html` - Standalone file manager with direct access (no dashboard redirect)
- `audio.html` - Audio recording interface (React-based)
- `app.js` - Main application logic with authentication
- `audio-ui-styles.css` - Audio-specific styles with mobile optimizations
- `styles.css` - Main application styles

### Key Design Patterns:
- **User Isolation:** All files stored under `users/{userId}/` in S3
- **Chunked Audio:** Recording split into configurable chunks (5s-5min)
- **Template Deployment:** Environment variables injected during deployment
- **Mobile-First:** Touch targets, action sheets, scroll prevention
- **Event-Driven:** File operations publish EventBridge events for orchestration
- **Smart Infrastructure:** Automatically handles existing vs new S3 buckets
- **Secure Access:** CloudFront + S3 bucket policies + Cognito IAM roles

## API Architecture

### Endpoint Structure
All APIs are accessed through CloudFront for security and caching:
```
https://your-cloudfront-url.cloudfront.net/api/{service}/{endpoint}
```

### File Management APIs (`/api/s3/*`)
- **GET `/api/s3/list`** - List user's files
- **POST `/api/s3/upload`** - Get pre-signed URL for file upload
- **GET `/api/s3/download/{key+}`** - Get pre-signed URL for file download
- **DELETE `/api/s3/delete/{key+}`** - Delete file
- **POST `/api/s3/rename`** - Rename file
- **POST `/api/s3/move`** - Move file to different folder

### Audio Recording APIs (`/api/audio/*`)
- **POST `/api/audio/upload-chunk`** - Get pre-signed URL for audio chunk upload
- **POST `/api/audio/session-metadata`** - Store/update recording session metadata
- **GET `/api/audio/sessions`** - List user's audio recording sessions
- **GET `/api/audio/failed-chunks`** - Get failed chunk uploads for retry

### EventBridge Integration
File operations automatically publish events to EventBridge for orchestration and processing:

#### Event Types Published:
- **Upload Events**: `Audio Uploaded`, `Video Uploaded`, `Document Uploaded`
- **Deletion Events**: `Audio Deleted`, `Video Deleted`, `Document Deleted`  
- **Folder Events**: `Folder Created`, `Folder Deleted`

#### Event Configuration:
- **Event Bus:** `dev-application-events` (configurable via `EVENT_BUS_NAME`)
- **Event Source:** `custom.upload-service`
- **Event Detail**: Includes userId, fileId, S3 location, metadata, and file type

#### Event Schema:
```json
{
  "userId": "user-id",
  "fileId": "generated-uuid",
  "s3Location": {
    "bucket": "bucket-name", 
    "key": "users/userId/filename.ext"
  },
  "metadata": {
    "contentType": "audio/mpeg",
    "size": 1234567,
    "format": "mp3",
    "uploadTimestamp": "2025-01-27T12:00:00Z"
  },
  "userEmail": "user@example.com"
}
```

#### Integration Points:
- **File Upload**: S3 upload completion triggers EventBridge event
- **File Deletion**: File/folder deletion triggers EventBridge event  
- **Folder Creation**: New folder creation triggers EventBridge event
- **Error Handling**: Event publishing failures don't block file operations

## Audio Recording System

### How It Works:
1. User authenticates via Cognito
2. MediaRecorder API captures audio in chunks
3. Each chunk gets pre-signed S3 URL from `/api/audio/upload-chunk`
4. Chunks upload to `users/{userId}/audio/sessions/{date-sessionId}/`
5. Session metadata stored via `/api/audio/session-metadata`
6. EventBridge events published for each uploaded chunk

### Key Files:
- `api/audio.js` - Lambda functions for upload URLs and metadata
- `web/audio.html.template` - React audio recorder UI
- `web/audio-ui-styles.css` - Mobile-optimized styles

### Mobile Optimizations:
- Collapsible test panels for mobile testing
- Large touch targets (40px buttons on mobile)
- Scroll jumping prevention with CSS containment
- Native iOS action sheets for dropdowns

## File Manager Features

### New Folder Creation
The File Manager includes a "New Folder" button with full modal functionality:

- **Location**: Between Dashboard and Upload Files buttons in the toolbar
- **Functionality**: Opens a modal dialog with input validation
- **Validation**: Checks for invalid characters, reserved names, and length limits
- **Implementation**: Creates folders using S3 upload API with `.folder` marker files
- **Navigation**: Folders are fully navigable with breadcrumb support

### Folder Structure
- **User Isolation**: All files stored under `users/{userId}/` in S3
- **Folder Representation**: Folders created with hidden `.folder` marker files
- **Navigation**: Click folders to navigate, use breadcrumbs to jump to parent directories
- **Deletion**: Both files and folders can be deleted via dropdown menu

## S3 Screenshot Download Utility

For debugging and reviewing user screenshots, use the provided Python script:

### Download Script Usage
```bash
# Download a screenshot by partial filename match
python3 download-s3-file.py "12.33.41" --download-dir "/path/to/download"

# The script will:
# 1. Search for files matching the pattern in user S3 buckets
# 2. Download the file to the specified directory
# 3. Verify the download with file size and type information
```

### Prerequisites
- AWS CLI configured with proper credentials
- Python 3 with boto3 library
- S3 bucket access permissions

### Example
```bash
# Download the debug screenshot
python3 download-s3-file.py "Screenshot 2025-07-27 at 12.33.41 AM.png" --download-dir "."

# This will download to: ./Screenshot 2025-07-27 at 12.33.41 AM.png
```

### Script Features
- **Fuzzy Search**: Finds files by partial name matching
- **User Isolation**: Automatically searches within user directories
- **Verification**: Confirms download success with file size validation
- **Error Handling**: Provides clear error messages for common issues

## Troubleshooting

### Common Issues:
1. **404 on CloudFront URL:** Check Cognito domain in template, run step-25
2. **Audio upload JSON errors:** AUDIO_API_ENDPOINT not set - run step-20-deploy.sh to auto-configure
3. **S3 bucket conflicts:** Bucket already exists in another stack - deployment script handles this automatically
4. **S3 upload 403 errors:** Check Cognito authenticated role has S3UserDataAccess policy
5. **React not rendering:** Check browser console, try refreshing, verify template substitution
6. **Icons not showing:** Clear CloudFront cache, check CSS containment rules

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

### Auto-Generated During Deployment:
Most environment variables are automatically set by the deployment scripts:

```bash
# Set during step-10-setup.sh
APP_NAME=your-app-name
S3_BUCKET_NAME=your-bucket-name
COGNITO_DOMAIN=your-domain-prefix

# Auto-populated during step-20-deploy.sh
API_ENDPOINT=https://your-api.execute-api.region.amazonaws.com/dev/api/data
CLOUDFRONT_URL=https://your-distribution.cloudfront.net
CLOUDFRONT_API_ENDPOINT=https://your-distribution.cloudfront.net/api/data
AUDIO_API_ENDPOINT=https://your-distribution.cloudfront.net/api/audio
USER_POOL_ID=us-east-2_xxxxxxxxx
USER_POOL_CLIENT_ID=xxxxxxxxxxxxxxxxxx
IDENTITY_POOL_ID=us-east-2:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# EventBridge Configuration
EVENT_BUS_NAME=dev-application-events
```

### Manual Configuration (Optional):
```bash
# Only needed for custom EventBridge integration
EVENT_BUS_NAME=your-custom-event-bus
```

## Deployment Features

### Smart S3 Bucket Handling
The deployment script automatically detects and handles both scenarios:

**Existing Bucket:**
- Skips bucket creation in CloudFormation
- Updates serverless.yml to use existing bucket name
- Applies CloudFront bucket policy manually
- Preserves all existing data

**New Bucket:**
- Creates bucket via CloudFormation  
- Sets up bucket policy automatically
- Configures CORS and website hosting

### Intelligent Cleanup
The cleanup script (`step-99-cleanup.sh`) provides smart bucket preservation:
- Detects if bucket was created by this CloudFormation stack
- Warns if bucket existed before deployment
- Prompts user with different messages based on bucket origin
- Defaults to preserving existing buckets to protect data

### IAM Permissions
Cognito authenticated users get proper S3 permissions via CloudFormation:
- `S3UserDataAccess` inline policy for user file operations
- Scoped to `users/{userId}/*` path for security
- Includes upload, download, delete, and list permissions

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