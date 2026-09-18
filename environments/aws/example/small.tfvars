# Sample defaults file for match-environment setup

# AWS Configuration
region                 = "us-east-1"
availability_zone_name = "us-east-1a"

# Basic Configuration
env_use           = "prod"
env_id            = "example" # use your company name here
env_region        = "us1"
env_additional_id = "sm"

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

# Network and Domain Configuration
cidr            = "10.25.0.0/16"
external_domain = "my-company.sbox.as-priv.net"

# Customer/Company specific (you'll still be prompted for cust_id)
# cust_id = "my-company"

rds_instance_class        = "db.m5.xlarge"
rds_allocated_storage     = 20
rds_max_allocated_storage = 100
