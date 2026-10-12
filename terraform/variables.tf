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
  default     = "10.10.1.0/24"
}