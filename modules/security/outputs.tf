output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
