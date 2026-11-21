# Single-AZ VPC (cost over resilience — this is a lab):
#   vpc_cidr: prime 172.18.0.0/16, community 172.17.0.0/16 (unless overridden)
#             (172.16.0.0/16 is skipped: the home IoT VLAN is 172.16.0.0/23)
#   public  subnet: cidrsubnet(vpc_cidr, 4, 0)  e.g. 172.18.0.0/20   — rancher-01 (Elastic IP, private .0.30)
#   private subnet: cidrsubnet(vpc_cidr, 4, 8)  e.g. 172.18.128.0/20 — downstream clusters later
# Index 1-7 / 9-15 are left free if a second AZ is ever wanted.
#
# NAT gateway is off by default (~$32/mo + data). rancher-01 is in the public
# subnet and needs no NAT. Turn it on (enable_nat_gateway) once something runs
# in the private subnet.
#
# Tailscale: a subnet router (tailscale.tf, tailscale_router_enabled) advertises
# vpc_cidr to the tailnet and nuc-00 advertises homelab_cidr; tailscale.tf adds
# a route for homelab_cidr via the router to both route tables.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  default_vpc_cidrs = {
    prime     = "172.18.0.0/16"
    community = "172.17.0.0/16"
  }
  vpc_cidr = coalesce(var.vpc_cidr, local.default_vpc_cidrs[var.environment])

  name = "homelab-${var.environment}"
  az   = var.availability_zone != "" ? var.availability_zone : data.aws_availability_zones.available.names[0]
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.az
  cidr_block              = cidrsubnet(local.vpc_cidr, 4, 0)
  map_public_ip_on_launch = false

  tags = {
    Name                     = "${local.name}-public-${local.az}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  availability_zone = local.az
  cidr_block        = cidrsubnet(local.vpc_cidr, 4, 8)

  tags = {
    Name                              = "${local.name}-private-${local.az}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${local.name}-nat" }
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = local.name }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-private" }
}

resource "aws_route" "private_default" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
