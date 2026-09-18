<!---
title: Deployment Sizing Options
folder: "Technical Documentation"
status: 2
-->

# Deployment Sizing Options

This reference architecture includes pre-configured sizing templates (`small`, `medium`, `large`). There are corresponding `small.yaml`, `medium.yaml` and `large.yaml` values in the Match Helm chart that match these capacities. Work with Ad Signal Technical Services to understand your individual system needs.

Across both clouds the dimension that actually changes between profiles is the **managed database** (instance size and storage). Node pools autoscale, and the cache defaults are sensible for most workloads — scale them up for higher-throughput environments.

## AWS

The profiles are defined in `environments/aws/example/{small,medium,large}.tfvars`. They set a statically sized RDS instance with storage autoscaling; EKS nodes autoscale.

| Tier | `rds_instance_class` | Storage (`rds_allocated_storage` → `rds_max_allocated_storage`) |
|---|---|---|
| Small | `db.m5.xlarge` (4 vCPU / 16 GiB) | 20 → 100 GB |
| Medium | `db.m5.4xlarge` (16 vCPU / 64 GiB) | 50 → 200 GB |
| Large | `db.m5.4xlarge` (16 vCPU / 64 GiB) | 100 → 350 GB |

Medium and Large share the same instance class and differ only in allocated storage and autoscaling headroom.

## GCP

GCP sizing is set in the module blocks in `environments/gcp/<your-env>/infrastructure/main.tf` (the `cloud_sql`, `gke`, and `memorystore` modules). The committed `example` environment ships at the **Internal / test** tier; the values below mirror the AWS profiles.

| Tier | GKE node `machine_type` | Cloud SQL `tier` | Cloud SQL `disk_size` → autoresize limit | Memorystore |
|---|---|---|---|---|
| Internal / test (example default) | `e2-standard-4` (4 vCPU / 16 GiB) | `db-custom-1-3840` (1 vCPU / 3.75 GiB) | 20 GiB | `BASIC`, 1 GiB |
| Small | `e2-standard-4` (4 vCPU / 16 GiB) | `db-custom-4-16384` (4 vCPU / 16 GiB) | 20 → 100 GiB | `BASIC`, 1 GiB |
| Medium | `e2-standard-8` (8 vCPU / 32 GiB) | `db-custom-16-65536` (16 vCPU / 64 GiB) | 50 → 200 GiB | `STANDARD_HA`, 4 GiB |
| Large | `e2-standard-16` (16 vCPU / 64 GiB) | `db-custom-16-65536` (16 vCPU / 64 GiB) | 100 → 350 GiB | `STANDARD_HA`, 5 GiB |

**Compute and cache notes:**
- `e2-standard-4` is the practical minimum machine type. The KEDA ingest scaledjobs request around 2 vCPU (and the fingerprinter init around 3), which cannot be scheduled on a 2-vCPU node (`e2-standard-2` has roughly 1.93 allocatable). Node counts in `tf-dt-gke` are **per zone** for a regional cluster.
- Memorystore `BASIC` has no replica/failover; `STANDARD_HA` adds a replica for high availability. Use `STANDARD_HA` for production-grade Medium/Large environments.

> The GCP `{small,medium,large}.tfvars` profiles are currently placeholders pending dedicated GCP sizing variables. Until those land, apply the values above by editing the module blocks in `main.tf` directly.
