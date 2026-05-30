###############################################################################
# Outputs
###############################################################################

output "sensitive_bucket_name" {
  description = "Name of the sensitive data S3 bucket scanned by Macie"
  value       = aws_s3_bucket.sensitive.id
}

output "quarantine_bucket_name" {
  description = "Name of the quarantine S3 bucket for objects with PII findings"
  value       = aws_s3_bucket.quarantine.id
}

output "clean_bucket_name" {
  description = "Name of the clean data S3 bucket"
  value       = aws_s3_bucket.clean.id
}

output "kms_key_arn" {
  description = "ARN of the shared KMS Customer Managed Key"
  value       = aws_kms_key.data.arn
}

output "kms_key_id" {
  description = "ID of the shared KMS Customer Managed Key"
  value       = aws_kms_key.data.key_id
}

output "lambda_function_name" {
  description = "Name of the Macie finding processor Lambda function"
  value       = aws_lambda_function.finding_processor.function_name
}

output "macie_job_id" {
  description = "ID of the Macie weekly classification job"
  value       = aws_macie2_classification_job.sensitive_data_scan.id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Macie finding alerts"
  value       = aws_sns_topic.macie_alerts.arn
}

output "kms_key_alias" {
  description = "Alias of the shared KMS CMK"
  value       = aws_kms_alias.data.name
}
