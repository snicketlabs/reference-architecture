# Backend configuration for Terraform state storage
# This file defines where Terraform state will be stored

terraform {
  backend "s3" {
    bucket       = "s3-terraform-state-example-sandbox"
    key          = "environments/example/infrastructure/s3/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true

  }
}
