# Infrastructure using Terraform

This folder provisions infrastructure on AWS using **Terraform**.

## What it creates (high level)

- DynamoDB table for URL mappings
- S3 bucket for Lambda artifacts (uploads the Java Lambda JAR + Lambda@Edge ZIP)
- Java Lambda function + IAM role/policies
- API Gateway (REST) wired to the Java Lambda
- S3 bucket for static UI + CloudFront distribution (with Origin Access Control)
- CloudFront logging bucket/policy
- Lambda@Edge function (viewer-request) used by CloudFront
- (Optional) 
  - Route53 records + custom domains (UI + API) when variables are provided
  - comment code in main.tf if you don't want to use custom domains

## Prerequisites

- Terraform `>= 1.2`
- AWS account and credentials configured (for example via `AWS_ACCESS_KEY_ID` / `AWS_SECRET_KEY`, or an AWS profile)
- Java + Maven (to build the Lambda JAR locally) 

> Note: Lambda@Edge and ACM certs for CloudFront must be in **us-east-1**.


## Initialize + deploy

From the repo root:

```bash
cd infra-terraform && terraform init  
terraform apply
```

Terraform will:
- create the infra
- upload the JAR/ZIP to the managed S3 bucket
- wire everything together

## Configuration

### Variables

Common variables you may need to set:

- `region` (default: `us-east-1`)
- `project_name` (default: `tinyurl`)
- `route53_zone_id` *(required if creating DNS records)*
- `acm_certificate_arn` *(required if using custom domains / TLS)*
- `ui_domain_name` *(optional custom UI domain, e.g. `links.example.com`)*
- `api_domain_name` *(optional custom API domain, e.g. `links-api.example.com`)*

You can set them via:

```bash 
terraform apply
    -var="route53_zone_id=<ROUTE53_ZONE_ID>"
    -var="acm_certificate_arn=<ACM_CERT_ARN>"
    -var="ui_domain_name=<UI_DOMAIN>"
    -var="api_domain_name=<API_DOMAIN>"
```

Or put them in a `terraform.tfvars` file. and run using command
```bash 
terraform apply -var-file terraform.tfvars`.
```
## Outputs

After apply, use below command to get the outputs mentioned in [outputs.tf](outputs.tf):

```bash
 terraform output
```

Key outputs include:
- API Gateway base URL
- CloudFront domain name
- Bucket names (static + artifacts)
- ARNs/IDs for the created resources

## Destroy

```bash 
terraform destroy
```

## Notes / gotchas

- If you enable custom domains, make sure:
    - the ACM cert covers the domain names
    - the cert is in **us-east-1**
    - the Route53 zone ID matches your domain
- If you change API Gateway resources/methods, Terraform may redeploy the API via deployment triggers.