<!---
title: Match Environment Reference Architecture - GCP
folder: "Technical Documentation"
status: 2
-->

# Match Environment Reference Architecture - GCP

## Overview

A Terraform-based reference architecture for deploying Match environments on **Google Kubernetes Engine (GKE)**. It provisions a GCP environment suitable for running Match including, Kubernetes cluster, database, cache, object storage, shared storage, secrets, autoscaling, and ingress with TLS - onto which the `helm-match` chart is installed.

> **Important Note**: This reference architecture is intended as a **guide and starting point**. The modules are composable, so you may adapt them to work with an existing project, VPC, or cluster rather than creating everything from scratch.

## Contents
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Required GCP Permissions](#required-gcp-permissions)
- [Quick Start](#quick-start)
- [Installing Match (application layer)](#installing-match-application-layer)
- [Secrets (ESO + Workload Identity)](#secrets-eso--workload-identity)
- [Shared storage (NFS provisioner vs Filestore)](#shared-storage-nfs-provisioner-vs-filestore)
- [Ingress, TLS, and DNS](#ingress-tls-and-dns)
- [Variable reference](#variable-reference)
- [Teardown](#teardown)
- [Deployment Sizing Options](./docs/deployment-sizing.md)
- [Terraform State](./docs/terraform-state.md)
- [Event Driven Autoscaling (KEDA)](./docs/keda.md)

## Architecture Overview

Running `terraform apply` in `environments/gcp/<your-env>/infrastructure` stands up the full platform in a **single apply**:

| Component | Module | Purpose |
|---|---|---|
| VPC + subnets + Cloud NAT + PSA | `tf-dt-vpc` | Network foundation, including the Private Service Access range for Cloud SQL and Memorystore |
| GKE cluster (regional, private nodes, Workload Identity, Gateway API) | `tf-dt-gke` | Managed Kubernetes |
| Cloud SQL for PostgreSQL (private IP) | `tf-dt-cloud-sql` | Application database |
| Memorystore for Redis (private IP) | `tf-dt-memorystore` | Sidekiq and cache |
| GCS bucket + HMAC key | `tf-dt-gcs-active-storage` | Active Storage object store (S3-interop) |
| Shared RWX storage | `tf-dt-nfs-provisioner` | `ReadWriteMany` storage for the pipeline (internal/test default). For production, swap in `tf-dt-filestore` - see below |
| Workload Identity GSAs | `tf-dt-workload-identity` | Keyless GCP authentication for the app and ESO |
| App secrets in Secret Manager | `tf-dt-application-secrets` | API keys and owning-user password |
| External Secrets Operator | `tf-dt-external-secrets` | Syncs Secret Manager into Kubernetes Secrets |
| KEDA | `tf-dt-keda` | Event-driven autoscaling for the ingest pipeline |
| cert-manager | `tf-dt-cert-manager` | TLS certificate issuance |
| Gateway + ClusterIssuer + Certificate | `tf-dt-gke-gateway-tls` | Gateway API ingress with Let's Encrypt TLS |
| external-dns | `tf-dt-external-dns` | Automatic DNS records for the Gateway |

The infrastructure layer is complete on its own. **Installing Match** is the application layer on top - the ESO secret sync and the `helm-match` chart. See [Installing Match](#installing-match-application-layer).

## Prerequisites

Before using this reference architecture, ensure you have:

1. **A GCP project.** You will need both its **ID** (alphanumeric, e.g. `acme-match-prod`) and its **number** (12-digit). Workload Identity and IAM require the project ID; a few service-agent emails need the number.
2. **The `gcloud` CLI** authenticated, with **Application Default Credentials** for Terraform:
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project <PROJECT_ID>
   ```
3. **Two APIs enabled up front** (everything else is enabled by the modules):
   ```bash
   gcloud services enable serviceusage.googleapis.com \
     cloudresourcemanager.googleapis.com --project <PROJECT_ID>
   ```
   The modules then enable `compute`, `container`, `sqladmin`, `redis`, `servicenetworking`, `secretmanager`, and others as needed.
4. **`gke-gcloud-auth-plugin`** on your PATH. Terraform's Kubernetes and Helm providers use it (exec auth) to reach the cluster:
   ```bash
   gcloud components install gke-gcloud-auth-plugin
   ```
   > **Homebrew gotcha (macOS):** if `gcloud` was installed via Homebrew, `gcloud components install` reports "up to date" but the plugin binary isn't symlinked onto PATH. Symlink it:
   > ```bash
   > ln -sf "$(gcloud info --format='value(installation.sdk_root)')/bin/gke-gcloud-auth-plugin" /opt/homebrew/bin/
   > ```
5. **`terraform`**, **`kubectl`**, and **`helm`**.
6. **For TLS and DNS - Optional:** a domain in Cloudflare and a Cloudflare API token scoped `Zone:DNS:Edit` and `Zone:Read` (used by both cert-manager's DNS-01 solver and external-dns). TLS is optional - see [Ingress, TLS, and DNS](#ingress-tls-and-dns).

### Tool and Provider Version Requirements

| Tool / Provider | Minimum Version | Purpose |
|---|---|---|
| **Terraform** | `>= 1.13` | Infrastructure as Code platform |
| **`gcloud` CLI** | latest | Authentication and Application Default Credentials |
| **`gke-gcloud-auth-plugin`** | latest | Exec auth for the Kubernetes/Helm providers |
| **kubectl** | `>= 1.28` | Kubernetes cluster management |
| **Helm** | `>= 3.0` | Match chart and add-on installation |
| **Google** | `>= 5.0` | GCP resource management (GKE/Cloud SQL/Memorystore/VPC) |
| **Kubernetes** | `>= 2.20` | In-cluster resource provisioning |
| **Helm (provider)** | `>= 2.9` | `helm_release` resources (Gateway/TLS, operators) |

> Provider versions are defined in `environments/gcp/example/infrastructure/provider.tf` - check there for the authoritative constraints.

## Required GCP Permissions

The principal running Terraform (your user via Application Default Credentials, or a CI service account) needs admin-level access across the services this architecture provisions:

- GKE cluster creation and management (`roles/container.admin`)
- Compute / VPC networking, including Cloud NAT and static IPs (`roles/compute.admin`)
- Cloud SQL instance management (`roles/cloudsql.admin`)
- Memorystore for Redis management (`roles/redis.admin`)
- GCS bucket and HMAC key operations (`roles/storage.admin`)
- Secret Manager (`roles/secretmanager.admin`)
- Service account creation and Workload Identity bindings (`roles/iam.serviceAccountAdmin`, `roles/iam.workloadIdentityPoolAdmin`)
- Project IAM policy management (`roles/resourcemanager.projectIamAdmin`)
- Private Service Access / service networking (`roles/servicenetworking.networksAdmin`)
- Enabling APIs (`roles/serviceusage.serviceUsageAdmin`)

**For short-lived testing**, granting `roles/owner` on the project is the simplest option. **For production**, prefer least-privilege: grant only the scoped roles above (or a custom role), separate responsibilities across principals, and audit IAM activity regularly.

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/ad-signalio/match-reference-architecture.git
   cd match-reference-architecture
   ```

2. **Bootstrap the Terraform state bucket.** The GCS state bucket can't be managed by the state it stores, so create it first with local state. See **[Terraform State](./docs/terraform-state.md)** and [`initial-state/gcp/example/README.md`](./initial-state/gcp/example/README.md) for the full bootstrap ordering. In short:
   ```bash
   cd initial-state/gcp
   cp -r example <your-env> && cd <your-env>
   # edit the (globally-unique) bucket name in main.tf, plus project/region in providers.tf
   terraform init && terraform apply
   ```

3. **Create your environment directory** from the committed `example`:
   ```bash
   cd environments/gcp
   cp -r example <your-env> && cd <your-env>/infrastructure
   ```

4. **Configure the backend** to point at your state bucket (GCS provides native state locking, so there is no lock table):
   ```hcl
   terraform {
     backend "gcs" {
       bucket = "<your-state-bucket>"
       prefix = "environments/gcp/<your-env>/infrastructure"
     }
   }
   ```

5. **Configure variables and deploy:**
   ```bash
   # edit <your-env>.tfvars (see Variable reference) and backend.tf
   terraform init
   terraform apply -var-file=<your-env>.tfvars
   ```

This is a **single apply** - there is no staged or tiered apply.

> **Note:** The `example` environment is the canonical, committed reference. Copy it per environment, and keep secrets (such as the Cloudflare token) out of committed tfvars - pass them via CI secrets or a gitignored tfvars.

## Installing Match (application layer)

The infrastructure apply does **not** install the application. After it completes:

1. **Sync the secrets (ESO + Workload Identity)** into the `match` namespace. The Terraform modules create the *source* secrets in Secret Manager (DB, Redis, GCS-HMAC, API keys, owning-user password); the `eso-support` chart's `SecretStore` and `ExternalSecret`s materialise them as the Kubernetes Secrets the app expects; and two are created manually (`match-docker-secret`, `match-honeybadger-secret`). See [Secrets (ESO + Workload Identity)](#secrets-eso--workload-identity) below for full detail, including the gcloud commands.
2. **Install the Match app.** Install the `helm-match` chart into `match` with the GCP values: Postgres → `match-postgres-credentials`, Redis → `match-redis`, Active Storage → GCS S3-interop endpoint + `match-s3-credentials`, shared storage → the `match-shared-storage-nfs` RWX class, `kedaAutoScaling.enabled`, `httpRoute.enabled` attaching to the `match-gateway`, and `gke.enabled` for the `/up` HealthCheckPolicy.

```bash
helm upgrade --install eso-support <eso-support chart> -n match -f <eso-values>
helm upgrade --install match <helm-match chart>       -n match -f <match-values>
```

Once the `helm-match` `HTTPRoute` exists, external-dns writes the DNS record and the Gateway routes traffic.


## Secrets (ESO + Workload Identity)

The secrets backend used in this reference architecture is **GCP Secret Manager** with the **[External Secrets Operator (ESO)](https://external-secrets.io/)**, authenticated with **GKE Workload Identity**. ESO syncs the external secrets into native Kubernetes Secrets, so no CSI or secret-sync workaround is needed.

### Created by Terraform ("baked in")

- **Cloud SQL** connection details - written to Secret Manager by `tf-dt-cloud-sql`.
- **Memorystore** connection details - written by `tf-dt-memorystore`.
- **API secrets and owning-user password** - created by `tf-dt-application-secrets`.
- **GCS HMAC key** - minted by `tf-dt-gcs-active-storage` (`create_hmac_key`), providing the Active Storage S3-interop credentials.

### Operator and access

- ESO is installed by the `tf-dt-external-secrets` module.
- Its service account is granted `roles/secretmanager.secretAccessor` via Workload Identity (`tf-dt-workload-identity`), with trust on the Google service account.
- The [`secrets-configuration/eso-support`](https://github.com/ad-signalio/match-reference-architecture/tree/main/optional-add-ons/secrets-configuration/eso-support) chart provides the `SecretStore` and `ExternalSecret`s that materialise the Kubernetes Secrets the app expects: `match-postgres-credentials`, `match-redis`, `match-api-secrets`, `match-owning-user-credentials`, `dockerconfig`, `honeybadger-api-key`, and `match-s3-credentials`.

### Prerequisites: manually created secrets

Two secrets must be created by hand in Secret Manager (plain string values):

1. Docker registry credentials (`match-docker-secret`):
   ```bash
   printf '%s' "$SECRET_JSON" | gcloud secrets create match-docker-secret \
     --project <your-project-id> --data-file=-
   ```
2. Honeybadger API token, which will be provided securely by Snicket Labs (`match-honeybadger-secret`):
   ```bash
   printf '%s' "$SECRET_API_KEY" | gcloud secrets create match-honeybadger-secret \
     --project <your-project-id> --data-file=-
   ```

## Shared storage (NFS provisioner vs Filestore)

The ingest pipeline needs a `ReadWriteMany` (RWX) volume that several pods mount at once - the `helm-match` chart claims it as `match-shared-storage`. This reference architecture offers **two ways** to back that claim. Both present the same `match-shared-storage` RWX claim to the chart, so switching between them does not change the application configuration - only the infrastructure module differs.

### Which one to choose

| | **NFS provisioner** (`tf-dt-nfs-provisioner`) | **Filestore** (`tf-dt-filestore`) |
|---|---|---|
| What it is | A single in-cluster NFS server pod backed by a GKE block disk | Managed GCP Filestore (a hosted NFS service) |
| Availability | Single point of failure - if the pod or its node is lost, the mount is unavailable until it reschedules | Managed and SLA-backed; no in-cluster server to lose |
| Cost | Low - just the backing disk (e.g. a 150 GiB `standard-rwo` PD) | Higher - BASIC_HDD has a **1 TiB minimum** (around $200/month) |
| Setup | Works out of the box; default in the example env | Needs the **GKE Filestore CSI driver addon** enabled on the cluster |
| Default in repo | **Yes** - wired into `environments/gcp/example` | Opt-in - swap it in for production |

**Use the NFS provisioner for** internal, test, demo, and bare-metal-style environments - anywhere a single-point-of-failure shared volume is acceptable and you want to keep cost low. This is the committed default.

**Use Filestore for** production and any environment that needs a resilient, SLA-backed shared filesystem. It is opt-in because of the 1 TiB minimum spend and the CSI driver requirement, so it is left commented out in the example env rather than provisioned by default.

> **Note:** Both options are recommendations and starting points, as elsewhere in this reference architecture. If you already run a shared filesystem (an existing Filestore instance, a third-party NFS server, etc.), you can point the `match-shared-storage` claim at your own RWX StorageClass instead.

### Using the NFS provisioner (default)

This is the block already present in `environments/gcp/example/infrastructure/main.tf`:

```hcl
module "nfs_provisioner" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=generic/tf-hosted-modules/tf-dt-nfs-provisioner/v1.0.0"

  # Pinned ClusterIP must sit in the GKE services range and be high enough to
  # avoid colliding with auto-assigned ClusterIPs (e.g. kube-dns).
  service_cluster_ip = "10.8.15.250"

  # GKE's default RWO StorageClass backs the NFS server's disk.
  backing_storage_class = "standard-rwo"
  backing_disk_size     = "150Gi"
  storage_class_name    = "match-shared-storage-nfs"

  depends_on = [module.gke]
}
```

The chart's `storage.sharedStorage` claim must fit under `backing_disk_size`, so bump the backing disk for anything beyond a smoke test. The corresponding Match values are:

```yaml
storage:
  sharedStorage:
    enabled: true
    claimName: match-shared-storage
    storageClassName: match-shared-storage-nfs
    size: 150Gi   # must fit under the provisioner's backing_disk_size
```

### Switching to Filestore (production)

To use Filestore instead, comment out the `nfs_provisioner` module, enable the Filestore CSI driver addon on the GKE cluster, and add the `tf-dt-filestore` module - for example:

```hcl
module "filestore" {
  source = "git::https://github.com/ad-signalio/terraform-utils.git?ref=gcp/tf-hosted-modules/tf-dt-filestore/<version>"

  project_id         = var.gcp_project_id
  env_name           = var.env_id
  location           = var.zone
  tier               = "BASIC_HDD"   # 1 TiB minimum
  capacity_gb        = 1024
  network            = module.vpc.network_self_link
  storage_class_name = "match-shared-storage-nfs"

  depends_on = [module.gke]
}
```

Then point the Match values at the same `match-shared-storage-nfs` StorageClass - the `claimName` (`match-shared-storage`) is unchanged.

> **Permissions gotcha:** Filestore has no per-export gid knob (unlike the NFS provisioner), so pods must write as nonroot via `podSecurityContext.fsGroup: 65532` rather than relying on a matching export gid. Confirm the app can write to `/app/storage` on first deploy.

## Ingress, TLS, and DNS

This reference architecture uses the **Gateway API** (not Ingress), with **cert-manager** for TLS and **external-dns** for DNS:

- **`tf-dt-gke-gateway-tls`** creates the `Gateway` (GatewayClass `gke-l7-global-external-managed`, a global external L7 load balancer) with an HTTP:80 listener always, and - when `gateway_enable_tls = true` - an HTTPS:443 listener bound to a reserved static IP, plus a cert-manager `ClusterIssuer` (ACME / Let's Encrypt, using the Cloudflare DNS-01 solver) and a `Certificate` for the app hostname.
- **cert-manager** issues the certificate via DNS-01. It creates temporary `_acme-challenge` TXT records; it does **not** manage your A record.
- **external-dns** (`tf-dt-external-dns`) reads the `HTTPRoute` hostname and the Gateway's IP and creates or updates the A record in Cloudflare. With `policy = sync` the record is also removed on teardown, so there are no dangling records.
- The app forces `https://<domain>` (`default_url_options`), so `gateway_hostname` **must equal** the app's `ADSIGNAL_BASE_DOMAIN`.

### Bringing your own TLS / DNS (no Cloudflare)

The automated TLS and DNS path depends on a Cloudflare-hosted domain. If you don't use Cloudflare, you have two options:

- **HTTP-only Gateway.** Set `gateway_enable_tls = false`. The Gateway is created with only the HTTP:80 listener and no cert-manager `ClusterIssuer`/`Certificate` and no static HTTPS IP. **You are then responsible for terminating TLS yourself** - e.g. fronting the Gateway with your own load balancer or CDN, or terminating at a proxy - and for creating the DNS record by hand.
- **Bring your own ingress entirely.** Comment out the `cert_manager` / `gateway_tls` / `external_dns` modules and wire up your own ingress, TLS issuance, and DNS.

> **Note:** We intend to offer TLS/DNS paths that don't depend on Cloudflare (for example HTTP-01 validation via cert-manager with DNS records added manually) in a future revision.

## Variable reference

Set these in `<your-env>.tfvars` (see `environments/gcp/example/infrastructure/variables.tf`):

| Variable | Required | Example | Notes |
|---|---|---|---|
| `gcp_project_id` | yes | `acme-match-prod` | Alphanumeric ID; used by GKE/WI/IAM |
| `gcp_project_number` | yes | `778387110885` | 12-digit; needed only in numeric form |
| `region` | yes | `us-central1` | Deployment region |
| `zone` | yes | `us-central1-a` | Default zone (Cloud SQL) |
| `env_id` | yes | `acme-prod` | Names all resources |
| `gateway_enable_tls` | no (default `true`) | `true` | HTTPS listener + cert + static IP |
| `gateway_hostname` | when TLS | `match.acme.com` | Must equal the app domain |
| `cluster_issuer_name` | no | `letsencrypt-prod` | cert-manager ClusterIssuer name |
| `acme_server` | no | LE prod URL | Use staging while testing |
| `acme_email` | when TLS | `infra@acme.com` | ACME account email (set via CI secret) |
| `cloudflare_api_token` | when TLS | _(secret)_ | `Zone:DNS:Edit`; prefer a CI secret or gitignored tfvars |

For sizing guidance (machine types, Cloud SQL tiers, Memorystore), see [Deployment Sizing Options](./docs/deployment-sizing.md). For autoscaling, see [Event Driven Autoscaling (KEDA)](./docs/keda.md).

## Teardown

`terraform destroy` works, with a few GCP quirks worth documenting for a *used* cluster:

1. **Operator Helm releases** can hang on uninstall due to finalizer deadlocks. Before destroy, `terraform state rm` the operator releases (cert-manager, external-secrets, keda) - they are removed with the cluster anyway. Keep `gateway_tls` in state (graceful Gateway removal cleans up the LB and NEGs) and `nfs_provisioner` (which reclaims its disk).
2. **PSA peering** reports "producer services still using" for a few minutes after Cloud SQL and Memorystore are deleted. Run `terraform state rm module.vpc.google_service_networking_connection.psa` and `gcloud compute networks peerings delete servicenetworking-googleapis-com --network=<env>`, then `terraform destroy -target=module.vpc`.
3. **Dynamically-provisioned PVs** can orphan as `pvc-*` disks - sweep them with `gcloud compute disks list` / `delete`.

The following persist by design and are not Terraform-managed: the state bucket, the WIF/CI config, and the manually-created Secret Manager secrets.

---

_This document covers the GCP reference architecture. For AWS, see [`README-aws.md`](./README-aws.md). For the repository overview, see [`README.md`](./README.md)._
