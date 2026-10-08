###############################################################################
# Lambda Function — Inspector Finding Processor
###############################################################################

# Create deployment package from source
data "archive_file" "finding_processor" {
  type        = "zip"
  source_file = "${path.module}/../lambda/finding_processor.py"
  output_path = "${path.module}/../lambda/finding_processor.zip"
}

# Lambda Function
resource "aws_lambda_function" "finding_processor" {
  filename         = data.archive_file.finding_processor.output_path
  function_name    = "${local.name_prefix}-finding-processor"
  role             = aws_iam_role.lambda_finding_processor.arn
  handler          = "finding_processor.lambda_handler"
  source_code_hash = data.archive_file.finding_processor.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      SNS_TOPIC_ARN      = aws_sns_topic.inspector_alerts.arn
      SEVERITY_THRESHOLD = var.severity_threshold
      TAG_INSTANCES      = tostring(var.tag_instances)
    }
  }

  tags = {
    Name = "${local.name_prefix}-finding-processor"
  }
}

# CloudWatch Log Group for Lambda — 14-day retention
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.finding_processor.function_name}"
  retention_in_days = 14

  tags = {
    Name = "${local.name_prefix}-lambda-logs"
  }
}
