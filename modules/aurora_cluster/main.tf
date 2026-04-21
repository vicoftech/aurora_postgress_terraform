resource "aws_rds_cluster" "aurora" {
  cluster_identifier = var.cluster_identifier

  engine         = "aurora-postgresql"
  engine_version = var.engine_version
  engine_mode    = "provisioned"

  database_name   = var.database_name
  master_username = var.master_username
  master_password = var.master_password

  db_subnet_group_name            = var.db_subnet_group_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = var.vpc_security_group_ids

  availability_zones = var.availability_zones

  port = 5432

  storage_encrypted            = var.storage_encrypted
  kms_key_id                   = var.kms_key_id
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.cluster_identifier}-final-snapshot"
  deletion_protection       = var.deletion_protection

  enabled_cloudwatch_logs_exports = ["postgresql"]

  iam_database_authentication_enabled = true

  tags = {
    Name = var.cluster_identifier
  }

  depends_on = [
    aws_rds_cluster_parameter_group.aurora,
    aws_iam_role.rds_monitoring
  ]

  lifecycle {
    ignore_changes = [
      availability_zones,
      master_password,
    ]
  }
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.cluster_identifier}-params"
  family      = "aurora-postgresql15"
  description = "Cluster parameter group for ${var.cluster_identifier}"

  parameter {
    name         = "max_connections"
    value        = tostring(var.max_connections)
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.cluster_identifier}-params"
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.cluster_identifier}-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${var.cluster_identifier}-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_identifier}-postgresql-logs"
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.cluster_identifier}-writer"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = var.instance_class
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id       = var.enable_performance_insights ? var.kms_key_id : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_days : null

  monitoring_interval = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_enhanced_monitoring && var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  auto_minor_version_upgrade = true
  availability_zone          = var.availability_zones[0]

  promotion_tier = 0

  tags = {
    Name = "${var.cluster_identifier}-writer"
    Role = "Writer"
  }

  depends_on = [
    aws_rds_cluster.aurora,
    aws_cloudwatch_log_group.postgresql
  ]
}

resource "aws_rds_cluster_instance" "readers" {
  count = var.replica_count

  identifier          = "${var.cluster_identifier}-reader-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = var.instance_class
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false

  performance_insights_enabled          = var.enable_performance_insights
  performance_insights_kms_key_id       = var.enable_performance_insights ? var.kms_key_id : null
  performance_insights_retention_period = var.enable_performance_insights ? var.performance_insights_retention_days : null

  monitoring_interval = var.enable_enhanced_monitoring ? var.monitoring_interval : 0
  monitoring_role_arn = var.enable_enhanced_monitoring && var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  auto_minor_version_upgrade = true
  availability_zone          = var.availability_zones[count.index % length(var.availability_zones)]

  promotion_tier = count.index + 1

  tags = {
    Name = "${var.cluster_identifier}-reader-${count.index + 1}"
    Role = "Reader"
  }

  depends_on = [
    aws_rds_cluster.aurora,
    aws_rds_cluster_instance.writer
  ]
}
