###############################################################################
# S3 Buckets — all private, KMS-encrypted with the shared CMK
###############################################################################

# ---------------------------------------------------------------------------
# Sensitive Data Bucket — stores PII/sensitive files to be scanned by Macie
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "sensitive" {
  bucket = "${local.name_prefix}-sensitive-data-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-sensitive-data"
    Purpose = "Sensitive data for Macie scanning"
  }
}

resource "aws_s3_bucket_versioning" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "sensitive" {
  bucket                  = aws_s3_bucket.sensitive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy: allow Macie to read objects for classification
resource "aws_s3_bucket_policy" "sensitive" {
  bucket = aws_s3_bucket.sensitive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMacieClassification"
        Effect = "Allow"
        Principal = {
          Service = "macie.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensitive.arn,
          "${aws_s3_bucket.sensitive.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Quarantine Bucket — objects with HIGH/CRITICAL PII findings are moved here
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "quarantine" {
  bucket = "${local.name_prefix}-quarantine-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-quarantine"
    Purpose = "Quarantine for objects with Macie PII findings"
  }
}

resource "aws_s3_bucket_versioning" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket                  = aws_s3_bucket.quarantine.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: move quarantined objects to Glacier after 90 days, expire after 365
resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "quarantine-retention"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# ---------------------------------------------------------------------------
# Clean Data Bucket — verified clean data after Macie scan
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "clean" {
  bucket = "${local.name_prefix}-clean-data-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-clean-data"
    Purpose = "Verified clean data storage"
  }
}

resource "aws_s3_bucket_versioning" "clean" {
  bucket = aws_s3_bucket.clean.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "clean" {
  bucket = aws_s3_bucket.clean.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "clean" {
  bucket                  = aws_s3_bucket.clean.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Macie Findings Export Bucket — separate bucket for Macie finding exports
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "macie_findings" {
  bucket = "${local.name_prefix}-macie-findings-${random_id.suffix.hex}"

  tags = {
    Name    = "${local.name_prefix}-macie-findings"
    Purpose = "Macie findings export destination"
  }
}

resource "aws_s3_bucket_versioning" "macie_findings" {
  bucket = aws_s3_bucket.macie_findings.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "macie_findings" {
  bucket = aws_s3_bucket.macie_findings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "macie_findings" {
  bucket                  = aws_s3_bucket.macie_findings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# Sample data uploads — only to sensitive bucket (< 1 MB to stay in free tier)
# ---------------------------------------------------------------------------

resource "aws_s3_object" "pii_sample_csv" {
  bucket = aws_s3_bucket.sensitive.id
  key    = "sample-data/pii_sample.csv"
  source = "${path.module}/../sample-data/pii_sample.csv"
  etag   = filemd5("${path.module}/../sample-data/pii_sample.csv")

  tags = {
    DataClassification = "Sensitive"
    UploadedFor        = "MacieTesting"
  }
}

resource "aws_s3_object" "pii_sample_json" {
  bucket = aws_s3_bucket.sensitive.id
  key    = "sample-data/pii_sample.json"
  source = "${path.module}/../sample-data/pii_sample.json"
  etag   = filemd5("${path.module}/../sample-data/pii_sample.json")

  tags = {
    DataClassification = "Sensitive"
    UploadedFor        = "MacieTesting"
  }
}

resource "aws_s3_object" "clean_data_csv" {
  bucket = aws_s3_bucket.sensitive.id
  key    = "sample-data/clean_data.csv"
  source = "${path.module}/../sample-data/clean_data.csv"
  etag   = filemd5("${path.module}/../sample-data/clean_data.csv")

  tags = {
    DataClassification = "Public"
    UploadedFor        = "MacieTesting"
  }
}
