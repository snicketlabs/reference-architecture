<!---
title: GCP Initial State — GCS Terraform State Bucket
folder: "Technical Documentation"
status: 2
-->

# GCP initial state — GCS Terraform state bucket

Creates the GCS bucket used for remote Terraform state storage — the GCP
equivalent of `initial-state/aws/example/` (S3). GCS has **native state
locking built in**, so no DynamoDB-equivalent resource is needed.

## Bootstrap ordering (chicken-and-egg)

The state bucket cannot be managed by the state it stores. As with AWS:

1. Apply this configuration **with local state** to create the bucket:

   ```bash
   cd initial-state/gcp/your-company
   # Edit bucket name in main.tf (globally unique) and project/region in providers.tf
   terraform init
   terraform apply
   ```

2. Point the environment at the new bucket in
   `environments/gcp/your-company/infrastructure/backend.tf`:

   ```hcl
   terraform {
     backend "gcs" {
       bucket = "<your-state-bucket>"
       prefix = "environments/gcp/your-company/infrastructure"
     }
   }
   ```

3. Run `terraform init` in the environment directory — Terraform will offer to
   migrate any existing local state to the GCS backend.

The local `terraform.tfstate` produced by step 1 only tracks the bucket
itself; keep it somewhere safe (or re-import with
`terraform import google_storage_bucket.state_bucket <bucket-name>` if lost).

## Usage

```bash
cd initial-state/gcp
cp -r example your-company
cd your-company
# Edit bucket name
vim main.tf
terraform init
terraform apply
```
