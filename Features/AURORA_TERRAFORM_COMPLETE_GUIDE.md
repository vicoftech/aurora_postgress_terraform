# Guía Completa: Aurora PostgreSQL Productivo con Terraform

**Versión**: 1.0  
**Fecha**: 2024  
**Autor**: DevOps Architecture  
**Nivel**: Intermediate to Advanced  
**Tiempo estimado**: 4-6 horas de implementación

---

## Tabla de Contenidos

1. [Arquitectura General](#arquitectura-general)
2. [Prerrequisitos y Setup](#prerrequisitos-y-setup)
3. [Estructura del Proyecto](#estructura-del-proyecto)
4. [Configuración del Backend Remoto](#configuración-del-backend-remoto)
5. [VPC y Networking](#vpc-y-networking)
6. [Security Groups y Firewall](#security-groups-y-firewall)
7. [Cluster Aurora PostgreSQL](#cluster-aurora-postgresql)
8. [Parameter Group y Optimización](#parameter-group-y-optimización)
9. [Snapshots y Backups](#snapshots-y-backups)
10. [Monitoreo y Métricas](#monitoreo-y-métricas)
11. [Alarmas y Notificaciones](#alarmas-y-notificaciones)
12. [Gestión de Credenciales](#gestión-de-credenciales)
13. [IAM Roles y Permisos](#iam-roles-y-permisos)
14. [Encryption y Seguridad](#encryption-y-seguridad)
15. [Performance Insights](#performance-insights)
16. [Despliegue Paso a Paso](#despliegue-paso-a-paso)
17. [Validación y Testing](#validación-y-testing)
18. [Troubleshooting](#troubleshooting)
19. [Mantenimiento Operativo](#mantenimiento-operativo)
20. [Estimación de Costos](#estimación-de-costos)

---

## Arquitectura General

### Diagrama de Alto Nivel

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Account                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                     │  │
│  │                                                          │  │
│  │  ┌────────────────┐           ┌────────────────┐        │  │
│  │  │   AZ: us-west-2a           │  AZ: us-west-2b        │  │
│  │  │                │           │                │        │  │
│  │  │  ┌──────────────────┐      │  ┌────────────────┐    │  │
│  │  │  │ Private Subnet   │      │  │ Private Subnet │    │  │
│  │  │  │ 10.0.1.0/24      │      │  │ 10.0.2.0/24    │    │  │
│  │  │  │                  │      │  │                │    │  │
│  │  │  │  ┌────────────────┐    │  │ ┌────────────────┐  │  │
│  │  │  │  │ Aurora Writer  │    │  │ │ Aurora Reader  │  │  │
│  │  │  │  │ db.t4g.medium  │◄──────►│ db.t4g.medium  │  │  │
│  │  │  │  │ PostgreSQL 15  │    │  │ │ PostgreSQL 15  │  │  │
│  │  │  │  │ Port: 5432     │    │  │ └────────────────┘  │  │
│  │  │  │  └────────────────┘    │  └────────────────┘    │  │
│  │  │  │                        │                  │      │  │
│  │  │  │ SG: rds-sg (5432)      │ (Read Replica)  │      │  │
│  │  │  └──────────────────┘      └────────────────┘      │  │
│  │  │                │           │                │        │  │
│  │  └────────────────┼───────────┼────────────────┘        │  │
│  │                   │ Replication Sync                    │  │
│  └───────────────────┼──────────────────────────────────────┘  │
│                      │                                         │
│  ┌───────────────────┼──────────────────────────────────────┐  │
│  │         Storage Layer                                    │  │
│  │  ┌─────────────────────────────────────────────────┐   │  │
│  │  │  Aurora Storage (Shared, Multi-AZ)               │   │  │
│  │  │  • Automatic replication across AZs             │   │  │
│  │  │  • 6-way mirrored (3 AZs × 2 copies)            │   │  │
│  │  │  • Encryption at rest (KMS)                     │   │  │
│  │  │  • Initial: 40GB (autoscales to 128GB)          │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │          Backup & Monitoring Infrastructure                │  │
│  │                                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │   Snapshots  │  │  CloudWatch  │  │    Logs      │   │  │
│  │  │  (30 days)   │  │   Metrics    │  │  (7 days)    │   │  │
│  │  │              │  │ + Alarms     │  │              │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  │                                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │  Performance │  │ SNS Topics   │  │   IAM Roles  │   │  │
│  │  │  Insights    │  │ (Alertas)    │  │  (Monitoring)│   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │        State Management (Backend Remoto)                   │  │
│  │                                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │  │
│  │  │   S3 Bucket  │  │  DynamoDB    │  │    KMS Key   │   │  │
│  │  │  (State)     │  │  (Lock Table)│  │ (Encryption) │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

```
Aplicación (en EC2/ECS)
    │
    ├─► Writer Endpoint (writer.workium-aurora.us-west-2.rds.amazonaws.com:5432)
    │       │
    │       ▼
    │   [Aurora Writer - db.t4g.medium]
    │       │
    │       ├─► Replicación Síncrona (mismo AZ después, diferente AZ luego)
    │       │
    │       ▼
    │   [Aurora Reader - db.t4g.medium]
    │
    ├─► Reader Endpoint (reader.workium-aurora.us-west-2.rds.amazonaws.com:5432)
    │       │
    │       ▼
    │   [Read Replicas - Load Balancing]
    │
    └─► Storage Layer (Shared, encrypted)
            │
            ├─► Snapshots automáticos (02:00 UTC diarios, 30 días)
            │
            ├─► CloudWatch Logs & Metrics
            │
            └─► Performance Insights
```

---

## Prerrequisitos y Setup

### 1. Requisitos del Entorno Local

```bash
# Verificar instalaciones previas
terraform --version          # >= 1.5.0
aws --version               # >= 2.13.0
psql --version              # >= 12 (para testing)

# Si falta alguno:
# macOS
brew install terraform aws-cli postgresql

# Linux (Debian/Ubuntu)
sudo apt-get install terraform awscli postgresql-client

# Windows (PowerShell con Admin)
choco install terraform awscli postgresql
```

### 2. Configuración AWS CLI

```bash
# Configurar perfil de AWS
aws configure --profile workium-prod

# Ingresar:
# AWS Access Key ID: [TU_KEY]
# AWS Secret Access Key: [TU_SECRET]
# Default region: us-west-2
# Default output format: json

# Validar
aws sts get-caller-identity --profile workium-prod
# Output esperado:
# {
#     "UserId": "AIDAI...",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/victor"
# }
```

### 3. Crear Roles IAM para Terraform (Least Privilege)

```bash
# Crear policy JSON para Terraform
cat > /tmp/terraform_policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds:*",
        "rds-db:*"
      ],
      "Resource": [
        "arn:aws:rds:*:123456789012:cluster/*",
        "arn:aws:rds:*:123456789012:db/*",
        "arn:aws:rds:*:123456789012:pg:*",
        "arn:aws:rds:*:123456789012:subgrp:*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "kms:CreateGrant",
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:*:123456789012:key/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::123456789012:role/rds-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DeleteLogGroup"
      ],
      "Resource": "arn:aws:logs:*:123456789012:log-group:/aws/rds/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms"
      ],
      "Resource": "arn:aws:cloudwatch:*:123456789012:alarm:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::terraform-state-*/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:123456789012:table/terraform-locks"
    }
  ]
}
EOF

# Crear rol
aws iam create-role \
  --role-name terraform-aurora-executor \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:user/victor"
      },
      "Action": "sts:AssumeRole"
    }]
  }' \
  --profile workium-prod

# Adjuntar policy al rol
aws iam put-role-policy \
  --role-name terraform-aurora-executor \
  --policy-name terraform-aurora-inline \
  --policy-document file:///tmp/terraform_policy.json \
  --profile workium-prod
```

### 4. Crear Bucket S3 para Estado (Bootstrap)

```bash
#!/bin/bash
# Script: bootstrap-state-bucket.sh

AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-west-2"
BUCKET_NAME="terraform-state-${AWS_ACCOUNT_ID}-aurora-${AWS_REGION}"

# 1. Crear bucket
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${AWS_REGION}" \
  --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
  --profile workium-prod

# 2. Habilitar versionado
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled \
  --profile workium-prod

# 3. Bloquear acceso público
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --profile workium-prod

# 4. Habilitar encriptación SSE-S3
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }' \
  --profile workium-prod

# 5. Agregar MFA Delete (opcional pero recomendado)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::123456789012:mfa/victor 123456" \
  --profile workium-prod

echo "✓ Bucket creado: ${BUCKET_NAME}"
```

```bash
chmod +x bootstrap-state-bucket.sh
./bootstrap-state-bucket.sh
```

### 5. Crear Tabla DynamoDB para Locks

```bash
#!/bin/bash
# Script: bootstrap-locks-table.sh

AWS_REGION="us-west-2"
TABLE_NAME="terraform-locks"

aws dynamodb create-table \
  --table-name "${TABLE_NAME}" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "${AWS_REGION}" \
  --profile workium-prod

# Esperar a que se cree
aws dynamodb wait table-exists \
  --table-name "${TABLE_NAME}" \
  --region "${AWS_REGION}" \
  --profile workium-prod

# Habilitar encriptación con KMS (recomendado)
aws dynamodb update-table \
  --table-name "${TABLE_NAME}" \
  --sse-specification Enabled=true,SSEType=KMS \
  --region "${AWS_REGION}" \
  --profile workium-prod

echo "✓ Tabla creada: ${TABLE_NAME}"
```

```bash
chmod +x bootstrap-locks-table.sh
./bootstrap-locks-table.sh
```

### 6. Crear KMS Key para Encriptación RDS

```bash
#!/bin/bash
# Script: bootstrap-kms-key.sh

AWS_REGION="us-west-2"
AWS_ACCOUNT_ID="123456789012"

# Crear key
KMS_KEY=$(aws kms create-key \
  --description "KMS key for Aurora RDS encryption" \
  --region "${AWS_REGION}" \
  --profile workium-prod \
  --query 'KeyMetadata.KeyId' \
  --output text)

echo "KMS Key ID: ${KMS_KEY}"

# Crear alias para más fácil referencia
aws kms create-alias \
  --alias-name "alias/workium-aurora-encryption" \
  --target-key-id "${KMS_KEY}" \
  --region "${AWS_REGION}" \
  --profile workium-prod

# Permitir que RDS use la key
aws kms put-key-policy \
  --key-id "${KMS_KEY}" \
  --policy-name default \
  --policy file:///tmp/kms_policy.json \
  --region "${AWS_REGION}" \
  --profile workium-prod

echo "✓ KMS Key configurada: ${KMS_KEY}"
echo "Guardar este ID en variables.tf"
```

```bash
cat > /tmp/kms_policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Id": "key-policy-1",
  "Statement": [
    {
      "Sid": "Enable IAM User Permissions",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "Allow RDS to use the key",
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:CreateGrant",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF
```

---

## Estructura del Proyecto

### Layout de Directorios Recomendado

```
workium-terraform/
│
├── README.md                          # Documentación principal
├── ARCHITECTURE.md                    # Diagrama de arquitectura
├── TROUBLESHOOTING.md                # Guía de troubleshooting
├── .gitignore                        # Ignorar archivos sensibles
│
├── terraform.lock.hcl                # Lock file (versionado)
│
├── environments/
│   ├── prod/
│   │   ├── terraform.tfvars          # Variables de producción
│   │   ├── backend.tf                # Backend remoto
│   │   └── override.tf               # Overrides específicos prod
│   │
│   ├── staging/
│   │   └── terraform.tfvars          # Variables de staging
│   │
│   └── dev/
│       └── terraform.tfvars          # Variables de desarrollo
│
├── modules/
│   ├── aurora_cluster/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   │
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   │
│   ├── monitoring/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   │
│   └── security/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── README.md
│
├── main.tf                           # Configuración principal
├── variables.tf                      # Variables globales
├── outputs.tf                        # Outputs globales
├── versions.tf                       # Versiones de providers
│
├── scripts/
│   ├── bootstrap.sh                 # Script de bootstrap
│   ├── init.sh                      # Script de inicialización
│   ├── validate.sh                  # Script de validación
│   ├── test-connection.sh           # Script de test de conexión
│   └── cleanup.sh                   # Script de limpieza
│
├── docs/
│   ├── DEPLOYMENT.md                # Guía de despliegue
│   ├── BACKUP_RECOVERY.md           # Guía de backups
│   ├── MONITORING.md                # Guía de monitoreo
│   └── SCALING.md                   # Guía de escalado
│
└── .terraform/                       # (Generado por Terraform, no versionar)
    ├── modules/
    ├── providers/
    └── terraform.tfstate.d/
```

### Archivos Base (Nivel Raíz)

#### 1. `versions.tf` - Versionamiento de Providers

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
    }
  }

  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.terraform_role}"
  }
}

provider "random" {}
```

#### 2. `variables.tf` - Variables Globales

```hcl
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
  description = "IAM role name for Terraform to assume"
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
  default     = "15.3"

  validation {
    condition     = can(regex("^[0-9]{2}\\.[0-9]$", var.aurora_engine_version))
    error_message = "Engine version must be in format XX.X"
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
  description = "Email for alarm notifications"
  type        = string
  sensitive   = true
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

# ============================================
# Tags
# ============================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Team      = "platform"
    Compliance = "pci-dss"
  }
}
```

#### 3. `outputs.tf` - Outputs Principales

```hcl
# ============================================
# Cluster Endpoints
# ============================================

output "cluster_endpoint" {
  description = "Aurora cluster endpoint (write)"
  value       = aws_rds_cluster.aurora.endpoint
  sensitive   = false
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster read endpoint"
  value       = aws_rds_cluster.aurora.reader_endpoint
  sensitive   = false
}

output "cluster_resource_id" {
  description = "Aurora cluster resource ID"
  value       = aws_rds_cluster.aurora.cluster_resource_id
  sensitive   = false
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.aurora.cluster_identifier
  sensitive   = false
}

# ============================================
# Instance Details
# ============================================

output "writer_instance_id" {
  description = "Writer instance ID"
  value       = aws_rds_cluster_instance.writer.id
  sensitive   = false
}

output "reader_instances" {
  description = "Reader instance IDs"
  value = {
    for k, v in aws_rds_cluster_instance.readers : k => v.id
  }
  sensitive = false
}

output "all_instance_endpoints" {
  description = "All instance endpoints (host:port)"
  value = merge(
    { writer = "${aws_rds_cluster_instance.writer.endpoint}:5432" },
    { for k, v in aws_rds_cluster_instance.readers : "reader_${k}" => "${v.endpoint}:5432" }
  )
  sensitive = false
}

# ============================================
# Database Configuration
# ============================================

output "database_name" {
  description = "Database name"
  value       = aws_rds_cluster.aurora.database_name
  sensitive   = false
}

output "database_port" {
  description = "Database port"
  value       = aws_rds_cluster.aurora.port
  sensitive   = false
}

output "master_username" {
  description = "Database master username"
  value       = aws_rds_cluster.aurora.master_username
  sensitive   = true
}

output "engine_version" {
  description = "Aurora PostgreSQL engine version"
  value       = aws_rds_cluster.aurora.engine_version
  sensitive   = false
}

# ============================================
# Security Configuration
# ============================================

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
  sensitive   = false
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.aurora.name
  sensitive   = false
}

# ============================================
# Monitoring and Backup
# ============================================

output "enhanced_monitoring_role_arn" {
  description = "IAM role for enhanced monitoring"
  value       = aws_iam_role.rds_monitoring.arn
  sensitive   = false
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.postgresql.name
  sensitive   = false
}

output "performance_insights_enabled" {
  description = "Performance Insights status"
  value       = aws_rds_cluster.aurora.enable_performance_insights
  sensitive   = false
}

# ============================================
# Networking
# ============================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
  sensitive   = false
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
  sensitive   = false
}

# ============================================
# Connection String Templates
# ============================================

output "connection_string_template" {
  description = "Template for connection string"
  value = "postgresql://<username>:<password>@${aws_rds_cluster.aurora.endpoint}:5432/${aws_rds_cluster.aurora.database_name}?sslmode=require"
  sensitive   = false
}

output "read_connection_string_template" {
  description = "Template for read connection string"
  value = "postgresql://<username>:<password>@${aws_rds_cluster.aurora.reader_endpoint}:5432/${aws_rds_cluster.aurora.database_name}?sslmode=require"
  sensitive   = false
}

# ============================================
# Terraform State Information
# ============================================

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  value       = "terraform-state-${var.aws_account_id}-aurora-${var.aws_region}"
  sensitive   = false
}

output "terraform_locks_table" {
  description = "DynamoDB table for Terraform locks"
  value       = "terraform-locks"
  sensitive   = false
}

# ============================================
# Useful Information for Operations
# ============================================

output "next_steps" {
  description = "Next steps for using the Aurora cluster"
  value = <<-EOT
    Aurora PostgreSQL cluster is now running!

    1. Test the connection:
       psql -h ${aws_rds_cluster.aurora.endpoint} -U postgres -d ${aws_rds_cluster.aurora.database_name}

    2. Query endpoints:
       Write: ${aws_rds_cluster.aurora.endpoint}
       Read:  ${aws_rds_cluster.aurora.reader_endpoint}

    3. View CloudWatch logs:
       aws logs tail /aws/rds/cluster/${aws_rds_cluster.aurora.cluster_identifier} --follow

    4. Check Performance Insights:
       AWS Console > RDS > Databases > ${aws_rds_cluster.aurora.cluster_identifier} > Performance Insights

    5. View alarms:
       AWS Console > CloudWatch > Alarms
  EOT
}
```

---

## Configuración del Backend Remoto

### `environments/prod/backend.tf`

```hcl
# ============================================
# Terraform Backend Configuration
# ============================================

terraform {
  backend "s3" {
    # S3 bucket for state storage
    bucket         = "terraform-state-123456789012-aurora-us-west-2"
    key            = "aurora/prod/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true

    # DynamoDB table for state locking
    dynamodb_table = "terraform-locks"

    # Additional security settings
    skip_credentials_validation = false
    skip_metadata_api_check     = false

    # Retry logic for transient failures
    max_retries = 5
  }
}

# Note: El backend se configura durante 'terraform init':
#
# terraform init \
#   -backend-config="bucket=terraform-state-123456789012-aurora-us-west-2" \
#   -backend-config="key=aurora/prod/terraform.tfstate" \
#   -backend-config="region=us-west-2" \
#   -backend-config="dynamodb_table=terraform-locks" \
#   -backend-config="encrypt=true"
```

### Inicialización del Backend

```bash
#!/bin/bash
# Script: scripts/init.sh

set -e

ENVIRONMENT=${1:-prod}
AWS_REGION=${2:-us-west-2}
AWS_ACCOUNT_ID=${3:-123456789012}

BUCKET_NAME="terraform-state-${AWS_ACCOUNT_ID}-aurora-${AWS_REGION}"
LOCKS_TABLE="terraform-locks"
STATE_KEY="aurora/${ENVIRONMENT}/terraform.tfstate"

echo "================================"
echo "Terraform Backend Initialization"
echo "================================"
echo "Environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"
echo "Bucket: ${BUCKET_NAME}"
echo "State Key: ${STATE_KEY}"
echo ""

# Verificar que el bucket existe
echo "✓ Validating S3 bucket..."
if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
    echo "✗ Bucket does not exist: ${BUCKET_NAME}"
    exit 1
fi

# Verificar que la tabla DynamoDB existe
echo "✓ Validating DynamoDB table..."
if ! aws dynamodb describe-table --table-name "${LOCKS_TABLE}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "✗ Table does not exist: ${LOCKS_TABLE}"
    exit 1
fi

# Inicializar Terraform
echo "✓ Initializing Terraform..."
terraform init \
    -backend-config="bucket=${BUCKET_NAME}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="dynamodb_table=${LOCKS_TABLE}" \
    -backend-config="encrypt=true" \
    -reconfigure

echo ""
echo "✓ Backend initialization complete!"
echo ""
echo "Current state files in bucket:"
aws s3 ls "s3://${BUCKET_NAME}/" --recursive | head -20

echo ""
echo "To view state:"
echo "  aws s3api get-object --bucket ${BUCKET_NAME} --key ${STATE_KEY} /dev/stdout | jq"
```

### Manejo del Estado Local (para Testing)

```bash
# Para desarrollo local, usar backend local:
terraform init -reconfigure -backend=false

# O usar backend local con archivo:
cat > .terraform/terraform.tfstate << 'EOF'
{
  "version": 4,
  "terraform_version": "1.5.0",
  "serial": 0,
  "lineage": "local-testing",
  "outputs": {},
  "resources": []
}
EOF
```

---

## VPC y Networking

### `modules/networking/main.tf`

```hcl
# ============================================
# VPC
# ============================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ============================================
# Internet Gateway
# ============================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ============================================
# Private Subnets para Aurora
# ============================================

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
    Type = "Private"
  }
}

# ============================================
# Elastic IP para NAT
# ============================================

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================
# NAT Gateway (para outbound traffic desde RDS)
# ============================================

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private[0].id

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ============================================
# Route Table para Subnets Privadas
# ============================================

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# ============================================
# Route Table Association
# ============================================

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ============================================
# DB Subnet Group
# ============================================

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-aurora-subnet-group"
  }
}

# ============================================
# Flow Logs (para debugging de conectividad)
# ============================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${var.project_name}-aurora"
  retention_in_days = 7

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${var.project_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${var.project_name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-vpc-flow-logs"
  }
}
```

### `modules/networking/outputs.tf`

```hcl
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.aurora.name
}

output "nat_gateway_ip" {
  description = "NAT Gateway Elastic IP"
  value       = aws_eip.nat.public_ip
}
```

---

## Security Groups y Firewall

### `modules/security/main.tf`

```hcl
# ============================================
# Security Group para RDS Aurora
# ============================================

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for Aurora RDS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# Ingress Rule: PostgreSQL from App Security Group
# ============================================

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_app" {
  description = "PostgreSQL access from application layer"

  security_group_id = aws_security_group.rds.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  # Referencing another security group (más seguro que CIDR)
  referenced_security_group_id = var.app_security_group_id

  tags = {
    Name = "PostgreSQL from App"
  }
}

# ============================================
# Ingress Rule: PostgreSQL from RDS itself (replicación)
# ============================================

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_rds" {
  description = "PostgreSQL replication from other RDS nodes"

  security_group_id = aws_security_group.rds.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  self = true

  tags = {
    Name = "PostgreSQL from RDS"
  }
}

# ============================================
# Egress Rules for RDS
# ============================================

# DNS Resolution (necesario para conectar a AWS services)
resource "aws_vpc_security_group_egress_rule" "dns" {
  description = "DNS resolution"

  security_group_id = aws_security_group.rds.id

  from_port   = 53
  to_port     = 53
  ip_protocol = "udp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "DNS"
  }
}

# NTP (Network Time Protocol - importante para logs y auditoría)
resource "aws_vpc_security_group_egress_rule" "ntp" {
  description = "NTP for time synchronization"

  security_group_id = aws_security_group.rds.id

  from_port   = 123
  to_port     = 123
  ip_protocol = "udp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "NTP"
  }
}

# HTTPS para conectar a AWS Secrets Manager y otros servicios
resource "aws_vpc_security_group_egress_rule" "https" {
  description = "HTTPS for AWS service communication"

  security_group_id = aws_security_group.rds.id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"

  tags = {
    Name = "HTTPS"
  }
}

# ============================================
# Security Group para Aplicaciones
# ============================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application servers"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# Permitir que la app pueda hablar con RDS
resource "aws_vpc_security_group_egress_rule" "app_to_rds" {
  description = "Allow app to connect to RDS"

  security_group_id = aws_security_group.app.id

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  referenced_security_group_id = aws_security_group.rds.id

  tags = {
    Name = "To RDS PostgreSQL"
  }
}

# ============================================
# Network ACLs (Opcional - para control adicional)
# ============================================

resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-private-nacl"
  }

  # Inbound: Ephemeral ports desde VPC
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5432
    to_port    = 5432
  }

  # Outbound: Todo hacia VPC
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}
```

### `modules/security/outputs.tf`

```hcl
output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "app_security_group_id" {
  description = "App security group ID"
  value       = aws_security_group.app.id
}
```

---

## Cluster Aurora PostgreSQL

### `modules/aurora_cluster/main.tf` - Parte 1: Cluster

```hcl
# ============================================
# Aurora Cluster
# ============================================

resource "aws_rds_cluster" "aurora" {
  # Identificación
  cluster_identifier              = var.cluster_identifier
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = var.master_password
  
  # Networking
  db_subnet_group_name            = var.db_subnet_group_name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = var.vpc_security_group_ids

  # Availability & Durability
  availability_zones = var.availability_zones
  multi_az           = true
  port               = 5432

  # Storage & Backup
  storage_encrypted           = var.storage_encrypted
  kms_key_id                  = var.kms_key_id
  backup_retention_period     = var.backup_retention_days
  preferred_backup_window     = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot       = true

  # Backup policy para snapshots
  skip_final_snapshot           = false
  final_snapshot_identifier     = "${var.cluster_identifier}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  deletion_protection           = var.deletion_protection

  # Enhanced Backup (PITR)
  backtrack_window = 7

  # Performance & Monitoring
  enable_cloudwatch_logs_exports = ["postgresql"]
  enable_http_endpoint           = false
  enable_iam_database_authentication = true

  # Performance Insights
  enable_performance_insights          = var.enable_performance_insights
  performance_insights_kms_key_id      = var.kms_key_id
  performance_insights_retention_period = var.performance_insights_retention_days

  # Enhanced Monitoring
  enable_enhanced_monitoring  = var.enable_enhanced_monitoring
  monitoring_interval        = var.monitoring_interval
  monitoring_role_arn       = aws_iam_role.rds_monitoring.arn

  # Logs
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Global Database (opcional para DR)
  # global_write_forwarding_enabled = false

  # Additional Options
  apply_immediately = false
  auto_minor_version_upgrade = true

  tags = {
    Name = var.cluster_identifier
  }

  depends_on = [
    aws_db_subnet_group.aurora,
    aws_rds_cluster_parameter_group.aurora,
    aws_iam_role.rds_monitoring
  ]
}

# ============================================
# DB Subnet Group
# ============================================

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.cluster_identifier}-subnet-group"
  }
}

# ============================================
# Cluster Parameter Group
# ============================================

resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.cluster_identifier}-params"
  family      = "aurora-postgresql15"
  description = "Cluster parameter group for ${var.cluster_identifier}"

  # Conexiones
  parameter {
    name  = "max_connections"
    value = var.max_connections
  }

  # Logging
  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_duration"
    value = "true"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # Log queries > 1 segundo
  }

  parameter {
    name  = "log_line_prefix"
    value = "%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h "
  }

  # Replicación Lógica (si se necesita CDC)
  parameter {
    name  = "rds.logical_replication"
    value = "1"
  }

  # pg_stat_statements (para performance analysis)
  parameter {
    name         = "shared_preload_libraries"
    value        = "pgaudit,pg_stat_statements,pgpartman"
    apply_method = "cluster-immediate"
  }

  # Performance
  parameter {
    name  = "work_mem"
    value = "16384" # 16MB por operación
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "262144" # 256MB para VACUUM, CREATE INDEX
  }

  # WAL (Write-Ahead Logging)
  parameter {
    name  = "wal_buffers"
    value = "16384" # 16MB (máximo)
  }

  # Checkpoint tuning
  parameter {
    name  = "checkpoint_completion_target"
    value = "0.9" # Spread checkpoints over 90% of interval
  }

  # Query Planning
  parameter {
    name  = "random_page_cost"
    value = "1.1" # Aurora usa SSD, no HDD
  }

  # Conexión Timeout
  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = "300000" # 5 minutos
  }

  tags = {
    Name = "${var.cluster_identifier}-params"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# IAM Role para Enhanced Monitoring
# ============================================

resource "aws_iam_role" "rds_monitoring" {
  name               = "${var.cluster_identifier}-monitoring-role"
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

# Adjuntar política de monitoreo
resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================
# CloudWatch Log Group para PostgreSQL Logs
# ============================================

resource "aws_cloudwatch_log_group" "postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.cluster_identifier}-postgresql-logs"
  }
}

# Log stream para DDL (crear cuando se necesite)
resource "aws_cloudwatch_log_stream" "postgresql_ddl" {
  name           = "ddl"
  log_group_name = aws_cloudwatch_log_group.postgresql.name
}
```

### `modules/aurora_cluster/main.tf` - Parte 2: Instancias

```hcl
# ============================================
# Aurora Cluster Instance - Writer
# ============================================

resource "aws_rds_cluster_instance" "writer" {
  identifier             = "${var.cluster_identifier}-writer"
  cluster_identifier     = aws_rds_cluster.aurora.id
  instance_class         = var.instance_class
  engine                 = aws_rds_cluster.aurora.engine
  engine_version         = aws_rds_cluster.aurora.engine_version
  publicly_accessible    = false

  # Performance & Monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_kms_key_id = var.kms_key_id
  monitoring_interval            = var.monitoring_interval
  monitoring_role_arn            = aws_iam_role.rds_monitoring.arn

  # Availability
  auto_minor_version_upgrade = true
  availability_zone          = var.availability_zones[0]

  # Promotion Tier (0 = prioritario para promover a writer)
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

# ============================================
# Aurora Cluster Instances - Readers (Replicas)
# ============================================

resource "aws_rds_cluster_instance" "readers" {
  count = var.replica_count

  identifier         = "${var.cluster_identifier}-reader-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false

  # Performance & Monitoring
  performance_insights_enabled    = var.enable_performance_insights
  performance_insights_kms_key_id = var.kms_key_id
  monitoring_interval            = var.monitoring_interval
  monitoring_role_arn            = aws_iam_role.rds_monitoring.arn

  # Availability
  auto_minor_version_upgrade = true
  availability_zone          = var.availability_zones[count.index % length(var.availability_zones)]

  # Promotion Tier (número más alto = menos prioritario)
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
```

### `modules/aurora_cluster/variables.tf`

```hcl
variable "cluster_identifier" {
  description = "Cluster identifier"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.3"
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
  description = "DB subnet group name"
  type        = string
}

variable "vpc_security_group_ids" {
  description = "VPC security group IDs"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subnet IDs for cluster"
  type        = list(string)
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
  description = "Number of read replicas"
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
  description = "Enable enhanced monitoring"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Monitoring interval (seconds)"
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
```

### `modules/aurora_cluster/outputs.tf`

```hcl
output "cluster_id" {
  value = aws_rds_cluster.aurora.id
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

output "writer_endpoint" {
  value = aws_rds_cluster_instance.writer.endpoint
}

output "reader_endpoints" {
  value = aws_rds_cluster_instance.readers[*].endpoint
}

output "monitoring_role_arn" {
  value = aws_iam_role.rds_monitoring.arn
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.postgresql.name
}
```

---

## Monitoreo y Métricas

### `modules/monitoring/main.tf`

```hcl
# ============================================
# CloudWatch Alarms - Conexiones
# ============================================

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.cluster_identifier}-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300 # 5 minutos
  statistic           = "Average"
  threshold           = var.max_connections * (var.connection_threshold_percent / 100)
  alarm_description   = "Alert when database connections exceed ${var.connection_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# CloudWatch Alarms - CPU
# ============================================

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.cluster_identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold_percent
  alarm_description   = "Alert when CPU utilization exceeds ${var.cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# CloudWatch Alarms - Storage
# ============================================

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  alarm_name          = "${var.cluster_identifier}-low-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 600 # 10 minutos
  statistic           = "Average"
  threshold           = 10737418240 # 10GB in bytes
  alarm_description   = "Alert when free storage is below 10GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# CloudWatch Alarms - Replication Lag
# ============================================

resource "aws_cloudwatch_metric_alarm" "replica_lag" {
  alarm_name          = "${var.cluster_identifier}-high-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraBinlogReplicaLag"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 100 # 100 ms
  alarm_description   = "Alert when replica lag exceeds 100ms"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# CloudWatch Alarms - Database Load
# ============================================

resource "aws_cloudwatch_metric_alarm" "database_load" {
  alarm_name          = "${var.cluster_identifier}-high-db-load"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseLoad"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 4 # Número de cores en db.t4g.medium
  alarm_description   = "Alert when database load exceeds number of vCPUs"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# CloudWatch Alarms - Failover Events
# ============================================

resource "aws_cloudwatch_metric_alarm" "failover_event" {
  alarm_name          = "${var.cluster_identifier}-failover-event"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "FailoverLatency"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alert on failover event"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = var.cluster_identifier
  }
}

# ============================================
# SNS Topic para Alertas
# ============================================

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

# ============================================
# CloudWatch Dashboard
# ============================================

resource "aws_cloudwatch_dashboard" "aurora" {
  dashboard_name = "${var.cluster_identifier}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", { stat = "Average" }],
            [".", "CPUUtilization", { stat = "Average" }],
            [".", "FreeStorageSpace", { stat = "Average" }],
            [".", "DatabaseLoad", { stat = "Average" }],
            [".", "DiskQueueDepth", { stat = "Average" }],
            [".", "NetworkReceiveThroughput", { stat = "Average" }],
            [".", "NetworkTransmitThroughput", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Aurora Cluster Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "ReadLatency"],
            [".", "WriteLatency"],
            [".", "CommitLatency"]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Database Latency (ms)"
        }
      },
      {
        type = "log"
        properties = {
          query   = "fields @timestamp, @message | filter @message like /ERROR/ | stats count() by bin(5m)"
          region  = var.aws_region
          title   = "PostgreSQL Errors"
        }
      }
    ]
  })
}

# ============================================
# Event Subscription para RDS
# ============================================

resource "aws_db_event_subscription" "aurora" {
  name        = "${var.cluster_identifier}-events"
  sns_topic   = aws_sns_topic.alerts.arn
  source_type = "cluster"

  event_categories = [
    "availability",
    "backup",
    "configuration",
    "creation",
    "deletion",
    "failover",
    "failure",
    "maintenance",
    "notification",
    "recovery"
  ]

  source_ids = [var.cluster_identifier]
  enabled    = true

  tags = {
    Name = "${var.cluster_identifier}-events"
  }
}
```

### `modules/monitoring/variables.tf`

```hcl
variable "cluster_identifier" {
  description = "Cluster identifier"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "max_connections" {
  description = "Maximum connections"
  type        = number
}

variable "connection_threshold_percent" {
  description = "Connection alarm threshold (%)"
  type        = number
  default     = 80
}

variable "cpu_threshold_percent" {
  description = "CPU alarm threshold (%)"
  type        = number
  default     = 75
}

variable "storage_threshold_percent" {
  description = "Storage alarm threshold (%)"
  type        = number
  default     = 80
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  sensitive   = true
}
```

---

## Despliegue Paso a Paso

### `scripts/init.sh` - Inicialización

```bash
#!/bin/bash

set -euo pipefail

# Colors para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Configuración
# ============================================

ENVIRONMENT=${1:-prod}
AWS_REGION=${2:-us-west-2}
AWS_PROFILE=${3:-workium-prod}

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile ${AWS_PROFILE})
BUCKET_NAME="terraform-state-${ACCOUNT_ID}-aurora-${AWS_REGION}"
LOCKS_TABLE="terraform-locks"
STATE_KEY="aurora/${ENVIRONMENT}/terraform.tfstate"

# ============================================
# Funciones
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# ============================================
# Validaciones Previas
# ============================================

log_info "Starting Terraform initialization..."
log_info "Environment: ${ENVIRONMENT}"
log_info "Region: ${AWS_REGION}"
log_info "Account: ${ACCOUNT_ID}"
echo ""

# Verificar AWS CLI
log_info "Checking AWS CLI..."
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed"
    exit 1
fi
log_success "AWS CLI found: $(aws --version)"

# Verificar Terraform
log_info "Checking Terraform..."
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed"
    exit 1
fi
log_success "Terraform found: $(terraform --version | head -n 1)"

# Verificar jq
log_info "Checking jq..."
if ! command -v jq &> /dev/null; then
    log_warning "jq is not installed (optional)"
else
    log_success "jq found"
fi

# Validar credenciales AWS
log_info "Validating AWS credentials..."
if ! aws sts get-caller-identity --profile ${AWS_PROFILE} &> /dev/null; then
    log_error "Cannot authenticate with AWS profile: ${AWS_PROFILE}"
    exit 1
fi
log_success "AWS credentials valid"

# ============================================
# Verificar Backend Bucket
# ============================================

echo ""
log_info "Validating backend infrastructure..."

if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" --profile ${AWS_PROFILE} 2>/dev/null; then
    log_error "S3 bucket does not exist: ${BUCKET_NAME}"
    log_warning "Please run: ./scripts/bootstrap.sh"
    exit 1
fi
log_success "S3 bucket exists: ${BUCKET_NAME}"

if ! aws dynamodb describe-table --table-name "${LOCKS_TABLE}" --region "${AWS_REGION}" --profile ${AWS_PROFILE} &> /dev/null; then
    log_error "DynamoDB locks table does not exist: ${LOCKS_TABLE}"
    log_warning "Please run: ./scripts/bootstrap.sh"
    exit 1
fi
log_success "DynamoDB locks table exists: ${LOCKS_TABLE}"

# ============================================
# Inicializar Terraform
# ============================================

echo ""
log_info "Initializing Terraform backend..."

terraform init \
    -upgrade \
    -backend-config="bucket=${BUCKET_NAME}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="dynamodb_table=${LOCKS_TABLE}" \
    -backend-config="encrypt=true" \
    -reconfigure

if [ $? -eq 0 ]; then
    log_success "Terraform initialized successfully"
else
    log_error "Terraform initialization failed"
    exit 1
fi

# ============================================
# Listar estado remoto existente
# ============================================

echo ""
log_info "Checking existing state files..."

STATE_FILES=$(aws s3api list-objects-v2 \
    --bucket "${BUCKET_NAME}" \
    --prefix "aurora/" \
    --region "${AWS_REGION}" \
    --profile ${AWS_PROFILE} \
    --query 'Contents[].Key' \
    --output text)

if [ -z "$STATE_FILES" ]; then
    log_warning "No existing state files found (fresh deployment)"
else
    log_info "Existing state files:"
    echo "$STATE_FILES" | tr ' ' '\n' | sed 's/^/  /'
fi

# ============================================
# Resumen Final
# ============================================

echo ""
echo -e "${GREEN}================================${NC}"
log_success "Initialization complete!"
echo -e "${GREEN}================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Review your configuration:"
echo "     terraform validate"
echo ""
echo "  2. Plan the deployment:"
echo "     terraform plan -var-file=environments/${ENVIRONMENT}/terraform.tfvars -out=tfplan"
echo ""
echo "  3. Apply the changes:"
echo "     terraform apply tfplan"
echo ""
echo "Environment files:"
echo "  - Configuration: environments/${ENVIRONMENT}/"
echo "  - Variables: environments/${ENVIRONMENT}/terraform.tfvars"
echo "  - Backend: environments/${ENVIRONMENT}/backend.tf"
echo ""
echo "For more information:"
echo "  - Documentation: ./docs/DEPLOYMENT.md"
echo "  - Troubleshooting: ./docs/TROUBLESHOOTING.md"
echo ""
```

### `scripts/validate.sh` - Validación

```bash
#!/bin/bash

set -euo pipefail

echo "🔍 Validating Terraform configuration..."
echo ""

# Validar sintaxis
echo "Step 1: Checking Terraform syntax..."
terraform fmt -recursive -check . || {
    echo "⚠️  Some files need formatting. Run: terraform fmt -recursive ."
}

terraform validate

# Validar modulos
echo ""
echo "Step 2: Validating modules..."
for module in modules/*/; do
    echo "  - $(basename $module)"
    terraform validate "$module"
done

# Terraform security scan (opcional con tfsec)
if command -v tfsec &> /dev/null; then
    echo ""
    echo "Step 3: Running security scan with tfsec..."
    tfsec . --minimum-severity WARNING || true
fi

# Terraform best practices (opcional con terraform-compliance)
if command -v terraform-compliance &> /dev/null; then
    echo ""
    echo "Step 4: Checking best practices..."
    terraform-compliance -p . || true
fi

echo ""
echo "✅ Validation complete!"
```

### `scripts/plan.sh` - Plan de Cambios

```bash
#!/bin/bash

set -euo pipefail

ENVIRONMENT=${1:-prod}
PLANFILE="tfplan-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"

echo "📋 Planning Terraform changes..."
echo "Environment: ${ENVIRONMENT}"
echo "Plan file: ${PLANFILE}"
echo ""

terraform plan \
    -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
    -out="${PLANFILE}" \
    -detailed-exitcode

EXITCODE=$?

case $EXITCODE in
    0)
        echo "✅ Plan: No changes needed"
        ;;
    1)
        echo "❌ Plan: Error during planning"
        exit 1
        ;;
    2)
        echo "📝 Plan: Changes planned (file: ${PLANFILE})"
        echo ""
        echo "Next step:"
        echo "  terraform apply ${PLANFILE}"
        ;;
esac

exit 0
```

### `scripts/apply.sh` - Aplicar Cambios

```bash
#!/bin/bash

set -euo pipefail

PLANFILE=${1:-tfplan}
ENVIRONMENT=${2:-prod}

if [ ! -f "${PLANFILE}" ]; then
    echo "❌ Plan file not found: ${PLANFILE}"
    exit 1
fi

echo "🚀 Applying Terraform plan..."
echo "Plan: ${PLANFILE}"
echo "Environment: ${ENVIRONMENT}"
echo ""

read -p "Are you sure you want to apply these changes? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

terraform apply "${PLANFILE}"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Apply complete!"
    echo ""
    echo "Getting outputs..."
    terraform output
else
    echo "❌ Apply failed"
    exit 1
fi
```

### `main.tf` - Configuración Principal

```hcl
# ============================================
# Terraform Principal Configuration
# ============================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
  }

  # Backend será configurado durante init
  # backend "s3" {
  #   bucket         = "terraform-state-..."
  #   key            = "aurora/..."
  #   region         = "us-west-2"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
      CreatedAt   = timestamp()
      CostCenter  = var.cost_center
    }
  }
}

# ============================================
# Módulo de Networking
# ============================================

module "networking" {
  source = "./modules/networking"

  project_name          = var.project_name
  vpc_cidr              = var.vpc_cidr
  private_subnet_cidrs  = var.private_subnet_cidrs
  availability_zones    = var.availability_zones
  aws_region            = var.aws_region
}

# ============================================
# Módulo de Security
# ============================================

module "security" {
  source = "./modules/security"

  project_name            = var.project_name
  vpc_id                  = module.networking.vpc_id
  private_subnet_ids      = module.networking.private_subnet_ids
  app_security_group_id   = aws_security_group.app.id

  depends_on = [module.networking]
}

# ============================================
# Módulo Aurora Cluster
# ============================================

module "aurora" {
  source = "./modules/aurora_cluster"

  cluster_identifier      = var.aurora_cluster_name
  engine_version          = var.aurora_engine_version
  database_name           = var.database_name
  master_username         = var.master_username
  master_password         = random_password.db_password.result
  instance_class          = var.aurora_instance_class
  replica_count           = var.aurora_replica_count
  max_connections         = var.max_connections

  db_subnet_group_name    = module.networking.db_subnet_group_name
  subnet_ids              = module.networking.private_subnet_ids
  vpc_security_group_ids  = [module.security.rds_security_group_id]
  availability_zones      = var.availability_zones

  storage_encrypted       = var.storage_encrypted
  kms_key_id              = var.kms_key_id
  backup_retention_days   = var.backup_retention_days
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  enable_enhanced_monitoring              = var.enable_enhanced_monitoring
  monitoring_interval                     = var.monitoring_interval
  enable_performance_insights             = var.enable_performance_insights
  performance_insights_retention_days     = var.performance_insights_retention_days
  log_retention_days                      = var.cloudwatch_log_retention_days

  depends_on = [
    module.networking,
    module.security
  ]
}

# ============================================
# Módulo de Monitoring
# ============================================

module "monitoring" {
  source = "./modules/monitoring"

  cluster_identifier         = var.aurora_cluster_name
  aws_region                 = var.aws_region
  max_connections            = var.max_connections
  connection_threshold_percent = var.connection_threshold_percent
  cpu_threshold_percent      = var.cpu_threshold_percent
  storage_threshold_percent  = var.storage_threshold_percent
  alert_email                = var.alarm_email

  depends_on = [module.aurora]
}

# ============================================
# Generador de Contraseña Aleatoria
# ============================================

resource "random_password" "db_password" {
  length  = 32
  special = true

  # Excluir caracteres que pueden causar problemas en URLs
  override_special = "!&#$^<>-"
}

# ============================================
# Security Group para Aplicaciones
# (Referenciado por el módulo security)
# ============================================

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application layer"
  vpc_id      = module.networking.vpc_id

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# ============================================
# Data Source para obtener VPC actual
# (Para validaciones)
# ============================================

data "aws_vpc" "main" {
  id = module.networking.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [module.networking.vpc_id]
  }

  filter {
    name   = "tag:Type"
    values = ["Private"]
  }
}
```

---

## Archivo de Variables - Producción

### `environments/prod/terraform.tfvars`

```hcl
# ============================================
# AWS Configuration
# ============================================

aws_region      = "us-west-2"
aws_account_id  = "123456789012"
terraform_role  = "terraform-aurora-executor"

# ============================================
# Project Configuration
# ============================================

project_name = "workium"
environment  = "prod"
cost_center  = "engineering"

# ============================================
# VPC Configuration
# ============================================

vpc_cidr             = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
availability_zones   = ["us-west-2a", "us-west-2b"]

# ============================================
# Aurora Configuration
# ============================================

aurora_cluster_name  = "workium-aurora-prod"
aurora_engine_version = "15.3"
aurora_instance_class = "db.t4g.medium"
aurora_replica_count = 1

database_name   = "workium_db"
master_username = "postgres"
max_connections = 100

# ============================================
# Backup Configuration
# ============================================

backup_retention_days = 30
backup_window        = "02:00-03:00"
maintenance_window   = "sun:03:00-sun:04:00"

# ============================================
# Monitoring Configuration
# ============================================

enable_enhanced_monitoring           = true
monitoring_interval                  = 60
enable_performance_insights          = true
performance_insights_retention_days  = 7
cloudwatch_log_retention_days        = 7

# ============================================
# Encryption Configuration
# ============================================

kms_key_id       = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
storage_encrypted = true

# ============================================
# Alerting Configuration
# ============================================

alarm_email                = "devops@example.com"
connection_threshold_percent = 80
cpu_threshold_percent      = 75
storage_threshold_percent  = 80

# ============================================
# Additional Tags
# ============================================

additional_tags = {
  Team       = "platform"
  Compliance = "pci-dss"
  CostCenter = "engineering"
  Owner      = "devops-team"
}
```

---

## Validación y Testing

### `scripts/test-connection.sh` - Test de Conexión

```bash
#!/bin/bash

set -euo pipefail

echo "🧪 Testing Aurora PostgreSQL Connection..."
echo ""

# Obtener outputs de Terraform
CLUSTER_ENDPOINT=$(terraform output -raw cluster_endpoint)
READER_ENDPOINT=$(terraform output -raw cluster_reader_endpoint)
DATABASE_NAME=$(terraform output -raw database_name)
MASTER_USERNAME=$(terraform output -raw master_username)

echo "Cluster Endpoint: ${CLUSTER_ENDPOINT}"
echo "Reader Endpoint: ${READER_ENDPOINT}"
echo "Database: ${DATABASE_NAME}"
echo ""

# Solicitar contraseña
echo -n "Enter database password: "
read -s DB_PASSWORD
echo ""

# Test 1: Conexión al Writer
echo ""
echo "Test 1: Connecting to Writer (${CLUSTER_ENDPOINT})..."
if psql -h "${CLUSTER_ENDPOINT}" \
        -U "${MASTER_USERNAME}" \
        -d "${DATABASE_NAME}" \
        -c "SELECT version();" \
        <<< "${DB_PASSWORD}" 2>/dev/null; then
    echo "✅ Writer connection successful"
else
    echo "❌ Writer connection failed"
    exit 1
fi

# Test 2: Conexión al Reader
echo ""
echo "Test 2: Connecting to Reader (${READER_ENDPOINT})..."
if psql -h "${READER_ENDPOINT}" \
        -U "${MASTER_USERNAME}" \
        -d "${DATABASE_NAME}" \
        -c "SELECT version();" \
        <<< "${DB_PASSWORD}" 2>/dev/null; then
    echo "✅ Reader connection successful"
else
    echo "❌ Reader connection failed (may be expected if no read replicas)"
fi

# Test 3: Check instance roles
echo ""
echo "Test 3: Checking instance roles..."
psql -h "${CLUSTER_ENDPOINT}" \
     -U "${MASTER_USERNAME}" \
     -d "${DATABASE_NAME}" \
     -c "SELECT usename, usecanlogin FROM pg_user LIMIT 5;" \
     <<< "${DB_PASSWORD}" 2>/dev/null || true

# Test 4: Monitor connections
echo ""
echo "Test 4: Monitoring connections..."
psql -h "${CLUSTER_ENDPOINT}" \
     -U "${MASTER_USERNAME}" \
     -d "${DATABASE_NAME}" \
     -c "SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname;" \
     <<< "${DB_PASSWORD}" 2>/dev/null || true

# Test 5: Verificar max_connections
echo ""
echo "Test 5: Checking max_connections parameter..."
psql -h "${CLUSTER_ENDPOINT}" \
     -U "${MASTER_USERNAME}" \
     -d "${DATABASE_NAME}" \
     -c "SHOW max_connections;" \
     <<< "${DB_PASSWORD}" 2>/dev/null || true

echo ""
echo "✅ Connection tests complete!"
```

### `scripts/test-backup.sh` - Test de Backups

```bash
#!/bin/bash

set -euo pipefail

ENVIRONMENT=${1:-prod}
CLUSTER_ID=$(terraform output -raw cluster_identifier)

echo "📦 Testing RDS Backups..."
echo "Cluster: ${CLUSTER_ID}"
echo ""

# Listar snapshots automáticos
echo "Recent automated snapshots:"
aws rds describe-db-cluster-snapshots \
    --db-cluster-identifier "${CLUSTER_ID}" \
    --snapshot-type automated \
    --query 'DBClusterSnapshots[0:5].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
    --output table

echo ""

# Verificar configuración de backup
echo "Backup configuration:"
aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_ID}" \
    --query 'DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow,LatestRestorableTime]' \
    --output table

echo ""
echo "✅ Backup test complete!"
```

---

## Troubleshooting

### Problemas Comunes

#### 1. **Errores de Conexión**

```bash
# Problema: psql: error: connection refused
# Causa: Security group no permite tráfico desde la fuente

# Solución:
aws ec2 describe-security-groups --group-ids sg-xxxxxx --query 'SecurityGroups[0].IpPermissions'

# Verificar que haya regla:
# - Port: 5432
# - Protocol: TCP
# - Source: Tu IP o security group de aplicación
```

#### 2. **Master Password Perdida**

```bash
# Terraform no guarda passwords en estado
# Guardar en Secrets Manager:

aws secretsmanager create-secret \
    --name workium/aurora/master-password \
    --secret-string '{"username":"postgres","password":"PASSWORD_HERE"}'

# Luego actualizar terraform:
# master_password = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string).password
```

#### 3. **Estado de Terraform Corrupto**

```bash
# Hacer backup del estado
aws s3 cp s3://terraform-state-xxx/aurora/prod/terraform.tfstate \
         ./terraform.tfstate.backup

# Forzar refresh
terraform refresh

# O reconstruir desde remoto
terraform state pull > terraform.tfstate.local
```

---

## Estimación de Costos

### Desglose Mensual (USA - us-west-2)

| Componente | Cantidad | Precio/mes | Total |
|---|---|---|---|
| **RDS Aurora** | | | |
| db.t4g.medium × 2 | 2 instancias | $0.40/hr | ~$288 |
| Storage Aurora | 50 GB | $0.10/GB | $5 |
| Snapshots (30 días) | 30 snapshots × 50GB | $0.023/GB-mo | ~$35 |
| **Enhanced Monitoring** | | | |
| RDS Enhanced Monitoring | 2 AZs | $0.02/AZ-hr | ~$29 |
| **Performance Insights** | | | |
| PI Retention (7 días) | Incluido | Gratis | $0 |
| **CloudWatch** | | | |
| Logs (7 días) | ~10GB/día | $0.50/GB | ~$15 |
| Custom Metrics | 10 métricas | $0.10 c/u | $1 |
| Alarms | 5 alarms | $0.10 c/u | $0.50 |
| **State Management** | | | |
| S3 (State + Backups) | 1 GB | $0.023/GB | $0.02 |
| DynamoDB (Locks) | <1GB | Pay per request | <$1 |
| **KMS Encryption** | | | |
| Key Cost | 1 key | $1.00/mo | $1 |
| API Calls | 100K calls | $0.03/10K | ~$0.30 |
| **Total Estimado** | | | **~$374-400/mes** |

### Optimizaciones Posibles

1. **Aurora Serverless v2**: Autoscaling, paga por ACU (Aurora Capacity Unit)
   - Costo: $2.255/ACU/hr
   - Para carga variable: potencialmente 40-60% más barato

2. **Reserved Instances (1 año)**:
   - db.t4g.medium: ~$150/mes (52% descuento)
   - Ahorro: ~$240/mes

3. **S3 Glacier para Snapshots Antiguos**:
   - Tras 30 días: mover a Glacier (~$0.004/GB)
   - Ahorro: ~$30/mes

---

## README.md Completo

```markdown
# Aurora PostgreSQL Infrastructure as Code

## Overview

This repository contains a complete, production-ready Terraform setup for deploying
a highly available Aurora PostgreSQL cluster with comprehensive monitoring, backup,
and security configurations.

## Architecture

- **High Availability**: Multi-AZ deployment with automated failover
- **Read Scaling**: Read replicas for query distribution
- **Backup Strategy**: Automated daily snapshots with 30-day retention
- **Monitoring**: CloudWatch metrics, Performance Insights, Enhanced Monitoring
- **Security**: Encryption at rest (KMS), VPC isolation, IAM roles
- **State Management**: Remote state with S3 + DynamoDB locks

## Prerequisites

- AWS Account with appropriate permissions
- Terraform >= 1.5.0
- AWS CLI >= 2.13.0
- PostgreSQL client (`psql`) for testing

## Quick Start

### 1. Bootstrap (One-time)

```bash
./scripts/bootstrap.sh
```

This creates:
- S3 bucket for Terraform state
- DynamoDB table for state locking
- KMS key for encryption

### 2. Initialize

```bash
./scripts/init.sh prod us-west-2
```

### 3. Plan

```bash
./scripts/plan.sh prod
```

### 4. Apply

```bash
./scripts/apply.sh tfplan-prod-* prod
```

## File Structure

```
├── environments/
│   └── prod/
│       ├── terraform.tfvars
│       └── backend.tf
├── modules/
│   ├── aurora_cluster/
│   ├── networking/
│   ├── monitoring/
│   └── security/
├── scripts/
├── main.tf
├── variables.tf
└── outputs.tf
```

## Outputs

After deployment, get connection details:

```bash
terraform output cluster_endpoint
terraform output cluster_reader_endpoint
terraform output database_name
```

## Testing Connection

```bash
./scripts/test-connection.sh
```

## Monitoring

Access CloudWatch dashboard:

```bash
aws cloudwatch describe-dashboards --dashboard-name-prefix workium-aurora
```

## Updating

To modify configuration:

```bash
# 1. Edit environments/prod/terraform.tfvars
# 2. Run plan to see changes
terraform plan -var-file=environments/prod/terraform.tfvars
# 3. Apply only if safe
terraform apply -var-file=environments/prod/terraform.tfvars
```

## Security Considerations

- Master password is randomly generated and should be stored in Secrets Manager
- All data encrypted at rest (KMS) and in transit (SSL)
- Database only accessible from private subnets
- IAM roles follow least privilege principle
- Deletion protection enabled for production

## Cost Estimation

See COST_ANALYSIS.md for detailed breakdown (~$400/month for standard config).

## Support

For issues, check:
- TROUBLESHOOTING.md
- AWS RDS documentation
- Terraform AWS provider docs

## License

Internal use only.
```

---

## Conclusión y Checklist Final

### ✅ Pre-Deployment Checklist

```bash
# 1. Validar configuración
terraform validate
terraform fmt -recursive -check .

# 2. Revisar plan
terraform plan -var-file=environments/prod/terraform.tfvars -out=tfplan

# 3. Verificar outputs críticos
terraform plan -var-file=environments/prod/terraform.tfvars -json | jq '.values'

# 4. Confirmar backend
aws s3 ls s3://terraform-state-123456789012-aurora-us-west-2/
aws dynamodb describe-table --table-name terraform-locks

# 5. KMS key
aws kms describe-key --key-id alias/workium-aurora-encryption

# 6. Security groups
aws ec2 describe-security-groups --filters Name=group-name,Values=*rds* --query 'SecurityGroups[0]'

# 7. Subnets
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-xxx
```

### ✅ Post-Deployment Checklist

```bash
# 1. Verificar cluster
aws rds describe-db-clusters --db-cluster-identifier workium-aurora-prod \
  --query 'DBClusters[0].[Status,Engine,EngineVersion,MultiAZ]'

# 2. Verificar instancias
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=workium-aurora-prod \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,AvailabilityZone]'

# 3. Probar conexión
psql -h $(terraform output -raw cluster_endpoint) -U postgres -d workium_db -c "SELECT version();"

# 4. Ver métricas
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=workium-aurora-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 5. Verificar alarms
aws cloudwatch describe-alarms --alarm-name-prefix workium-aurora

# 6. Ver backups
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier workium-aurora-prod \
  --query 'DBClusterSnapshots[0:5].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]'
```

---

Este es el documento más completo posible para tu proyecto de Aurora con Terraform. Contiene:

✅ **Arquitectura detallada** con diagramas ASCII  
✅ **Todos los módulos Terraform** (networking, security, aurora, monitoring)  
✅ **Scripts listos para usar** (bootstrap, init, plan, apply, validate, test)  
✅ **Configuración de backend** S3 + DynamoDB  
✅ **Snapshots, métricas, alarmas**  
✅ **Checklists y troubleshooting**  
✅ **Estimación de costos**  
✅ **Ejemplos de comandos AWS CLI**  

Puedes copiar y adaptar directamente a tu proyecto. ¿Necesitás que expanda algo en particular?
