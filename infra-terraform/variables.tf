variable "region" {
  description = "AWS region (use us-east-1)."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for resources."
  type        = string
  default     = "tinyurl"
}

variable "lambda_zip_path" {
  description = "Local path to the built Python Lambda zip."
  type        = string
  default     = "../lambda-python/tinyurl.zip"
}

variable "edge_zip_path" {
  description = "Local path to the Lambda@Edge zip."
  type        = string
  default     = "../lambda-edge/index.zip"
}

variable "lambda_code_s3_key_zip" {
  description = "S3 key to store the Python Lambda artifact."
  type        = string
  default     = "tinyurl.zip"
}

variable "edge_code_s3_key_zip" {
  description = "S3 key to store the Lambda@Edge artifact."
  type        = string
  default     = "index.zip"
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for hemantkumar.dev (used for ACM validation + DNS records)."
  type        = string
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN in us-east-1 that covers domains"
  type        = string
}

variable "ui_domain_name" {
  description = "Custom domain name for the CloudFront UI distribution."
  type        = string
  default     = ""
}

variable "api_domain_name" {
  description = "Custom domain name for the API Gateway endpoint."
  type        = string
  default     = ""
}

variable "allowed_origin" {
  description = "Allowed CORS origin for POST /urls (e.g. https://links.example.com)"
  type        = string
}