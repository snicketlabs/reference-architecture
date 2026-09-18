# Variables aws specific
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.25.0.0/16"
  validation {
    condition     = can(cidrhost(var.cidr, 0))
    error_message = "cidr must be a valid IPv4 CIDR block (e.g., 10.25.0.0/16)."
  }
}

# Variables specific to self hosted match environments
variable "env_id" {
  description = "The name of the environment, used to name terraformed resources"
  type        = string
  validation {
    condition     = length(var.env_id) >= 3 && length(var.env_id) <= 30 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.env_id))
    error_message = "env_id must start with a letter and be 3-30 characters long, containing only letters, numbers, and hyphens."
  }
}

variable "env_use" {
  description = "The use case for the environment (e.g., test, staging, prod)"
  type        = string
  validation {
    condition     = length(var.env_use) >= 3 && length(var.env_use) <= 20 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.env_use))
    error_message = "env_use must start with a letter and be 3-20 characters long, containing only letters, numbers, and hyphens."
  }
}

variable "env_region" {
  description = "The region identifier for the environment (e.g., us1, eu1)"
  type        = string
  validation {
    condition     = length(var.env_region) >= 2 && length(var.env_region) <= 10 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.env_region))
    error_message = "env_region must start with a letter and be 2-10 characters long, containing only letters, numbers, and hyphens."
  }
}

variable "env_additional_id" {
  description = "An additional identifier for the environment (e.g., sm, db)"
  type        = string
  default     = ""
  validation {
    condition     = length(var.env_additional_id) <= 10 && can(regex("^[a-zA-Z0-9-]*$", var.env_additional_id))
    error_message = "env_additional_id must be up to 10 characters long, containing only letters, numbers, and hyphens."
  }
}

variable "availability_zone_name" {
  description = "For One Zone systems, specify the AWS Availability Zone in which to create the EKS cluster and EFS."
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for the application"
  type        = string
  default     = "match"
}

variable "external_domain" {
  description = "External domain name for the application"
  type        = string
  default     = "example.sbox.as-priv.net"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", var.external_domain))
    error_message = "external_domain must be a valid domain name format."
  }
}

variable "rds_instance_class" {
  description = "RDS instance class for the PostgreSQL database"
  type        = string
  default     = "db.t3.small"
  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.rds_instance_class))
    error_message = "rds_instance_class must be a valid RDS instance class (e.g., db.t3.small, db.r5.large)."
  }
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage in GB for the RDS PostgreSQL instance"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum storage in GB that RDS autoscaling can grow to"
  type        = number
  default     = 100
}

variable "admin_access_sso_permission_set_names" {
  description = "Names of pre-existing AWS SSO permission sets to grant EKS cluster admin access. These must already exist in your AWS account — this match reference architecture will not create them. Example: [\"infra\", \"developer\"]"
  type        = list(string)
  default     = []
}

variable "admin_access_role_names" {
  description = "Names of pre-existing AWS IAM roles to grant EKS cluster admin access. These must already exist in your AWS account — this match reference architecture will not create them. Example: [\"Infra\", \"DevOps\"]"
  type        = list(string)
  default     = []
}

variable "install_helm_charts" {
  description = "Use helm to install Keda crds instead of kubernetes manifests."
  type        = bool
  default     = true
}

variable "aws_marketplace_product_code" {
  description = "AWS Marketplace product code. Enable this for deployments purchased through AWS Marketplace: resources are tagged aws-apn-id = pc:<code> so AWS attributes your spend to the vendor. Leave empty if this deployment did not come through AWS Marketplace. Use the product code, not the prod-... Product ID."
  type        = string
  default     = ""
  validation {
    condition     = var.aws_marketplace_product_code == "" || can(regex("^[a-z0-9]+$", var.aws_marketplace_product_code))
    error_message = "aws_marketplace_product_code must be the alphanumeric product code, not the prod-... Product ID, or empty to disable."
  }
}
