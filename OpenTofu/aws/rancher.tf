# Rancher Manager: a single node, rancher-01, in the public subnet with an
# Elastic IP (no load balancer — one node does not need one, and an NLB is
# ~$16/mo). Same shape as the Harvester VMs (SL Micro; 6.1 here because 6.2 is not in AWS yet), user "sles", the
# same SSH keys. RKE2 + Rancher are installed afterwards by Scripts/09 and 10
# (SSH from nuc-00 needs Tailscale).
#
#   RANCHER_VIP (env.sh)       = private IP, pinned to <public subnet>.30 so
#                                nuc-00's post-Tailscale DNS record never moves
#   rancher-aws.<env>.<domain> = Elastic IP — UI and downstream agents. Not
#                                "rancher.<env>": nuc-00 serves that name as the
#                                on-prem VIP (.30), so the two must not share it.

data "aws_ami" "sl_micro" {
  count       = var.rancher_ami_id == "" ? 1 : 0
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  rancher_ami_id     = var.rancher_ami_id != "" ? var.rancher_ami_id : data.aws_ami.sl_micro[0].id
  rancher_hostname   = "rancher-aws.${var.environment}.${var.domain}"
  rancher_private_ip = cidrhost(aws_subnet.public.cidr_block, 30)

  # Reuse the sles user + SSH keys from the Harvester cloud-init template so
  # the keys live in one place. The password hash is dropped (key-only in AWS)
  # as is qemu-guest-agent (Harvester-specific).
  generic_cloudinit = yamldecode(file("${path.module}/../../Files/CloudConfigurationTemplates/${var.cloudinit_template}"))
  sles_user         = one([for u in local.generic_cloudinit.users : u if u.name == "sles"])
}

resource "aws_instance" "rancher" {
  ami                    = local.rancher_ami_id
  instance_type          = var.rancher_instance_type
  subnet_id              = aws_subnet.public.id
  private_ip             = local.rancher_private_ip
  vpc_security_group_ids = [aws_security_group.rancher.id]

  # install_RKE2.sh keys off the hostname (rancher-01 = genesis node)
  user_data = join("\n", ["#cloud-config", yamlencode({
    hostname          = "rancher-01"
    fqdn              = "rancher-01.${var.environment}.${var.domain}"
    preserve_hostname = false
    write_files = [{
      path        = "/etc/sudoers.d/sles"
      content     = "sles ALL=(ALL) NOPASSWD:ALL\n"
      permissions = "0440"
      owner       = "root:root"
    }]
    users = [{
      name                = "sles"
      lock_passwd         = true
      groups              = "users,wheel"
      shell               = "/bin/bash"
      ssh_authorized_keys = local.sles_user.ssh_authorized_keys
    }]
  })])

  root_block_device {
    volume_type = "gp3"
    volume_size = var.rancher_root_volume_gb
    encrypted   = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # pods on the node can still reach IMDS
  }

  tags = {
    Name                          = "rancher-01"
    "homelab.kubernerdes.com/app" = "rancher-manager"
  }

  lifecycle {
    # A newer AMI or edited cloud-init must not silently replace the Rancher node.
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "rancher" {
  domain   = "vpc"
  instance = aws_instance.rancher.id
  tags     = { Name = "rancher-01" }

  depends_on = [aws_internet_gateway.main]
}
