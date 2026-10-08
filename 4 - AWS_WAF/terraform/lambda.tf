###############################################################################
# Lambda Function — Protected Web Application Backend
###############################################################################

# Create deployment package from app/app_handler.py
data "archive_file" "app_handler" {
  type        = "zip"
  source_file = "${path.module}/../app/app_handler.py"
  output_path = "${path.module}/../app/app_handler.zip"
}

# Lambda Function
resource "aws_lambda_function" "app_handler" {
  filename         = data.archive_file.app_handler.output_path
  function_name    = "${local.name_prefix}-app-handler"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "app_handler.lambda_handler"
  source_code_hash = data.archive_file.app_handler.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ENVIRONMENT = var.environment
      PROJECT     = var.project_name
    }
  }

  tags = {
    Name = "${local.name_prefix}-app-handler"
  }
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.app_handler.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name_prefix}-lambda-logs"
  }
}
