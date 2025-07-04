# Audio Recording Functionality Setup

This document describes how to set up and use the audio recording functionality in CloudDrive.

## 🎤 Overview

The audio recording feature allows users to:
- Record audio in real-time with automatic chunking
- Upload chunks to S3 with user isolation
- Store session metadata for future processing
- Manage recording sessions with authentication
- Prepare audio for transcription (Whisper-compatible format)

## 🏗️ Architecture

```
User Browser → Audio UI → Lambda Functions → S3 Storage
     ↓              ↓           ↓              ↓
  MediaRecorder   Cognito   Pre-signed URLs  Audio Chunks
    API          Auth         & Metadata     & Sessions
```

### Audio Storage Structure
```
s3://bucket-name/
└── users/
    └── {userId}/
        └── audio/
            └── sessions/
                └── {YYYY-MM-DD}-{sessionId}/
                    ├── metadata.json
                    ├── chunk-001.webm
                    ├── chunk-002.webm
                    └── chunk-XXX.webm
```

## 🚀 Setup Instructions

### Step 1: Deploy Audio Infrastructure
```bash
# Run the audio setup script
./step-45-setup-audio.sh
```

This script will:
- Deploy Lambda functions for audio operations
- Configure API Gateway endpoints
- Set up S3 permissions for audio storage
- Validate the audio infrastructure

### Step 2: Upload Web Files
```bash
# Update and upload web files including audio UI
./step-25-update-web-files.sh
```

This will:
- Update audio.html with correct API endpoints
- Upload audio UI to S3/CloudFront
- Create CloudFront invalidation

### Step 3: Validate Setup
```bash
# Validate that everything is working
./step-47-validate-audio.sh
```

## 🎵 Using the Audio Recorder

### Accessing the Audio Recorder
1. Navigate to your CloudFront URL + `/audio.html`
2. Log in with your Cognito credentials
3. Grant microphone permissions when prompted

### Recording Audio
1. **Set Chunk Duration**: Choose between 5 seconds to 5 minutes
2. **Start Recording**: Click the microphone button
3. **Monitor Progress**: Watch real-time upload status for each chunk
4. **Stop Recording**: Click the stop button to end the session

### Features
- **Real-time Upload**: Chunks upload automatically as they're created
- **Upload Status**: Visual indicators show upload progress
- **Session Management**: Each recording session has a unique ID
- **Playback**: Test recorded chunks locally
- **Metadata Tracking**: Automatic session metadata storage

## 🔧 API Endpoints

### Audio Chunk Upload
```http
POST /api/audio/upload-chunk
Authorization: Bearer {jwt-token}
Content-Type: application/json

{
  "sessionId": "session-123",
  "chunkNumber": 1,
  "contentType": "audio/webm",
  "duration": 5
}
```

### Session Metadata
```http
POST /api/audio/session-metadata
Authorization: Bearer {jwt-token}
Content-Type: application/json

{
  "sessionId": "session-123",
  "metadata": {
    "status": "recording",
    "chunkDuration": 5,
    "conversationContext": "Meeting notes"
  }
}
```

### List Sessions
```http
GET /api/audio/sessions
Authorization: Bearer {jwt-token}
```

### Check Failed Chunks
```http
GET /api/audio/failed-chunks?sessionId=session-123
Authorization: Bearer {jwt-token}
```

## 🔐 Security Features

### User Isolation
- Each user can only access their own audio files
- S3 paths are user-scoped: `users/{userId}/audio/`
- JWT tokens validate user identity

### Upload Security
- Pre-signed URLs with 5-minute expiration
- Maximum chunk size of 25MB (Whisper compatible)
- Content-type validation
- Path traversal protection

### Authentication
- All endpoints require valid Cognito JWT tokens
- User identity extracted from token claims
- Automatic session expiration

## 📊 Metadata Structure

### Session Metadata (metadata.json)
```json
{
  "sessionId": "session-1704467445123-abc123",
  "userId": "cognito-user-id",
  "userEmail": "user@example.com",
  "createdAt": "2025-01-04T15:30:45.123Z",
  "updatedAt": "2025-01-04T15:35:12.456Z",
  "duration": 285,
  "chunkCount": 57,
  "chunkDuration": 5,
  "status": "completed",
  "transcriptionStatus": "pending",
  "summary": "",
  "keywords": [],
  "conversationContext": "Voice recording session",
  "previousSession": null,
  "nextSession": null
}
```

## 🎯 Future Enhancements

### Transcription Pipeline
```bash
# Future: Set up Whisper transcription
aws transcribe start-transcription-job \
  --transcription-job-name audio-session-123 \
  --media MediaFileUri=s3://bucket/users/123/audio/sessions/session-123/chunk-001.webm
```

### Search & Memory Features
- Full-text search of transcriptions
- Conversation threading and context linking
- AI-powered summarization
- Keyword extraction and tagging

### Batch Operations
- Retry failed uploads
- Concatenate chunks into full sessions
- Bulk transcription processing
- Archive old sessions

## 🧪 Testing

### Manual Testing Checklist
- [ ] Audio UI loads correctly
- [ ] User authentication works
- [ ] Microphone permissions granted
- [ ] Recording starts/stops properly
- [ ] Chunks upload to S3 automatically
- [ ] Session metadata is created
- [ ] Upload status indicators work
- [ ] Local playback functions
- [ ] Failed uploads show retry option

### Automated Testing
```bash
# Run validation script
./step-47-validate-audio.sh

# Test API endpoints directly
./test-audio-upload.sh [API_URL] [JWT_TOKEN]
```

### Browser Compatibility
- Chrome 47+ ✅
- Firefox 25+ ✅
- Safari 14.1+ ✅
- Edge 79+ ✅

**Note**: HTTPS is required for microphone access in production.

## 🐛 Troubleshooting

### Common Issues

#### "Microphone access denied"
- Ensure HTTPS in production
- Check browser permissions
- Verify audio hardware

#### "Upload failed" errors
- Check AWS credentials
- Verify S3 bucket permissions
- Check internet connectivity
- Validate JWT token expiration

#### "Audio UI not loading"
- Run `step-25-update-web-files.sh`
- Check CloudFront invalidation
- Verify S3 bucket permissions

#### "Authentication required"
- Ensure user is logged in
- Check JWT token validity
- Verify Cognito configuration

### Debug Information
The audio UI includes a debug panel with:
- Real-time logging
- Upload status tracking
- Session information
- Error messages

### Log Analysis
```bash
# Check Lambda logs
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/audio

# Monitor S3 uploads
aws s3 ls s3://your-bucket/users/ --recursive | grep audio
```

## 📚 Additional Resources

- [MediaRecorder API Documentation](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder)
- [OpenAI Whisper Documentation](https://openai.com/research/whisper)
- [AWS S3 Pre-signed URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)
- [AWS Cognito Authentication](https://docs.aws.amazon.com/cognito/latest/developerguide/)

## 🤝 Contributing

When adding audio features:
1. Follow the existing authentication patterns
2. Maintain user isolation in S3 paths
3. Use pre-signed URLs for uploads
4. Include proper error handling
5. Add debug logging
6. Update validation scripts

## 📞 Support

For issues with audio recording:
1. Run `step-47-validate-audio.sh` for diagnostics
2. Check browser developer console for errors
3. Verify AWS permissions and configuration
4. Review Lambda function logs in CloudWatch