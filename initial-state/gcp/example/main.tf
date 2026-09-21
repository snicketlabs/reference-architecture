resource "google_storage_bucket" "state_bucket" {
  name     = "example-tf-state"
  location = "US"

  force_destroy            = false
  public_access_prevention = "enforced"

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}
