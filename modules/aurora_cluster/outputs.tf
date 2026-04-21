output "cluster_id" {
  description = "Cluster identifier (same as input)"
  value       = aws_rds_cluster.aurora.cluster_identifier
}

output "cluster_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  value = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_resource_id" {
  value = aws_rds_cluster.aurora.cluster_resource_id
}

output "writer_instance_id" {
  value = aws_rds_cluster_instance.writer.id
}

output "reader_instance_ids" {
  value = aws_rds_cluster_instance.readers[*].id
}

output "all_instance_endpoints" {
  value = merge(
    { writer = "${aws_rds_cluster_instance.writer.endpoint}:5432" },
    { for i, r in aws_rds_cluster_instance.readers : "reader_${i + 1}" => "${r.endpoint}:5432" }
  )
}

output "database_name" {
  value = aws_rds_cluster.aurora.database_name
}

output "database_port" {
  value = aws_rds_cluster.aurora.port
}

output "master_username" {
  value     = aws_rds_cluster.aurora.master_username
  sensitive = true
}

output "engine_version" {
  value = aws_rds_cluster.aurora.engine_version
}

output "monitoring_role_arn" {
  value = aws_iam_role.rds_monitoring.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.postgresql.name
}

output "connection_string_template" {
  value = "postgresql://<username>:<password>@${aws_rds_cluster.aurora.endpoint}:5432/${aws_rds_cluster.aurora.database_name}?sslmode=require"
}

output "read_connection_string_template" {
  value = "postgresql://<username>:<password>@${aws_rds_cluster.aurora.reader_endpoint}:5432/${aws_rds_cluster.aurora.database_name}?sslmode=require"
}
