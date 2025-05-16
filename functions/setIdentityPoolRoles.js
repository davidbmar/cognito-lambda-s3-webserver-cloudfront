'use strict';

const AWS = require('aws-sdk');
const https = require('https');
const url = require('url');

// Send response to CloudFormation
async function sendResponse(event, context, responseStatus, responseData) {
  try {
    // Log all inputs for debugging
    console.log('Sending response:');
    console.log('  Status:', responseStatus);
    console.log('  Data:', JSON.stringify(responseData));
    
    const responseBody = JSON.stringify({
      Status: responseStatus,
      Reason: responseData.Error ? responseData.Error : 'See the details in CloudWatch Log Stream: ' + context.logStreamName,
      PhysicalResourceId: context.logStreamName,
      StackId: event.StackId,
      RequestId: event.RequestId,
      LogicalResourceId: event.LogicalResourceId,
      Data: responseData
    });

    console.log('Response body:', responseBody);

    // Additional check for response URL
    if (!event.ResponseURL) {
      console.error('No ResponseURL found in the event!');
      return;
    }

    const parsedUrl = url.parse(event.ResponseURL);
    const options = {
      hostname: parsedUrl.hostname,
      port: 443,
      path: parsedUrl.path,
      method: 'PUT',
      headers: {
        'Content-Type': '',
        'Content-Length': responseBody.length
      }
    };

    console.log('Sending HTTP request to:', event.ResponseURL);
    
    return new Promise((resolve, reject) => {
      const request = https.request(options, (response) => {
        console.log(`Status code: ${response.statusCode}`);
        console.log(`Status message: ${response.statusMessage}`);
        resolve();
      });

      request.on('error', (error) => {
        console.log(`send() error: ${error}`);
        reject(error);
      });

      request.write(responseBody);
      request.end();
    });
  } catch (error) {
    console.error('Error sending response:', error);
    throw error;
  }
}

exports.handler = async (event, context) => {
  console.log('REQUEST RECEIVED:', JSON.stringify(event));
  console.log('CONTEXT:', JSON.stringify(context));
  console.log('ENV VARS:', JSON.stringify(process.env));
  
  // For Delete operations, just succeed
  if (event.RequestType === 'Delete') {
    try {
      await sendResponse(event, context, 'SUCCESS', {});
    } catch (error) {
      console.error('Error sending response for Delete:', error);
    }
    return;
  }
  
  try {
    const cognitoidentity = new AWS.CognitoIdentity({ region: process.env.AWS_REGION || 'us-east-2' });
    
    // Get values from event or environment variables
    const identityPoolId = event.ResourceProperties?.IdentityPoolId || process.env.IDENTITY_POOL_ID;
    const authenticatedRoleArn = event.ResourceProperties?.Roles?.authenticated || process.env.AUTHENTICATED_ROLE_ARN;
    
    if (!identityPoolId) {
      throw new Error('IdentityPoolId is not defined in ResourceProperties or environment variables');
    }
    
    if (!authenticatedRoleArn) {
      throw new Error('authenticatedRoleArn is not defined in ResourceProperties or environment variables');
    }
    
    console.log(`Setting roles for identity pool ${identityPoolId}`);
    console.log(`Authenticated role: ${authenticatedRoleArn}`);
    
    const params = {
      IdentityPoolId: identityPoolId,
      Roles: {
        authenticated: authenticatedRoleArn
      }
    };
    
    console.log('SetIdentityPoolRoles params:', JSON.stringify(params));
    
    const result = await cognitoidentity.setIdentityPoolRoles(params).promise();
    console.log('SetIdentityPoolRoles result:', JSON.stringify(result));
    
    console.log('Successfully set identity pool roles');
    await sendResponse(event, context, 'SUCCESS', {});
  } catch (error) {
    console.error('Error setting identity pool roles:', error);
    const errorMessage = error.message || 'Unknown error';
    const errorStack = error.stack || '';
    console.error('Error stack:', errorStack);
    
    try {
      await sendResponse(event, context, 'FAILED', { 
        Error: `Error setting identity pool roles: ${errorMessage}`,
        ErrorType: error.name || 'Unknown',
        ErrorStack: errorStack
      });
    } catch (sendError) {
      console.error('Error sending failure response:', sendError);
    }
  }
};
