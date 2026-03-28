# terraform.tfvars

aws_region            = "us-east-1"
environment           = "production"
vpc_cidr              = "10.0.0.0/16"
bastion_instance_type = "t3.micro"
private_instance_type = "t3.micro"
key_name              = "my-key-pair"

# IMPORTANT: Change this to your IP address
# Find your IP: curl ifconfig.me
allowed_ssh_cidr = "YOUR.IP.ADDRESS/32"

# Alert email for notifications
alert_email = "your-email@example.com"

# Feature toggles
enable_flow_logs         = true
enable_cloudwatch_alarms = true

# Retention and thresholds
flow_logs_retention_days = 30
cpu_alarm_threshold      = 80
disk_alarm_threshold     = 80

# Instance count
private_instance_count = 2

# Network configuration
public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24",
  "10.0.3.0/24"
]

private_subnet_cidrs = [
  "10.0.101.0/24",
  "10.0.102.0/24",
  "10.0.103.0/24"
]

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c"
]

# ==================================================================
# VARIABLES FOR LAB 2 - GuardDuty + Threat simulation and remdiation
# ==================================================================

# GuardDuty Lab Configuration
enable_guardduty       = true
guardduty_alert_email  = "your-email@example.com"
slack_webhook_url      = ""  # Add your Slack webhook if you have one
enable_threat_simulation = true