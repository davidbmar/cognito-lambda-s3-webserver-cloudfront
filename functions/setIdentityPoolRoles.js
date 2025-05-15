'use strict';

const AWS = require('aws-sdk');
const https = require('https');
const url = require('url');

// Send response to CloudFormation
function sendResponse(event, context, responseStatus, responseData) {
  const responseBody = JSON.stringify({
    Status: responseStatus,
    Reason: `See the details in CloudWatch Log Stream: ${context.logStreamName}`,
    PhysicalResourceId: context.logStreamName,
    StackId: event.StackId,
    RequestId: event.RequestId,
    LogicalResourceId: event.LogicalResourceId,
    Data: responseData
  });

  console.log('Response body:', responseBody);

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
}

module.exports.handler = async (event, context) => {
  console.log('REQUEST RECEIVED:', JSON.stringify(event));
  
  // For Delete operations, just succeed
  if (event.RequestType === 'Delete') {
    await sendResponse(event, context, 'SUCCESS', {});
    return;
  }
  
  try {
    const cognitoidentity = new AWS.CognitoIdentity();
    
    // Either get the values from the event or from environment variables
    const identityPoolId = event.ResourceProperties?.IdentityPoolId || process.env.IDENTITY_POOL_ID;
    const authenticatedRoleArn = event.ResourceProperties?.Roles?.authenticated || process.env.AUTHENTICATED_ROLE_ARN;
    
    console.log(`Setting roles for identity pool ${identityPoolId}`);
    console.log(`Authenticated role: ${authenticatedRoleArn}`);
    
    await cognitoidentity.setIdentityPoolRoles({
      IdentityPoolId: identityPoolId,
      Roles: {
        authenticated: authenticatedRoleArn
      }
    }).promise();
    
    console.log('Successfully set identity pool roles');
    await sendResponse(event, context, 'SUCCESS', {});
  } catch (error) {
    console.error('Error setting identity pool roles:', error);
    await sendResponse(event, context, 'FAILED', { Error: error.message });
  }
};
