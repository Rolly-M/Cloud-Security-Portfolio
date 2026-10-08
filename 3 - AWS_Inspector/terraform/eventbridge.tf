###############################################################################
# EventBridge Rules for Inspector v2 Findings
###############################################################################

# Rule: Inspector2 HIGH and CRITICAL findings — route to Lambda processor
resource "aws_cloudwatch_event_rule" "inspector_high_critical" {
  name        = "${local.name_prefix}-inspector-high-critical"
  description = "Capture Inspector v2 HIGH and CRITICAL findings for processing"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["HIGH", "CRITICAL"]
    }
  })

  tags = {
    Name = "${local.name_prefix}-inspector-high-critical"
  }
}

resource "aws_cloudwatch_event_target" "inspector_to_lambda" {
  rule      = aws_cloudwatch_event_rule.inspector_high_critical.name
  target_id = "SendToFindingProcessor"
  arn       = aws_lambda_function.finding_processor.arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.finding_processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.inspector_high_critical.arn
}
