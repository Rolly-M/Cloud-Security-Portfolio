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
  default     = "inspector-security"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "security-team"
}

# Inspector Variables
variable "enable_inspector" {
  description = "Enable AWS Inspector v2"
  type        = bool
  default     = true
}

# SNS / Alerting Variables
variable "alert_email" {
  description = "Email address for Inspector finding alerts"
  type        = string
}

# Finding Processing Variables
variable "severity_threshold" {
  description = "Minimum CVSS score to trigger notification and instance tagging (0-10)"
  type        = string
  default     = "7.0"
}

variable "tag_instances" {
  description = "Tag EC2 instances with Inspector finding metadata when threshold is exceeded"
  type        = bool
  default     = true
}

# VPC / Network Variables (optional — reuse Project 1 VPC or create standalone)
variable "vpc_id" {
  description = "Existing VPC ID to deploy test instances into. Leave empty to create a minimal standalone VPC."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for test EC2 instances. Required when vpc_id is provided."
  type        = list(string)
  default     = []
}
