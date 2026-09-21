output "bucket_name" {
  description = "The name of the GCS bucket created for Terraform state storage"
  value       = google_storage_bucket.state_bucket.name
}

output "bucket_url" {
  description = "The gs:// URL of the state bucket"
  value       = google_storage_bucket.state_bucket.url
}
