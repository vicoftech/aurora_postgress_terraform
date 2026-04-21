# ============================================
# Networking
# ============================================

module "networking" {
  count  = var.use_existing_vpc ? 0 : 1
  source = "./modules/networking"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0
  id    = var.existing_vpc_id
}

resource "aws_db_subnet_group" "existing_vpc" {
  count = var.use_existing_vpc ? 1 : 0
  name  = "${var.project_name}-aurora-subnet-group-existing"

  subnet_ids = var.existing_private_subnet_ids

  tags = {
    Name = "${var.project_name}-aurora-subnet-group-existing"
  }
}

locals {
  selected_vpc_id               = var.use_existing_vpc ? data.aws_vpc.existing[0].id : module.networking[0].vpc_id
  selected_vpc_cidr             = var.use_existing_vpc ? data.aws_vpc.existing[0].cidr_block : var.vpc_cidr
  selected_private_subnet_ids   = var.use_existing_vpc ? var.existing_private_subnet_ids : module.networking[0].private_subnet_ids
  selected_db_subnet_group_name = var.use_existing_vpc ? aws_db_subnet_group.existing_vpc[0].name : module.networking[0].db_subnet_group_name
}

# ============================================
# Application security group (attach to app tier)
# ============================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application layer"
  vpc_id      = local.selected_vpc_id

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# ============================================
# Security (RDS SG, NACLs, rules)
# ============================================

module "security" {
  source = "./modules/security"

  project_name           = var.project_name
  vpc_id                 = local.selected_vpc_id
  vpc_cidr               = local.selected_vpc_cidr
  private_subnet_ids     = local.selected_private_subnet_ids
  app_security_group_id  = aws_security_group.app.id
  postgres_ingress_cidrs = var.postgres_ingress_cidrs

  depends_on = [module.networking, aws_db_subnet_group.existing_vpc]
}

# ============================================
# Bastion (small EC2 in public subnet; SSM Session Manager)
# ============================================

module "bastion" {
  count  = var.enable_bastion && !var.use_existing_vpc ? 1 : 0
  source = "./modules/bastion"

  project_name              = var.project_name
  vpc_id                    = local.selected_vpc_id
  public_subnet_id          = module.networking[0].public_subnet_ids[0]
  instance_type             = var.bastion_instance_type
  ssh_cidrs                 = var.bastion_ssh_cidrs
  key_name                  = var.bastion_key_name
  install_postgresql_client = var.bastion_install_postgresql_client

  depends_on = [module.networking]
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_bastion" {
  count                        = var.enable_bastion && !var.use_existing_vpc ? 1 : 0
  description                  = "PostgreSQL from bastion host in same VPC"
  security_group_id            = module.security.rds_security_group_id
  referenced_security_group_id = module.bastion[0].security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"

  tags = {
    Name = "${var.project_name}-postgres-from-bastion"
  }

  depends_on = [
    module.security,
    module.bastion,
  ]
}

# ============================================
# Aurora cluster
# ============================================

module "aurora" {
  source = "./modules/aurora_cluster"

  cluster_identifier  = var.aurora_cluster_name
  engine_version      = var.aurora_engine_version
  database_name       = var.database_name
  master_username     = var.master_username
  master_password     = var.master_password
  instance_class      = var.aurora_instance_class
  replica_count       = var.aurora_replica_count
  max_connections     = var.max_connections
  deletion_protection = var.deletion_protection

  db_subnet_group_name   = local.selected_db_subnet_group_name
  subnet_ids             = local.selected_private_subnet_ids
  vpc_security_group_ids = [module.security.rds_security_group_id]
  availability_zones     = var.availability_zones

  storage_encrypted     = var.storage_encrypted
  kms_key_id            = var.kms_key_id
  backup_retention_days = var.backup_retention_days
  backup_window         = var.backup_window
  maintenance_window    = var.maintenance_window

  enable_enhanced_monitoring          = var.enable_enhanced_monitoring
  monitoring_interval                 = var.monitoring_interval
  enable_performance_insights         = var.enable_performance_insights
  performance_insights_retention_days = var.performance_insights_retention_days
  log_retention_days                  = var.cloudwatch_log_retention_days
  skip_final_snapshot                 = var.skip_final_snapshot

  depends_on = [
    module.networking,
    aws_db_subnet_group.existing_vpc,
    module.security
  ]
}

# ============================================
# Monitoring & alarms
# ============================================

module "monitoring" {
  source = "./modules/monitoring"

  cluster_identifier           = var.aurora_cluster_name
  aws_region                   = var.aws_region
  max_connections              = var.max_connections
  connection_threshold_percent = var.connection_threshold_percent
  cpu_threshold_percent        = var.cpu_threshold_percent
  storage_threshold_percent    = var.storage_threshold_percent
  alert_email                  = var.alarm_email

  depends_on = [module.aurora]
}

