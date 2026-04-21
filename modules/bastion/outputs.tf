output "instance_id" {
  description = "EC2 instance id (use with aws ssm start-session --target)"
  value       = aws_instance.bastion.id
}

output "security_group_id" {
  description = "Bastion security group (allowed to reach RDS)"
  value       = aws_security_group.bastion.id
}

output "public_ip" {
  description = "Public IPv4 (if assigned)"
  value       = aws_instance.bastion.public_ip
}

output "private_ip" {
  description = "Private IPv4 in the VPC"
  value       = aws_instance.bastion.private_ip
}
