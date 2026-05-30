###############################################################################
# Outputs
###############################################################################

output "web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "ID of the WAFv2 Web ACL"
  value       = aws_wafv2_web_acl.main.id
}

output "api_endpoint" {
  description = "API Gateway HTTP API invoke URL"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "waf_log_group_name" {
  description = "CloudWatch Log Group name for WAF logs"
  value       = aws_cloudwatch_log_group.waf_logs.name
}

output "ip_set_arn" {
  description = "ARN of the WAFv2 IP Set used for custom IP blocking"
  value       = aws_wafv2_ip_set.blocked.arn
}

output "lambda_function_name" {
  description = "Name of the protected application Lambda function"
  value       = aws_lambda_function.app_handler.function_name
}

output "lambda_function_arn" {
  description = "ARN of the protected application Lambda function"
  value       = aws_lambda_function.app_handler.arn
}
