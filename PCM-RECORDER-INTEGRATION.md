# PCM Audio Recorder Integration

## Overview
This document describes the integration of a high-quality PCM/WAV audio recorder to replace or supplement the existing WebM/Opus recorder in the CloudDrive application.

## Why PCM/WAV?

### Advantages for Transcription
- **Higher Accuracy**: Whisper performs better with uncompressed audio
- **No Compression Artifacts**: Full frequency spectrum preserved
- **Better Speech Detection**: Clearer consonants and quiet speech
- **Universal Compatibility**: WAV is supported by all transcription services

### Trade-offs
- **Larger Files**: ~10x bigger than WebM/Opus
- **More Bandwidth**: Higher upload times and storage costs
- **But Worth It**: For applications requiring high-quality transcription

## Architecture

### Recording Pipeline
```
Microphone → PCM Recorder → Float32Array → WAV Encoder → S3 Upload
                ↓                              ↓
          IndexedDB (backup)            Pre-signed URLs
```

### Key Components

#### 1. PCM Recorder (`js/recorder-box.js`)
- Captures raw PCM audio using Web Audio API
- Configurable chunk duration (5s - 5min)
- Frame-accurate chunking
- Real-time level metering

#### 2. WAV Encoder (`js/wav-encoder.js`)
- Converts Float32Array PCM to WAV format
- Adds proper WAV headers
- 48kHz sample rate, 16-bit depth

#### 3. S3 Storage Adapter (`js/storage-s3.js`)
- Replaces IndexedDB with S3 upload
- Maintains local backup option
- Uses existing authentication
- Uploads WAV chunks to S3

#### 4. UI (`audio-pcm.html`)
- Modern, responsive interface
- Real-time upload status
- Chunk duration control
- Session management

## File Structure

```
web/
├── audio-pcm.html           # Main PCM recorder page
├── audio-pcm.html.template  # Template for deployment
├── js/
│   ├── recorder-box.js      # Core PCM recorder
│   ├── wav-encoder.js       # PCM to WAV conversion
│   ├── storage-s3.js        # S3 upload adapter
│   └── adapters/
│       ├── storage-indexeddb.js  # Local storage backup
│       └── recorder-box.js       # Recorder adapter
```

## Deployment

### 1. Run the deployment script
```bash
./step-025-update-web-files.sh
```

This will:
- Process the template files
- Replace placeholders with actual AWS resource IDs
- Upload to S3
- Invalidate CloudFront cache

### 2. Access the new recorder
```
https://your-cloudfront-url/audio-pcm.html
```

## Configuration

### Chunk Duration
Users can select chunk duration from 5 seconds to 5 minutes using the slider.

### Audio Format
- **Format**: WAV (PCM)
- **Sample Rate**: 48 kHz
- **Bit Depth**: 16-bit
- **Channels**: Mono

## S3 Storage Structure

```
s3://your-bucket/
└── users/
    └── {userId}/
        └── audio/
            └── sessions/
                └── {sessionId}/
                    ├── chunk-000.wav
                    ├── chunk-001.wav
                    └── metadata.json
```

## API Integration

### Upload Chunk Endpoint
```javascript
POST /api/audio/upload-chunk
{
    "sessionId": "session-123",
    "chunkNumber": 0,
    "contentType": "audio/wav",
    "duration": 10
}
```

### Session Metadata Endpoint
```javascript
POST /api/audio/session-metadata
{
    "sessionId": "session-123",
    "metadata": {
        "status": "recording",
        "chunkDuration": 10,
        "createdAt": "2025-01-01T00:00:00Z"
    }
}
```

## Migration from WebM to PCM

### For Users
1. Both recorders are available side-by-side
2. WebM recorder: `/audio.html` (smaller files)
3. PCM recorder: `/audio-pcm.html` (better quality)

### For Developers
1. Existing WebM recordings remain compatible
2. Transcription pipeline works with both formats
3. Can gradually migrate to PCM for better quality

## Browser Compatibility

### Supported Browsers
- Chrome 90+
- Firefox 85+
- Safari 14.1+
- Edge 90+

### Required APIs
- MediaDevices.getUserMedia
- Web Audio API
- ES6 Modules
- IndexedDB (for backup)

## Security

### Authentication
- Uses existing Cognito authentication
- JWT tokens for API calls
- User isolation in S3

### Data Protection
- Local IndexedDB backup
- Encrypted S3 storage
- Pre-signed URLs for uploads

## Troubleshooting

### Common Issues

#### 1. Microphone Permission Denied
- Check browser permissions
- Ensure HTTPS connection
- Allow microphone access

#### 2. Upload Failures
- Check authentication token
- Verify S3 bucket permissions
- Check network connectivity

#### 3. No Audio Level
- Verify microphone is working
- Check browser console for errors
- Ensure Web Audio API support

## Future Enhancements

### Planned Features
- Real-time transcription preview
- Multi-track recording
- Noise reduction filters
- Automatic gain control
- Voice activity detection

### Integration Points
- Whisper transcription service
- Real-time streaming to Lambda
- WebRTC for remote recording
- Cloud-based audio processing

## Performance Considerations

### File Sizes
- WebM/Opus: ~150 KB/minute
- WAV/PCM: ~1.5 MB/minute

### Upload Times
- Depends on network speed
- Chunked upload reduces latency
- Background upload capability

### Storage Costs
- WAV files are ~10x larger
- Consider lifecycle policies
- Archive old recordings to Glacier

## Support

For issues or questions:
1. Check browser console for errors
2. Review debug logs in the UI
3. Verify AWS resource configuration
4. Check CloudWatch logs for Lambda errors

## License
This integration maintains compatibility with the existing CloudDrive application license.