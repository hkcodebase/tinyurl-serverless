provider "aws" {
  region = var.region
}

# Lambda@Edge must be in us-east-1. Since var.region is us-east-1, this is effectively the same,
# but keeping the alias makes the intent explicit.
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  lambda_code_bucket_name = "${var.project_name}-lambda-code-bucket-${local.account_id}-${var.region}"
  static_bucket_name      = "${var.project_name}-static-code-bucket-${local.account_id}-${var.region}"
  cloudfront_log_bucket   = "${var.project_name}-cloudfrontlog-bucket-${local.account_id}-${var.region}"

  dynamodb_table_name = "Url"

  apigw_lambda_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.tinyurl.arn}/invocations"
}

# -----------------------
# DynamoDB + Lambda code bucket
# -----------------------
resource "aws_dynamodb_table" "url" {
  name           = local.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "hash"

  attribute {
    name = "hash"
    type = "S"
  }
}

resource "aws_s3_bucket" "lambda_code" {
  bucket = local.lambda_code_bucket_name
}

resource "aws_s3_bucket_versioning" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_code" {
  bucket                  = aws_s3_bucket.lambda_code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload artifacts (Terraform-managed)
resource "aws_s3_object" "tinyurl_jar" {
  bucket = aws_s3_bucket.lambda_code.bucket
  key    = var.lambda_code_s3_key_jar
  source = var.lambda_jar_path

  etag = filemd5(var.lambda_jar_path)

  depends_on = [aws_s3_bucket_versioning.lambda_code]
}

resource "aws_s3_object" "edge_zip" {
  bucket = aws_s3_bucket.lambda_code.bucket
  key    = var.edge_code_s3_key_zip
  source = var.edge_zip_path

  etag = filemd5(var.edge_zip_path)

  depends_on = [aws_s3_bucket_versioning.lambda_code]
}

# -----------------------
# Main Lambda + IAM role/policy
# -----------------------
resource "aws_iam_role" "tinyurl_lambda_exec" {
  name = "TinyurlLambdaExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.tinyurl_lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name = "DynamoDBAccessPolicy"
  role = aws_iam_role.tinyurl_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:UpdateItem"
      ]
      Resource = "arn:aws:dynamodb:${var.region}:${local.account_id}:table/${local.dynamodb_table_name}"
    }]
  })
}

resource "aws_lambda_function" "tinyurl" {
  function_name = "TinyurlLambdaFunction"
  runtime       = "java21"
  handler       = "hk.prj.TinyurlHandler::handleRequest"
  role          = aws_iam_role.tinyurl_lambda_exec.arn

  s3_bucket        = aws_s3_bucket.lambda_code.bucket
  s3_key           = aws_s3_object.tinyurl_jar.key
  source_code_hash = filebase64sha256(var.lambda_jar_path)

  timeout     = 30
  memory_size = 512
  description = "Tinyurl Lambda function with Java21 runtime and restricted DynamoDB access"

  depends_on = [
    aws_s3_object.tinyurl_jar,
    aws_iam_role_policy.dynamodb_access,
    aws_iam_role_policy_attachment.lambda_basic
  ]
}

# -----------------------
# API Gateway REST API (/urls, /{hash})
# -----------------------
resource "aws_api_gateway_rest_api" "api" {
  name        = "UrlShortenerAPI"
  description = "API Gateway for URL Shortener"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "urls" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "urls"
}

resource "aws_api_gateway_resource" "hash" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "{hash}"
}

# POST /urls
resource "aws_api_gateway_method" "post_urls" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.urls.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "post_urls" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.urls.id
  http_method             = aws_api_gateway_method.post_urls.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.apigw_lambda_uri
}

# DELETE /urls
# resource "aws_api_gateway_method" "delete_urls" {
#   rest_api_id   = aws_api_gateway_rest_api.api.id
#   resource_id   = aws_api_gateway_resource.urls.id
#   http_method   = "DELETE"
#   authorization = "NONE"
# }
#
# resource "aws_api_gateway_integration" "delete_urls" {
#   rest_api_id             = aws_api_gateway_rest_api.api.id
#   resource_id             = aws_api_gateway_resource.urls.id
#   http_method             = aws_api_gateway_method.delete_urls.http_method
#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = local.apigw_lambda_uri
# }

# OPTIONS /urls (CORS)
resource "aws_api_gateway_method" "options_urls" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.urls.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_urls" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.urls.id
  http_method = aws_api_gateway_method.options_urls.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_urls_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.urls.id
  http_method = aws_api_gateway_method.options_urls.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_urls_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.urls.id
  http_method = aws_api_gateway_method.options_urls.http_method
  status_code = aws_api_gateway_method_response.options_urls_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization,X-Amz-Date,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,DELETE'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://links.hemantkumar.dev'"
  }
}

# GET /{hash}
resource "aws_api_gateway_method" "get_hash" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hash.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_hash" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.hash.id
  http_method             = aws_api_gateway_method.get_hash.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = local.apigw_lambda_uri
}

# OPTIONS /{hash} (CORS)
resource "aws_api_gateway_method" "options_hash" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.hash.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_hash" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hash.id
  http_method = aws_api_gateway_method.options_hash.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_hash_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hash.id
  http_method = aws_api_gateway_method.options_hash.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_hash_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.hash.id
  http_method = aws_api_gateway_method.options_hash.http_method
  status_code = aws_api_gateway_method_response.options_hash_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET,POST,DELETE'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tinyurl.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${local.account_id}:${aws_api_gateway_rest_api.api.id}/*/*"
}

# Deployment + Stage (fixed trigger expression)
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeploy = sha1(join(",", [
      aws_api_gateway_resource.urls.id,
      aws_api_gateway_resource.hash.id,

      aws_api_gateway_method.post_urls.id,
      #aws_api_gateway_method.delete_urls.id,
      aws_api_gateway_method.get_hash.id,
      aws_api_gateway_method.options_urls.id,
      aws_api_gateway_method.options_hash.id,

      aws_api_gateway_integration.post_urls.id,
      #aws_api_gateway_integration.delete_urls.id,
      aws_api_gateway_integration.get_hash.id,
      aws_api_gateway_integration.options_urls.id,
      aws_api_gateway_integration.options_hash.id,

      aws_api_gateway_method_response.options_urls_200.id,
      aws_api_gateway_method_response.options_hash_200.id,

      aws_api_gateway_integration_response.options_urls_200.id,
      aws_api_gateway_integration_response.options_hash_200.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.post_urls,
    #aws_api_gateway_integration.delete_urls,
    aws_api_gateway_integration.get_hash,
    aws_api_gateway_integration.options_urls,
    aws_api_gateway_integration.options_hash,
    aws_api_gateway_integration_response.options_urls_200,
    aws_api_gateway_integration_response.options_hash_200
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.deployment.id
  stage_name    = "prod"
}

# -----------------------
# API custom domain: api.links.hemantkumar.dev (uses existing ACM cert)
# -----------------------
resource "aws_api_gateway_domain_name" "api_custom" {
  domain_name = var.api_domain_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  regional_certificate_arn = var.acm_certificate_arn
  security_policy          = "TLS_1_2"
}

resource "aws_api_gateway_base_path_mapping" "api_custom_prod" {
  api_id      = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  domain_name = aws_api_gateway_domain_name.api_custom.domain_name
}

resource "aws_route53_record" "api_alias_a" {
  zone_id = var.route53_zone_id
  name    = var.api_domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.api_custom.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.api_custom.regional_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "api_alias_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.api_domain_name
  type    = "AAAA"

  alias {
    name                   = aws_api_gateway_domain_name.api_custom.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.api_custom.regional_zone_id
    evaluate_target_health = false
  }
}


# -----------------------
# Static UI: S3 + CloudFront + OAC + logging + Lambda@Edge
# -----------------------
resource "aws_s3_bucket" "static" {
  bucket = local.static_bucket_name
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "cf_logs" {
  bucket = local.cloudfront_log_bucket
}

resource "aws_s3_bucket_ownership_controls" "cf_logs" {
  bucket = aws_s3_bucket.cf_logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "cf_logs" {
  bucket                  = aws_s3_bucket.cf_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "edge_role" {
  provider = aws.use1
  name     = "${var.project_name}-redirect-function-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = ["lambda.amazonaws.com", "edgelambda.amazonaws.com"] }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "edge_logs" {
  provider = aws.use1
  name     = "lambda-execute"
  role     = aws_iam_role.edge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

resource "aws_lambda_function" "edge_redirect" {
  provider      = aws.use1
  function_name = "${var.project_name}-redirect-function"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.edge_role.arn

  s3_bucket        = aws_s3_bucket.lambda_code.bucket
  s3_key           = aws_s3_object.edge_zip.key
  source_code_hash = filebase64sha256(var.edge_zip_path)

  publish = true

  depends_on = [
    aws_s3_object.edge_zip,
    aws_iam_role_policy.edge_logs
  ]
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-static-oac"
  description                       = "Origin access control (OAC) for CloudFront to access the static S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  default_root_object = "index.html"
  http_version        = "http2"

  aliases = [var.ui_domain_name]

  origin {
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id                = "${var.project_name}-static-hosting"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "${var.project_name}-static-hosting"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.edge_redirect.qualified_arn
      include_body = false
    }
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/404.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/403.html"
  }

  logging_config {
    bucket          = aws_s3_bucket.cf_logs.bucket_domain_name
    prefix          = "logs/"
    include_cookies = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Route53 alias: links.hemantkumar.dev -> CloudFront
resource "aws_route53_record" "ui_alias_a" {
  zone_id = var.route53_zone_id
  name    = var.ui_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_s3_bucket_policy" "static_policy" {
  bucket = aws_s3_bucket.static.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action = "s3:GetObject"
      Resource = "arn:aws:s3:::${aws_s3_bucket.static.bucket}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.cdn.arn
        }
      }
    }]
  })

  depends_on = [aws_cloudfront_distribution.cdn]
}

resource "aws_s3_bucket_policy" "cf_logs_policy" {
  bucket = aws_s3_bucket.cf_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontToWriteLogs"
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action   = "s3:PutObject"
      Resource = "arn:aws:s3:::${aws_s3_bucket.cf_logs.bucket}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceAccount" = local.account_id
        }
        ArnLike = {
          "AWS:SourceArn" = "arn:aws:cloudfront::${local.account_id}:distribution/${aws_cloudfront_distribution.cdn.id}/*"
        }
      }
    }]
  })

  depends_on = [aws_cloudfront_distribution.cdn]
}