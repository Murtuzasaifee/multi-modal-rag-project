variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for mount targets"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least one subnet must be provided."
  }
}

variable "security_group_id" {
  description = "Security group ID for mount targets"
  type        = string
}

variable "performance_mode" {
  description = "EFS performance mode (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "throughput_mode" {
  description = "EFS throughput mode (bursting or provisioned)"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "provisioned"], var.throughput_mode)
    error_message = "throughput_mode must be either 'bursting' or 'provisioned'."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "Provisioned throughput in MiB/s (only when throughput_mode is 'provisioned')"
  type        = number
  default     = null
}

variable "create_access_points" {
  description = "Create EFS access points"
  type        = bool
  default     = true
}

variable "access_points" {
  description = "Map of access points to create"
  type = map(object({
    path            = string
    posix_user_uid  = number
    posix_user_gid  = number
    owner_uid       = number
    owner_gid       = number
    permissions     = string
  }))

  default = {}
}

variable "transit_encryption" {
  description = "Enable transit encryption"
  type        = bool
  default     = true
}

variable "at_rest_encryption" {
  description = "Enable encryption at rest (null for default KMS key)"
  type        = string
  default     = null
}
