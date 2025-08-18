'use strict';

const AWS = require('aws-sdk');
const s3 = new AWS.S3();
const { createUploadEvent } = require('./eventbridge-utils');

// Generate pre-signed URL for audio chunk upload
module.exports.uploadChunk = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown';
    
    console.log(`User ${email} (${userId}) requesting audio chunk upload`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Parse request body
    const body = JSON.parse(event.body || '{}');
    const { sessionId, chunkNumber, contentType, duration } = body;

    // Validate required fields
    if (!sessionId || chunkNumber === undefined) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'sessionId and chunkNumber are required' }),
      };
    }

    // Validate chunk number
    if (typeof chunkNumber !== 'number' || chunkNumber < 1) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'Invalid chunk number' }),
      };
    }

    // Sanitize session ID to prevent path traversal
    const sanitizedSessionId = sessionId.replace(/[^a-zA-Z0-9\-_]/g, '');
    if (!sanitizedSessionId) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'Invalid session ID' }),
      };
    }

    // Use the sessionId directly as the folder name (frontend now generates timestamped sessionId)
    const paddedChunkNumber = chunkNumber.toString().padStart(3, '0');
    
    // Build S3 key with user isolation
    const s3Key = `users/${userId}/audio/sessions/${sanitizedSessionId}/chunk-${paddedChunkNumber}.wav`;
    
    console.log(`Generating upload URL for chunk ${chunkNumber} of session ${sanitizedSessionId}`);

    // Generate pre-signed URL for upload
    const uploadUrl = s3.getSignedUrl('putObject', {
      Bucket: bucketName,
      Key: s3Key,
      Expires: 300, // 5 minutes
      ContentType: contentType || 'audio/webm'
    });

    console.log(`Generated upload URL for ${s3Key}`);

    // Publish EventBridge event for audio upload
    try {
      const fileSize = body.fileSize || 0;
      const fileName = `chunk-${paddedChunkNumber}.wav`;
      const eventId = await createUploadEvent(userId, email, fileName, s3Key, 'audio/wav', fileSize);
      console.log(`Published audio upload event with ID: ${eventId}`);
    } catch (eventError) {
      // Don't fail the upload if event publishing fails
      console.warn('Failed to publish audio upload event:', eventError.message);
    }

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'Upload URL generated successfully',
        uploadUrl: uploadUrl,
        s3Key: s3Key,
        sessionId: sanitizedSessionId,
        chunkNumber: chunkNumber,
        expiresIn: 300,
        maxSizeBytes: 26214400,
        timestamp: new Date().toISOString()
      }),
    };
  } catch (error) {
    console.error('Error generating audio upload URL:', error);
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({ 
        error: error.message,
        timestamp: new Date().toISOString()
      }),
    };
  }
};

// Create or update session metadata
module.exports.updateSessionMetadata = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown';
    
    console.log(`User ${email} (${userId}) updating session metadata`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Parse request body
    const body = JSON.parse(event.body || '{}');
    const { sessionId, metadata } = body;

    if (!sessionId || !metadata) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'sessionId and metadata are required' }),
      };
    }

    // Sanitize session ID
    const sanitizedSessionId = sessionId.replace(/[^a-zA-Z0-9\-_]/g, '');
    const timestamp = new Date().toISOString().split('T')[0];
    
    // Build metadata S3 key
    const metadataKey = `users/${userId}/audio/sessions/${timestamp}-${sanitizedSessionId}/metadata.json`;
    
    // Prepare metadata object with additional fields for future consciousness features
    const fullMetadata = {
      sessionId: sanitizedSessionId,
      userId: userId,
      userEmail: email,
      createdAt: metadata.createdAt || new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      duration: metadata.duration || 0,
      chunkCount: metadata.chunkCount || 0,
      chunkDuration: metadata.chunkDuration || 5,
      status: metadata.status || 'recording',
      transcriptionStatus: 'pending',
      // Fields for future memory/consciousness features
      summary: metadata.summary || '',
      keywords: metadata.keywords || [],
      conversationContext: metadata.conversationContext || '',
      previousSession: metadata.previousSession || null,
      nextSession: null,
      ...metadata
    };

    // Upload metadata to S3
    await s3.putObject({
      Bucket: bucketName,
      Key: metadataKey,
      Body: JSON.stringify(fullMetadata, null, 2),
      ContentType: 'application/json'
    }).promise();

    console.log(`Updated metadata for session ${sanitizedSessionId}`);

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'Session metadata updated successfully',
        sessionId: sanitizedSessionId,
        metadataKey: metadataKey,
        timestamp: new Date().toISOString()
      }),
    };
  } catch (error) {
    console.error('Error updating session metadata:', error);
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({ 
        error: error.message,
        timestamp: new Date().toISOString()
      }),
    };
  }
};

// List audio sessions for a user
module.exports.listSessions = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown';
    
    console.log(`User ${email} (${userId}) listing audio sessions`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // List all session folders for the user
    const prefix = `users/${userId}/audio/sessions/`;
    
    const s3Response = await s3.listObjectsV2({
      Bucket: bucketName,
      Prefix: prefix,
      Delimiter: '/'
    }).promise();

    // Extract session folders from CommonPrefixes
    const sessions = [];
    if (s3Response.CommonPrefixes) {
      for (const prefix of s3Response.CommonPrefixes) {
        const sessionFolder = prefix.Prefix.split('/').slice(-2)[0]; // Get folder name
        
        // Try to load metadata for each session
        try {
          const metadataKey = `${prefix.Prefix}metadata.json`;
          const metadataObj = await s3.getObject({
            Bucket: bucketName,
            Key: metadataKey
          }).promise();
          
          const metadata = JSON.parse(metadataObj.Body.toString());
          sessions.push({
            sessionId: metadata.sessionId,
            folder: sessionFolder,
            metadata: metadata
          });
        } catch (err) {
          // If no metadata, just include basic info
          sessions.push({
            sessionId: sessionFolder,
            folder: sessionFolder,
            metadata: null
          });
        }
      }
    }

    // Sort sessions by creation date (newest first)
    sessions.sort((a, b) => {
      const dateA = a.metadata?.createdAt || a.folder;
      const dateB = b.metadata?.createdAt || b.folder;
      return dateB.localeCompare(dateA);
    });

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'Sessions listed successfully',
        user: email,
        userId: userId,
        sessions: sessions,
        count: sessions.length,
        timestamp: new Date().toISOString()
      }),
    };
  } catch (error) {
    console.error('Error listing sessions:', error);
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({ 
        error: error.message,
        timestamp: new Date().toISOString()
      }),
    };
  }
};

// Get failed chunks for a session (for batch retry)
module.exports.getFailedChunks = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const userId = claims.sub || 'unknown';
    
    // Get session ID from query parameters
    const sessionId = event.queryStringParameters?.sessionId;
    if (!sessionId) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'sessionId is required' }),
      };
    }

    // This endpoint would typically check a database or DynamoDB table
    // For MVP, we'll return expected chunks vs actual chunks in S3
    
    const bucketName = process.env.S3_BUCKET_NAME;
    const sanitizedSessionId = sessionId.replace(/[^a-zA-Z0-9\-_]/g, '');
    const timestamp = new Date().toISOString().split('T')[0];
    const prefix = `users/${userId}/audio/sessions/${timestamp}-${sanitizedSessionId}/`;
    
    // List existing chunks
    const s3Response = await s3.listObjectsV2({
      Bucket: bucketName,
      Prefix: prefix
    }).promise();
    
    const existingChunks = (s3Response.Contents || [])
      .filter(obj => obj.Key.includes('chunk-'))
      .map(obj => {
        const match = obj.Key.match(/chunk-(\d+)\.wav$/);
        return match ? parseInt(match[1]) : null;
      })
      .filter(num => num !== null);
    
    // Get metadata to know expected chunks
    try {
      const metadataKey = `${prefix}metadata.json`;
      const metadataObj = await s3.getObject({
        Bucket: bucketName,
        Key: metadataKey
      }).promise();
      
      const metadata = JSON.parse(metadataObj.Body.toString());
      const expectedChunks = metadata.chunkCount || 0;
      
      // Find missing chunks
      const missingChunks = [];
      for (let i = 1; i <= expectedChunks; i++) {
        if (!existingChunks.includes(i)) {
          missingChunks.push(i);
        }
      }
      
      return {
        statusCode: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({
          sessionId: sanitizedSessionId,
          expectedChunks: expectedChunks,
          uploadedChunks: existingChunks.sort((a, b) => a - b),
          missingChunks: missingChunks,
          timestamp: new Date().toISOString()
        }),
      };
    } catch (err) {
      // No metadata found
      return {
        statusCode: 200,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({
          sessionId: sanitizedSessionId,
          uploadedChunks: existingChunks.sort((a, b) => a - b),
          missingChunks: [],
          error: 'No metadata found for session',
          timestamp: new Date().toISOString()
        }),
      };
    }
  } catch (error) {
    console.error('Error checking failed chunks:', error);
    return {
      statusCode: 500,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({ 
        error: error.message,
        timestamp: new Date().toISOString()
      }),
    };
  }
};