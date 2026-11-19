# Tailscale subnet router: tailscale-01 joins the tailnet and advertises the
# VPC, and the VPC routes homelab_cidr back through it. Opt-in with
# tailscale_router_enabled. The on-prem side (nuc-00 advertising homelab_cidr)
# is set up by hand; see README.md "Tailscale subnet router".
#
#   tailscale-01  SL Micro (same AMI as rancher-01), public subnet, pinned
#                 private IP <public subnet>.10, an auto-assigned public IP
#                 (no Elastic IP: Tailscale does not need a fixed address).
#                 Source/destination check off so it can forward.
#
# The auth key is never in OpenTofu (state or user_data): Scripts/awsctl
# tailscale-up passes it over SSH after boot.

locals {
  tailscale_private_ip = cidrhost(aws_subnet.public.cidr_block, 10)
}

resource "aws_security_group" "tailscale" {
  count       = var.tailscale_router_enabled ? 1 : 0
  name        = "${local.name}-tailscale"
  description = "Tailscale subnet router"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-tailscale" }
}

# Direct WireGuard connections (otherwise traffic falls back to DERP relays)
resource "aws_vpc_security_group_ingress_rule" "tailscale_wireguard" {
  count = var.tailscale_router_enabled ? 1 : 0

  security_group_id = aws_security_group.tailscale[0].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 41641
  to_port           = 41641
  ip_protocol       = "udp"
}

# Everything in the VPC that is headed on-prem passes through the router
resource "aws_vpc_security_group_ingress_rule" "tailscale_vpc" {
  count = var.tailscale_router_enabled ? 1 : 0

  security_group_id = aws_security_group.tailscale[0].id
  cidr_ipv4         = local.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "tailscale_ssh_homelab" {
  count = var.tailscale_router_enabled ? 1 : 0

  security_group_id = aws_security_group.tailscale[0].id
  cidr_ipv4         = var.homelab_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Pre-Tailscale SSH (awsctl tailscale-up) over the public IP, same as rancher-01
resource "aws_vpc_security_group_ingress_rule" "tailscale_ssh_admin" {
  for_each = var.tailscale_router_enabled ? toset(var.admin_cidrs) : toset([])

  security_group_id = aws_security_group.tailscale[0].id
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "tailscale" {
  count = var.tailscale_router_enabled ? 1 : 0

  security_group_id = aws_security_group.tailscale[0].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "tailscale" {
  count = var.tailscale_router_enabled ? 1 : 0

  ami                         = local.rancher_ami_id
  instance_type               = var.tailscale_instance_type
  subnet_id                   = aws_subnet.public.id
  private_ip                  = local.tailscale_private_ip
  associate_public_ip_address = true
  source_dest_check           = false
  vpc_security_group_ids      = [aws_security_group.tailscale[0].id]

  user_data = join("\n", ["#cloud-config", yamlencode({
    hostname          = "tailscale-01"
    fqdn              = "tailscale-01.${var.environment}.${var.domain}"
    preserve_hostname = false
    write_files = [
      {
        path        = "/etc/sudoers.d/sles"
        content     = "sles ALL=(ALL) NOPASSWD:ALL\n"
        permissions = "0440"
        owner       = "root:root"
      },
      {
        path    = "/etc/sysctl.d/99-tailscale.conf"
        content = "net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n"
      },
      {
        path    = "/etc/profile.d/tailscale.sh"
        content = "export PATH=\"$PATH:/opt/tailscale/bin\"\n"
      },
      {
        # Upstream unit (from the tarball), with the binaries in /opt
        path    = "/etc/systemd/system/tailscaled.service"
        content = <<-EOT
          [Unit]
          Description=Tailscale node agent
          Documentation=https://tailscale.com/docs/
          Wants=network-pre.target
          After=network-pre.target NetworkManager.service systemd-resolved.service

          [Service]
          ExecStart=/opt/tailscale/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/run/tailscale/tailscaled.sock --port=41641
          ExecStopPost=/opt/tailscale/bin/tailscaled --cleanup
          Restart=on-failure
          RuntimeDirectory=tailscale
          RuntimeDirectoryMode=0755
          StateDirectory=tailscale
          StateDirectoryMode=0700
          CacheDirectory=tailscale
          CacheDirectoryMode=0750
          Type=notify

          [Install]
          WantedBy=multi-user.target
        EOT
      },
      {
        path        = "/opt/tailscale/install.sh"
        content     = file("${path.module}/files/tailscale_install.sh")
        permissions = "0755"
      },
    ]
    users = [{
      name                = "sles"
      lock_passwd         = true
      groups              = "users,wheel"
      shell               = "/bin/bash"
      ssh_authorized_keys = local.sles_user.ssh_authorized_keys
    }]
    runcmd = [
      ["sysctl", "--system"],
      ["/opt/tailscale/install.sh", var.tailscale_version],
    ]
  })])

  root_block_device {
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 only
  }

  tags = {
    Name                          = "tailscale-01"
    "homelab.kubernerdes.com/app" = "tailscale-subnet-router"
  }

  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_internet_gateway.main]
}

# Send on-prem traffic from both subnets through the router
resource "aws_route" "public_homelab" {
  count                  = var.tailscale_router_enabled ? 1 : 0
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.homelab_cidr
  network_interface_id   = aws_instance.tailscale[0].primary_network_interface_id
}

resource "aws_route" "private_homelab" {
  count                  = var.tailscale_router_enabled ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.homelab_cidr
  network_interface_id   = aws_instance.tailscale[0].primary_network_interface_id
}
