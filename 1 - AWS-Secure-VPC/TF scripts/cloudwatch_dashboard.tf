# cloudwatch_dashboard.tf

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-infrastructure-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      # Title Widget
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ${var.environment} Infrastructure Dashboard"
        }
      },
      
      # Bastion Host Section
      {
        type   = "text"
        x      = 0
        y      = 1
        width  = 24
        height = 1
        properties = {
          markdown = "## Bastion Host"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Bastion CPU Utilization"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.bastion.id]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Bastion Network In/Out"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.bastion.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.bastion.id]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Bastion Status Check"
          region = var.aws_region
          metrics = [
            ["AWS/EC2", "StatusCheckFailed", "InstanceId", aws_instance.bastion.id]
          ]
          period = 300
          stat   = "Maximum"
        }
      },
      
      # Private Instances Section
      {
        type   = "text"
        x      = 0
        y      = 8
        width  = 24
        height = 1
        properties = {
          markdown = "## Private Instances"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Private Instances CPU Utilization"
          region = var.aws_region
          metrics = [
            for idx, instance in aws_instance.private : 
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance.id, { label = "Instance ${idx + 1}" }]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 9
        width  = 12
        height = 6
        properties = {
          title  = "Private Instances Network Traffic"
          region = var.aws_region
          metrics = concat(
            [for idx, instance in aws_instance.private : 
              ["AWS/EC2", "NetworkIn", "InstanceId", instance.id, { label = "In - Instance ${idx + 1}" }]
            ],
            [for idx, instance in aws_instance.private : 
              ["AWS/EC2", "NetworkOut", "InstanceId", instance.id, { label = "Out - Instance ${idx + 1}" }]
            ]
          )
          period = 300
          stat   = "Sum"
        }
      },
      
      # NAT Gateway Section
      {
        type   = "text"
        x      = 0
        y      = 15
        width  = 24
        height = 1
        properties = {
          markdown = "## NAT Gateway"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 16
        width  = 8
        height = 6
        properties = {
          title  = "NAT Gateway Bytes Out"
          region = var.aws_region
          metrics = [
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", aws_nat_gateway.main.id]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 16
        width  = 8
        height = 6
        properties = {
          title  = "NAT Gateway Active Connections"
          region = var.aws_region
          metrics = [
            ["AWS/NATGateway", "ActiveConnectionCount", "NatGatewayId", aws_nat_gateway.main.id]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 16
        width  = 8
        height = 6
        properties = {
          title  = "NAT Gateway Port Allocation Errors"
          region = var.aws_region
          metrics = [
            ["AWS/NATGateway", "ErrorPortAllocation", "NatGatewayId", aws_nat_gateway.main.id]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      
      # Security Section
      {
        type   = "text"
        x      = 0
        y      = 22
        width  = 24
        height = 1
        properties = {
          markdown = "## Security Monitoring (VPC Flow Logs)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 23
        width  = 8
        height = 6
        properties = {
          title  = "Rejected SSH Attempts"
          region = var.aws_region
          metrics = [
            ["${var.environment}/Security", "SSHRejectedAttempts"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 23
        width  = 8
        height = 6
        properties = {
          title  = "Potential Port Scans"
          region = var.aws_region
          metrics = [
            ["${var.environment}/Security", "PotentialPortScan"]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 23
        width  = 8
        height = 6
        properties = {
          title  = "Large Data Transfers"
          region = var.aws_region
          metrics = [
            ["${var.environment}/Security", "LargeDataTransfers"]
          ]
          period = 3600
          stat   = "Sum"
        }
      },
      
      # Alarms Section
      {
        type   = "text"
        x      = 0
        y      = 29
        width  = 24
        height = 1
        properties = {
          markdown = "## Active Alarms"
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 30
        width  = 24
        height = 4
        properties = {
          title  = "Alarm Status"
          alarms = compact([
            var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.bastion_cpu[0].arn : "",
            var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.bastion_status_check[0].arn : "",
            var.enable_cloudwatch_alarms && var.enable_flow_logs ? aws_cloudwatch_metric_alarm.ssh_rejected[0].arn : "",
            var.enable_cloudwatch_alarms && var.enable_flow_logs ? aws_cloudwatch_metric_alarm.port_scan[0].arn : ""
          ])
        }
      }
    ]
  })
}