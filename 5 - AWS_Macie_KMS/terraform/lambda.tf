###############################################################################
# Lambda — Macie finding processor
###############################################################################

# Package the Lambda function source
data "archive_file" "finding_processor" {
  type        = "zip"
  source_file = "${path.module}/../lambda/finding_processor.py"
  output_path = "${path.module}/../lambda/finding_processor.zip"
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "finding_processor" {
  function_name    = "${local.name_prefix}-finding-processor"
  description      = "Processes Macie findings: quarantine PII objects, tag resources, send alerts"
  filename         = data.archive_file.finding_processor.output_path
  source_code_hash = data.archive_file.finding_processor.output_base64sha256
  handler          = "finding_processor.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_execution.arn
  memory_size      = 256
  timeout          = 60

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      SNS_TOPIC_ARN      = aws_sns_topic.macie_alerts.arn
      QUARANTINE_BUCKET  = aws_s3_bucket.quarantine.id
      SENSITIVE_BUCKET   = aws_s3_bucket.sensitive.id
      ENABLE_QUARANTINE  = tostring(var.enable_quarantine)
      SEVERITY_THRESHOLD = var.severity_threshold
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_logs,
    aws_cloudwatch_log_group.finding_processor
  ]

  tags = {
    Name = "${local.name_prefix}-finding-processor"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group — 14-day retention
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "finding_processor" {
  name              = "/aws/lambda/${local.name_prefix}-finding-processor"
  retention_in_days = 14

  tags = {
    Name = "${local.name_prefix}-finding-processor-logs"
  }
}
