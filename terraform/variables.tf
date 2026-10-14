variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Region for subnet, NAT and VMs"
  type        = string
  default     = "me-west1"
}

variable "zone" {
  description = "Zone for the VMs"
  type        = string
  default     = "me-west1-b"
}

variable "subnet_cidr" {
  description = "IP range of the subnet"
  type        = string
  default     = "10.10.0.0/24"
}

variable "mngmt_cidr" {
  description = "IP range of the management subnet"
  type        = string
  default     = "35.235.240.0/20"
}

variable "enable_nat" {
  description = "Outbound internet for the private subnet. true during bootstrap, false afterwards for zero egress."
  type        = bool
  default     = false
}

variable "ssh_user" {
  description = "Linux user created on both VMs for SSH"
  type        = string
  default     = "fde"
}

variable "ssh_public_key_path" {
  description = "Public key allowed to log in (the private half never leaves the laptop)"
  type        = string
  default     = "~/.ssh/df-airis.pub"
}