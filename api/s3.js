'use strict';

const AWS = require('aws-sdk');
const s3 = new AWS.S3();

module.exports.listObjects = async (event) => {
  try {
    // Get user claims from the authorizer
    const claims = event.requestContext?.authorizer?.claims || {};
    const email = claims.email || 'Anonymous';

    // Get bucket name from environment variable
    const bucketName = process.env.S3_BUCKET_NAME;
    if (!bucketName) {
      throw new Error('S3_BUCKET_NAME environment variable not set');
    }

    // Parse query parameters
    const queryParams = event.queryStringParameters || {};
    const onlyNames = queryParams.onlyNames === 'true';

    //const prefix = queryParams.prefix || 'uploads/'; // Default to uploads/ folder
    const prefix = queryParams.prefix || ''; // Default to root folder (all files)

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
      // Return just filenames
      files = (s3Response.Contents || []).map(obj => obj.Key);
    } else {
      // Return full metadata
      files = (s3Response.Contents || []).map(obj => ({
        key: obj.Key,
        size: obj.Size,
        lastModified: obj.LastModified,
        etag: obj.ETag,
        storageClass: obj.StorageClass || 'STANDARD'
      }));
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
        bucket: bucketName,
        prefix: prefix,
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
