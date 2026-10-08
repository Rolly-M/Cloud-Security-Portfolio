###############################################################################
# AWS Inspector v2 — EC2 Vulnerability Scanning
###############################################################################

# Enable Inspector v2 for EC2 scanning only (Lambda/ECR scanning costs extra)
resource "aws_inspector2_enabler" "main" {
  count        = var.enable_inspector ? 1 : 0
  account_ids  = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2"]
}

###############################################################################
# SNS — Inspector Finding Alerts
###############################################################################

resource "aws_sns_topic" "inspector_alerts" {
  name              = "${local.name_prefix}-inspector-alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = {
    Name = "${local.name_prefix}-inspector-alerts"
  }
}

# Allow Inspector (via EventBridge) and Lambda to publish to the topic
resource "aws_sns_topic_policy" "inspector_alerts" {
  arn = aws_sns_topic.inspector_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.inspector_alerts.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:events:${var.aws_region}:${data.aws_caller_identity.current.account_id}:rule/*"
          }
        }
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_finding_processor.arn
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.inspector_alerts.arn
      }
    ]
  })
}

# Email subscription for alert notifications
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.inspector_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
