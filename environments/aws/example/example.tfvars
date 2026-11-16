# Sample defaults file for the reference architecture.
# Copy this to your own <company>.tfvars and edit. There are no small/medium/large
# presets: node pools autoscale, and the database is sized per deployment --
# see docs/deployment-sizing.md.

# AWS Configuration
region                 = "us-east-1"
availability_zone_name = "us-east-1a"



# Basic Configuration
env_use           = "prod"
env_id            = "example" # use your company name here
env_region        = "us1"
env_additional_id = "" # optional short suffix for resource names, e.g. "eu"

# EKS Admin Access
# Provide names of pre-existing IAM roles and/or SSO permission sets in your AWS account
# to grant EKS cluster admin access. This match reference architecture does not create
# these — it only grants them cluster admin access. You are responsible for creating
# them via your own Terraform or IAM tooling.
#
# NOTE: If neither variable is set, no EKS admin access is configured. The first
# terraform apply (AWS infrastructure) will succeed, but you will have no kubectl
# access and the second terraform apply (Kubernetes resources) will fail.
#
# admin_access_sso_permission_set_names = ["infra", "developer"]
# admin_access_role_names               = ["Infra"]


tags = {
  Environment = "prod"
  Company     = "example-company"
  ManagedBy   = "Terraform"
  #...
}

# Load Balancer Exposure
# Who can reach Match. The defaults publish it to the internet. See
# "Load balancer exposure" in README-aws.md before changing them.
#
# load_balancer_type = "internal"  # VPC-only; no public access at all
# load_balancer_ip_ranges = ["203.0.113.0/24", "198.51.100.7/32"]  # your egress ranges
# snicket_labs_remote_lb_access = false  # only with another support route agreed
load_balancer_type            = "internet-facing"
load_balancer_ip_ranges       = ["0.0.0.0/0"]
snicket_labs_remote_lb_access = true

# Network and Domain Configuration
cidr            = "10.25.0.0/16"
external_domain = "my-company.sbox.as-priv.net"

# Customer/Company specific (you'll still be prompted for cust_id)
# cust_id = "my-company"


# Database. This is the one value that genuinely has to be chosen per deployment:
# content, library size, comparison types and which features you use all load it
# differently. Start here and move up if you need to -- docs/deployment-sizing.md
# carries the full ladder and says which rungs are measured.
#
#   db.t3.medium    2 vCPU / 4 GiB    internal and PoC only; saturates under real load
#   db.m5.xlarge    4 vCPU / 16 GiB   default starting position
#   db.m5.2xlarge   8 vCPU / 32 GiB   first step up
#   db.m5.4xlarge  16 vCPU / 64 GiB   headroom for a large established library
rds_instance_class = "db.m5.xlarge"

# Storage autoscales, and RDS storage never shrinks -- so start low and let it grow.
rds_allocated_storage     = 20
rds_max_allocated_storage = 350
