# vpc_flow_logs.tf

# ============================================
# CLOUDWATCH LOG GROUP FOR VPC FLOW LOGS
# ============================================

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.environment}-flow-logs"
  retention_in_days = var.flow_logs_retention_days
  
  tags = {
    Name        = "${var.environment}-vpc-flow-logs"
    Environment = var.environment
  }
}

# ============================================
# VPC FLOW LOGS - ALL TRAFFIC
# ============================================

resource "aws_flow_log" "main" {
  count                = var.enable_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs.arn
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.main.id
  max_aggregation_interval = 60
  
  tags = {
    Name        = "${var.environment}-vpc-flow-log"
    Environment = var.environment
  }
}

# ============================================
# VPC FLOW LOGS - REJECTED TRAFFIC ONLY (Security Monitoring)
# ============================================

resource "aws_cloudwatch_log_group" "flow_logs_rejected" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.environment}-flow-logs-rejected"
  retention_in_days = var.flow_logs_retention_days
  
  tags = {
    Name        = "${var.environment}-vpc-flow-logs-rejected"
    Environment = var.environment
  }
}

resource "aws_flow_log" "rejected" {
  count                = var.enable_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.flow_logs.arn
  log_destination      = aws_cloudwatch_log_group.flow_logs_rejected[0].arn
  traffic_type         = "REJECT"
  vpc_id               = aws_vpc.main.id
  max_aggregation_interval = 60
  
  tags = {
    Name        = "${var.environment}-vpc-flow-log-rejected"
    Environment = var.environment
  }
}

# ============================================
# METRIC FILTERS FOR SECURITY EVENTS
# ============================================

# Detect SSH attempts on rejected traffic
resource "aws_cloudwatch_log_metric_filter" "ssh_rejected" {
  count          = var.enable_flow_logs ? 1 : 0
  name           = "${var.environment}-ssh-rejected-attempts"
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport=22, protocol, packets, bytes, start, end, action=REJECT, log_status]"
  log_group_name = aws_cloudwatch_log_group.flow_logs_rejected[0].name
  
  metric_transformation {
    name          = "SSHRejectedAttempts"
    namespace     = "${var.environment}/Security"
    value         = "1"
    default_value = "0"
  }
}

# Detect large data transfers (potential data exfiltration)
resource "aws_cloudwatch_log_metric_filter" "large_transfers" {
  count          = var.enable_flow_logs ? 1 : 0
  name           = "${var.environment}-large-data-transfers"
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol, packets, bytes>=1000000000, start, end, action, log_status]"
  log_group_name = aws_cloudwatch_log_group.flow_logs[0].name
  
  metric_transformation {
    name          = "LargeDataTransfers"
    namespace     = "${var.environment}/Security"
    value         = "1"
    default_value = "0"
  }
}

# Detect port scanning (multiple rejected connections)
resource "aws_cloudwatch_log_metric_filter" "port_scan" {
  count          = var.enable_flow_logs ? 1 : 0
  name           = "${var.environment}-potential-port-scan"
  pattern        = "[version, account_id, interface_id, srcaddr, dstaddr, srcport, dstport, protocol=6, packets=1, bytes, start, end, action=REJECT, log_status]"
  log_group_name = aws_cloudwatch_log_group.flow_logs_rejected[0].name
  
  metric_transformation {
    name          = "PotentialPortScan"
    namespace     = "${var.environment}/Security"
    value         = "1"
    default_value = "0"
  }
}