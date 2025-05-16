#!/bin/bash

aws logs delete-log-group --log-group-name "/aws/lambda/cloudfront-cognito-app-dev-setIdentityPoolRoles"


sleep 10

serverless remove


