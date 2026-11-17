# Output contract with Scripts/env.sh (and 09). After `tofu apply`, on nuc-00:
#
#   mkdir -p ~/.config/homelab
#   tofu -chdir=OpenTofu/aws output -json > ~/.config/homelab/<ENVIRONMENT>-aws-outputs.json
#
# env.sh reads these names; renaming one here breaks the scripts.
#   rancher_vip       string        Elastic IP while admin_cidrs is set, else private IP (becomes RANCHER_VIP)
#   rancher_node_ips  list(string)  node private IPs, rancher-01 first
#   rancher_hostname  string        rancher-aws.<env>.<domain> (read by 09)

output "environment" {
  description = "ENVIRONMENT this state belongs to."
  value       = var.environment
}

output "base_domain" {
  description = "<environment>.<domain>, matching BASE_DOMAIN in env.sh."
  value       = "${var.environment}.${var.domain}"
}

output "vpc_cidr" {
  description = "VPC CIDR (advertised by the Tailscale subnet router)."
  value       = local.vpc_cidr
}

locals {
  # Address nuc-00 uses for SSH + kube API: the Elastic IP while admin_cidrs
  # is set (pre-Tailscale), otherwise the private IP over Tailscale.
  rancher_admin_ip = length(var.admin_cidrs) > 0 ? aws_eip.rancher.public_ip : aws_instance.rancher.private_ip
}

output "rancher_vip" {
  description = "RANCHER_VIP for env.sh: Elastic IP while admin_cidrs is set, else rancher-01's private IP (Tailscale)."
  value       = local.rancher_admin_ip
}

output "rancher_node_ips" {
  description = "Rancher node IPs nuc-00 SSHes to, rancher-01 first (single node). Same switch as rancher_vip."
  value       = [local.rancher_admin_ip]
}

output "rancher_private_ip" {
  description = "rancher-01 private IP (always), for the post-Tailscale nuc-00 DNS record."
  value       = aws_instance.rancher.private_ip
}

output "rancher_public_ip" {
  description = "rancher-01 Elastic IP (target of rancher-aws.<environment>.<domain>)."
  value       = aws_eip.rancher.public_ip
}

output "rancher_hostname" {
  description = "rancher-aws.<environment>.<domain> (RANCHER_HOSTNAME in env.sh for aws)."
  value       = local.rancher_hostname
}

output "rancher_ami_id" {
  description = "AMI rancher-01 was built from — check it is the SL Micro 6.1 BYOS image you expect."
  value       = aws_instance.rancher.ami
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Subnet for Rancher-provisioned downstream clusters (needs enable_nat_gateway)."
  value       = aws_subnet.private.id
}

output "downstream_security_group" {
  description = "Security group name to select in Rancher EC2 machine pools."
  value       = aws_security_group.downstream.name
}

output "rancher_node_driver_user" {
  description = "IAM user for the Rancher Amazon EC2 cloud credential (create its access key by hand)."
  value       = aws_iam_user.node_driver.name
}
