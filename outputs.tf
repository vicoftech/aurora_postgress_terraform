output "cluster_endpoint" {
  description = "Aurora cluster endpoint (write)"
  value       = module.aurora.cluster_endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster read endpoint"
  value       = module.aurora.cluster_reader_endpoint
}

output "cluster_resource_id" {
  description = "Aurora cluster resource ID"
  value       = module.aurora.cluster_resource_id
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = module.aurora.cluster_id
}

output "writer_instance_id" {
  description = "Writer instance ID"
  value       = module.aurora.writer_instance_id
}

output "reader_instance_ids" {
  description = "Reader instance IDs"
  value       = module.aurora.reader_instance_ids
}

output "all_instance_endpoints" {
  description = "All instance endpoints (host:port)"
  value       = module.aurora.all_instance_endpoints
}

output "database_name" {
  description = "Database name"
  value       = module.aurora.database_name
}

output "database_port" {
  description = "Database port"
  value       = module.aurora.database_port
}

output "master_username" {
  description = "Database master username"
  value       = module.aurora.master_username
  sensitive   = true
}

output "master_password" {
  description = "Master password configured for the database"
  value       = var.master_password
  sensitive   = true
}

output "engine_version" {
  description = "Aurora PostgreSQL engine version"
  value       = module.aurora.engine_version
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = module.security.rds_security_group_id
}

output "app_security_group_id" {
  description = "Application security group ID"
  value       = aws_security_group.app.id
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID (aws ssm start-session --target <id>)"
  value       = var.enable_bastion && !var.use_existing_vpc ? module.bastion[0].instance_id : null
}

output "bastion_public_ip" {
  description = "Bastion public IPv4 (if assigned)"
  value       = var.enable_bastion && !var.use_existing_vpc ? module.bastion[0].public_ip : null
}

output "bastion_security_group_id" {
  description = "Bastion security group ID"
  value       = var.enable_bastion && !var.use_existing_vpc ? module.bastion[0].security_group_id : null
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = local.selected_db_subnet_group_name
}

output "enhanced_monitoring_role_arn" {
  description = "IAM role for enhanced monitoring"
  value       = module.aurora.monitoring_role_arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for PostgreSQL"
  value       = module.aurora.log_group_name
}

output "performance_insights_enabled" {
  description = "Performance Insights enabled on instances"
  value       = var.enable_performance_insights
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.selected_vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = local.selected_private_subnet_ids
}

output "connection_string_template" {
  description = "Template for connection string"
  value       = module.aurora.connection_string_template
}

output "read_connection_string_template" {
  description = "Template for read connection string"
  value       = module.aurora.read_connection_string_template
}

output "terraform_state_bucket_hint" {
  description = "Expected S3 bucket name pattern for remote state (after bootstrap)"
  value       = "terraform-state-${var.aws_account_id}-aurora-${var.aws_region}"
  sensitive   = true
}

output "terraform_locks_table" {
  description = "DynamoDB table name for Terraform locks (default in guide)"
  value       = "terraform-locks"
}

output "next_steps" {
  description = "Operational hints after deploy"
  value       = <<-EOT
    1. Store the master password from output "master_password" in AWS Secrets Manager.
    2. Connect to Aurora via bastion (same VPC): aws ssm start-session --target $(terraform output -raw bastion_instance_id), then psql -h <cluster_endpoint> -U postgres -d <database_name> (see outputs cluster_endpoint, database_name).
    3. If you enabled bastion_ssh_cidrs + bastion_key_name, you can SSH to bastion_public_ip instead of SSM.
    4. Confirm SNS email subscription for alarms in the AWS console.
  EOT
}
