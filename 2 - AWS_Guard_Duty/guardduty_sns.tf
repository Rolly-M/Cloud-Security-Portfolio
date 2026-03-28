# guardduty_sns.tf - SNS Topics for GuardDuty Alerts

# ==========================================
# SNS TOPIC FOR ALL GUARDDUTY FINDINGS
# ==========================================
resource "aws_sns_topic" "guardduty_alerts" {
  count = var.enable_guardduty ? 1 : 0
  name  = "${var.environment}-guardduty-alerts"

  tags = {
    Name        = "${var.environment}-guardduty-alerts"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "guardduty_email" {
  count     = var.enable_guardduty ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_alerts[0].arn
  protocol  = "email"
  endpoint  = var.guardduty_alert_email
}

# ==========================================
# SNS TOPIC FOR CRITICAL FINDINGS
# ==========================================
resource "aws_sns_topic" "guardduty_critical" {
  count = var.enable_guardduty ? 1 : 0
  name  = "${var.environment}-guardduty-critical"

  tags = {
    Name        = "${var.environment}-guardduty-critical"
    Environment = var.environment
    Severity    = "CRITICAL"
  }
}

resource "aws_sns_topic_subscription" "guardduty_critical_email" {
  count     = var.enable_guardduty ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_critical[0].arn
  protocol  = "email"
  endpoint  = var.guardduty_alert_email
}

# ==========================================
# SNS TOPIC FOR REMEDIATION NOTIFICATIONS
# ==========================================
resource "aws_sns_topic" "remediation_notifications" {
  count = var.enable_guardduty ? 1 : 0
  name  = "${var.environment}-remediation-notifications"

  tags = {
    Name        = "${var.environment}-remediation-notifications"
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "remediation_email" {
  count     = var.enable_guardduty ? 1 : 0
  topic_arn = aws_sns_topic.remediation_notifications[0].arn
  protocol  = "email"
  endpoint  = var.guardduty_alert_email
}

# ==========================================
# SNS TOPIC POLICY
# ==========================================
resource "aws_sns_topic_policy" "guardduty_alerts" {
  count = var.enable_guardduty ? 1 : 0
  arn   = aws_sns_topic.guardduty_alerts[0].arn

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
        Resource = aws_sns_topic.guardduty_alerts[0].arn
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.guardduty_alerts[0].arn
      }
    ]
  })
}

resource "aws_sns_topic_policy" "remediation_notifications" {
  count = var.enable_guardduty ? 1 : 0
  arn   = aws_sns_topic.remediation_notifications[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.remediation_notifications[0].arn
      }
    ]
  })
}