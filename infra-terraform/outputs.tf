output "account_id" {
  description = "AWS Account ID used for naming/ARNs."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "AWS region where the stack is deployed."
  value       = var.region
}

output "dynamodb_table_name" {
  description = "DynamoDB table name."
  value       = aws_dynamodb_table.url.name
}

output "lambda_code_bucket_name" {
  description = "S3 bucket name storing Lambda artifacts (jar/zip)."
  value       = aws_s3_bucket.lambda_code.bucket
}

output "uploaded_lambda_zip_key" {
  description = "S3 key for the uploaded Python Lambda zip."
  value       = aws_s3_object.tinyurl_zip.key
}

output "uploaded_edge_zip_key" {
  description = "S3 key for the uploaded Lambda@Edge zip."
  value       = aws_s3_object.edge_zip.key
}

output "tinyurl_lambda_arn" {
  description = "ARN of the Tinyurl Python Lambda function."
  value       = aws_lambda_function.tinyurl.arn
}

output "api_gateway_rest_api_id" {
  description = "API Gateway REST API id."
  value       = aws_api_gateway_rest_api.api.id
}

output "api_gateway_stage_name" {
  description = "API Gateway stage name."
  value       = aws_api_gateway_stage.prod.stage_name
}

output "api_gateway_base_url" {
  description = "Base URL for the API Gateway stage."
  value       = "https://${aws_api_gateway_rest_api.api.id}.execute-api.${var.region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/"
}

output "static_bucket_name" {
  description = "S3 bucket used for UI static content."
  value       = aws_s3_bucket.static.bucket
}

output "cloudfront_log_bucket_name" {
  description = "S3 bucket used for CloudFront logs."
  value       = aws_s3_bucket.cf_logs.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution id."
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.cdn.arn
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (use as the CDN URL)."
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "edge_redirect_function_arn" {
  description = "Lambda@Edge function ARN (unqualified)."
  value       = aws_lambda_function.edge_redirect.arn
}

output "edge_redirect_function_qualified_arn" {
  description = "Lambda@Edge function qualified ARN (includes published version) used by CloudFront association."
  value       = aws_lambda_function.edge_redirect.qualified_arn
}