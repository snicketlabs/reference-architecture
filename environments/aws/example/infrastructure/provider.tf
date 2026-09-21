terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

locals {
  # AWS Partner Revenue Measurement tag, attributing this account's spend to the
  # software vendor. Set aws_marketplace_product_code on deployments purchased
  # through AWS Marketplace; empty everywhere else.
  # https://docs.aws.amazon.com/PRM/latest/aws-prm-onboarding-guide/resource-tagging.html
  prm_tags = var.aws_marketplace_product_code == "" ? {} : {
    "aws-apn-id" = "pc:${var.aws_marketplace_product_code}"
  }
}

provider "aws" {
  region = var.region

  # Backstop for anything not created through a module, carrying the same set the
  # modules get so the two cannot drift. Modules are still tagged explicitly:
  # default_tags does not populate the EKS launch template's tag_specifications,
  # which is what reaches EC2 instances.
  default_tags {
    tags = merge(module.label.tags, local.prm_tags)
  }
}

provider "kubernetes" {
  host                   = module.eks.eks_cluster_endpoint
  cluster_ca_certificate = module.eks.eks_cluster_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.eks_cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.eks_cluster_endpoint
    cluster_ca_certificate = module.eks.eks_cluster_certificate
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.eks_cluster_name]
      command     = "aws"
    }
  }
}