###############################################################################
# WAFv2 Web ACL, IP Set, Logging Configuration, and ACL Association
###############################################################################

# IP Set for custom IP blocking (initially empty — populate as threats are identified)
resource "aws_wafv2_ip_set" "blocked" {
  name               = "${local.name_prefix}-blocked-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = []

  tags = {
    Name = "${local.name_prefix}-blocked-ips"
  }
}

# WAFv2 Web ACL
resource "aws_wafv2_web_acl" "main" {
  name  = "${local.name_prefix}-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed Common Rule Set
  # Override NoUserAgent_HEADER to Count — many legitimate tools/scripts omit the header
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        rule_action_override {
          name = "NoUserAgent_HEADER"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed SQL Injection Rule Set
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed Known Bad Inputs Rule Set (log4j, SSRF, etc.)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate limiting — 2000 requests per 5-minute window per IP
  rule {
    name     = "RateLimitPerIP"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_threshold
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # Rule 5: Custom IP blocklist
  rule {
    name     = "BlockListedIPs"
    priority = 5

    action {
      block {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocked.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-blocked-ips"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name_prefix}-web-acl"
  }
}

# CloudWatch Log Group for WAF logs
# Name MUST start with "aws-waf-logs-" — this is an AWS requirement
resource "aws_cloudwatch_log_group" "waf_logs" {
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "aws-waf-logs-${local.name_prefix}"
  }
}

# WAFv2 Logging Configuration — sends logs to CloudWatch (cheaper than Kinesis Firehose)
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf_logs.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn

  depends_on = [aws_cloudwatch_log_group.waf_logs]
}

# Associate the WebACL with the API Gateway stage
resource "aws_wafv2_web_acl_association" "api_gateway" {
  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn

  depends_on = [
    aws_apigatewayv2_stage.default,
    aws_wafv2_web_acl.main,
  ]
}
