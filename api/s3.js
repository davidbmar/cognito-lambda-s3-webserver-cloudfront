'use strict';

const AWS = require('aws-sdk');
const s3 = new AWS.S3();

module.exports.listObjects = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown'; // Cognito user ID
    
    console.log(`User ${email} (${userId}) requesting S3 objects`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Parse query parameters
    const queryParams = event.queryStringParameters || {};
    const onlyNames = queryParams.onlyNames === 'true';
    const userScope = queryParams.userScope !== 'false'; // Default to user-scoped


    // Determine the prefix based on user scope
    let prefix;
    if (userScope) {
      // User-specific files only
      const userPrefix = `users/${userId}/`;
      prefix = queryParams.prefix ? `${userPrefix}${queryParams.prefix}` : userPrefix;
    } else {
      // Global files - allow memory files and user files for authenticated users
      prefix = queryParams.prefix || '';
      
      // Security check: only allow memory paths and user paths when userScope=false
      if (prefix && !prefix.startsWith('claude-memory/') && !prefix.startsWith(`users/${userId}/`)) {
        throw new Error('Access denied: Invalid prefix for global scope');
      }
    }
    
    console.log(`Listing S3 objects in bucket: ${bucketName}, prefix: ${prefix}, onlyNames: ${onlyNames}`);

    // List objects in S3 bucket
    const s3Params = {
      Bucket: bucketName,
      Prefix: prefix,
      MaxKeys: 100 // Limit results for now
    };

    const s3Response = await s3.listObjectsV2(s3Params).promise();
    
    console.log(`Found ${s3Response.Contents?.length || 0} objects`);

    // Process the results based on the onlyNames flag
    let files;
    if (onlyNames) {
      // Return just filenames, removing the user prefix for cleaner display
      files = (s3Response.Contents || []).map(obj => {
        if (userScope && obj.Key.startsWith(`users/${userId}/`)) {
          return obj.Key.replace(`users/${userId}/`, '');
        }
        return obj.Key;
      });
    } else {
      // Return full metadata with clean display names
      files = (s3Response.Contents || []).map(obj => {
        let displayKey = obj.Key;
        if (userScope && obj.Key.startsWith(`users/${userId}/`)) {
          displayKey = obj.Key.replace(`users/${userId}/`, '');
        }
        
        return {
          key: obj.Key, // Original S3 key
          displayKey: displayKey, // Clean display name
          size: obj.Size,
          lastModified: obj.LastModified,
          etag: obj.ETag,
          storageClass: obj.StorageClass || 'STANDARD'
        };
      });
    }

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'S3 listing successful',
        user: email,
        userId: userId,
        bucket: bucketName,
        prefix: prefix,
        userScope: userScope,
        count: files.length,
        onlyNames: onlyNames,
        files: files,
        timestamp: new Date().toISOString()
      }, null, 2),
    };
  } catch (error) {
    console.error('Error listing S3 objects:', error);
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

// New function for generating pre-signed download URLs
module.exports.getDownloadUrl = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown';
    
    console.log(`User ${email} (${userId}) requesting download URL`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Get the file key from path parameters
    const fileKey = event.pathParameters?.key;
    if (!fileKey) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'File key is required' }),
      };
    }

    // Decode the file key (in case it was URL encoded)
    const decodedKey = decodeURIComponent(fileKey);

   
    // REPLACE with this enhanced security check:
    // Security check: Allow access to user files AND their memory files
    const userPrefix = `users/${userId}/`;
    const userMemoryPrefix = `claude-memory/${userId}/`;
    const publicMemoryPrefix = `claude-memory/public/`;
    
    if (!decodedKey.startsWith(userPrefix) && 
        !decodedKey.startsWith(userMemoryPrefix) && 
        !decodedKey.startsWith(publicMemoryPrefix)) {
      return {
        statusCode: 403,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ 
          error: 'Access denied: You can only access your own files and memory data' 
        }),
      };
    }

    // Check if file exists
    try {
      await s3.headObject({ Bucket: bucketName, Key: decodedKey }).promise();
    } catch (error) {
      if (error.code === 'NotFound') {
        return {
          statusCode: 404,
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Credentials': true,
          },
          body: JSON.stringify({ error: 'File not found' }),
        };
      }
      throw error;
    }

    // Generate pre-signed URL for download (valid for 15 minutes)
    const downloadUrl = s3.getSignedUrl('getObject', {
      Bucket: bucketName,
      Key: decodedKey,
      Expires: 60 * 15, // 15 minutes
      ResponseContentDisposition: `attachment; filename="${decodedKey.split('/').pop()}"` // Force download
    });

    console.log(`Generated download URL for ${decodedKey}`);

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'Download URL generated successfully',
        user: email,
        userId: userId,
        fileKey: decodedKey,
        downloadUrl: downloadUrl,
        expiresIn: 900, // 15 minutes in seconds
        timestamp: new Date().toISOString()
      }),
    };
  } catch (error) {
    console.error('Error generating download URL:', error);
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

// New function for generating pre-signed upload URLs
module.exports.getUploadUrl = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';
    const userId = claims.sub || 'unknown';
    
    console.log(`User ${email} (${userId}) requesting upload URL`);

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Parse request body
    const body = JSON.parse(event.body || '{}');
    const fileName = body.fileName;
    const contentType = body.contentType || 'application/octet-stream';
    const fileSize = body.fileSize;

    // Validate input
    if (!fileName) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ error: 'fileName is required' }),
      };
    }

    // Validate file size (max 100MB)
    const maxSize = 100 * 1024 * 1024; // 100MB
    if (fileSize && fileSize > maxSize) {
      return {
        statusCode: 400,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': true,
        },
        body: JSON.stringify({ 
          error: `File size exceeds maximum allowed size of ${maxSize / 1024 / 1024}MB` 
        }),
      };
    }

    // Sanitize filename - remove any path traversal attempts
    const sanitizedFileName = fileName.split('/').pop().split('\\').pop();
    
    // Create the S3 key for the user's file
    const fileKey = `users/${userId}/${sanitizedFileName}`;
    
    console.log(`Generating upload URL for ${fileKey}, content-type: ${contentType}`);

    // Generate pre-signed URL for upload (valid for 5 minutes)
    const uploadUrl = s3.getSignedUrl('putObject', {
      Bucket: bucketName,
      Key: fileKey,
      Expires: 60 * 5, // 5 minutes
      ContentType: contentType
    });

    console.log(`Generated upload URL for ${fileKey}`);

    return {
      statusCode: 200,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Credentials': true,
      },
      body: JSON.stringify({
        message: 'Upload URL generated successfully',
        user: email,
        userId: userId,
        fileName: sanitizedFileName,
        fileKey: fileKey,
        uploadUrl: uploadUrl,
        contentType: contentType,
        expiresIn: 300, // 5 minutes in seconds
        timestamp: new Date().toISOString()
      }),
    };
  } catch (error) {
    console.error('Error generating upload URL:', error);
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
