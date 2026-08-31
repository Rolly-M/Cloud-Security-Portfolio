variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ca-central-1"
}

variable "table_name" {
  description = "DynamoDB table name for visit data"
  type        = string
  default     = "portfolio-visits"
}

variable "project_name" {
  description = "Prefix applied to all resource names and tags"
  type        = string
  default     = "portfolio-visitor-counter"
}

variable "portfolio_origin" {
  description = "Netlify origin allowed to call the API (CORS)"
  type        = string
  default     = "https://rollymougoue.netlify.app"
}

variable "visitor_ttl_seconds" {
  description = "Seconds before a unique-visitor record expires (24 h default)"
  type        = number
  default     = 86400
}
