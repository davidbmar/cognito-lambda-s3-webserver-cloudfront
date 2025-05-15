'use strict';

const AWS = require('aws-sdk');

module.exports.handler = async (event) => {
  const cognitoidentity = new AWS.CognitoIdentity();
  
  try {
    const identityPoolId = process.env.IDENTITY_POOL_ID;
    const authenticatedRoleArn = process.env.AUTHENTICATED_ROLE_ARN;
    
    console.log();
    
    await cognitoidentity.setIdentityPoolRoles({
      IdentityPoolId: identityPoolId,
      Roles: {
        authenticated: authenticatedRoleArn
      }
    }).promise();
    
    console.log('Successfully set identity pool roles');
    
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Identity pool roles set successfully' })
    };
  } catch (error) {
    console.error('Error setting identity pool roles:', error);
    
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  }
};
