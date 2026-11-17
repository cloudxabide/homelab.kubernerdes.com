# Copy to <ENVIRONMENT>.tfvars (gitignored) and adjust. Defaults already match Scripts/env.sh.
environment          = "community"
aws_region           = "us-east-1"
vpc_cidr             = "172.16.0.0/16"
public_ingress_cidrs = ["203.0.113.10/32"] # your home egress IP, or "0.0.0.0/0"
