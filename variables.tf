# ============================================
# AWS Configuration
# ============================================

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be in valid format (e.g., us-west-2)."
  }
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "AWS Account ID must be 12 digits."
  }
}

variable "terraform_role" {
  description = "IAM role name for Terraform to assume (optional; configure provider separately if used)"
  type        = string
  default     = "terraform-aurora-executor"
}

# ============================================
# Project Configuration
# ============================================

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "workium"

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20
    error_message = "Project name must be between 3 and 20 characters."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# ============================================
# VPC Configuration
# ============================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (NAT gateway placement)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "Must have at least 1 public subnet for NAT."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "Must have at least 2 private subnets for HA."
  }
}

variable "availability_zones" {
  description = "Availability zones to use"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Must have at least 2 AZs for multi-AZ deployment."
  }
}

variable "use_existing_vpc" {
  description = "Use an existing VPC and private subnets instead of creating networking resources"
  type        = bool
  default     = false
}

variable "existing_vpc_id" {
  description = "Existing VPC ID to use when use_existing_vpc is true"
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.existing_vpc_id == null || can(regex("^vpc-[a-z0-9]+$", var.existing_vpc_id))
    error_message = "existing_vpc_id must look like a valid VPC ID (vpc-xxxxxxxx)."
  }

  validation {
    condition     = !var.use_existing_vpc || var.existing_vpc_id != null
    error_message = "existing_vpc_id is required when use_existing_vpc is true."
  }
}

variable "existing_private_subnet_ids" {
  description = "Private subnet IDs in the existing VPC for Aurora (at least two)"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for subnet_id in var.existing_private_subnet_ids : can(regex("^subnet-[a-z0-9]+$", subnet_id))
    ])
    error_message = "All existing_private_subnet_ids must look like valid subnet IDs."
  }

  validation {
    condition     = !var.use_existing_vpc || length(var.existing_private_subnet_ids) >= 2
    error_message = "At least two existing_private_subnet_ids are required when use_existing_vpc is true."
  }
}

# ============================================
# Aurora Configuration
# ============================================

variable "aurora_cluster_name" {
  description = "Name of Aurora cluster"
  type        = string
  default     = "workium-aurora-prod"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$", var.aurora_cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric and hyphens."
  }
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.17"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.aurora_engine_version))
    error_message = "Engine version must be like 15.17"
  }
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora nodes"
  type        = string
  default     = "db.t4g.medium"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.aurora_instance_class))
    error_message = "Instance class must be valid (e.g., db.t4g.medium)."
  }
}

variable "aurora_replica_count" {
  description = "Number of read replicas"
  type        = number
  default     = 1

  validation {
    condition     = var.aurora_replica_count >= 1 && var.aurora_replica_count <= 15
    error_message = "Replica count must be between 1 and 15."
  }
}

variable "database_name" {
  description = "Initial database name"
  type        = string
  default     = "workium_db"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]*$", var.database_name))
    error_message = "Database name must start with lowercase letter or underscore."
  }
}

variable "master_username" {
  description = "Master database username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "master_password" {
  description = "Master database password"
  type        = string
  sensitive   = true
}

variable "max_connections" {
  description = "Maximum database connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections >= 20 && var.max_connections <= 16000
    error_message = "Max connections must be between 20 and 16000."
  }
}

# ============================================
# Backup Configuration
# ============================================

variable "backup_retention_days" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Retention must be between 1 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window (HH:MM-HH:MM UTC)"
  type        = string
  default     = "02:00-03:00"

  validation {
    condition     = can(regex("^(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]-(0[0-9]|1[0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Backup window must be in HH:MM-HH:MM format (UTC)."
  }
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "sun:03:00-sun:04:00"
}

variable "deletion_protection" {
  description = "Enable deletion protection on the Aurora cluster"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the cluster (use only in non-prod)"
  type        = bool
  default     = false
}

# ============================================
# Monitoring Configuration
# ============================================

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval (seconds)"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Valid intervals: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "enable_performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention (days)"
  type        = number
  default     = 7

  validation {
    condition     = var.performance_insights_retention_days == 7 || var.performance_insights_retention_days == 31
    error_message = "Can be 7 (free tier) or 31 (extended, paid)."
  }
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention (days)"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Must be a valid CloudWatch retention period."
  }
}

# ============================================
# Encryption Configuration
# ============================================

variable "kms_key_id" {
  description = "KMS key ID for RDS encryption"
  type        = string
  sensitive   = true
}

variable "storage_encrypted" {
  description = "Enable storage encryption"
  type        = bool
  default     = true
}

# ============================================
# Alerting Configuration
# ============================================

variable "alarm_email" {
  description = "Email for alarm notifications (SNS subscription; override in environments/prod/terraform.tfvars)"
  type        = string
  sensitive   = true
  default     = "devops@example.com"
}

variable "connection_threshold_percent" {
  description = "Percentage of max connections to trigger alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.connection_threshold_percent > 0 && var.connection_threshold_percent <= 100
    error_message = "Must be between 0 and 100 percent."
  }
}

variable "cpu_threshold_percent" {
  description = "CPU utilization threshold for alarm"
  type        = number
  default     = 75

  validation {
    condition     = var.cpu_threshold_percent > 0 && var.cpu_threshold_percent <= 100
    error_message = "Must be between 0 and 100 percent."
  }
}

variable "storage_threshold_percent" {
  description = "Storage utilization threshold for alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.storage_threshold_percent > 0 && var.storage_threshold_percent <= 100
    error_message = "Must be between 0 and 100 percent."
  }
}

variable "postgres_ingress_cidrs" {
  description = "CIDRs allowed to connect to PostgreSQL:5432 on the RDS security group (e.g. Client VPN CIDR or office). Empty = only app SG + self. Traffic must reach the VPC (VPN/bastion); Aurora is not internet-facing."
  type        = list(string)
  default     = []
}

# ============================================
# Bastion (EC2)
# ============================================

variable "bastion_instance_type" {
  description = "Bastion instance type (t3.micro is free-tier eligible in many accounts)"
  type        = string
  default     = "t3.micro"
}

variable "bastion_ssh_cidrs" {
  description = "CIDRs allowed to SSH (22) to the bastion. Empty = no SSH; use AWS SSM Session Manager only (recommended)."
  type        = list(string)
  default     = []
}

variable "bastion_key_name" {
  description = "Optional EC2 key pair name (only needed if using SSH)"
  type        = string
  default     = null
  nullable    = true
}

variable "bastion_install_postgresql_client" {
  description = "Install psql on the bastion via user-data (Amazon Linux 2023)"
  type        = bool
  default     = true
}

variable "enable_bastion" {
  description = "Enable bastion host creation"
  type        = bool
  default     = true
}

# ============================================
# Tags
# ============================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Team       = "platform"
    Compliance = "pci-dss"
  }
}
