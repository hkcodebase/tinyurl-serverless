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

variable "lambda_jar_path" {
  description = "Local path to the built Lambda jar."
  type        = string
  default     = "../lambda/target/tinyurl.jar"
}

variable "edge_zip_path" {
  description = "Local path to the Lambda@Edge zip."
  type        = string
  default     = "../lambda-edge/index.zip"
}

variable "lambda_code_s3_key_jar" {
  description = "S3 key to store the Java Lambda artifact."
  type        = string
  default     = "tinyurl.jar"
}

variable "edge_code_s3_key_zip" {
  description = "S3 key to store the Lambda@Edge artifact."
  type        = string
  default     = "index.zip"
}