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

## GCP: the database

The default is set in the `cloud_sql` module block in
`environments/gcp/example/infrastructure/main.tf`. Copy the environment and edit
the `tier` there.

| Machine tier | vCPU / RAM | When |
|---|---|---|
| `db-custom-1-3840` | 1 / 3.75 GiB | Internal and proof-of-concept only. Not for production or production sized comparisons. |
| **`db-custom-4-16384`** | **4 / 16 GiB** | **Default starting position.** |
| `db-custom-8-32768` | 8 / 32 GiB | First step up. |
| `db-custom-16-65536` | 16 / 64 GiB | Headroom for a large, established library. |

The rungs mirror the AWS ladder vCPU for vCPU. Storage starts at
`disk_size = 20` (GiB) with `disk_autoresize = true`. Cloud SQL storage never
shrinks, and there is no upper limit on automatic growth.

The same symptoms described under [Knowing when to move](#knowing-when-to-move)
apply.

## GCP: compute

On AWS the cluster picks an instance type for each workload. On GKE each node
pool has one fixed machine type, so the reference architecture runs two pools,
both autoscaling, set in the `gke` module block in the same `main.tf`. Node
counts are **per zone** for a regional cluster.

| Pool | Machine type | Nodes per zone | Why |
|---|---|---|---|
| `default` | `e2-standard-4` (4 vCPU / 16 GiB) | 1 to 2 | Most workers. The practical minimum: ingest jobs request 2 vCPU, which cannot be scheduled on an `e2-standard-2` (roughly 1.93 vCPU allocatable). |
| `large` | `e2-standard-16` (16 vCPU / 64 GiB) | 0 to 1 | Fingerprinting jobs whose CPU request is larger than one `default` node can allocate, up to 12 vCPU for the heaviest. Scales up from zero when such a job is waiting, and back to zero once idle. |

A pod never spans nodes, so without the `large` pool those jobs stay pending
however far the `default` pool scales.

Raise `max_node_count` on either pool if you raise the throughput values above
and want the capacity to follow.

The `large` pool is tainted so nothing else lands on it and it can scale back to
zero promptly. The fingerprinting tiers that need it carry a matching toleration
in the chart values; see "Installing the platform" in `README-gcp.md`.

Work with Snicket Labs Technical Services to understand your individual system
needs.
