# guardduty_eventbridge.tf - EventBridge Rules for GuardDuty Findings

# ==========================================
# RULE: ALL GUARDDUTY FINDINGS -> SNS
# ==========================================
resource "aws_cloudwatch_event_rule" "guardduty_all_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.environment}-guardduty-all-findings"
  description = "Capture all GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })

  tags = {
    Name        = "${var.environment}-guardduty-all-findings"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "guardduty_all_to_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_all_findings[0].name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.guardduty_alerts[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      finding     = "$.detail.type"
      description = "$.detail.description"
      region      = "$.region"
      account     = "$.account"
      time        = "$.time"
    }
    input_template = <<EOF
"🔔 GuardDuty Finding Detected

⏰ Time: <time>
📊 Severity: <severity>
🔍 Finding: <finding>
🌎 Region: <region>
🔑 Account: <account>

📝 Description:
<description>

View in console: https://console.aws.amazon.com/guardduty/home#/findings"
EOF
  }
}

# ==========================================
# RULE: HIGH SEVERITY (7+) -> ISOLATE INSTANCE
# ==========================================
resource "aws_cloudwatch_event_rule" "guardduty_high_severity" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.environment}-guardduty-high-severity"
  description = "High severity GuardDuty findings - trigger instance isolation"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })

  tags = {
    Name        = "${var.environment}-guardduty-high-severity"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "high_severity_isolate" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity[0].name
  target_id = "isolate-instance"
  arn       = aws_lambda_function.isolate_instance[0].arn
}

resource "aws_lambda_permission" "high_severity_isolate" {
  count         = var.enable_guardduty ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.isolate_instance[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high_severity[0].arn
}

resource "aws_cloudwatch_event_target" "high_severity_critical_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_high_severity[0].name
  target_id = "send-to-critical-sns"
  arn       = aws_sns_topic.guardduty_critical[0].arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      finding     = "$.detail.type"
      description = "$.detail.description"
      instanceId  = "$.detail.resource.instanceDetails.instanceId"
      time        = "$.time"
    }
    input_template = <<EOF
"🚨🚨🚨 CRITICAL SECURITY ALERT 🚨🚨🚨

HIGH SEVERITY GUARDDUTY FINDING!

⏰ Time: <time>
📊 Severity: <severity>
🔍 Finding: <finding>
🖥️ Instance: <instanceId>

📝 Description:
<description>

⚡ AUTOMATED REMEDIATION TRIGGERED:
- Instance is being isolated (moved to quarantine security group)
- All network access will be revoked

IMMEDIATE ACTION REQUIRED!"
EOF
  }
}

# ==========================================
# RULE: UNAUTHORIZED ACCESS / BRUTE FORCE -> BLOCK IP
# ==========================================
resource "aws_cloudwatch_event_rule" "guardduty_unauthorized_access" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.environment}-guardduty-unauthorized-access"
  description = "Unauthorized access attempts - trigger IP blocking"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        { prefix = "UnauthorizedAccess:" },
        { prefix = "Recon:EC2/PortProbeUnprotectedPort" },
        { prefix = "Recon:EC2/Portscan" },
        { prefix = "Impact:EC2/PortSweep" }
      ]
    }
  })

  tags = {
    Name        = "${var.environment}-guardduty-unauthorized-access"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "unauthorized_block_ip" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_unauthorized_access[0].name
  target_id = "block-ip-nacl"
  arn       = aws_lambda_function.block_ip_nacl[0].arn
}

resource "aws_lambda_permission" "unauthorized_block_ip" {
  count         = var.enable_guardduty ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.block_ip_nacl[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_unauthorized_access[0].arn
}

# ==========================================
# RULE: CRYPTOCURRENCY MINING -> STOP INSTANCE
# ==========================================
resource "aws_cloudwatch_event_rule" "guardduty_crypto_mining" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.environment}-guardduty-crypto-mining"
  description = "Cryptocurrency mining detection - trigger instance stop"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        { prefix = "CryptoCurrency:" },
        { prefix = "Impact:EC2/BitcoinDomainRequest" },
        { prefix = "Impact:EC2/MaliciousDomainRequest.Reputation" }
      ]
    }
  })

  tags = {
    Name        = "${var.environment}-guardduty-crypto-mining"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "crypto_mining_stop" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_crypto_mining[0].name
  target_id = "stop-instance"
  arn       = aws_lambda_function.stop_crypto_mining[0].arn
}

resource "aws_lambda_permission" "crypto_mining_stop" {
  count         = var.enable_guardduty ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_crypto_mining[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_crypto_mining[0].arn
}

# ==========================================
# RULE: SLACK NOTIFICATIONS (OPTIONAL)
# ==========================================
resource "aws_cloudwatch_event_rule" "guardduty_slack" {
  count       = var.enable_guardduty && var.slack_webhook_url != "" ? 1 : 0
  name        = "${var.environment}-guardduty-slack"
  description = "Send all GuardDuty findings to Slack"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })

  tags = {
    Name        = "${var.environment}-guardduty-slack"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_event_target" "guardduty_slack" {
  count     = var.enable_guardduty && var.slack_webhook_url != "" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_slack[0].name
  target_id = "send-to-slack"
  arn       = aws_lambda_function.slack_notification[0].arn
}

resource "aws_lambda_permission" "guardduty_slack" {
  count         = var.enable_guardduty && var.slack_webhook_url != "" ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notification[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_slack[0].arn
}