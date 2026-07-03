variable "tenancy_ocid" {
  description = "The OCID of the tenancy"
  type        = string
}

variable "compartment_id" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
  default     = null # If null, will use tenancy_ocid (backward compatibility)
}

variable "region" {
  description = "The OCI region"
  type        = string
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+-[0-9]+$", var.region))
    error_message = "Region must be in format like 'us-ashburn-1'."
  }
}

variable "project" {
  description = "The OCI project name (used for naming resources)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens."
  }
}


variable "vcn_cidr_block" {
  description = "The VCN CIDR block (e.g., 10.0.0.0/16)"
  type        = string
  validation {
    condition     = can(cidrhost(var.vcn_cidr_block, 0))
    error_message = "VCN CIDR block must be a valid CIDR notation."
  }
}

variable "public_subnet_cidr" {
  description = "The public subnet CIDR (must be within VCN CIDR)"
  type        = string
  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "Public subnet CIDR must be a valid CIDR notation."
  }
}

variable "private_subnet_cidr" {
  description = "The private subnet CIDR (must be within VCN CIDR)"
  type        = string
  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "Private subnet CIDR must be a valid CIDR notation."
  }
}

variable "nat_subnet_cidr" {
  description = "The NAT subnet CIDR (must be within VCN CIDR)"
  type        = string
  validation {
    condition     = can(cidrhost(var.nat_subnet_cidr, 0))
    error_message = "NAT subnet CIDR must be a valid CIDR notation."
  }
}

variable "vcn_dns_label" {
  description = "The VCN DNS label (used for DNS resolution)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{1,15}$", var.vcn_dns_label))
    error_message = "VCN DNS label must be 1-15 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "ssh_authorized_keys" {
  description = "SSH public key used for authenticating with instances"
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)", var.ssh_authorized_keys))
    error_message = "SSH authorized key must be a valid SSH public key."
  }
}

variable "user_ip_address" {
  description = "IP address/CIDR for SSH whitelisting (e.g., 1.2.3.4/32)"
  type        = string
  validation {
    condition     = can(cidrhost(var.user_ip_address, 0))
    error_message = "User IP address must be a valid IP address or CIDR notation."
  }
}

variable "instance_peer_ssh_cidrs" {
  description = "Additional IP address/CIDR blocks allowed to SSH into public instances."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.instance_peer_ssh_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Each instance peer SSH CIDR must be a valid IP address or CIDR notation."
  }
}

variable "TAILSCALE_AUTH_KEY" {
  description = "Tailscale Auth Key to automatically join the Tailnet"
  type        = string
  sensitive   = true
}
