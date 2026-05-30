###############################################################################
# EventBridge — Route Macie findings to Lambda for automated response
###############################################################################

# SNS topic for finding alerts
resource "aws_sns_topic" "macie_alerts" {
  name              = "${local.name_prefix}-macie-alerts"
  kms_master_key_id = aws_kms_key.data.arn

  tags = {
    Name = "${local.name_prefix}-macie-alerts"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.macie_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# EventBridge Rule — match Macie findings with severity >= HIGH (score >= 7)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "macie_findings" {
  name        = "${local.name_prefix}-macie-findings"
  description = "Capture Macie findings with HIGH or CRITICAL severity"

  event_pattern = jsonencode({
    source      = ["aws.macie2"]
    detail-type = ["Macie Finding"]
    detail = {
      severity = {
        score = [{ numeric = [">=", 7] }]
      }
    }
  })

  tags = {
    Name = "${local.name_prefix}-macie-findings"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.macie_findings.name
  target_id = "MacieFindingProcessor"
  arn       = aws_lambda_function.finding_processor.arn
}

# Allow EventBridge to invoke the Lambda function
resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finding_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.macie_findings.arn
}
