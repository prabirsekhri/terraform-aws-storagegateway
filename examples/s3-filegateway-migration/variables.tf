################################################################################
# Required Variables
################################################################################

variable "gateway_id" {
  type        = string
  description = "The Storage Gateway ID (e.g., sgw-12A3456B) of the gateway to migrate. The EC2 instance ID will be automatically discovered."
  validation {
    condition     = can(regex("^sgw-[A-Z0-9]{8}$", var.gateway_id))
    error_message = "The gateway_id must be a valid Storage Gateway ID (e.g., sgw-12A3456B)."
  }
}

################################################################################
# Optional Variables
################################################################################

variable "gateway_type" {
  type        = string
  description = "Type of the gateway. Valid options are FILE_S3, VTL, CACHED, STORED"
  default     = "FILE_S3"
  validation {
    condition     = contains(["FILE_S3", "CACHED"], var.gateway_type)
    error_message = "Incorrect gateway type. Valid options are FILE_S3, CACHED."
  }
}

variable "instance_type" {
  type        = string
  description = "Instance type for the new AL2023 gateway. If not specified, uses the same type as the old gateway. Recommended: m7i.xlarge, m7i.2xlarge, r7i.xlarge, etc."
  default     = null
}

variable "reuse_eip" {
  type        = bool
  description = "Reattach the existing Elastic IP from the old gateway to the new gateway"
  default     = false
}

variable "root_block_device" {
  description = "Customize details about the root block device of the instance"
  type        = map(any)
  default = {
    kms_key_id  = null
    disk_size   = 80
    volume_type = "gp3"
  }
  validation {
    condition     = try(tonumber(var.root_block_device["disk_size"]), 80) >= 80
    error_message = "The root_block_device disk_size must be at least 80 GB per AWS Storage Gateway requirements."
  }
}
