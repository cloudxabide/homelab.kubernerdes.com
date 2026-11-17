# Security groups.
#   rancher-01  — 80/443 from public_ingress_cidrs (Rancher UI, downstream
#                 agent registration); 22/6443 from homelab_cidr (nuc-00 over
#                 Tailscale — no effect until Tailscale is up); all from the VPC
#   downstream  — clusters Rancher provisions with the Amazon EC2 node driver

# --- Rancher node ----------------------------------------------------------
resource "aws_security_group" "rancher" {
  name        = "${local.name}-rancher"
  description = "Rancher Manager node"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-rancher" }
}

resource "aws_vpc_security_group_ingress_rule" "rancher_public" {
  for_each = { for pair in setproduct(var.public_ingress_cidrs, [80, 443]) : "${pair[0]}-${pair[1]}" => pair }

  security_group_id = aws_security_group.rancher.id
  cidr_ipv4         = each.value[0]
  from_port         = each.value[1]
  to_port           = each.value[1]
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rancher_homelab" {
  for_each = toset(["22", "443", "6443"])

  security_group_id = aws_security_group.rancher.id
  cidr_ipv4         = var.homelab_cidr
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rancher_vpc" {
  security_group_id = aws_security_group.rancher.id
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "rancher" {
  security_group_id = aws_security_group.rancher.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Downstream clusters (provisioned by Rancher's Amazon EC2 node driver) --
# Select this group in the Rancher EC2 machine pool instead of letting the
# driver create its own "rancher-nodes" group.
resource "aws_security_group" "downstream" {
  name        = "${local.name}-downstream"
  description = "RKE2 downstream clusters provisioned by Rancher"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-downstream" }
}

resource "aws_vpc_security_group_ingress_rule" "downstream_self" {
  security_group_id            = aws_security_group.downstream.id
  referenced_security_group_id = aws_security_group.downstream.id
  ip_protocol                  = "-1"
}

# Rancher provisions machines over SSH (22) and talks to the RKE2 API (6443).
resource "aws_vpc_security_group_ingress_rule" "downstream_from_rancher" {
  for_each = toset(["22", "6443"])

  security_group_id            = aws_security_group.downstream.id
  referenced_security_group_id = aws_security_group.rancher.id
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "downstream_from_homelab" {
  for_each = toset(["22", "6443"])

  security_group_id = aws_security_group.downstream.id
  cidr_ipv4         = var.homelab_cidr
  from_port         = tonumber(each.value)
  to_port           = tonumber(each.value)
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "downstream" {
  security_group_id = aws_security_group.downstream.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
