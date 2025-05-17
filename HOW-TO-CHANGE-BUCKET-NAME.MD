# Modifying the S3 bucket name in serverless.yml

1. Open the `serverless.yml` file in your project.

2. Look for the `custom` section, which should look similar to this:
   ```yaml
   custom:
     s3Bucket: ${self:service}-dbm-website-${sls:stage}-${aws:accountId}
   ```

3. You have several options to change the bucket name:

   a) Change the whole pattern:
   ```yaml
   custom:
     s3Bucket: my-new-website-bucket-${sls:stage}-${aws:accountId}
   ```

   b) Just change the service name at the top of the file:
   ```yaml
   service: my-new-service-name
   ```
   This will automatically update the bucket name if you're using ${self:service} in the s3Bucket pattern.

   c) For a completely fixed name (not recommended):
   ```yaml
   custom:
     s3Bucket: my-unique-fixed-bucket-name
   ```

4. Save the file, and then run your deployment script:
   ```bash
   ./deploy.sh
   ```

IMPORTANT NOTES:

- The bucket name must be globally unique across all AWS accounts
- Use dynamic parts like ${sls:stage} and ${aws:accountId} to help ensure uniqueness
- S3 bucket names have specific rules:
  - Must be between 3 and 63 characters
  - Can only contain lowercase letters, numbers, periods, and hyphens
  - Must begin and end with a letter or number
  - Cannot be formatted as an IP address

- If you get an error about the bucket already existing, choose a different name pattern

This change only needs to be done once before your first deployment. The deploy.sh script will use whatever bucket name is defined in serverless.yml.
