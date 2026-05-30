###############################################################################
# Project 5: AWS Macie + KMS - Sensitive Data Discovery & Encryption
#
# This project implements:
# - AWS Macie for automated PII/sensitive data discovery in S3
# - KMS Customer Managed Key (CMK) shared across all S3 buckets
# - Scheduled (weekly) Macie classification jobs — not continuous monitoring
# - EventBridge + Lambda for automated finding processing and quarantine
# - SNS alerting for HIGH/CRITICAL severity findings
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
      Project     = "Macie-KMS-Security"
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
}
