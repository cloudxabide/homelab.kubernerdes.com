# OpenTofu (not Terraform). 1.10+ for native S3 state locking (use_lockfile);
# state encryption and early-evaluated variables in this block need 1.8+.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Partial config: bucket/key/region come from backend.hcl (not committed).
  #   cp backend.hcl.example backend.hcl   # edit, then:
  #   tofu init -backend-config=backend.hcl
  backend "s3" {}

  # OpenTofu state + plan encryption. The passphrase comes from
  # TF_VAR_state_passphrase (sourced from ~/.config/<concern>/creds, never
  # this repo). Losing it means losing the state — keep it in a password manager.
  encryption {
    key_provider "pbkdf2" "main" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "main" {
      keys = key_provider.pbkdf2.main
    }
    state {
      method   = method.aes_gcm.main
      enforced = true
    }
    plan {
      method   = method.aes_gcm.main
      enforced = true
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "homelab.kubernerdes.com"
      Environment = var.environment
      ManagedBy   = "opentofu"
    }
  }
}
