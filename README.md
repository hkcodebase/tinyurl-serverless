# TinyURL

TinyURL is a URL shortening service built using **AWS Serverless Services** with Lambda code in **Java**, designed as a **learning experiment** 
and **side project** to explore cloud technologies and serverless architectures. 
This project is not intended for production use but serves as a great hands-on exercise in building scalable web applications

# App
- Infrastructure is created using AWS Cloudformation
- Lambda function is a maven application with [AWS Java SDK 2.x](https://github.com/aws/aws-sdk-java-v2) dependencies.
- UI is build using HTML/Javascript/CSS and Served using S3 and Cloudfront.
- Database is DynamoDB
- APIs are deployed in AWS API Gateway  

## Prerequisites
- Java 21
- Apache Maven
- AWS Account 
- AWS CLI Installed & Configured to use with Access Keys [Ref Article](https://medium.com/@hkcodeblogs/aws-cli-connect-to-aws-using-command-line-41925af062bd)

## Building the lambda jar

```bash
cd lambda && mvn clean package && cd ..
```

# Create Infra 

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




## Development

App generated using maven from below command -
```maven
mvn archetype:generate ^
   -DarchetypeGroupId=software.amazon.awssdk ^
   -DarchetypeArtifactId=archetype-app-quickstart ^
   -DarchetypeVersion=2.22.0
```

Below is the structure of the generated Lambda project.

```
├── src
│   ├── main
│   │   ├── java
│   │   │   └── package
│   │   │       ├── DynamoDBService.java
│   │   │       ├── DependencyFactory.java
│   │   │       └── TinyurlHandler.java
│   │   └── resources
│   │       └── simplelogger.properties
```

- `DynamoDBService.java`: Interacts with DynamoDB
- `DependencyFactory.java`: creates the SDK client
- `TinyurlHandler.java`: you can invoke the api calls using the SDK client here.
