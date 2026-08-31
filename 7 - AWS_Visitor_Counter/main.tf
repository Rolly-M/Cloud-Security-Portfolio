terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  tags = { Project = var.project_name }
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────
resource "aws_dynamodb_table" "visits" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # TTL lets unique-visitor tokens expire automatically after 24 h
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = local.tags
}

# ── IAM: shared assume-role policy ───────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── IAM: Visitor Counter ──────────────────────────────────────────────────────
resource "aws_iam_role" "visitor_counter" {
  name               = "${var.project_name}-visitor-counter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "visitor_counter" {
  statement {
    sid     = "DynamoDB"
    actions = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.visits.arn]
  }
  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-visitor-counter:*"
    ]
  }
}

resource "aws_iam_role_policy" "visitor_counter" {
  name   = "visitor-counter-policy"
  role   = aws_iam_role.visitor_counter.id
  policy = data.aws_iam_policy_document.visitor_counter.json
}

# ── IAM: Metrics Reader ───────────────────────────────────────────────────────
resource "aws_iam_role" "metrics_reader" {
  name               = "${var.project_name}-metrics-reader"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "metrics_reader" {
  statement {
    sid     = "DynamoDB"
    actions = ["dynamodb:GetItem"]
    resources = [aws_dynamodb_table.visits.arn]
  }
  statement {
    sid     = "CloudWatch"
    actions = ["cloudwatch:GetMetricStatistics"]
    resources = ["*"]
  }
  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-metrics-reader:*"
    ]
  }
}

resource "aws_iam_role_policy" "metrics_reader" {
  name   = "metrics-reader-policy"
  role   = aws_iam_role.metrics_reader.id
  policy = data.aws_iam_policy_document.metrics_reader.json
}

# ── Lambda: Visitor Counter ───────────────────────────────────────────────────
data "archive_file" "visitor_counter" {
  type        = "zip"
  source_file = "${path.module}/lambda/visitor_counter/handler.py"
  output_path = "${path.module}/.build/visitor_counter.zip"
}

resource "aws_lambda_function" "visitor_counter" {
  function_name    = "${var.project_name}-visitor-counter"
  role             = aws_iam_role.visitor_counter.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.visitor_counter.output_path
  source_code_hash = data.archive_file.visitor_counter.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME          = aws_dynamodb_table.visits.name
      VISITOR_TTL_SECONDS = tostring(var.visitor_ttl_seconds)
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "visitor_counter" {
  name              = "/aws/lambda/${aws_lambda_function.visitor_counter.function_name}"
  retention_in_days = 14
  tags              = local.tags
}

# ── Lambda: Metrics Reader ────────────────────────────────────────────────────
data "archive_file" "metrics_reader" {
  type        = "zip"
  source_file = "${path.module}/lambda/metrics_reader/handler.py"
  output_path = "${path.module}/.build/metrics_reader.zip"
}

resource "aws_lambda_function" "metrics_reader" {
  function_name    = "${var.project_name}-metrics-reader"
  role             = aws_iam_role.metrics_reader.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.metrics_reader.output_path
  source_code_hash = data.archive_file.metrics_reader.output_base64sha256
  timeout          = 15
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME            = aws_dynamodb_table.visits.name
      COUNTER_FUNCTION_NAME = aws_lambda_function.visitor_counter.function_name
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "metrics_reader" {
  name              = "/aws/lambda/${aws_lambda_function.metrics_reader.function_name}"
  retention_in_days = 14
  tags              = local.tags
}

# ── IAM: Activity Tracker ────────────────────────────────────────────────────
resource "aws_iam_role" "activity_tracker" {
  name               = "${var.project_name}-activity-tracker"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "activity_tracker" {
  statement {
    sid     = "DynamoDB"
    actions = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.visits.arn]
  }
  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${var.project_name}-activity-tracker:*"
    ]
  }
}

resource "aws_iam_role_policy" "activity_tracker" {
  name   = "activity-tracker-policy"
  role   = aws_iam_role.activity_tracker.id
  policy = data.aws_iam_policy_document.activity_tracker.json
}

# ── Lambda: Activity Tracker ──────────────────────────────────────────────────
data "archive_file" "activity_tracker" {
  type        = "zip"
  source_file = "${path.module}/lambda/activity_tracker/handler.py"
  output_path = "${path.module}/.build/activity_tracker.zip"
}

resource "aws_lambda_function" "activity_tracker" {
  function_name    = "${var.project_name}-activity-tracker"
  role             = aws_iam_role.activity_tracker.arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.activity_tracker.output_path
  source_code_hash = data.archive_file.activity_tracker.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.visits.name
      ACTIVITY_TTL_SECONDS = "2592000"
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "activity_tracker" {
  name              = "/aws/lambda/${aws_lambda_function.activity_tracker.function_name}"
  retention_in_days = 14
  tags              = local.tags
}

# ── API Gateway HTTP API ──────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "portfolio" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.portfolio_origin]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.portfolio.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
  }

  tags = local.tags
}

# ── Route: POST /visit → visitor_counter ─────────────────────────────────────
resource "aws_apigatewayv2_integration" "visitor_counter" {
  api_id                 = aws_apigatewayv2_api.portfolio.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visitor_counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_visit" {
  api_id    = aws_apigatewayv2_api.portfolio.id
  route_key = "POST /visit"
  target    = "integrations/${aws_apigatewayv2_integration.visitor_counter.id}"
}

resource "aws_lambda_permission" "visitor_counter" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.portfolio.execution_arn}/*/*"
}

# ── Route: GET /metrics → metrics_reader ─────────────────────────────────────
resource "aws_apigatewayv2_integration" "metrics_reader" {
  api_id                 = aws_apigatewayv2_api.portfolio.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.metrics_reader.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_metrics" {
  api_id    = aws_apigatewayv2_api.portfolio.id
  route_key = "GET /metrics"
  target    = "integrations/${aws_apigatewayv2_integration.metrics_reader.id}"
}

resource "aws_lambda_permission" "metrics_reader" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.metrics_reader.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.portfolio.execution_arn}/*/*"
}

# ── Route: POST /activity → activity_tracker ─────────────────────────────────
resource "aws_apigatewayv2_integration" "activity_tracker" {
  api_id                 = aws_apigatewayv2_api.portfolio.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.activity_tracker.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_activity" {
  api_id    = aws_apigatewayv2_api.portfolio.id
  route_key = "POST /activity"
  target    = "integrations/${aws_apigatewayv2_integration.activity_tracker.id}"
}

resource "aws_lambda_permission" "activity_tracker" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.activity_tracker.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.portfolio.execution_arn}/*/*"
}
