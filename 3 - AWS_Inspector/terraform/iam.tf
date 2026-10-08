###############################################################################
# IAM Role and Policies for the Lambda Finding Processor
###############################################################################

# Lambda Execution Role
resource "aws_iam_role" "lambda_finding_processor" {
  name = "${local.name_prefix}-lambda-finding-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-lambda-finding-processor-role"
  }
}

# CloudWatch Logs — write Lambda execution logs
resource "aws_iam_role_policy" "lambda_logs" {
  name = "${local.name_prefix}-lambda-logs"
  role = aws_iam_role.lambda_finding_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# EC2 — describe instances and tag them with finding metadata
resource "aws_iam_role_policy" "ec2_tagging" {
  name = "${local.name_prefix}-ec2-tagging"
  role = aws_iam_role.lambda_finding_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Tag"
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
      }
    ]
  })
}

# SNS — publish finding notifications
resource "aws_iam_role_policy" "sns_publish" {
  name = "${local.name_prefix}-sns-publish"
  role = aws_iam_role.lambda_finding_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.inspector_alerts.arn
      }
    ]
  })
}

# Inspector2 — list findings for cross-referencing
resource "aws_iam_role_policy" "inspector2_read" {
  name = "${local.name_prefix}-inspector2-read"
  role = aws_iam_role.lambda_finding_processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "inspector2:ListFindings"
        ]
        Resource = "*"
      }
    ]
  })
}
