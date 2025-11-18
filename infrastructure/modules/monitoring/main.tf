# SNS (email)
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.sns_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ECS Alarms
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.project_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  period              = 300
  statistic           = "Average"
  threshold           = 70
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
  alarm_description   = "ECS service CPU > 70% for 10m"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_mem_high" {
  alarm_name          = "${var.project_name}-ecs-mem-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  period              = 300
  statistic           = "Average"
  threshold           = 75
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
  alarm_description   = "ECS service Memory > 75% for 10m"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# ALB Alarms 
# 5xx seen by the load balancer (bad gateway, etc.)
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  alarm_description   = "ALB 5xx > 5 in 5m"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Slow targets (p95 > 1.0s)
resource "aws_cloudwatch_metric_alarm" "alb_target_latency_p95" {
  alarm_name                = "${var.project_name}-alb-target-latency-p95"
  comparison_operator       = "GreaterThanThreshold"
  evaluation_periods        = 2
  period                    = 300
  extended_statistic        = "p95"
  threshold                 = 1.0
  metric_name               = "TargetResponseTime"
  namespace                 = "AWS/ApplicationELB"
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.tg_arn_suffix
  }
  alarm_description         = "Target p95 response time > 1s for 10m"
  alarm_actions             = [aws_sns_topic.alerts.arn]
  ok_actions                = [aws_sns_topic.alerts.arn]
}

# RDS Alarms
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  period              = 300
  statistic           = "Average"
  threshold           = 80
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  dimensions = {
    DBInstanceIdentifier = var.db_identifier
  }
  alarm_description   = "RDS CPU > 80% for 10m"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${var.project_name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  period              = 300
  statistic           = "Average"
  threshold           = 2e9  # 2 GB
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  dimensions = {
    DBInstanceIdentifier = var.db_identifier
  }
  alarm_description   = "RDS free storage < 2GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Metric filter
resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.project_name}-app-error-filter"
  log_group_name = var.log_group_name
  pattern        = "\"ERROR\""
  metric_transformation {
    name      = "${var.project_name}-app-error-count"
    namespace = "App/Logs"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.project_name}-app-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  metric_name         = "${var.project_name}-app-error-count"
  namespace           = "App/Logs"
  alarm_description   = ">= 5 ERROR log lines in 5m"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  depends_on          = [aws_cloudwatch_log_metric_filter.app_errors]
}

# Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        "type":"metric","x":0,"y":0,"width":12,"height":6,
        "properties":{
          "title":"ECS CPU/Memory",
          "metrics":[
            [ "AWS/ECS","CPUUtilization","ClusterName",var.ecs_cluster_name,"ServiceName",var.ecs_service_name ],
            [ ".",     "MemoryUtilization",".",var.ecs_cluster_name,".",var.ecs_service_name ]
          ],
          "period":300,"stat":"Average","region":"${data.aws_region.current.name}"
        }
      },
      {
        "type":"metric","x":12,"y":0,"width":12,"height":6,
        "properties":{
          "title":"ALB 5xx & p95 latency",
          "metrics":[
            [ "AWS/ApplicationELB","HTTPCode_ELB_5XX_Count","LoadBalancer",var.alb_arn_suffix, { "stat":"Sum" } ],
            [ ".","TargetResponseTime","LoadBalancer",var.alb_arn_suffix,"TargetGroup",var.tg_arn_suffix, { "stat":"p95" } ]
          ],
          "period":300,"region":"${data.aws_region.current.name}"
        }
      },
      {
        "type":"metric","x":0,"y":6,"width":12,"height":6,
        "properties":{
          "title":"RDS CPU & FreeStorage",
          "metrics":[
            [ "AWS/RDS","CPUUtilization","DBInstanceIdentifier",var.db_identifier ],
            [ ".","FreeStorageSpace",".",var.db_identifier, { "stat":"Average" } ]
          ],
          "period":300,"region":"${data.aws_region.current.name}"
        }
      }
    ]
  })
}

data "aws_region" "current" {}
