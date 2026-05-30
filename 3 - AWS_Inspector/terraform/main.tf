###############################################################################
# Project 3: AWS Inspector v2 - Vulnerability Scanning & Finding Processor
#
# This project builds upon the portfolio infrastructure to implement:
# - AWS Inspector v2 for EC2 vulnerability scanning
# - Automated finding processing using Lambda
# - Real-time alerting via SNS
# - EventBridge rules for event-driven security responses
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
      Project     = "Inspector-Vulnerability-Scanning"
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
  name_prefix  = "${var.project_name}-${var.environment}"
  lambda_zip   = "${path.module}/../lambda/finding_processor.zip"
}
