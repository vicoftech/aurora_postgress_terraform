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
  description = "Reserved for future storage alarms"
  type        = number
  default     = 80
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  sensitive   = true
}
