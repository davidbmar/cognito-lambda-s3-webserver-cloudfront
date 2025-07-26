'use strict';

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Initialize EventBridge client
const eventbridge = new AWS.EventBridge();

// Import event schemas from the orchestrator project
const path = require('path');
const fs = require('fs');

// Event schema validation functions
const validateEventSchema = (eventData, schemaPath) => {
  try {
    // For now, we'll do basic validation
    // In production, you'd use a JSON schema validator like ajv
    if (!eventData.userId || !eventData.fileId || !eventData.s3Location) {
      throw new Error('Missing required fields: userId, fileId, or s3Location');
    }
    
    if (!eventData.s3Location.bucket || !eventData.s3Location.key) {
      throw new Error('Missing required s3Location fields: bucket or key');
    }
    
    if (!eventData.metadata || !eventData.metadata.contentType) {
      throw new Error('Missing required metadata fields');
    }
    
    return true;
  } catch (error) {
    console.error('Event validation error:', error.message);
    return false;
  }
};

// Get file type from content type or file extension
const getFileType = (contentType, fileName) => {
  // Audio types
  if (contentType.startsWith('audio/') || 
      fileName.match(/\.(mp3|wav|flac|m4a|aac|ogg|opus)$/i)) {
    return 'audio';
  }
  
  // Video types
  if (contentType.startsWith('video/') || 
      fileName.match(/\.(mp4|avi|mov|mkv|wmv|flv|webm)$/i)) {
    return 'video';
  }
  
  // Document types
  if (contentType.includes('pdf') || contentType.includes('document') ||
      fileName.match(/\.(pdf|doc|docx|txt|rtf|odt)$/i)) {
    return 'document';
  }
  
  // Default to document for other file types
  return 'document';
};

// Generate detailed event metadata
const generateEventMetadata = (contentType, fileSize, fileName) => {
  const fileType = getFileType(contentType, fileName);
  const metadata = {
    format: fileName.split('.').pop()?.toLowerCase() || 'unknown',
    size: fileSize || 0,
    contentType: contentType,
    uploadTimestamp: new Date().toISOString()
  };
  
  // Add type-specific metadata
  if (fileType === 'audio') {
    metadata.estimatedDuration = Math.floor((fileSize || 0) / (128 * 1024 / 8)); // Rough estimate
    metadata.bitrate = 128; // Default estimate
    metadata.sampleRate = 44100; // Default estimate
    metadata.channels = 2; // Default estimate
  } else if (fileType === 'video') {
    metadata.estimatedDuration = Math.floor((fileSize || 0) / (1024 * 1024)); // Very rough estimate
    metadata.resolution = 'unknown';
    metadata.codec = 'unknown';
  } else if (fileType === 'document') {
    metadata.pageCount = null;
    metadata.language = 'unknown';
  }
  
  return metadata;
};

// Publish event to EventBridge
const publishEvent = async (eventType, eventDetail, userEmail = 'unknown') => {
  try {
    const eventBusName = process.env.EVENT_BUS_NAME || 'default';
    
    // Validate the event data
    if (!validateEventSchema(eventDetail)) {
      console.error('Event validation failed, skipping publication');
      return false;
    }
    
    const eventEntry = {
      Source: 'custom.upload-service',
      DetailType: eventType,
      Detail: JSON.stringify(eventDetail),
      EventBusName: eventBusName,
      Time: new Date()
    };
    
    console.log(`Publishing ${eventType} event to ${eventBusName}:`, {
      userId: eventDetail.userId,
      fileId: eventDetail.fileId,
      s3Key: eventDetail.s3Location.key
    });
    
    const result = await eventbridge.putEvents({
      Entries: [eventEntry]
    }).promise();
    
    if (result.FailedEntryCount > 0) {
      console.error('Failed to publish event:', result.Entries[0].ErrorMessage);
      return false;
    }
    
    console.log(`Successfully published ${eventType} event:`, result.Entries[0].EventId);
    return result.Entries[0].EventId;
    
  } catch (error) {
    console.error('Error publishing event to EventBridge:', error);
    return false;
  }
};

// Create upload event after successful presigned URL generation
const createUploadEvent = async (userId, userEmail, fileName, fileKey, contentType, fileSize) => {
  const fileType = getFileType(contentType, fileName);
  const metadata = generateEventMetadata(contentType, fileSize, fileName);
  
  const eventDetail = {
    userId: userId,
    fileId: uuidv4(),
    s3Location: {
      bucket: process.env.S3_BUCKET_NAME,
      key: fileKey
    },
    metadata: metadata,
    userEmail: userEmail,
    fileName: fileName
  };
  
  const eventType = `${fileType.charAt(0).toUpperCase() + fileType.slice(1)} Uploaded`;
  return await publishEvent(eventType, eventDetail, userEmail);
};

// Create deletion event after successful file deletion
const createDeletionEvent = async (userId, userEmail, fileKey) => {
  const fileName = fileKey.split('/').pop();
  const fileExtension = fileName.split('.').pop()?.toLowerCase();
  const fileType = getFileType('', fileName);
  
  const eventDetail = {
    userId: userId,
    fileId: uuidv4(),
    s3Location: {
      bucket: process.env.S3_BUCKET_NAME,
      key: fileKey
    },
    metadata: {
      format: fileExtension || 'unknown',
      deletionTimestamp: new Date().toISOString()
    },
    userEmail: userEmail,
    fileName: fileName,
    action: 'deleted'
  };
  
  const eventType = `${fileType.charAt(0).toUpperCase() + fileType.slice(1)} Deleted`;
  return await publishEvent(eventType, eventDetail, userEmail);
};

// Create move/rename event after successful file operation
const createMoveEvent = async (userId, userEmail, oldKey, newKey, operation = 'moved') => {
  const fileName = newKey.split('/').pop();
  const fileType = getFileType('', fileName);
  
  const eventDetail = {
    userId: userId,
    fileId: uuidv4(),
    s3Location: {
      bucket: process.env.S3_BUCKET_NAME,
      key: newKey
    },
    previousLocation: {
      bucket: process.env.S3_BUCKET_NAME,
      key: oldKey
    },
    metadata: {
      operation: operation,
      operationTimestamp: new Date().toISOString()
    },
    userEmail: userEmail,
    fileName: fileName
  };
  
  const eventType = `${fileType.charAt(0).toUpperCase() + fileType.slice(1)} ${operation.charAt(0).toUpperCase() + operation.slice(1)}`;
  return await publishEvent(eventType, eventDetail, userEmail);
};

module.exports = {
  publishEvent,
  createUploadEvent,
  createDeletionEvent,
  createMoveEvent,
  validateEventSchema,
  getFileType,
  generateEventMetadata
};