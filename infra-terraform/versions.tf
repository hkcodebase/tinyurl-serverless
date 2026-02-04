terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  backend "s3" {
    encrypt        = true
    use_lockfile   = true # enable S3 native locking
  }

  required_version = ">= 1.2"
}
