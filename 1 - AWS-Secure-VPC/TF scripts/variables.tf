# variables.tf

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "bastion_instance_type" {
  description = "EC2 instance type for bastion host"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion (your IP)"
  type        = string
  default     = "0.0.0.0/0"  # Change to your IP: "YOUR.IP.ADDRESS/32"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = "my-key-pair"
}

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "private_instance_type" {
  description = "EC2 instance type for private instances"
  type        = string
  default     = "t3.micro"
}

# NEW VARIABLES

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "Number of days to retain flow logs"
  type        = number
  default     = 30
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for CloudWatch alerts"
  type        = string
  default     = "your-email@example.com"
}

variable "private_instance_count" {
  description = "Number of private EC2 instances to create"
  type        = number
  default     = 2
}

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 80
}

variable "disk_alarm_threshold" {
  description = "Disk utilization threshold for alarm"
  type        = number
  default     = 80
}