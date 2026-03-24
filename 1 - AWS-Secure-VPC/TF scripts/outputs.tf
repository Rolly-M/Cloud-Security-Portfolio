# outputs.tf

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = aws_eip.bastion.public_ip
}

output "bastion_instance_id" {
  description = "Bastion host instance ID"
  value       = aws_instance.bastion.id
}

output "private_instance_ids" {
  description = "Private instance IDs"
  value       = aws_instance.private[*].id
}

output "private_instance_ips" {
  description = "Private instance private IPs"
  value       = aws_instance.private[*].private_ip
}

output "private_security_group_id" {
  description = "Security group ID for private instances"
  value       = aws_security_group.private_instances.id
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = aws_eip.nat.public_ip
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.environment}-infrastructure-dashboard"
}

output "flow_logs_log_group" {
  description = "VPC Flow Logs CloudWatch Log Group"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : "Flow logs disabled"
}

output "ssh_command_bastion" {
  description = "SSH command to connect to bastion"
  value       = "ssh -i ${var.key_name}.pem ec2-user@${aws_eip.bastion.public_ip}"
}

output "ssh_command_private_instances" {
  description = "SSH commands to connect to private instances (from bastion)"
  value       = [for ip in aws_instance.private[*].private_ip : "ssh ec2-user@${ip}"]
}