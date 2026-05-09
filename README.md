# TinyURL — Serverless URL Shortener on AWS

A URL shortening service built entirely on **AWS serverless services**. Started as a learning experiment, it has grown to include two Lambda implementations (Java and Python), two infrastructure-as-code options (Terraform and CloudFormation), a static UI served via CloudFront, and a full CI/CD pipeline via GitHub Actions.

## Architecture

```
Browser / Client
      │
      ▼
CloudFront  ──────────────────────────────────────────────►  S3 (static UI)
(links.hemantkumar.dev)
      │ viewer-request
      ▼
Lambda@Edge (Node.js)
      │ hash pattern match
      ▼
API Gateway (api.links.hemantkumar.dev)
      │
      ├── POST /urls      ──► Lambda (Python 3.12)  ──► DynamoDB (write)
      └── GET  /{hash}    ──► Lambda (Python 3.12)  ──► DynamoDB (read)
                                                              │
                                                              ▼
                                                     302 redirect to original URL
```

## Repository Structure

```
.
├── lambda/                        # Java 21 Lambda (original implementation)
│   └── src/main/java/hk/prj/
│       ├── TinyurlHandler.java
│       ├── DynamoDBService.java
│       └── DependencyFactory.java
├── lambda-python/                 # Python 3.12 Lambda (current implementation)
│   ├── handler.py                 # Entry point — routes by HTTP method
│   ├── dynamodb_service.py        # DynamoDB read/write + SHA-256 hashing
│   ├── requirements-dev.txt       # Test dependencies (pytest, moto)
│   ├── pytest.ini
│   ├── test/                      # Sample API Gateway events for manual testing
│   │   ├── create_url.json
│   │   └── redirect_url.json
│   └── tests/
│       ├── unit/                  # Isolated tests with mocked DynamoDB
│       │   ├── test_handler.py
│       │   └── test_dynamodb_service.py
│       └── integration/           # Full POST→GET flow via moto
│           └── test_integration.py
├── lambda-edge/                   # Node.js 18 Lambda@Edge for CloudFront routing
│   └── index.js
├── ui/                            # Static HTML/CSS/JS frontend
│   └── index.html
├── infra-terraform/               # Terraform (recommended)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── versions.tf
│   └── README.md
├── infra-cloudformation/          # CloudFormation (alternative)
│   ├── tinyurl-dynamodb-s3.yaml
│   ├── tinyurl-lambda.yaml
│   ├── tinyurl-ui-s3-cloudfront.yaml
│   └── README.md
└── .github/workflows/
    └── deploy-lambda.yml          # CI/CD: auto-deploy on merge to main
```

## Tech Stack

| Layer | Technology |
|---|---|
| Lambda | Python 3.12 (boto3, hashlib) |
| Database | AWS DynamoDB |
| API | AWS API Gateway (REST, regional) |
| CDN / UI hosting | AWS CloudFront + S3 |
| Edge routing | Lambda@Edge (Node.js 18) |
| Infrastructure | Terraform >= 1.2 / AWS CloudFormation |
| CI/CD | GitHub Actions |

---

## Prerequisites

- AWS account with credentials configured (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` or an AWS profile)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) installed and configured
- [Terraform >= 1.2](https://developer.hashicorp.com/terraform/install) (if using Terraform)
- Python 3.12+ (for local development and testing)

---

## Lambda — Python (Current)

### Build artifact

`boto3` is pre-installed in the Lambda Python 3.12 runtime, so the deployment package only contains the two source files:

```bash
cd lambda-python
zip tinyurl.zip handler.py dynamodb_service.py
```

### Run tests locally

```bash
cd lambda-python

# Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate        # Mac/Linux
.venv\Scripts\activate           # Windows

# Install test dependencies
pip install -r requirements-dev.txt

# Run all tests
pytest

# Unit tests only
pytest tests/unit/

# Integration tests only (full POST→GET flow via moto — no AWS needed)
pytest tests/integration/

# With coverage report
pytest --cov=. --cov-report=term-missing
```

Tests use [moto](https://github.com/getmoto/moto) to intercept all boto3 calls — no AWS credentials or network access required.

### Invoke manually (without AWS)

```bash
cd lambda-python
python - <<'EOF'
import json, handler
event = json.load(open("test/create_url.json"))
print(json.dumps(handler.lambda_handler(event, None), indent=2))
EOF
```

> This will attempt a real DynamoDB call. For local invocation against real AWS, ensure credentials are configured.

---

## Lambda — Java (Original)

The original Java 21 implementation is kept in `lambda/` for reference.

### Build artifact

```bash
cd lambda && mvn clean package && cd ..
```

Produces `lambda/target/tinyurl.jar`.

---

## Lambda@Edge

Routes incoming CloudFront requests: hashes matching `^/[a-f0-9]+$` are forwarded to the API Gateway; all other requests are passed through to the S3 origin.

```bash
# Build the zip (required before first deploy or after editing index.js)
cd lambda-edge && zip index.zip index.js && cd ..
```

After deploying infrastructure, update `REPLACE_ME` in `lambda-edge/index.js` with the API Gateway URL from Terraform output or CloudFormation output, then redeploy.

---

## Deployment

### Option 1 — Terraform (recommended)

#### First-time setup

```bash
cd infra-terraform

terraform init \
  -backend-config="bucket=<YOUR_TF_STATE_BUCKET>" \
  -backend-config="key=tinyurl/terraform.tfstate" \
  -backend-config="region=us-east-1"
```

#### Deploy

```bash
terraform apply \
  -var="route53_zone_id=<ZONE_ID>" \
  -var="acm_certificate_arn=<CERT_ARN>" \
  -var="ui_domain_name=links.example.com" \
  -var="api_domain_name=api.links.example.com"
```

Or create a `terraform.tfvars` file:

```hcl
route53_zone_id      = "ZXXXXXXXXXXXXX"
acm_certificate_arn  = "arn:aws:acm:us-east-1:123456789:certificate/..."
ui_domain_name       = "links.example.com"
api_domain_name      = "api.links.example.com"
```

```bash
terraform apply -var-file=terraform.tfvars
```

Terraform will:
1. Create DynamoDB table, S3 buckets, IAM roles
2. Upload `tinyurl.zip` and `index.zip` to S3
3. Create the Python Lambda, API Gateway, CloudFront distribution, and Lambda@Edge
4. Create Route53 DNS records (if domain variables are set)

#### Key variables

| Variable | Default | Description |
|---|---|---|
| `region` | `us-east-1` | AWS region |
| `project_name` | `tinyurl` | Resource name prefix |
| `lambda_zip_path` | `../lambda-python/tinyurl.zip` | Path to built Python zip |
| `edge_zip_path` | `../lambda-edge/index.zip` | Path to Lambda@Edge zip |
| `route53_zone_id` | *(required for DNS)* | Route53 hosted zone ID |
| `acm_certificate_arn` | *(required for custom domains)* | ACM cert ARN (must be in us-east-1) |
| `ui_domain_name` | `""` | Custom domain for CloudFront |
| `api_domain_name` | `""` | Custom domain for API Gateway |

#### Outputs

```bash
terraform output
```

Key outputs: `api_gateway_base_url`, `cloudfront_domain_name`, `lambda_code_bucket_name`.

#### Destroy

```bash
terraform destroy
```

---

### Option 2 — CloudFormation

See [infra-cloudformation/README.md](infra-cloudformation/README.md) for full step-by-step instructions.

Summary:

```bash
# 1. Create DynamoDB table + S3 bucket for Lambda code
aws cloudformation create-stack \
  --stack-name tinyurl-dynamodb-s3 \
  --template-body file://infra-cloudformation/tinyurl-dynamodb-s3.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 2. Package and upload Lambda zip
cd lambda-python && zip tinyurl.zip handler.py dynamodb_service.py && cd ..
aws s3 cp lambda-python/tinyurl.zip s3://tinyurl-lambda-code-bucket-<ACCOUNT_ID>-us-east-1/

# 3. Deploy Lambda + API Gateway
aws cloudformation create-stack \
  --stack-name tinyurl-lambda \
  --template-body file://infra-cloudformation/tinyurl-lambda.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 4. Package and upload Lambda@Edge zip
cd lambda-edge && zip index.zip index.js && cd ..
aws s3 cp lambda-edge/index.zip s3://tinyurl-lambda-code-bucket-<ACCOUNT_ID>-us-east-1/

# 5. Deploy CloudFront + S3 static UI
aws cloudformation create-stack \
  --stack-name tinyurl-ui-s3-cloudfront \
  --template-body file://infra-cloudformation/tinyurl-ui-s3-cloudfront.yaml \
  --capabilities CAPABILITY_NAMED_IAM

# 6. Upload UI files
aws s3 cp ui/ s3://tinyurl-static-code-bucket-<ACCOUNT_ID>-us-east-1/ --recursive
```

After step 3, copy the API Gateway URL from the stack outputs and replace `REPLACE_ME` in `lambda-edge/index.js`, then re-zip and re-upload before step 4.

---

## CI/CD — GitHub Actions

The workflow at [.github/workflows/deploy-lambda.yml](.github/workflows/deploy-lambda.yml) triggers automatically on every push to `main` when any of these files change:

- `lambda-python/handler.py`
- `lambda-python/dynamodb_service.py`
- `infra-terraform/main.tf`
- `infra-terraform/variables.tf`

**Pipeline steps:**
1. Checkout code
2. Configure AWS credentials
3. Package `tinyurl.zip` from `handler.py` + `dynamodb_service.py`
4. `terraform init` (S3 backend)
5. `terraform plan`
6. `terraform apply`
7. Print the live API Gateway URL

### Required GitHub secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role to assume via OIDC (e.g. `arn:aws:iam::123456789:role/github-deploy`) |
| `TF_BACKEND_BUCKET` | S3 bucket for Terraform remote state |
| `TF_BACKEND_KEY` | State file key (e.g. `tinyurl/terraform.tfstate`) |
| `TF_VAR_route53_zone_id` | Route53 hosted zone ID |
| `TF_VAR_acm_certificate_arn` | ACM certificate ARN |
| `TF_VAR_allowed_origin` | CORS allowed origin (e.g. `https://links.example.com`) |
| `TF_VAR_ui_domain_name` | UI domain (e.g. `links.example.com`) |
| `TF_VAR_api_domain_name` | API domain (e.g. `api.links.example.com`) |

> `UI_BUCKET_NAME` should be set as a **variable** (not secret) under Settings → Variables → Actions.

### One-time AWS OIDC setup

No long-lived access keys are stored in GitHub. Instead, GitHub requests a short-lived OIDC token and exchanges it for temporary AWS credentials by assuming an IAM role. This requires a one-time setup in AWS:

**1. Create the OIDC identity provider**
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**2. Create the IAM role with a trust policy scoped to this repository**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<GITHUB_ORG>/<REPO_NAME>:ref:refs/heads/main"
      }
    }
  }]
}
```

**3. Attach the required permissions to the role**

The role needs: `lambda:*`, `dynamodb:*`, `s3:*`, `apigateway:*`, `cloudfront:*`, `iam:*`, `route53:*`, `acm:Describe*`.

The IAM user needs permissions for: `lambda:*`, `dynamodb:*`, `s3:*`, `apigateway:*`, `cloudfront:*`, `iam:*`, `cloudformation:*`, `route53:*`.

---

## API Reference

Base URL: `https://api.links.hemantkumar.dev` (or your API Gateway URL)

### POST /urls — Shorten a URL

**Request body** (plain text): the full URL to shorten

```bash
curl -X POST https://<api-url>/prod/urls \
  -d "https://example.com/some/very/long/path"
```

**Response 200**
```json
{ "tinyurl": "a379a6f6" }
```

**Response 400** — missing or invalid URL
```json
{ "error": "Invalid URL: ..." }
```

---

### GET /{hash} — Redirect to original URL

```bash
curl -L https://<api-url>/prod/a379a6f6
```

**Response 302** — `Location` header set to the original URL

**Response 302** (unknown hash) — redirected to `404.html`

---

## DynamoDB Schema

Table name: `Url`

| Attribute | Type | Description |
|---|---|---|
| `hash` | String (PK) | First 8 chars of SHA-256 of the original URL |
| `redirect_url` | String | The original long URL |

---

## Notes

- **Hash collisions**: SHA-256 truncated to 8 hex chars gives ~4 billion unique values. Collision probability is low for typical usage but not zero. If the same URL is shortened twice, the same hash is returned (idempotent).
- **Lambda@Edge region**: must be deployed to `us-east-1` regardless of the main stack region — this is an AWS requirement for CloudFront associations.
- **ACM certificates** for CloudFront must also be in `us-east-1`.
- **Custom domains** are optional. If `ui_domain_name` and `api_domain_name` variables are left empty, the CloudFront and API Gateway default URLs are used instead.
