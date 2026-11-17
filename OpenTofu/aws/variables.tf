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

variable "availability_zone" {
  description = "Single AZ for everything. Empty = first available AZ in the region."
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "NAT gateway for the private subnet (~$32/mo + data). Off until something runs there."
  type        = bool
  default     = false
}

variable "public_ingress_cidrs" {
  description = "CIDRs allowed to reach Rancher on 80/443 (UI + downstream agent registration). No default: decide deliberately (your home egress IP /32, or 0.0.0.0/0)."
  type        = list(string)

  validation {
    condition     = length(var.public_ingress_cidrs) > 0 && alltrue([for c in var.public_ingress_cidrs : can(cidrnetmask(c))])
    error_message = "public_ingress_cidrs must be a non-empty list of valid CIDRs."
  }
}

# --- Rancher node ----------------------------------------------------------
variable "rancher_instance_type" {
  description = "rancher-01 instance type. t3a.xlarge = 4 vCPU / 16 GiB."
  type        = string
  default     = "t3a.xlarge"
}

variable "rancher_root_volume_gb" {
  description = "rancher-01 root volume (gp3, encrypted)."
  type        = number
  default     = 64
}

variable "rancher_ami_id" {
  description = "Pin an exact AMI. Empty = newest match for ami_owner + ami_name_filter."
  type        = string
  default     = ""
}

variable "ami_owner" {
  description = "AMI owner account for the SL Micro lookup (SUSE)."
  type        = string
  default     = "013907871322"
}

variable "ami_name_filter" {
  description = "AMI name pattern for the SL Micro 6.2 lookup."
  type        = string
  default     = "suse-sl-micro-6-2-*"
}

variable "cloudinit_template" {
  description = "File under Files/CloudConfigurationTemplates/ whose sles user + SSH keys are reused."
  type        = string
  default     = "sl-micro-6-generic.yaml"
}

# --- DNS -------------------------------------------------------------------
variable "manage_dns" {
  description = "Create rancher.<environment>.<domain> in Route 53."
  type        = bool
  default     = true
}

variable "route53_zone_name" {
  description = "Public Route 53 zone that holds <environment>.<domain> records."
  type        = string
  default     = "kubernerdes.com"
}
