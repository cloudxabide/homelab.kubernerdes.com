# Output contract with Scripts/env.sh (and 09). After `tofu apply`, on nuc-00:
#
#   mkdir -p ~/.config/homelab
#   tofu -chdir=OpenTofu/aws output -json > ~/.config/homelab/<ENVIRONMENT>-aws-outputs.json
#
# env.sh reads these names; renaming one here breaks the scripts.
#   rancher_lb_dns    string        NLB DNS name (becomes RANCHER_VIP)
#   rancher_node_ips  list(string)  rancher-01..03 private IPs, in that order
#
# Defined below once the resources exist. Only non-resource outputs for now.

output "environment" {
  description = "ENVIRONMENT this state belongs to."
  value       = var.environment
}

output "base_domain" {
  description = "<environment>.<domain>, matching BASE_DOMAIN in env.sh."
  value       = "${var.environment}.${var.domain}"
}

output "vpc_cidr" {
  description = "VPC CIDR (for the site-to-site link and routes on the homelab side)."
  value       = var.vpc_cidr
}
