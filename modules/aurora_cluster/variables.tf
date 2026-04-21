variable "cluster_identifier" {
  description = "Cluster identifier"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.17"
}

variable "database_name" {
  description = "Initial database name"
  type        = string
}

variable "master_username" {
  description = "Master username"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password"
  type        = string
  sensitive   = true
}

variable "db_subnet_group_name" {
  description = "DB subnet group name (from networking)"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "VPC security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnet IDs (used for documentation / future subnet group validation)"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
}

variable "instance_class" {
  description = "Instance class"
  type        = string
  default     = "db.t4g.medium"
}

variable "replica_count" {
  description = "Number of reader instances"
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1 && var.replica_count <= 15
    error_message = "Must be between 1 and 15."
  }
}

variable "max_connections" {
  description = "Maximum connections"
  type        = number
  default     = 100
}

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
  sensitive   = true
}

variable "backup_retention_days" {
  description = "Backup retention days"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Backup window"
  type        = string
  default     = "02:00-03:00"
}

variable "maintenance_window" {
  description = "Maintenance window"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring on instances"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Monitoring interval (seconds); 0 disables enhanced monitoring"
  type        = number
  default     = 60
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention days"
  type        = number
  default     = 7
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (non-prod only)"
  type        = bool
  default     = false
}
