<!---
title: Snicket Labs Reference Architecture - GCP
folder: "Technical Documentation"
status: 2
-->

# Snicket Labs Reference Architecture - GCP

## Overview

A Terraform-based reference architecture for deploying the Snicket Labs system on **Google Kubernetes Engine (GKE)**. It provisions a GCP environment suitable for running the platform including, Kubernetes cluster, database, object storage, secrets, autoscaling, and ingress with TLS - onto which the platform helm chart is installed.

> **Important Note**: This reference architecture is intended as a **guide and starting point**. The modules are composable, so you may adapt them to work with an existing project, VPC, or cluster rather than creating everything from scratch.

## Contents
- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Required GCP Permissions](#required-gcp-permissions)
- [Quick Start](#quick-start)
- [Installing the platform (application layer)](#installing-the-platform-application-layer)
- [Secrets (ESO + Workload Identity)](#secrets-eso--workload-identity)
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
| VPC + subnets + Cloud NAT + PSA | `tf-dt-vpc` | Network foundation, including the Private Service Access range for Cloud SQL |
| GKE cluster (regional, private nodes, Workload Identity, Gateway API) | `tf-dt-gke` | Managed Kubernetes |
| Cloud SQL for PostgreSQL (private IP) | `tf-dt-cloud-sql` | Application database |
| GCS bucket + HMAC key | `tf-dt-gcs-active-storage` | Active Storage object store (S3-interop) |
| Workload Identity GSAs | `tf-dt-workload-identity` | Keyless GCP authentication for the app and ESO |
| App secrets in Secret Manager | `tf-dt-application-secrets` | API keys and owning-user password |
| External Secrets Operator | `tf-dt-external-secrets` | Syncs Secret Manager into Kubernetes Secrets |
| KEDA | `tf-dt-keda` | Event-driven autoscaling for the ingest pipeline |
| cert-manager | `tf-dt-cert-manager` | TLS certificate issuance |
| Gateway + ClusterIssuer + Certificate | `tf-dt-gke-gateway-tls` | Gateway API ingress with Let's Encrypt TLS |
| external-dns | `tf-dt-external-dns` | Automatic DNS records for the Gateway |

The infrastructure layer is complete on its own. **Installing the platform** is the application layer on top - the ESO secret sync and the platform helm chart. See [Installing the platform](#installing-the-platform-application-layer).

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
   The modules then enable `compute`, `container`, `sqladmin`, `servicenetworking`, `secretmanager`, and others as needed.
4. **`gke-gcloud-auth-plugin`** on your PATH. Terraform's Kubernetes and Helm providers use it (exec auth) to reach the cluster:
   ```bash
   gcloud components install gke-gcloud-auth-plugin
   ```
   > **Homebrew gotcha (macOS):** if `gcloud` was installed via Homebrew, `gcloud components install` reports success but installs **no binary at all** - there is nothing under the SDK root to symlink, so check before trusting it:
   > ```bash
   > find "$(gcloud info --format='value(installation.sdk_root)')" -name 'gke-gcloud-auth-plugin' -type f
   > ```
   > If that prints nothing, install the plugin outside gcloud (e.g. from the GKE release archive) or skip the exec plugin entirely by handing kubectl a token directly:
   > ```bash
   > kubectl config set-credentials <user> --token="$(gcloud auth print-access-token)"
   > ```
   > The token is short-lived, so this suits one-off access rather than daily use.
5. **`terraform`**, **`kubectl`**, and **`helm`**.
6. **For TLS and DNS - Optional:** a domain in Cloudflare and a Cloudflare API token scoped `Zone:DNS:Edit` and `Zone:Read` (used by both cert-manager's DNS-01 solver and external-dns). TLS is optional - see [Ingress, TLS, and DNS](#ingress-tls-and-dns).

### Tool and Provider Version Requirements

| Tool / Provider | Minimum Version | Purpose |
|---|---|---|
| **Terraform** | `>= 1.13` | Infrastructure as Code platform |
| **`gcloud` CLI** | latest | Authentication and Application Default Credentials |
| **`gke-gcloud-auth-plugin`** | latest | Exec auth for the Kubernetes/Helm providers |
| **kubectl** | `>= 1.28` | Kubernetes cluster management |
| **Helm** | `>= 3.0` | Platform chart and add-on installation |
| **Google** | `>= 5.0` | GCP resource management (GKE/Cloud SQL/VPC) |
| **Kubernetes** | `>= 2.20` | In-cluster resource provisioning |
| **Helm (provider)** | `>= 2.9` | `helm_release` resources (Gateway/TLS, operators) |

> Provider versions are defined in `environments/gcp/example/infrastructure/provider.tf` - check there for the authoritative constraints.

## Required GCP Permissions

The principal running Terraform (your user via Application Default Credentials, or a CI service account) needs admin-level access across the services this architecture provisions:

- GKE cluster creation and management (`roles/container.admin`)
- Compute / VPC networking, including Cloud NAT and static IPs (`roles/compute.admin`)
- Cloud SQL instance management (`roles/cloudsql.admin`)
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
   git clone https://github.com/snicketlabs/reference-architecture.git
   cd reference-architecture
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

## Installing the platform (application layer)

The infrastructure apply does **not** install the application. After it completes:

1. **Sync the secrets (ESO + Workload Identity)** into the `match` namespace. The Terraform modules create the *source* secrets in Secret Manager (DB, GCS-HMAC, API keys, owning-user password); the `eso-support` chart's `SecretStore` and `ExternalSecret`s materialise them as the Kubernetes Secrets the app expects; and one or two are created manually (`match-honeybadger-secret`, plus `match-docker-secret` unless you deploy through Distr). See [Secrets (ESO + Workload Identity)](#secrets-eso--workload-identity) below for full detail, including the gcloud commands.
2. **Install the platform.** Start from the chart's own [customer values template](https://github.com/snicketlabs/helm-charts/tree/main/charts/platform), which documents every key including the GCP-specific ones. For an environment built from this reference architecture, the values that matter are:

   | Value | Set it to |
   |---|---|
   | `domain` | your `gateway_hostname` |
   | `httpRoute.parentRefs[0].name` | `match-gateway` - the Gateway `tf-dt-gke-gateway-tls` creates |
   | `httpRoute.hostnames` | the same host as `domain` |
   | `gke.enabled` | `true`, for the `/up` HealthCheckPolicy. Without it the Gateway returns 503 with healthy pods behind it |
   | `postgres.*Secret` | read host, database, username and password from `postgres-credentials`. A rebuilt Cloud SQL instance gets a new private IP, so avoid literals |
   | `kedaAutoScaling.postgres.host` | the Cloud SQL private IP, literally - the chart cannot resolve it at render time once `dbPrimaryHostSecret` is set |
   | `s3.primaryBucket` / `region` | the bucket `tf-dt-gcs-active-storage` created, and your region |
   | `s3.compatibleEndpoint` | `https://storage.googleapis.com`, with `compatibleCredentialsSecret: s3-credentials` |
   | `metrics.enabled` | `false` - see the note above |
   | `imagePullSecrets` | `dockerconfig` for a plain Helm install. Leave it **unset** if deploying through Distr, which injects its own pull secret |

```bash
helm upgrade --install eso-support <secrets-configuration-gcp chart> -n match -f <eso-values>
helm upgrade --install match <platform chart>                        -n match -f <match-values>
```

> **`metrics.enabled` needs the Prometheus Operator CRDs.** The platform chart defaults `metrics.enabled: true`, which renders a `PodMonitor` (`monitoring.coreos.com/v1`). GKE ships Google Managed Prometheus, which does **not** install that CRD, so a stock install fails at render with `no matches for kind "PodMonitor"`. Either set `metrics.enabled: false`, or install the Prometheus Operator CRDs first. This is independent of `monitoring.enabled`.

Once the platform chart's `HTTPRoute` exists, external-dns writes the DNS record and the Gateway routes traffic.


## Secrets (ESO + Workload Identity)

The secrets backend used in this reference architecture is **GCP Secret Manager** with the **[External Secrets Operator (ESO)](https://external-secrets.io/)**, authenticated with **GKE Workload Identity**. ESO syncs the external secrets into native Kubernetes Secrets, so no CSI or secret-sync workaround is needed.

### Created by Terraform ("baked in")

- **Cloud SQL** connection details - written to Secret Manager by `tf-dt-cloud-sql`.
- **API secrets and owning-user password** - created by `tf-dt-application-secrets`.
- **GCS HMAC key** - minted by `tf-dt-gcs-active-storage` (`create_hmac_key`), providing the Active Storage S3-interop credentials.

### Operator and access

- ESO is installed by the `tf-dt-external-secrets` module.
- Its service account is granted `roles/secretmanager.secretAccessor` via Workload Identity (`tf-dt-workload-identity`), with trust on the Google service account.
- The [`secrets-configuration-gcp`](https://github.com/snicketlabs/helm-charts/tree/main/charts/secrets-configuration-gcp) chart provides the `SecretStore` and `ExternalSecret`s that materialise the Kubernetes Secrets the app expects: `postgres-credentials`, `api-secrets`, `owning-user-credentials`, `dockerconfig`, `honeybadger-api-key`, and `s3-credentials`. See [Installing the chart](#installing-the-chart) below.

### Prerequisites: manually created secrets

Up to two secrets are created by hand in Secret Manager (plain string values).

1. Docker registry credentials (`match-docker-secret`) - **only for a plain `helm install`**:
   ```bash
   printf '%s' "$SECRET_JSON" | gcloud secrets create match-docker-secret \
     --project <your-project-id> --data-file=-
   ```

   > **Skip this if you deploy the platform chart through Distr.** The Distr agent
   > injects its own pull secret covering the registry, so the chart has nothing to
   > add. Set `docker.enabled: false` in the values below and do not create this
   > secret - with the default `true` and no secret to read, the `dockerconfig`
   > `ExternalSecret` never syncs and sits failing.
   >
   > Do not set `imagePullSecrets` on the platform chart in that case either. Its
   > Distr base values keep that an empty list specifically so the agent can inject
   > into it, and Helm replaces lists rather than merging them - an entry there
   > removes the marker the agent looks for and nothing can pull.

2. Honeybadger API token, which will be provided securely by Snicket Labs (`match-honeybadger-secret`):
   ```bash
   printf '%s' "$SECRET_API_KEY" | gcloud secrets create match-honeybadger-secret \
     --project <your-project-id> --data-file=-
   ```

### Installing the chart

> Requires **chart 0.5.0 or later**. 0.4.0 removed the Redis secret, which this architecture no longer provisions - installing 0.3.0 or below fails to sync against a Secret Manager entry that does not exist. 0.5.0 added `docker.enabled`, used below.

The chart creates the Kubernetes service account that ESO authenticates as. Terraform deliberately does **not** create it - `tf-dt-workload-identity` is applied with `use_existing_k8s_sa = true` for the ESO identity, and only binds the Google service account to it - so the name here must match the `k8s_sa_name` Terraform was given (`match-secrets` in the committed example).

Secret Manager names are prefixed with your `env_id`, except the two you created by hand above. For `env_id = acme-prod`:

```yaml
# eso-values.yaml
clusterName: acme-prod
refreshInterval: 1h

serviceAccount:
  name: match-secrets        # must equal the eso_secrets_wi module's k8s_sa_name
  annotations:
    iam.gke.io/gcp-service-account: acme-prod-eso@<your-project-id>.iam.gserviceaccount.com

secretStore:
  name: gcp-secret-store
  provider:
    gcpsm:
      projectID: <your-project-id>
      auth:
        workloadIdentity:
          clusterLocation: us-central1   # the cluster's region, not the zone
          clusterName: acme-prod
          serviceAccountRef:
            name: match-secrets

# On Distr, set this false and drop secretNames.docker: the agent supplies the
# pull credentials, so there is no dockerconfig Secret for the chart to make.
docker:
  enabled: true

secretNames:                              # sources in Secret Manager
  cloudSql: acme-prod-cloud-sql           # tf-dt-cloud-sql
  api: acme-prod-api-secrets              # tf-dt-application-secrets
  user: acme-prod-user-password           # tf-dt-application-secrets
  docker: match-docker-secret             # created by hand, see above
  honeybadger: match-honeybadger-secret   # created by hand, see above

k8sSecretNames:                           # Kubernetes Secrets produced
  rdsPg: postgres-credentials
  api: api-secrets
  user: owning-user-credentials
  docker: dockerconfig
  honeybadger: honeybadger-api-key

gcsS3Interop:
  enabled: true
  secretName: acme-prod-gcs-hmac          # tf-dt-gcs-active-storage
  k8sSecretName: s3-credentials

smtp:
  enabled: false
```

```bash
helm repo add snicketlabs https://snicketlabs.github.io/helm-charts
helm upgrade --install eso-support snicketlabs/secrets-configuration-gcp \
  --version 0.5.0 -n match -f eso-values.yaml
```

Confirm every secret landed before installing the platform chart - the app fails in
confusing ways if one is missing:

```bash
kubectl get externalsecret -n match     # all should report SecretSynced
kubectl get secretstore -n match        # should report Valid / Ready
```

A `SecretStore` stuck invalid is almost always the Workload Identity binding: check that
`serviceAccount.name` matches Terraform's `k8s_sa_name`, and that the annotation names the
right Google service account.

> **Note:** on AWS this layer is installed by Terraform (`tf-dt-eks-secret-provider-classes`). On GCP it is a manual Helm install for now; bringing it under Terraform to match is intended in a future revision.

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

For sizing guidance (machine types, Cloud SQL tiers), see [Deployment Sizing Options](./docs/deployment-sizing.md). For autoscaling, see [Event Driven Autoscaling (KEDA)](./docs/keda.md).

## Teardown

`terraform destroy` works, with a few GCP quirks worth documenting for a *used* cluster:

1. **Operator Helm releases** can hang on uninstall due to finalizer deadlocks. Before destroy, `terraform state rm` the operator releases (cert-manager, external-secrets, keda) - they are removed with the cluster anyway. Keep `gateway_tls` in state - graceful Gateway removal cleans up the LB and NEGs.
2. **PSA peering** reports "producer services still using" for a few minutes after Cloud SQL is deleted, which also blocks the subnet (`resourceInUseByAnotherResource`). Delete the peering and retry just the VPC - two steps, not three:
   ```bash
   gcloud compute networks peerings delete servicenetworking-googleapis-com --network=<env>
   terraform destroy -target=module.vpc -var-file=<your-env>.tfvars
   ```
   The service networking connection is already out of state by this point, so `terraform state rm` on it is **not** needed.
3. **Dynamically-provisioned PVs** can orphan as `pvc-*` disks - sweep them with `gcloud compute disks list` / `delete`. Nothing in this architecture claims a volume any more, so there is normally nothing to find; the step stays for environments that mounted their own content PVCs.

The following persist by design and are not Terraform-managed: the state bucket, the WIF/CI config, and the manually-created Secret Manager secrets.

---

_This document covers the GCP reference architecture. For AWS, see [`README-aws.md`](./README-aws.md). For the repository overview, see [`README.md`](./README.md)._
