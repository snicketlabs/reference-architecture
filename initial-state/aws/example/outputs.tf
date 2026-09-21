output "bucket_name" {
  description = "The name of the S3 bucket created for Terraform state storage"
  value       = module.state_bucket.s3_bucket_id
}
