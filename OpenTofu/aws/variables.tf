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
  description = "VPC CIDR inside 172.16.0.0/12. null = per-environment default (prime 172.16.0.0/16, community 172.17.0.0/16; same map as Scripts/env.sh) so environments never overlap on the tailnet."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_cidr == null ? true : try(cidrcontains("172.16.0.0/12", var.vpc_cidr), false)
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
  description = "AMI name pattern for the SL Micro lookup. 6.2 is not published in AWS yet (2026-11); 6.1 BYOS is the newest. SUSE names them suse-sle-micro-*."
  type        = string
  default     = "suse-sle-micro-6-1-byos-v*-hvm-ssd-x86_64"
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
  description = "Public Route 53 zone, in this AWS account, that holds the rancher-aws record. If the parent zone is in another account, delegate rancher-aws.<environment>.<domain> and set that name here (see README.md)."
  type        = string
  default     = "kubernerdes.com"
}

variable "admin_cidrs" {
  description = <<-EOT
    Pre-Tailscale admin access. CIDRs (your home egress IP /32) allowed to reach rancher-01 on
    22 (SSH) and 6443 (kube API) over its Elastic IP. While non-empty, the rancher_vip and
    rancher_node_ips outputs are the Elastic IP, so Scripts/09 and 10 on nuc-00 work without
    Tailscale. Set back to [] once Tailscale is up: outputs revert to the private IP and the
    public 22/6443 rules are removed.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "admin_cidrs must be valid CIDRs, and not 0.0.0.0/0 (that would expose SSH and the kube API to the internet)."
  }
}

# --- Tailscale subnet router -----------------------------------------------
variable "tailscale_router_enabled" {
  description = "Build tailscale-01, a Tailscale subnet router that advertises the VPC, and route homelab_cidr through it (see tailscale.tf)."
  type        = bool
  default     = false
}

variable "tailscale_instance_type" {
  description = "tailscale-01 instance type. t3a.micro = 2 vCPU / 1 GiB, plenty for a lab subnet router."
  type        = string
  default     = "t3a.micro"
}

variable "tailscale_version" {
  description = "Tailscale release installed on first boot: \"latest\" (newest stable) or an exact version such as \"1.104.7\"."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^(latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.tailscale_version))
    error_message = "tailscale_version must be \"latest\" or a version such as \"1.104.7\"."
  }
}

variable "rancher_cert_dns01" {
  description = "Give rancher-01 an instance role that lets cert-manager issue its own Let's Encrypt cert for rancher-aws.<env>.<domain> (Route 53 DNS-01), independent of nuc-00's *.<env> wildcard."
  type        = bool
  default     = true
}
