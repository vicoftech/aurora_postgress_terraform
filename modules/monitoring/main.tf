resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.cluster_identifier}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.max_connections * (var.connection_threshold_percent / 100)
  alarm_description   = "Database connections exceed ${var.connection_threshold_percent}% of max_connections"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.cluster_identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold_percent
  alarm_description   = "CPU utilization exceeds ${var.cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${var.cluster_identifier}-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeLocalStorage"
  namespace           = "AWS/RDS"
  period              = 600
  statistic           = "Average"
  threshold           = 10737418240
  alarm_description   = "Free local storage below 10GB on an instance"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  alarm_name          = "${var.cluster_identifier}-high-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1000
  alarm_description   = "Replica lag exceeds 1000 ms"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "database_load" {
  alarm_name          = "${var.cluster_identifier}-high-db-load"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseLoad"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 4
  alarm_description   = "Database load exceeds threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.cluster_identifier}-alerts"

  tags = {
    Name = "${var.cluster_identifier}-alerts"
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "cloudwatch.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_dashboard" "aurora" {
  dashboard_name = "${var.cluster_identifier}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", var.cluster_identifier],
            [".", "CPUUtilization", ".", "."],
            [".", "FreeLocalStorage", ".", "."],
            [".", "DatabaseLoad", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Aurora cluster metrics"
        }
      }
    ]
  })
}

resource "aws_db_event_subscription" "aurora" {
  name      = "${var.cluster_identifier}-events"
  sns_topic = aws_sns_topic.alerts.arn

  source_type = "db-cluster"

  event_categories = [
    "creation",
    "deletion",
    "failover",
    "failure",
    "maintenance",
    "notification",
    "migration",
    "configuration change",
    "global-failover",
    "serverless"
  ]

  source_ids = [var.cluster_identifier]
  enabled    = true

  tags = {
    Name = "${var.cluster_identifier}-events"
  }
}
