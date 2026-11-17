# Self-contained: these are NOT read from Scripts/env.sh. Defaults match it;
# override in a local *.tfvars (gitignored) or TF_VAR_* env vars.

variable "environment" {
  description = "Homelab ENVIRONMENT this AWS side belongs to. enclave is air-gapped and cannot use AWS."
  type        = string
  default     = "community"

  validation {
    condition     = contains(["community", "prime"], var.environment)
    error_message = "environment must be community or prime (enclave is air-gapped and stays on-prem)."
  }
}

variable "aws_region" {
  description = "AWS region for the hybrid-cloud side."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR, carved from the reserved 172.16.0.0/12 (no overlap with the homelab or storage network)."
  type        = string
  default     = "172.16.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && cidrcontains("172.16.0.0/12", var.vpc_cidr)
    error_message = "vpc_cidr must be a valid CIDR inside 172.16.0.0/12."
  }
}

variable "homelab_cidr" {
  description = "On-prem supernet reachable over the site-to-site link."
  type        = string
  default     = "10.10.12.0/22"
}

variable "domain" {
  description = "Parent DNS domain; the base domain is <environment>.<domain>."
  type        = string
  default     = "kubernerdes.com"
}

variable "state_passphrase" {
  description = "Passphrase for OpenTofu state encryption (min 16 chars). Set via TF_VAR_state_passphrase."
  type        = string
  sensitive   = true
}
