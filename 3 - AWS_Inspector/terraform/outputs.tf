###############################################################################
# Outputs
###############################################################################

output "lambda_function_name" {
  description = "Inspector finding processor Lambda function name"
  value       = aws_lambda_function.finding_processor.function_name
}

output "lambda_function_arn" {
  description = "Inspector finding processor Lambda function ARN"
  value       = aws_lambda_function.finding_processor.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for Inspector finding alerts"
  value       = aws_sns_topic.inspector_alerts.arn
}

output "inspector_enabler_account_id" {
  description = "AWS account ID in which Inspector v2 was enabled"
  value       = var.enable_inspector ? data.aws_caller_identity.current.account_id : null
}

output "test_instance_ids" {
  description = "IDs of the EC2 test instances being scanned by Inspector"
  value = [
    aws_instance.test_instance_a.id,
    aws_instance.test_instance_b.id,
  ]
}

output "vpc_id" {
  description = "VPC ID used for test instances"
  value       = local.resolved_vpc_id
}

output "eventbridge_rule_name" {
  description = "EventBridge rule that routes Inspector findings to Lambda"
  value       = aws_cloudwatch_event_rule.inspector_high_critical.name
}
