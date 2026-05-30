###############################################################################
# IAM — Lambda execution role with least-privilege permissions
###############################################################################

# ---------------------------------------------------------------------------
# Lambda execution role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_execution" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-lambda-role"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Logs policy
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.name_prefix}-lambda-logs"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-finding-processor:*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# S3 policy — sensitive, quarantine, and clean buckets
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_s3" {
  name = "${local.name_prefix}-lambda-s3"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ObjectOperations"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:CopyObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging"
        ]
        Resource = [
          "${aws_s3_bucket.sensitive.arn}/*",
          "${aws_s3_bucket.quarantine.arn}/*",
          "${aws_s3_bucket.clean.arn}/*"
        ]
      },
      {
        Sid    = "AllowS3BucketList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.sensitive.arn,
          aws_s3_bucket.quarantine.arn,
          aws_s3_bucket.clean.arn
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# SNS policy — publish finding alerts
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_sns" {
  name = "${local.name_prefix}-lambda-sns"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = [aws_sns_topic.macie_alerts.arn]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# KMS policy — decrypt and generate data keys for S3 operations
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_kms" {
  name = "${local.name_prefix}-lambda-kms"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSOperations"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.data.arn]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Macie policy — retrieve full finding details
# ---------------------------------------------------------------------------

resource "aws_iam_role_policy" "lambda_macie" {
  name = "${local.name_prefix}-lambda-macie"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowMacieGetFinding"
        Effect = "Allow"
        Action = ["macie2:GetFindings"]
        Resource = "*"
      }
    ]
  })
}
