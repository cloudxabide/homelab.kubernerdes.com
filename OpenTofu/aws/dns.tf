# Public DNS: rancher.<env>.<domain> -> rancher-01's Elastic IP, in the Route 53
# zone already used for Let's Encrypt DNS-01.
#
# Split horizon: nuc-00's BIND is authoritative for <env>.<domain> on the
# homelab and still answers with the on-prem VIP (.30). Updating that zone is
# part of the hybrid integration step, not this directory.

data "aws_route53_zone" "main" {
  count        = var.manage_dns ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "rancher" {
  count   = var.manage_dns ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = local.rancher_hostname
  type    = "A"
  ttl     = 300
  records = [aws_eip.rancher.public_ip]
}
