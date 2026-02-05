# URl shortener using AWS Serverless Services

this project is a URL shortening service built using **AWS Serverless Services** with Lambda code in **Java**, designed as a **learning experiment** 
and **side project** to explore cloud technologies and serverless architectures. 
This project is not intended for production use but serves as a great hands-on exercise in building scalable web applications

# App
- Infrastructure can be created using:
  - **AWS CloudFormation** (see `infra-cloudformation/`)
  - **Terraform** (see `infra-terraform/`)
- Lambda function is a maven application with [AWS Java SDK 2.x](https://github.com/aws/aws-sdk-java-v2) dependencies.
- UI is build using HTML/Javascript/CSS and Served using S3 and Cloudfront.
- Database is DynamoDB
- APIs are deployed in AWS API Gateway  

## Prerequisites (required)
- Java 21
- Apache Maven
- AWS Account
- AWS CLI Installed & Configured to use with Access Keys [Ref Article](https://medium.com/@hkcodeblogs/aws-cli-connect-to-aws-using-command-line-41925af062bd)

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


## Build artifacts (required)

From the repo root:

```bash
cd lambda && mvn clean package && cd ..
```

Ensure the Edge zip exists as well (this project expects a zip at `lambda-edge/index.zip`).
> Note: if not, you can build it manually using `cd lambda-edge && zip -r index.zip * && cd ..`
> Note: this must be updated after any change in index.js code.


# Deployment 
> Infra using CloudFormation or Terraform (any one)
 ## Using CloudFormation [here](infra-cloudformation/README.md)
 ## Using Terraform [here](infra-terraform/README.md)

