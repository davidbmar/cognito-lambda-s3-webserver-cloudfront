# EventBridge Integration for Audio Upload System

This document explains the EventBridge integration added to the audio upload system to enable event-driven architecture.

## Overview

The integration publishes structured events to AWS EventBridge whenever users interact with files (upload, delete, rename, move). These events can be consumed by other services for processing, notifications, or analytics.

## Event Types Published

### 1. Audio Uploaded
- **Trigger**: When upload URL is generated for audio files
- **Event Type**: `Audio Uploaded`
- **Source**: `custom.upload-service`

### 2. Video Uploaded  
- **Trigger**: When upload URL is generated for video files
- **Event Type**: `Video Uploaded`
- **Source**: `custom.upload-service`

### 3. Document Uploaded
- **Trigger**: When upload URL is generated for document files
- **Event Type**: `Document Uploaded`
- **Source**: `custom.upload-service`

### 4. File Deleted
- **Trigger**: When files are successfully deleted
- **Event Types**: `Audio Deleted`, `Video Deleted`, `Document Deleted`

### 5. File Operations
- **Trigger**: When files are renamed or moved
- **Event Types**: `Audio Renamed`, `Video Renamed`, `Document Renamed`, etc.

## Event Schema

All events follow this structure:

```json
{
  "userId": "cognito-user-id",
  "fileId": "uuid-v4-identifier", 
  "s3Location": {
    "bucket": "bucket-name",
    "key": "users/userId/filename.ext"
  },
  "metadata": {
    "format": "mp3",
    "size": 1024000,
    "contentType": "audio/mpeg",
    "uploadTimestamp": "2024-01-01T12:00:00.000Z"
  },
  "userEmail": "user@example.com",
  "fileName": "recording.mp3"
}
```

## File Type Detection

The system automatically detects file types based on:
- Content-Type header
- File extension
- Defaults to "document" for unknown types

## Validation

Events are validated before publishing to ensure:
- Required fields are present (userId, fileId, s3Location)
- S3 location has bucket and key
- Metadata contains contentType

## Configuration

### Environment Variables

Add to your deployment:

```bash
export EVENT_BUS_NAME="your-custom-event-bus"  # Optional, defaults to "default"
```

### IAM Permissions

The serverless.yml.template includes:

```yaml
- Effect: Allow
  Action:
    - events:PutEvents
  Resource: "*"
```

## Files Added/Modified

### New Files
- `api/eventbridge-utils.js` - Event publishing utilities
- `package.json` - Node.js dependencies

### Modified Files
- `api/s3.js` - Added event publishing to all S3 operations
- `serverless.yml.template` - Added EventBridge permissions and environment variables

## Error Handling

- EventBridge publishing failures do NOT block S3 operations
- Errors are logged but don't affect user experience
- Events are published asynchronously after successful S3 operations

## Integration Benefits

1. **Decoupled Architecture**: Services can react to file events without direct coupling
2. **Scalable Processing**: Multiple consumers can process the same events
3. **Audit Trail**: Complete history of file operations
4. **Real-time Notifications**: Immediate notifications of file activities
5. **Analytics**: File usage patterns and user behavior insights

## Deployment

1. Install dependencies: `npm install`
2. Set EVENT_BUS_NAME environment variable (optional)
3. Deploy with existing serverless deployment process
4. Events will automatically be published to the configured EventBridge bus

## Monitoring

Events can be monitored through:
- AWS CloudWatch Events console
- EventBridge rules and targets
- Lambda function logs (search for "Published [event-type] event")

## Breaking Changes

**None** - This integration is fully backwards compatible and additive only.