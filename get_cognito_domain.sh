#!/bin/bash
# This script helps retrieve the Cognito domain for an existing User Pool

if [ -z "$1" ]; then
  echo "Usage: ./get_cognito_domain.sh USER_POOL_ID"
  echo "Example: ./get_cognito_domain.sh us-east-2_xGof4XEwA"
  exit 1
fi

USER_POOL_ID=$1

# Get the user pool to check if it has a domain
echo "Checking Cognito domain for User Pool $USER_POOL_ID..."
USER_POOL_DETAILS=$(aws cognito-idp describe-user-pool --user-pool-id $USER_POOL_ID)

# First, try a more comprehensive method to find the domain
DOMAIN_NAME=$(echo "$USER_POOL_DETAILS" | grep -A 5 "Domain" | grep -o '"[^"]*"' | grep -v "Domain" | head -1 | sed 's/"//g')

if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" == "null" ]; then
  echo "No domain found using primary method. Trying alternate method..."
  
  # Try another approach with jq if available
  if command -v jq &> /dev/null; then
    DOMAIN_NAME=$(echo "$USER_POOL_DETAILS" | jq -r '.UserPool.Domain')
    if [ "$DOMAIN_NAME" == "null" ]; then
      DOMAIN_NAME=""
    fi
  fi
fi

if [ -z "$DOMAIN_NAME" ] || [ "$DOMAIN_NAME" == "null" ]; then
  echo "No domain found. This User Pool does not have a domain configured."
  echo "You will need to create one in the AWS Console or by running:"
  echo "aws cognito-idp create-user-pool-domain --domain YOUR-DOMAIN-NAME --user-pool-id $USER_POOL_ID"
else
  echo "Found domain: $DOMAIN_NAME"
  echo "Full domain URL: $DOMAIN_NAME.auth.$(aws configure get region).amazoncognito.com"
fi
