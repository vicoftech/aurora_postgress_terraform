variable "project_name" {
  description = "Project name prefix for resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (NAT gateway)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (Aurora)"
  type        = list(string)
}

variable "availability_zones" {
  description = "AZs (must align with subnet counts)"
  type        = list(string)
}
