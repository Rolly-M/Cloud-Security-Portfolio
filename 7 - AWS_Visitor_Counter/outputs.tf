output "api_base_url" {
  description = "Base URL of the HTTP API — append /visit or /metrics"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "metrics_endpoint" {
  description = "Paste this into portfolio/js/main.js → API_URL"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/metrics"
}

output "visit_endpoint" {
  description = "Paste this into portfolio/js/main.js → VISIT_URL"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/visit"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.visits.name
}

output "visitor_counter_function_name" {
  value = aws_lambda_function.visitor_counter.function_name
}

output "metrics_reader_function_name" {
  value = aws_lambda_function.metrics_reader.function_name
}
