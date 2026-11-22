# OpenTofu/aws — hybrid (AWS) infrastructure

AWS side of the **hybrid-cloud** setup: Rancher Manager (and optionally Observability)
runs in AWS and manages downstream clusters both on-prem (Harvester) and in AWS.
Used when the matching `*_LOCATION=aws` is set (see `Scripts/env.sh`).

## Coupling to on-prem
This directory is **self-contained**. It has its own variables (`*.tfvars`, kept out of git) and does
not source `Scripts/env.sh`, so `tofu apply` / `tofu destroy` work whether or not the homelab is up.
It links to on-prem at only three points, all handled by one integration step
(planned: `Scripts/40_connect_hybrid.sh`):
1. Connectivity between the VPC and `10.10.12.0/22`
2. DNS that both sides can resolve
3. Importing Harvester and the on-prem downstream clusters into the AWS-hosted Rancher

| Variable | Values | Default |
|:---------|:-------|:--------|
| `RANCHER_LOCATION` | `onprem` \| `aws` | `onprem` |
| `OBS_LOCATION`     | `onprem` \| `aws` | `onprem` |

`ENVIRONMENT=enclave` is air-gapped and refuses any `aws` location.

## What it builds (cost over resilience: single AZ, single node)
- VPC from `vpc_cidr` (per-environment default: prime `172.18.0.0/16`, community `172.17.0.0/16`,
  both inside the reserved 172.16.0.0/12, so two environments never overlap on the tailnet; 172.16.0.0/16
  is skipped because the home IoT VLAN is 172.16.0.0/23), one AZ,
  one public + one private subnet; NAT gateway off by default (`enable_nat_gateway`)
- `rancher-01`: SL Micro 6.1 BYOS EC2 instance (6.2 is not published in AWS yet) (default `t3a.xlarge`) in the public subnet with an Elastic IP
  and a pinned private IP (`<vpc>.0.30`, mirroring the on-prem `.30` VIP).
  No load balancer. 80/443 open to `public_ingress_cidrs`; 22/443/6443 open to `homelab_cidr`
  (that last part only works once Tailscale is up). Cloud-init reuses the `sles` user and SSH keys
  from `Files/CloudConfigurationTemplates/`
- Route 53 `A` record `rancher-aws.<environment>.<domain>` → the Elastic IP (`manage_dns`).
  The name is `rancher-aws`, not `rancher`, because nuc-00's BIND is authoritative for
  `<environment>.<domain>` on the homelab and serves `rancher` as the on-prem VIP. nuc-00 gets its own
  static `rancher-aws` record (commented out in `Files/nuc-00/var/lib/named/master/db.<env>.kubernerdes.com`).
  The `*.<environment>.<domain>` Let's Encrypt wildcard covers both names.
- An instance role on `rancher-01` (`rancher_cert_dns01`) that lets cert-manager issue and renew its own
  Let's Encrypt certificate for `rancher-aws.<environment>.<domain>` (Route 53 DNS-01). It may only write
  the TXT record `_acme-challenge.rancher-aws.<environment>.<domain>`. nuc-00's `*.<environment>` wildcard,
  its key, and its certbot renewal hook are not involved (`Scripts/modules/common/rancher_aws_le_cert.sh`).
- For Rancher-provisioned downstream clusters on EC2: a `downstream` security group and an
  IAM user for the Amazon EC2 node driver (create its access key by hand; it is kept out of state)

## Not yet
- Automating the on-prem half of Tailscale (ts-onprem VM, host routes); it is done by hand for now, see
  "Tailscale subnet router" (planned: `Scripts/40_connect_hybrid.sh`)
- Importing Harvester and the on-prem clusters into this Rancher

## Check before the first apply
- **AMI:** owner `013907871322` (SUSE) and the name pattern are confirmed (2026-11-17). SL Micro 6.2 is
  not published in AWS yet; the newest x86_64 image is `suse-sle-micro-6-1-byos-v20261111-hvm-ssd-x86_64`
  (`ami-0074608a2dc0cbdba` in us-east-1). List what is current with:
  ```bash
  aws ec2 describe-images --owners 013907871322 \
    --filters 'Name=name,Values=suse-sle-micro-6-*-byos-v*-hvm-ssd-x86_64' \
    --query 'reverse(sort_by(Images,&CreationDate))[:5].[ImageId,Name,CreationDate]' --output table
  ```
  When 6.2 shows up, set `ami_name_filter` to the 6-2 pattern (an existing node keeps its AMI).
- **BYOS:** no SUSE charge on the hourly price, but the instance needs registering for updates:
  `sudo transactional-update register -r <Prime regcode>` (then reboot).
- **Verified on this image (2026-11-18, `ami-0074608a2dc0cbdba`):** cloud-init runs, creating the `sles`
  user and setting the `rancher-01` hostname, and `install_RKE2.sh` completes its reboot + postboot path.
- **Route 53 zone:** must be a public zone in the same AWS account as these credentials. If
  `kubernerdes.com` is in another account, see "Route 53 zone in a different AWS account" below.
- Rough cost: t3a.xlarge ≈ $110/mo + 64 GiB gp3 ≈ $5 + public IPv4 ≈ $4. Stop the instance when idle.

After this provisions `rancher-01`, the existing scripts (`09_install_RKE2_for_rancher_manager.sh`,
`10_install_rancher_manager.sh`) do the install, the same way they do on-prem (with `replicas=1`).

## Getting started
```bash
cd OpenTofu/aws
cp backend.hcl.example backend.hcl            # set the bucket name; one-time manual bucket create
cp example.tfvars community.tfvars            # optional; defaults match Scripts/env.sh
export TF_VAR_state_passphrase=...            # from ~/.config/<concern>/creds, 16+ chars
tofu init -backend-config=backend.hcl
tofu plan -var-file=community.tfvars
tofu apply -var-file=community.tfvars
mkdir -p ~/.config/homelab
tofu output -json > ~/.config/homelab/community-aws-outputs.json   # read by Scripts/env.sh
```

| File | Purpose |
|:-----|:--------|
| `versions.tf` | OpenTofu/provider versions, S3 backend (partial), state + plan encryption, AWS provider |
| `variables.tf` | Inputs; `environment` rejects `enclave`, `vpc_cidr` must sit inside 172.16.0.0/12 |
| `network.tf` / `security.tf` | VPC, subnets, routes, optional NAT; security groups |
| `rancher.tf` / `dns.tf` / `iam.tf` | rancher-01 + Elastic IP; Route 53 record; node-driver IAM user |
| `tailscale.tf` / `files/tailscale_install.sh` | Optional Tailscale subnet router (tailscale-01), its VPC routes, its first-boot install |
| `outputs.tf` | Output contract with `Scripts/env.sh` (`rancher_vip`, `rancher_node_ips`) |
| `backend.hcl.example` / `example.tfvars` | Templates for the gitignored local copies |

## First deploy, before Tailscale (prime shown)
`Scripts/awsctl` wraps steps 3–4 (`ENVIRONMENT=prime Scripts/awsctl build`) and forces the state key to
`<ENVIRONMENT>/aws.tfstate`; `Scripts/awsctl help` for the rest. The manual commands below are what it runs.

Uses `admin_cidrs` so nuc-00 reaches `rancher-01` over its Elastic IP. Your home egress IP
(`curl -s https://checkip.amazonaws.com`) goes in both `public_ingress_cidrs` and `admin_cidrs`.

1. **One-time state setup** (laptop or nuc-00, wherever `tofu` + AWS creds live):
   ```bash
   aws s3api create-bucket --bucket <bucket> --region us-east-1
   aws s3api put-bucket-versioning --bucket <bucket> --versioning-configuration Status=Enabled
   aws s3api put-public-access-block --bucket <bucket> --public-access-block-configuration \
     BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
   cp backend.hcl.example backend.hcl   # bucket=<bucket>, key="prime/aws.tfstate"
   ```
2. **Vars** — `prime.tfvars`:
   ```hcl
   environment          = "prime"
   public_ingress_cidrs = ["<home-ip>/32"]
   admin_cidrs          = ["<home-ip>/32"]
   ```
3. **Apply**:
   ```bash
   export TF_VAR_state_passphrase=...   # 16+ chars, keep it safe
   tofu init -backend-config=backend.hcl
   tofu plan  -var-file=prime.tfvars
   tofu apply -var-file=prime.tfvars
   tofu output -json > prime-aws-outputs.json
   ```
4. **First-boot checks** (`ssh -i ~/.ssh/id_rsa-prime sles@<rancher_public_ip>`):
   `hostname` is `rancher-01` (cloud-init ran); then register the BYOS image:
   `sudo transactional-update register -r <regcode> && sudo reboot`.
5. **nuc-00 DNS** — in `/var/lib/named/master/db.prime.kubernerdes.com` uncomment `rancher-aws` with the
   Elastic IP, bump the serial, `rndc reload prime.kubernerdes.com`. Check `dig +short rancher-aws.prime.kubernerdes.com`.
6. **On nuc-00**, from `Scripts/`:
   ```bash
   mkdir -p ~/.config/homelab && cp prime-aws-outputs.json ~/.config/homelab/
   export ENVIRONMENT=prime RANCHER_LOCATION=aws
   ./09_install_RKE2_for_rancher_manager.sh
   ./10_install_rancher_manager.sh
   ```
   09 and 10 save the kubeconfig as `~/.kube/prime-rancher-aws.kubeconfig` (the on-prem one is left alone).
   With `RANCHER_CERT=letsencrypt`, 10 has cert-manager issue the `rancher-aws` certificate. To try the
   certificate step against the staging CA first:
   `KUBECONFIG=~/.kube/prime-rancher-aws.kubeconfig STAGING=1 modules/common/rancher_aws_le_cert.sh`
7. **Later, once Tailscale is up:** set `admin_cidrs = []`, `tofu apply`, re-export the outputs file
   (now the private IP), and point nuc-00's `rancher-aws` record at `rancher_private_ip`.

## Route 53 zone in a different AWS account
OpenTofu and `rancher-01`'s instance role only work with a zone in the lab account. When `kubernerdes.com`
is hosted in another account, delegate just the Rancher name to a small zone in the lab account (prime shown).
No credentials cross accounts, and no code changes are needed.

1. **Lab account:** create the public zone and note its four name servers:
   ```bash
   ZONE=rancher-aws.prime.kubernerdes.com
   ZONE_ID=$(aws route53 create-hosted-zone --name "$ZONE" \
     --caller-reference "$ZONE-$(date +%s)" --query 'HostedZone.Id' --output text)
   aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output text
   ```
2. **Account that owns `kubernerdes.com`:** add an `NS` record named `rancher-aws.prime.kubernerdes.com`
   with those four name servers.
3. **Check from a public resolver** (nuc-00's BIND answers for `prime` locally):
   `dig +short NS rancher-aws.prime.kubernerdes.com @1.1.1.1`
4. **`prime.tfvars`:** `route53_zone_name = "rancher-aws.prime.kubernerdes.com"`

The A record and the `_acme-challenge` TXT record then both live in the delegated zone.

- Do not delegate all of `prime.kubernerdes.com`: nuc-00's `*.prime` wildcard certificate solves its DNS-01
  challenge in the parent zone. That certificate uses root's own AWS credentials on nuc-00, which must keep
  pointing at the account that owns `kubernerdes.com`, separate from the lab credentials used here.
- OpenTofu does not manage this zone, so `Scripts/awsctl destroy` leaves it and the delegation in place for
  the next rebuild (about $0.50/month). Delete the zone and the `NS` record by hand when finished with AWS.

## Tailscale subnet router (prime shown)
`tailscale_router_enabled = true` builds `tailscale-01`: SL Micro (same AMI as rancher-01), `t3a.micro`,
pinned private IP `<vpc>.0.10`, an auto-assigned public IP (no Elastic IP), source/destination check off.
Both VPC route tables send `homelab_cidr` through it. Rough cost: ≈ $7/mo + public IPv4 ≈ $4; `awsctl stop`
stops it along with rancher-01.

Cloud-init installs Tailscale from the static tarball into `/opt/tailscale` (checksum verified;
`tailscale_version`, default newest stable) because SL Micro's `/usr` is read-only. Upgrade later with
`sudo /opt/tailscale/install.sh [version]`. **Not yet verified on the image**; if `tailscale-up` reports it
missing, look at `/var/log/cloud-init-output.log` on tailscale-01.

The on-prem end is **ts-onprem** (`ts-onprem.homelab.kubernerdes.com`, 10.10.12.14): a small VM on nuc-00,
bridged onto the homelab network (not libvirt's NAT network), so nuc-00 stays out of the routing path.

The VPC range must not overlap any home subnet, including IoT or guest VLANs: check before step 5
(once ts-onprem accepts routes, it sends the whole VPC range into the tunnel).

1. **Auth key:** Tailscale admin console → Settings → Keys → generate an auth key (not reusable, not
   ephemeral). Add it to `~/.config/homelab/creds` (`chmod 600`) on the machine that runs `awsctl`:
   ```bash
   export TAILSCALE_AUTHKEY='tskey-auth-...'
   ```
   It never goes into OpenTofu state or user_data: `tailscale-up` passes it over SSH.
2. **Build:** add `tailscale_router_enabled = true` to `prime.tfvars`, then `ENVIRONMENT=prime Scripts/awsctl build`.
3. **Join:** `ENVIRONMENT=prime Scripts/awsctl tailscale-up` (joins as `aws-prime-router`, advertising `vpc_cidr`).
4. **Admin console:** approve the `172.18.0.0/16` subnet route for `aws-prime-router`, and disable key expiry for it.
5. **ts-onprem** (on-prem side; VM on nuc-00, static 10.10.12.14/22, gateway 10.10.12.1, DNS nuc-00;
   the `ts-onprem` A/PTR records are in `Files/nuc-00/var/lib/named/master/`). On SLES / openSUSE:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' | sudo tee /etc/sysctl.d/99-tailscale.conf
   sudo sysctl --system
   sudo tailscale up --hostname=ts-onprem --advertise-routes=10.10.12.0/22 --accept-routes
   ```
   If firewalld is running, put `tailscale0` in the trusted zone (or stop firewalld) so it forwards.
   Approve the `10.10.12.0/22` route for ts-onprem in the admin console, and disable its key expiry.
   This alone is enough for **AWS → homelab** (Rancher SSHing to VMs it provisions on Harvester, the kube API
   of imported clusters): ts-onprem source-NATs that traffic to 10.10.12.14, so replies come straight back.
6. **Homelab → AWS routes.** On-prem hosts that open connections to the VPC need `172.18.0.0/16 via
   10.10.12.14`. The homelab is one flat /22, so put the route **on the hosts**, not only on the Sophos
   firewall: a firewall route makes the path asymmetric (out via the firewall, replies straight from
   ts-onprem on the same LAN), and a stateful firewall may drop those flows.
   - **nuc-00 (needed for 09/10/awsctl over the tunnel):**
     `sudo ip route add 172.18.0.0/16 via 10.10.12.14`, made persistent in nuc-00's network config
     (wicked: add `172.18.0.0/16 10.10.12.14 - -` to `/etc/sysconfig/network/routes`;
     NetworkManager: `nmcli connection modify <conn> +ipv4.routes "172.18.0.0/16 10.10.12.14"`).
   - **Rancher agents** (Harvester, imported clusters) reaching `rancher-aws` on 443: simplest is to keep
     the `rancher-aws` record on the Elastic IP (agents go over the internet, limited to
     `public_ingress_cidrs`). To keep them private, give those hosts the same route (or push DHCP option
     121 from nuc-00's dhcpd to DHCP clients) before moving the record to the private IP.
7. **Check from nuc-00:** `ping -c3 172.18.0.30` and `ssh -i ~/.ssh/id_rsa-prime sles@172.18.0.30 hostname`.
8. **Switch admin to the tunnel:** set `admin_cidrs = []`, `ENVIRONMENT=prime Scripts/awsctl apply`, then
   `ENVIRONMENT=prime Scripts/awsctl outputs` (rancher and router addresses become the private IPs), and
   point `~/.kube/prime-rancher-aws.kubeconfig` at `172.18.0.30` (or rerun 10). Move nuc-00's
   `rancher-aws` record to `172.18.0.30` only once every agent host has the route from step 6.

## Rules
- Use OpenTofu (`tofu`), not Terraform. `required_version` is pinned to OpenTofu 1.10+.
  (`.terraform.lock.hcl` is excluded by the global git ignore, so it is not committed.)
- No credentials or state in this repo. Use a remote backend such as S3, and turn on OpenTofu state encryption,
  or keep local state outside the checkout. AWS creds follow the `~/.bashrc.d` / `~/.config` pattern in PLAN.md.
