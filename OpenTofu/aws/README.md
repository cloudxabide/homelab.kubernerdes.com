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

## Rules
- Use OpenTofu (`tofu`), not Terraform. Commit `.terraform.lock.hcl`; pin `required_version` to an OpenTofu release.
- No credentials or state in this repo. Use a remote backend such as S3, and turn on OpenTofu state encryption,
  or keep local state outside the checkout. AWS creds follow the `~/.bashrc.d` / `~/.config` pattern in PLAN.md.
