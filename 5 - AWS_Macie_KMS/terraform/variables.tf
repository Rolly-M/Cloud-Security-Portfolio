###############################################################################
# Variables
###############################################################################

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "macie-kms-security"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "security-team"
}

variable "alert_email" {
  description = "Email address for Macie finding alerts"
  type        = string
  default     = ""
}

variable "enable_quarantine" {
  description = "Whether to automatically move objects with PII findings to quarantine bucket"
  type        = bool
  default     = true
}

variable "severity_threshold" {
  description = "Minimum Macie severity score (0-10) to trigger automated response"
  type        = string
  default     = "7.0"
}

variable "scan_schedule" {
  description = "Frequency for Macie scheduled classification jobs (DAILY, WEEKLY, MONTHLY)"
  type        = string
  default     = "WEEKLY"
}
