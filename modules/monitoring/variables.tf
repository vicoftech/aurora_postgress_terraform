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

variable "db_instance_identifiers" {
  description = "Aurora instance identifiers for instance-scoped RDS metrics (e.g. postgres-aurora-prod-writer). FreeLocalStorage and FreeEphemeralStorage require DBInstanceIdentifier, not DBClusterIdentifier."
  type        = list(string)
}

variable "free_local_storage_alarm_below_bytes" {
  description = "Trigger alarm when Average FreeLocalStorage is below this (bytes)."
  type        = number
}

variable "free_ephemeral_storage_alarm_below_bytes" {
  description = "Trigger alarm when Average FreeEphemeralStorage is below this (bytes)."
  type        = number
}

variable "enable_free_ephemeral_storage_alarm" {
  description = "Whether to emit FreeEphemeralStorage alarms."
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  sensitive   = true
}
