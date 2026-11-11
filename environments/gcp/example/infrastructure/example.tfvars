gcp_project_id     = "gcp-client-hosted-sandbox"
gcp_project_number = "778387110885"
region             = "us-central1"
zone               = "us-central1-a"
env_id             = "sandbox-testing"

# cloudflare_api_token and acme_email are deliberately NOT set here. A tfvars
# file beats TF_VAR_ in Terraform's precedence order, so setting them would
# silently override whatever your pipeline injects -- a placeholder here means
# cert-manager's DNS-01 solver and external-dns both get junk and
# fail. Pass them as TF_VAR_cloudflare_api_token / TF_VAR_acme_email from your
# pipeline's secret store, or from a gitignored tfvars for a local apply.
