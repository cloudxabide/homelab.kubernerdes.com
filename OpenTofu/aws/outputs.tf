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

output "route53_zone_id" {
  description = "Hosted zone cert-manager uses for the rancher-aws DNS-01 challenge (Scripts/modules/common/rancher_aws_le_cert.sh)."
  value       = try(data.aws_route53_zone.main[0].zone_id, "")
}

output "aws_region" {
  value = var.aws_region
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

output "rancher_instance_id" {
  description = "rancher-01 instance ID (Scripts/awsctl stop/start/status)."
  value       = aws_instance.rancher.id
}

# Tailscale subnet router — empty strings when tailscale_router_enabled = false
output "tailscale_router_instance_id" {
  description = "tailscale-01 instance ID (Scripts/awsctl stop/start/status)."
  value       = try(aws_instance.tailscale[0].id, "")
}

output "tailscale_router_private_ip" {
  description = "tailscale-01 private IP (<public subnet>.10)."
  value       = try(aws_instance.tailscale[0].private_ip, "")
}

output "tailscale_router_public_ip" {
  description = "tailscale-01 public IP. Not an Elastic IP: it changes when the instance is stopped and started."
  value       = try(aws_instance.tailscale[0].public_ip, "")
}

output "tailscale_router_admin_ip" {
  description = "Address Scripts/awsctl uses to SSH to tailscale-01: the public IP while admin_cidrs is set, else the private IP (over Tailscale)."
  value       = try(length(var.admin_cidrs) > 0 ? aws_instance.tailscale[0].public_ip : aws_instance.tailscale[0].private_ip, "")
}
