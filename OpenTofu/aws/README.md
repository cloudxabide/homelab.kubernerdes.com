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
- VPC from `vpc_cidr` (per-environment default: prime `172.16.0.0/16`, community `172.17.0.0/16`,
  both inside the reserved 172.16.0.0/12, so two environments never overlap on the tailnet), one AZ,
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
- For Rancher-provisioned downstream clusters on EC2: a `downstream` security group and an
  IAM user for the Amazon EC2 node driver (create its access key by hand; it is kept out of state)

## Not yet (needs Tailscale)
- Tailscale subnet router + routes for `homelab_cidr`
- Running `Scripts/09` / `10` against `rancher-01` (SSH and 6443 from nuc-00)
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
- **Not yet verified on this image:** that it runs cloud-init (the `sles` user and `rancher-01`
  hostname depend on it), and that `/etc/os-release` reports `NAME="SL-Micro"`, which
  `install_RKE2.sh` uses to pick the reboot + postboot path. Check both after the first boot.
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
| `outputs.tf` | Output contract with `Scripts/env.sh` (`rancher_vip`, `rancher_node_ips`) |
| `backend.hcl.example` / `example.tfvars` | Templates for the gitignored local copies |

## Rules
- Use OpenTofu (`tofu`), not Terraform. `required_version` is pinned to OpenTofu 1.10+.
  (`.terraform.lock.hcl` is excluded by the global git ignore, so it is not committed.)
- No credentials or state in this repo. Use a remote backend such as S3, and turn on OpenTofu state encryption,
  or keep local state outside the checkout. AWS creds follow the `~/.bashrc.d` / `~/.config` pattern in PLAN.md.
