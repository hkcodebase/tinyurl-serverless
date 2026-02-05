1. Create DynamoDB table (to store data) and s3 bucket (for lambda code)
    ```bash
   aws cloudformation create-stack --stack-name tinyurl-dynamodb-s3 --template-body file://infra/tinyurl-dynamodb-s3.yaml --capabilities CAPABILITY_NAMED_IAM
   ```
   ```bash
   aws cloudformation describe-stacks --stack-name tinyurl-dynamodb-s3 --query Stacks[0].StackStatus
   ```
2. upload packaged lambda jar to s3 bucket (created in step 1)
    ```bash
   aws s3 cp lambda\target\tinyurl.jar s3://tinyurl-lambda-code-bucket-<REPLACE-AWS::AccountId>-us-east-1
   ```
3. Create lambda, lambda role and API Gateway
    ```bash
   aws cloudformation create-stack --stack-name tinyurl-lambda --template-body file://infra/tinyurl-lambda.yaml --capabilities CAPABILITY_NAMED_IAM
   ```
   ```bash
    aws cloudformation describe-stacks --stack-name tinyurl-lambda --query Stacks[0].StackStatus
    ```
   ### Copy apigateway url from output of this stack to REPLACE_ME in [index.js](lambda-edge/index.js) & [index.html](ui/index.html)

4. Create index.zip of index.js in lambda-edge
   ```bash
   aws s3 cp lambda-edge\index.zip s3://tinyurl-lambda-code-bucket-<REPLACE-AWS::AccountId>-us-east-1
   ```
5. Create S3 Bucket (for UI Code) and Cloudfront (CDN to serve static pages)
   ```bash
   aws cloudformation create-stack --stack-name tinyurl-ui-s3-cloudfront --template-body file://infra/tinyurl-ui-s3-cloudfront.yaml --capabilities CAPABILITY_NAMED_IAM
   ```
   ```bash
    aws cloudformation describe-stacks --stack-name tinyurl-ui-s3-cloudfront --query Stacks[0].StackStatus
    ```
6. Copy UI code to s3 bucket (created in step 5)
   ```bash
   aws s3 cp ui\  s3://tinyurl-static-code-bucket-<REPLACE-AWS::AccountId>-us-east-1 --recursive
   ```
