# ============================================
# AWS Configuration
# ============================================

aws_region     = "us-east-1"
aws_account_id = "913123310997"
terraform_role = "terraform-aurora-executor"

# ============================================
# Project Configuration
# ============================================

project_name = "alert"
environment  = "prod"
cost_center  = "engineering"

# ============================================
# VPC Configuration
# ============================================

vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
availability_zones   = ["us-east-1a", "us-east-1b"]
use_existing_vpc     = true
existing_vpc_id      = "vpc-0220b63692086a550"
existing_private_subnet_ids = [
  "subnet-09808b125e81feda6",
  "subnet-04cc462043523dcb9",
  "subnet-0254c9d900c8b2fdc"
]

# ============================================
# Aurora Configuration
# ============================================

aurora_cluster_name   = "postgres-aurora-prod"
aurora_engine_version = "15.17"
aurora_instance_class = "db.t4g.medium"
aurora_replica_count  = 1

database_name   = "alert_db"
master_username = "postgres"
master_password = "Asap.2026!"
max_connections = 100

deletion_protection = true
skip_final_snapshot = false

# ============================================
# Backup Configuration
# ============================================

backup_retention_days = 30
backup_window         = "02:00-03:00"
maintenance_window    = "sun:03:00-sun:04:00"

# ============================================
# Monitoring Configuration
# ============================================

enable_enhanced_monitoring          = true
monitoring_interval                 = 60
enable_performance_insights         = true
performance_insights_retention_days = 7
cloudwatch_log_retention_days       = 7

# ============================================
# Encryption Configuration
# ============================================

kms_key_id        = "arn:aws:kms:us-east-1:913123310997:key/2dbb98c3-6428-4b1c-bf1c-3a528cb72e7d"
storage_encrypted = true

# ============================================
# RDS connectivity (optional)
# ============================================
# Solo tiene efecto si el cliente ya está en/redirigido a la VPC (VPN, bastión, etc.).
# Aurora NO es público: desde Internet directo seguirá dando timeout.
# Ejemplo VPN: postgres_ingress_cidrs = ["10.100.0.0/16"]
# postgres_ingress_cidrs = []

enable_bastion = false

# ============================================
# Alerting Configuration
# ============================================

alarm_email                  = "devops@example.com"
connection_threshold_percent = 80
cpu_threshold_percent        = 75
storage_threshold_percent    = 80

# ============================================
# Additional Tags
# ============================================

additional_tags = {
  Team       = "platform"
  Compliance = "pci-dss"
  CostCenter = "engineering"
  Owner      = "devops-team"
}
