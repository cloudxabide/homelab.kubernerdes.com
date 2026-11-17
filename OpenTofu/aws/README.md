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

## Scope (planned)
- VPC from `AWS_VPC_CIDR` (default `172.16.0.0/16`, carved from the reserved 172.16.0.0/12)
- Site-to-site connectivity to the homelab supernet `10.10.12.0/22`
- EC2 instances for the Rancher Manager RKE2 cluster (3 nodes) plus an NLB on ports 80/443/6443/9345
- Optional: EC2 instances + NLB for Observability
- Subnets / security groups / IAM for AWS downstream clusters that Rancher provisions (EC2 node driver)
- Route 53 records for `rancher.${BASE_DOMAIN}` / `observability.${BASE_DOMAIN}`

After this provisions the nodes, the existing scripts (`09_install_RKE2_for_rancher_manager.sh`,
`10_install_rancher_manager.sh`) do the install, the same way they do on-prem.

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
| `outputs.tf` | Output contract with `Scripts/env.sh` (`rancher_lb_dns`, `rancher_node_ips`) |
| `backend.hcl.example` / `example.tfvars` | Templates for the gitignored local copies |

## Rules
- Use OpenTofu (`tofu`), not Terraform. `required_version` is pinned to OpenTofu 1.10+.
  (`.terraform.lock.hcl` is excluded by the global git ignore, so it is not committed.)
- No credentials or state in this repo. Use a remote backend such as S3, and turn on OpenTofu state encryption,
  or keep local state outside the checkout. AWS creds follow the `~/.bashrc.d` / `~/.config` pattern in PLAN.md.
