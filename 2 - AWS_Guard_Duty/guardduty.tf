# guardduty.tf - GuardDuty Threat Detection

# ==========================================
# GUARDDUTY DETECTOR
# ==========================================
resource "aws_guardduty_detector" "main" {
  count = var.enable_guardduty ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name        = "${var.environment}-guardduty-detector"
    Environment = var.environment
    Lab         = "GuardDuty-Remediation"
  }
}

# ==========================================
# S3 BUCKET FOR FINDINGS EXPORT
# ==========================================
resource "aws_s3_bucket" "guardduty_findings" {
  count  = var.enable_guardduty ? 1 : 0
  bucket = "${var.environment}-guardduty-findings-${data.aws_caller_identity.current.account_id}"

  force_destroy = true  # Allow deletion for lab purposes

  tags = {
    Name        = "${var.environment}-guardduty-findings"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "guardduty_findings" {
  count  = var.enable_guardduty ? 1 : 0
  bucket = aws_s3_bucket.guardduty_findings[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "guardduty_findings" {
  count  = var.enable_guardduty ? 1 : 0
  bucket = aws_s3_bucket.guardduty_findings[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "guardduty_findings" {
  count  = var.enable_guardduty ? 1 : 0
  bucket = aws_s3_bucket.guardduty_findings[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==========================================
# QUARANTINE SECURITY GROUP
# ==========================================
resource "aws_security_group" "quarantine" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.environment}-${var.quarantine_sg_name}"
  description = "Quarantine security group - NO inbound/outbound traffic"
  vpc_id      = aws_vpc.main.id

  # NO ingress rules - completely isolated

  # NO egress rules - completely isolated
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["127.0.0.1/32"]  # Only localhost (effectively nothing)
    description = "Block all outbound traffic"
  }

  tags = {
    Name        = "${var.environment}-quarantine-sg"
    Environment = var.environment
    Purpose     = "Isolate compromised instances"
  }
}

# ==========================================
# DYNAMODB TABLE FOR TRACKING REMEDIATION
# ==========================================
resource "aws_dynamodb_table" "guardduty_remediation" {
  count        = var.enable_guardduty ? 1 : 0
  name         = "${var.environment}-guardduty-remediation-log"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "FindingId"
  range_key    = "Timestamp"

  attribute {
    name = "FindingId"
    type = "S"
  }

  attribute {
    name = "Timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ExpirationTime"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment}-guardduty-remediation-log"
    Environment = var.environment
  }
}