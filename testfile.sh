#!/bin/bash

# Load environment variables
source .env

# Check that variables are loaded
echo "Bucket name: $S3_BUCKET_NAME"

# User ID (replace with actual user sub)
USER_ID="110bc530-4091-7070-b239-5517fb40f966"

# Create test file
echo "Hello from S3! This is a test file for download." > test-download.txt

# Upload with proper bucket name
echo "Uploading to: s3://${S3_BUCKET_NAME}/users/${USER_ID}/test-download.txt"
aws s3 cp test-download.txt s3://${S3_BUCKET_NAME}/users/${USER_ID}/test-download.txt

# List files to verify
echo "Files in user directory:"
aws s3 ls s3://${S3_BUCKET_NAME}/users/${USER_ID}/
