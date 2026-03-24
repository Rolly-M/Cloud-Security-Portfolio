# cloudwatch_monitoring.tf

# ============================================
# BASTION HOST ALARMS
# ============================================

resource "aws_cloudwatch_metric_alarm" "bastion_cpu" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.environment}-bastion-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Bastion CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    InstanceId = aws_instance.bastion.id
  }
  
  tags = {
    Name        = "${var.environment}-bastion-high-cpu"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "bastion_status_check" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.environment}-bastion-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Bastion host status check failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    InstanceId = aws_instance.bastion.id
  }
  
  tags = {
    Name        = "${var.environment}-bastion-status-check-failed"
    Environment = var.environment
  }
}

# ============================================
# PRIVATE INSTANCE ALARMS
# ============================================

resource "aws_cloudwatch_metric_alarm" "private_cpu" {
  count               = var.enable_cloudwatch_alarms ? var.private_instance_count : 0
  alarm_name          = "${var.environment}-private-instance-${count.index + 1}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  alarm_description   = "Private instance ${count.index + 1} CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    InstanceId = aws_instance.private[count.index].id
  }
  
  tags = {
    Name        = "${var.environment}-private-instance-${count.index + 1}-high-cpu"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "private_status_check" {
  count               = var.enable_cloudwatch_alarms ? var.private_instance_count : 0
  alarm_name          = "${var.environment}-private-instance-${count.index + 1}-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Private instance ${count.index + 1} status check failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    InstanceId = aws_instance.private[count.index].id
  }
  
  tags = {
    Name        = "${var.environment}-private-instance-${count.index + 1}-status-check-failed"
    Environment = var.environment
  }
}

# ============================================
# SECURITY ALARMS (VPC FLOW LOGS)
# ============================================

resource "aws_cloudwatch_metric_alarm" "ssh_rejected" {
  count               = var.enable_cloudwatch_alarms && var.enable_flow_logs ? 1 : 0
  alarm_name          = "${var.environment}-ssh-rejected-attempts-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SSHRejectedAttempts"
  namespace           = "${var.environment}/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "High number of rejected SSH attempts detected - possible brute force attack"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = {
    Name        = "${var.environment}-ssh-rejected-attempts-high"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "port_scan" {
  count               = var.enable_cloudwatch_alarms && var.enable_flow_logs ? 1 : 0
  alarm_name          = "${var.environment}-potential-port-scan"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PotentialPortScan"
  namespace           = "${var.environment}/Security"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Potential port scan detected - multiple rejected connection attempts"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = {
    Name        = "${var.environment}-potential-port-scan"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "large_transfers" {
  count               = var.enable_cloudwatch_alarms && var.enable_flow_logs ? 1 : 0
  alarm_name          = "${var.environment}-large-data-transfers"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "LargeDataTransfers"
  namespace           = "${var.environment}/Security"
  period              = 3600
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Multiple large data transfers detected - possible data exfiltration"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"
  
  tags = {
    Name        = "${var.environment}-large-data-transfers"
    Environment = var.environment
  }
}

# ============================================
# NAT GATEWAY ALARMS
# ============================================

resource "aws_cloudwatch_metric_alarm" "nat_gateway_error" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.environment}-nat-gateway-error-port-allocation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Gateway port allocation errors detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    NatGatewayId = aws_nat_gateway.main.id
  }
  
  tags = {
    Name        = "${var.environment}-nat-gateway-error-port-allocation"
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "nat_gateway_bandwidth" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.environment}-nat-gateway-high-bandwidth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BytesOutToDestination"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 5000000000  # 5 GB in 5 minutes
  alarm_description   = "NAT Gateway bandwidth usage is very high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    NatGatewayId = aws_nat_gateway.main.id
  }
  
  tags = {
    Name        = "${var.environment}-nat-gateway-high-bandwidth"
    Environment = var.environment
  }
}