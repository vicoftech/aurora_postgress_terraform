variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Public subnet for the bastion (must route to Internet Gateway)"
  type        = string
}

variable "instance_type" {
  description = "e.g. t3.micro (free tier eligible in many accounts)"
  type        = string
  default     = "t3.micro"
}

variable "ssh_cidrs" {
  description = "CIDRs allowed to SSH (port 22). Empty = no SSH rule; use AWS SSM Session Manager only."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH"
  type        = string
  default     = null
}

variable "install_postgresql_client" {
  description = "Install psql via user-data (Amazon Linux 2023)"
  type        = bool
  default     = true
}
