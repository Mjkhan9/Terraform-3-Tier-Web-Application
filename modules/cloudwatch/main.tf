# CloudWatch Alarm: High CPU Utilization
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  tags = {
    Name = "${var.project_name}-high-cpu-alarm"
  }
}

# CloudWatch Alarm: Low CPU Utilization
resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "This metric monitors ec2 cpu utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    AutoScalingGroupName = var.asg_name
  }

  tags = {
    Name = "${var.project_name}-low-cpu-alarm"
  }
}

# CloudWatch Alarm: ALB Target Response Time
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.project_name}-alb-high-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2.0
  alarm_description   = "This metric monitors ALB target response time"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-response-time-alarm"
  }
}

# CloudWatch Alarm: ALB Unhealthy Hosts
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "This metric monitors ALB unhealthy host count"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = split("/", var.target_group_arn)[1]
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-unhealthy-hosts-alarm"
  }
}

# CloudWatch Alarm: ALB 5xx Errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors ALB 5xx errors"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = {
    Name = "${var.project_name}-alb-5xx-errors-alarm"
  }
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"

  tags = {
    Name = "${var.project_name}-alerts-topic"
  }
}

# SNS Topic Subscription (email - optional, uncomment and set email)
# resource "aws_sns_topic_subscription" "email" {
#   topic_arn = aws_sns_topic.alerts.arn
#   protocol  = "email"
#   endpoint  = "your-email@example.com"
# }

# ═══════════════════════════════════════════════════════════════════════════════
# CLOUDWATCH DASHBOARD
# ═══════════════════════════════════════════════════════════════════════════════
# Centralized operational dashboard showing key metrics across all tiers.
# Follows AWS Well-Architected Framework observability best practices.
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-operations"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Application Load Balancer Metrics
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# 🌐 Application Load Balancer"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Request Count"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Target Response Time"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix]
          ]
          annotations = {
            horizontal = [
              {
                label = "SLA Threshold"
                value = 2.0
                color = "#ff7f0e"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "HTTP Error Codes"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { color = "#9467bd" }]
          ]
        }
      },

      # Row 2: Auto Scaling Group Metrics
      {
        type   = "text"
        x      = 0
        y      = 7
        width  = 24
        height = 1
        properties = {
          markdown = "# 🖥️ Compute (Auto Scaling Group)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "CPU Utilization"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
          ]
          annotations = {
            horizontal = [
              {
                label = "Scale Up"
                value = 80
                color = "#d62728"
              },
              {
                label = "Scale Down"
                value = 20
                color = "#2ca02c"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Network I/O"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/EC2", "NetworkIn", "AutoScalingGroupName", var.asg_name, { color = "#1f77b4" }],
            ["AWS/EC2", "NetworkOut", "AutoScalingGroupName", var.asg_name, { color = "#ff7f0e" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "Healthy vs Unhealthy Hosts"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", split("/", var.target_group_arn)[1], "LoadBalancer", var.alb_arn_suffix, { color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", split("/", var.target_group_arn)[1], "LoadBalancer", var.alb_arn_suffix, { color = "#d62728" }]
          ]
        }
      },

      # Row 3: Database Metrics
      {
        type   = "text"
        x      = 0
        y      = 14
        width  = 24
        height = 1
        properties = {
          markdown = "# 🗄️ Database (RDS PostgreSQL)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 6
        height = 6
        properties = {
          title  = "DB CPU Utilization"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "${var.project_name}-db"]
          ]
          annotations = {
            horizontal = [
              {
                label = "Warning"
                value = 80
                color = "#ff7f0e"
              }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 15
        width  = 6
        height = 6
        properties = {
          title  = "DB Connections"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "${var.project_name}-db"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 15
        width  = 6
        height = 6
        properties = {
          title  = "Read/Write IOPS"
          region = var.region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", "${var.project_name}-db", { color = "#1f77b4" }],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", "${var.project_name}-db", { color = "#ff7f0e" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 15
        width  = 6
        height = 6
        properties = {
          title  = "Free Storage Space"
          region = var.region
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "${var.project_name}-db"]
          ]
          annotations = {
            horizontal = [
              {
                label = "Low Storage Warning"
                value = 5368709120 # 5GB in bytes
                color = "#d62728"
              }
            ]
          }
        }
      },

      # Row 4: Alarms Status
      {
        type   = "text"
        x      = 0
        y      = 21
        width  = 24
        height = 1
        properties = {
          markdown = "# 🚨 Active Alarms"
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 22
        width  = 24
        height = 3
        properties = {
          title = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.high_cpu.arn,
            aws_cloudwatch_metric_alarm.low_cpu.arn,
            aws_cloudwatch_metric_alarm.alb_response_time.arn,
            aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.alb_5xx_errors.arn
          ]
        }
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLOUDWATCH LOG METRIC FILTERS
# ═══════════════════════════════════════════════════════════════════════════════
# Extract custom metrics from application logs for deeper observability.
# ═══════════════════════════════════════════════════════════════════════════════

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project_name}-error-count"
  pattern        = "ERROR"
  log_group_name = "/aws/ec2/${var.project_name}"

  metric_transformation {
    name      = "ApplicationErrorCount"
    namespace = "Custom/${var.project_name}"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "db_connection_errors" {
  name           = "${var.project_name}-db-connection-errors"
  pattern        = "?\"connection refused\" ?\"timeout\" ?\"password authentication failed\""
  log_group_name = "/aws/ec2/${var.project_name}"

  metric_transformation {
    name      = "DatabaseConnectionErrors"
    namespace = "Custom/${var.project_name}"
    value     = "1"
    unit      = "Count"
  }
}

# Alarm for Application Errors
resource "aws_cloudwatch_metric_alarm" "application_errors" {
  alarm_name          = "${var.project_name}-application-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApplicationErrorCount"
  namespace           = "Custom/${var.project_name}"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "Application error rate exceeded threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "${var.project_name}-application-errors-alarm"
  }
}

