variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  description = "Security group ID for application tier (ingress to PostgreSQL)"
  type        = string
}

variable "postgres_ingress_cidrs" {
  description = "Extra CIDR blocks allowed to reach PostgreSQL on 5432 (e.g. VPN or office). Must be inside or routed to the VPC for connectivity to work."
  type        = list(string)
  default     = []
}
