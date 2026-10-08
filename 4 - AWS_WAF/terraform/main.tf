###############################################################################
# Project 4: AWS WAF v2 - Web Application Firewall
#
# This project implements:
# - AWS WAFv2 WebACL with managed rule groups (SQLi, XSS, Known Bad Inputs)
# - API Gateway HTTP API as the protected endpoint (cost-effective ALB alternative)
# - Lambda function as the backend web application
# - Rate limiting and custom IP blocking rules
# - CloudWatch Logs for WAF logging (no Kinesis Firehose overhead)
###############################################################################

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "WAF-Web-Application-Firewall"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  lambda_zip  = "${path.module}/../app/app_handler.zip"
}
