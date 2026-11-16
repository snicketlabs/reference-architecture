<!---
title: Deployment Sizing Options
folder: "Technical Documentation"
status: 2
-->

# Deployment Sizing Options

There are no small, medium and large deployment profiles. There used to be, and
they were removed deliberately.

The presets predated autoscaling. They fixed a static number of workers against a
fixed database size, and the numbers were as much guesswork as measurement. Node
pools now autoscale, and the application scales its workers to demand, so the
presets mostly served to cap throughput in advance.

More importantly, a generic database size is not something we can get right on
your behalf. How hard your database works depends on your content, your library
size, the kinds of comparison you run and which features you use. Two deployments
processing the same number of content-minutes can need very different databases.

So the reference architecture ships **one starting position**, and we measure and
tell you when to move.

## Throughput

Two values bound throughput, and they ship aligned:

| Value | Default | What it does |
|---|---|---|
| `materialProcessingCount` | `"default=5"` | How many materials the application admits for processing at once |
| `maxReplicaCount` | per worker, in the chart's `values.yaml` | How far each worker may scale out |

They are set so no single stage caps throughput below what the application
admits. Raise both together in your own values file if you want more throughput
and have the cluster capacity for it — raising one alone will not help.

Node pools autoscale, so compute follows demand rather than a preset.

## AWS: the database

The default is set in `environments/aws/example/example.tfvars`. Copy it to your
own `<company>.tfvars` and edit.

| Instance class | vCPU / RAM | When |
|---|---|---|
| `db.t3.medium` | 2 / 4 GiB | Internal and proof-of-concept only. Not for production or production sized comparisons. |
| **`db.m5.xlarge`** | **4 / 16 GiB** | **Default starting position.** |
| `db.m5.2xlarge` | 8 / 32 GiB | First step up. |
| `db.m5.4xlarge` | 16 / 64 GiB | Headroom for a large, established library.|

Storage autoscales, and RDS storage never shrinks, so the default starts low and
grows: `rds_allocated_storage = 20`, `rds_max_allocated_storage = 350`.

### Knowing when to move

The symptom to watch for is material processing getting slower while the workers
themselves are not busy. A database short of CPU holds the pipeline up: jobs wait
on it, so wall times stretch while worker CPU stays low. Processing that has
gradually slowed down without the workers working harder is the signal to step up
a rung.

Database CPU sustained near its limit says the same thing more directly.

Work with Snicket Labs Technical Services to understand your individual system
needs.

## GCP

GCP sizing is set in the module blocks in
`environments/gcp/<your-env>/infrastructure/main.tf` (the `cloud_sql` and `gke`
modules).

> **GCP still carries the old tier tables.** The committed `example` environment
> ships at the Internal / test tier, and the `{small,medium,large}.tfvars` files
> there are placeholders pending dedicated GCP sizing variables. Bringing GCP in
> line with the single-default approach above is tracked separately. Until then,
> treat the table below as the existing starting points and apply them by editing
> the module blocks in `main.tf` directly.

| Tier | GKE node `machine_type` | Cloud SQL `tier` | Cloud SQL `disk_size` → autoresize limit |
|---|---|---|---|
| Internal / test (example default) | `e2-standard-4` (4 vCPU / 16 GiB) | `db-custom-1-3840` (1 vCPU / 3.75 GiB) | 20 GiB |
| Small | `e2-standard-4` (4 vCPU / 16 GiB) | `db-custom-4-16384` (4 vCPU / 16 GiB) | 20 → 100 GiB |
| Medium | `e2-standard-8` (8 vCPU / 32 GiB) | `db-custom-16-65536` (16 vCPU / 64 GiB) | 50 → 200 GiB |
| Large | `e2-standard-16` (16 vCPU / 64 GiB) | `db-custom-16-65536` (16 vCPU / 64 GiB) | 100 → 350 GiB |

**Compute notes:**
- `e2-standard-4` is the practical minimum machine type. The KEDA ingest scaledjobs request around 2 vCPU (and the fingerprinter init around 3), which cannot be scheduled on a 2-vCPU node (`e2-standard-2` has roughly 1.93 allocatable). Node counts in `tf-dt-gke` are **per zone** for a regional cluster.
