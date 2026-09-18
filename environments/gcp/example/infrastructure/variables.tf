variable "gcp_project_id" {
  description = "GCP project ID (alphanumeric, e.g. gcp-client-hosted-sandbox). Use this for resource `project` args — GKE Workload Identity and IAM require the ID form, not the number."
  type        = string
}

variable "gcp_project_number" {
  description = "GCP project number (12-digit, e.g. 778387110885). Only for the few places that require the numeric form (e.g. service-agent SA emails). Most things want gcp_project_id."
  type        = string
}

variable "region" {
  description = "GCP region to deploy into (e.g. us-central1)"
  type        = string
}

variable "zone" {
  description = "GCP zone to deploy into (e.g. us-central1-c)"
  type        = string
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

variable "env_additional_id" {
  description = "An additional identifier for the environment (e.g., sm, db)"
  type        = string
  default     = ""
  validation {
    condition     = length(var.env_additional_id) <= 10 && can(regex("^[a-zA-Z0-9-]*$", var.env_additional_id))
    error_message = "env_additional_id must be up to 10 characters long, containing only letters, numbers, and hyphens."
  }
}

variable "gateway_enable_tls" {
  description = "Enable the HTTPS listener + static IP + cert-manager ClusterIssuer (needs gateway_hostname + cloudflare_api_token). false = HTTP-only Gateway."
  type        = bool
  default     = true
}

variable "gateway_hostname" {
  description = "Public hostname for the HTTPS listener + cert (must equal the app's ADSIGNAL_BASE_DOMAIN/SNICKET_BASE_DOMAIN). Only used when gateway_enable_tls=true."
  type        = string
  default     = "match-gcp-sandbox.ad-signal.io"
}

variable "dns_zone" {
  description = "The DNS zone external-dns manages records in. Must be the zone name as it appears in the DNS provider (e.g. \"ad-signal.io\"), NOT the full gateway hostname — external-dns matches domain_filters against zone names, so a full hostname matches nothing and silently skips all records."
  type        = string
  default     = "ad-signal.io"
}

variable "cluster_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer to annotate the Gateway with."
  type        = string
  default     = "letsencrypt-prod"
}

variable "acme_server" {
  description = "ACME directory URL. Staging avoids LE rate limits but issues untrusted certs; prod = browser-trusted (rate-limited)."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
}

variable "acme_email" {
  description = "Contact email for the Let's Encrypt ACME account (ClusterIssuer). Only used when gateway_enable_tls=true."
  type        = string
  default     = ""
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token scoped Zone:DNS:Edit for the DNS-01 solver. Only used when gateway_enable_tls=true. Prefer sourcing via ESO over passing here."
  type        = string
  default     = ""
  sensitive   = true
}