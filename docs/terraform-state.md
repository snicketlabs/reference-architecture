<!---
title: Terraform State
folder: "Technical Documentation"
status: 2
-->

# Terraform State

It's recommended you use a suitable [remote state](https://developer.hashicorp.com/terraform/language/state/remote) data store with Terraform.

The `initial-state/` directory contains Terraform configurations for creating a state bucket for remote Terraform state storage, one per cloud provider:

- `initial-state/aws/` — S3 (documented below)
- `initial-state/gcp/` — GCS (see [`initial-state/gcp/example/README.md`](../initial-state/gcp/example/README.md), including the bootstrap ordering)

The state bucket can't be managed by the state it stores, so it is created first with local state, then the environment's `backend.tf` is pointed at it.

## AWS (S3)

Each initial-state environment contains:

```
initial-state/aws/your-company/
├── main.tf               # S3 state bucket module configuration
├── providers.tf          # AWS provider configuration
└── outputs.tf            # Bucket information outputs
```

**Purpose**: Creates encrypted S3 buckets with versioning for Terraform state locking, providing a secure foundation for Terraform remote state management.

**Usage**:
```bash
cd initial-state/aws
cp -r example your-company
cd your-company
# Edit bucket name
vim main.tf
terraform init
terraform apply
```

Then point the environment's `backend.tf` at the bucket:

```hcl
terraform {
  backend "s3" {
    bucket       = "my-s3-bucket"
    key          = "environments/aws/your-company-name/infrastructure/s3/terraform.tfstate"
    region       = "your-region"
    use_lockfile = true
    encrypt      = true
  }
}
```

## GCP (GCS)

The GCS state bucket can't be managed by the state it stores, so create it first with local state. See **[`initial-state/gcp/example/README.md`](../initial-state/gcp/example/README.md)** for full detail, including the bootstrap ordering. In short:

```bash
cd initial-state/gcp
cp -r example <your-env> && cd <your-env>
# edit the (globally-unique) bucket name in main.tf, plus project/region in providers.tf
terraform init && terraform apply
```

Then point the environment's `backend.tf` at the bucket (GCS provides native state locking, so there is no lock table):

```hcl
terraform {
  backend "gcs" {
    bucket = "<your-state-bucket>"
    prefix = "environments/gcp/<your-env>/infrastructure"
  }
}
```
