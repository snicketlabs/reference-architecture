module "vpc" {
  source             = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-vpc/v1.0.0"
  project_id         = var.gcp_project_number
  env_name           = var.env_id
  region             = var.region
  control_plane_cidr = "172.16.0.0/28"
}

module "gke" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-gke/v1.0.0"

  project_id   = var.gcp_project_id
  cluster_name = var.env_id
  region       = var.region
  # Regional/multi-zone: us-central1-a kept hitting ZONE_RESOURCE_POOL_EXHAUSTED
  # (e2-standard-2/4) and -c stocked out earlier — spread nodes across -b and -f
  # so node creation isn't pinned to one capacity-starved zone. Control plane is
  # regional (us-central1); Cloud SQL/Memorystore reachable via PSA regardless.
  regional = true
  zones    = ["us-central1-b", "us-central1-f"]

  network             = module.vpc.network_name
  subnetwork          = module.vpc.subnet_name
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name

  master_ipv4_cidr_block = "172.16.0.0/28"

  # e2-standard-4 (4 vCPU, ~3.92 allocatable): the KEDA ingest scaledjobs
  # (process-qc, fingerprint, etc.) request cpu:2 from the chart defaults, which
  # can never fit an e2-standard-2 (~1.93 allocatable)

  machine_type   = "e2-standard-4"
  min_node_count = 1
  max_node_count = 2


  gateway_api_channel = "CHANNEL_STANDARD"
}


module "nfs_provisioner" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-nfs-provisioner/v1.0.0"

  # Pinned ClusterIP must sit in the GKE services range (10.8.0.0/20) and be
  # high enough to avoid colliding with auto-assigned ClusterIPs (e.g. kube-dns).
  service_cluster_ip = "10.8.15.250"

  # GKE's default RWO StorageClass backs the NFS server's disk.
  # Must exceed the chart's storage.sharedStorage.size (default 100Gi) plus
  # headroom, or the match-shared-storage RWX claim can't be provisioned and
  # every app pod hangs on an unbound PVC.
  backing_storage_class = "standard-rwo"
  backing_disk_size     = "150Gi"
  storage_class_name    = "match-shared-storage-nfs"

  depends_on = [module.gke]
}


# Production-tier shared storage — OPT-IN alternative to module.nfs_provisioner
# above. The NFS provisioner is single-pod
# managed GCP Filestore (tf-dt-filestore) is SLA-backed RWX for production. To use
# it: comment out module.nfs_provisioner above, uncomment this, enable the GKE
# Filestore CSI driver addon, set storage.sharedStorage.claimName=match-shared-storage
# + podSecurityContext.fsGroup=65532 in match-values. 
# module "filestore" {
#   source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-filestore/v1.0.0"
#
#   project_id = var.gcp_project_id
#   name       = "${var.env_id}-fs"
#   location   = var.zone               # BASIC tiers are zonal
#   network    = module.vpc.network_name
#   namespace  = "match"                # creates the match-shared-storage RWX PVC
#
#   depends_on = [module.gke]
# }

module "cloud_sql" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-cloud-sql/v1.0.0"

  project_id = var.gcp_project_id
  env_name   = var.env_id
  region     = var.region
  zone       = var.zone
  tier       = "db-custom-1-3840" # smallest tier that supports private IP (db-custom-1-3840 = 1 vCPU, 3.75 GiB RAM)

  # self_link (ID-form) not network_id: the VPC runs on the project NUMBER, so
  # network_id is "projects/778387110885/..." which Cloud SQL rejects (project id
  # must start with a lowercase letter). The self-link carries the project ID.
  private_network    = module.vpc.network_self_link
  allocated_ip_range = module.vpc.psa_range_name

  depends_on = [module.vpc]
}

#  BASIC tier, 1 GiB.
module "memorystore" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-memorystore/v1.0.0"

  project_id     = var.gcp_project_id
  env_name       = var.env_id
  region         = var.region
  tier           = "BASIC"
  memory_size_gb = 1

  network           = module.vpc.network_self_link
  reserved_ip_range = module.vpc.psa_range_name

  depends_on = [module.vpc]
}

module "active_storage" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-gcs-active-storage/v1.0.0"

  project_id            = var.gcp_project_id
  env_name              = var.env_id
  location              = var.region
  force_destroy         = true
  service_account_email = module.workload_identity.gcp_service_account_email
  create_hmac_key       = true
  # CORS origin for Active Storage browser direct-uploads (PUT straight to GCS).
  # Without this the browser's cross-origin PUT to storage.googleapis.com is
  # blocked and material creation silently never submits.
  app_url = ["https://${var.gateway_hostname}"]
}


module "workload_identity" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-workload-identity/v1.0.0"

  project_id   = var.gcp_project_id
  name         = "${var.env_id}-app"
  cluster_name = module.gke.cluster_name
  location     = module.gke.location
  namespace    = "default"
  k8s_sa_name  = "match-app"
  roles        = ["roles/secretmanager.secretAccessor"]

  depends_on = [module.gke]
}


module "application_secrets" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-application-secrets/v1.0.0"

  project_id = var.gcp_project_id
  env_name   = var.env_id
}

module "external_secrets" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-external-secrets/v1.0.0"

  depends_on = [module.gke]
}

# The shared "match" namespace — owned explicitly here rather than created
# incidentally by a module's helm create_namespace. Every consumer (gateway_tls,
# keda RBAC, the helm app layer) depends on this, so there's one well-defined
# owner and ordering instead of a race between whichever module happens to make
# the ns first.
resource "kubernetes_namespace_v1" "match" {
  metadata {
    name = "match"
  }
  depends_on = [module.gke]
}

# KEDA — autoscaling operator for the match chart's ScaledJob/ScaledObject
# workloads. Watches the "match" namespace. create_match_namespace=false: ns
# "match" is owned by kubernetes_namespace_v1.match above. depends_on it so the
# ns EXISTS before KEDA installs its RBAC into it.
module "keda" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-keda/v1.0.5"

  namespace              = "keda"
  application_namespace  = "match"
  create_match_namespace = false

  depends_on = [module.gke, kubernetes_namespace_v1.match]
}

module "eso_secrets_wi" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-workload-identity/v1.0.0"

  project_id          = var.gcp_project_id
  name                = "${var.env_id}-eso"
  cluster_name        = module.gke.cluster_name
  location            = module.gke.location
  namespace           = "match"
  k8s_sa_name         = "match-secrets"
  use_existing_k8s_sa = true
  annotate_k8s_sa     = false
  roles               = ["roles/secretmanager.secretAccessor"]

  depends_on = [module.gke]
}

# --- Gateway API + cert-manager ---
# This reference architecture is based upon the Gateway API (not Ingress) and cert-manager for TLS. 
# We recommend using a real domain and cert-manager for TLS, as well as enabling external-dns to automatically manage the DNS records for the Gateway hostname.
# The the following modules can be commented out if you wish to use a different ingress solution or manage TLS and DNS manually.

module "cert_manager" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-cert-manager/v1.0.0"

  chart_version = "v1.16.2"

  depends_on = [module.gke]
}

module "gateway_tls" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-gke-gateway-tls/v1.0.0"

  project_id             = var.gcp_project_id
  namespace              = "match"
  enable_tls             = var.gateway_enable_tls
  hostname               = var.gateway_hostname
  cluster_issuer_name    = var.cluster_issuer_name
  acme_server            = var.acme_server
  acme_email             = var.acme_email
  cloudflare_api_token   = var.cloudflare_api_token
  cert_manager_namespace = module.cert_manager.namespace
  static_ip_name         = "${var.env_id}-match-gw"
  create_namespace       = false # ns "match" is owned by kubernetes_namespace_v1.match

  # Cluster (Gateway API CRDs) + cert-manager (its CRDs) + ns "match" must exist
  # before the helm release applies; depends_on enforces that within one apply.
  depends_on = [module.gke, module.cert_manager, kubernetes_namespace_v1.match]
}


module "external_dns" {
  count  = var.gateway_enable_tls ? 1 : 0
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-external-dns/v1.0.0"

  # external-dns matches domain_filters against DNS *zone* names, so this must be
  # the zone (ad-signal.io), not the full gateway hostname. registry=txt + txt_owner_id
  # scopes it to only the records it creates, so a zone-wide filter is safe here.
  domain_filters       = [var.dns_zone]
  txt_owner_id         = var.env_id
  policy               = "sync"
  cloudflare_api_token = var.cloudflare_api_token

  depends_on = [module.gke]
}