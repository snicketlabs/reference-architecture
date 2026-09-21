terraform {
  backend "gcs" {
    bucket = "client-hosted-sandbox-tf-state"
    prefix = "environments/gcp/example/infrastructure"
  }
}
