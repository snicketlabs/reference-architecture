# Cost benchmarking

How we measure the self-host cost-per-content-minute of a Match reference-architecture
deployment, and how to reproduce it.

> **Internal.** This document has no Freshservice frontmatter block and `docs/**` is outside the
> public-sync allowlist, so it is not published. Keep it that way — it names internal
> environments, load-test corpora and configuration variables.

## What this measures, and what it does not

The output is a spreadsheet that separates **baseline** AWS resources — paid whether or not any
video is processed — from **variable** consumption attributable to a known quantity of content.
Rates are public us-east-1 on-demand list prices, and every one is overridable so a customer can
apply their own region, discounts and reservations.

Deliberately excluded: S3 API request charges, any non-processing work (UI browsing, viewing or
downloading content over the NAT gateway, egress to end users), and cross-region transfer. The
model assumes source content already exists in an S3 bucket **in the same region**, reachable
through an S3 gateway VPC endpoint.

## Environment prerequisites

The measured environment needs three things that a stock deployment does not have.

**1. The load-testing image.** `app/services/load_testing/` is excluded from the distribution
image, so `LoadTesting::RunTest` does not exist there. Confusingly `lib/tasks/load_testing.rake`
and `config/load_testing.yml` *do* ship, so the rake task is present with no implementation
behind it and fails with `uninitialized constant LoadTesting`. Set the platform image to a
`loadtest-*` tag:

```
--set image.tag=loadtest-<version>
```

**2. S3 read access to the corpus bucket.** The environment's IRSA role can read its own primary
bucket and `*-autoingest`, but not the shared corpus bucket. Without this the run fails with
`Aws::S3::Errors::Forbidden` from `check_files_are_present`:

```bash
AWS_PROFILE=<profile> aws iam put-role-policy \
  --role-name <env>-service-account-role \
  --policy-name cost-benchmark-loadtest-assets-read \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
    "Action":["s3:GetObject","s3:ListBucket"],
    "Resource":["arn:aws:s3:::<corpus-bucket>","arn:aws:s3:::<corpus-bucket>/*"]}]}'
```

**3. An in-region corpus bucket.** `LOAD_TESTING_BUCKET` defaults to a bucket in **eu-west-2**.
Using it from a us-east-1 cluster drags the whole corpus cross-region over the NAT gateway —
real cost, and it corrupts the NAT measurement that validates our own caveat. `preflight`
asserts the bucket's region matches the cluster's and fails if it does not.

> **Important:** the bucket must be overridden with `env LOAD_TESTING_BUCKET=...` *before* the
> process starts. `config/load_testing.yml` resolves `ENV.fetch` at boot, so assigning `ENV[]`
> inside a `rails runner` script is too late and silently has no effect.

## The throughput ceiling

`MATERIAL_PROCESSING_COUNT` (default `default=5`) is admission control, not a resource limit:
`MaterialProcessing::Pipeline#current_capacity` caps how many materials are in `processing` at
once. It is the binding constraint on throughput — the autoscaler rarely reaches its replica
ceilings — so the system has a definite, measurable capacity.

No sizing profile overrides it, so small, medium and large all admit five concurrent materials
and share one throughput ceiling. Raising it increases throughput and *reduces* cost per minute,
because the fixed baseline spreads over more content. Any capacity figure must state the value
it was measured at.

## Choosing a corpus

| Corpus | Content | Use |
|---|---|---|
| `short_form_1` | one file, ~50 s | tooling shakeout; too small for any real figure |
| `short_form_5` | five files, ~2 min | exercises full concurrency and the saturated-window analysis cheaply |
| `feature_length_10` | ten files, 1,200 min | the **cost** run |
| `feature_length_20` | twenty files, ~2,400 min | the **capacity** run |

Two runs are needed. At concurrency 5, `feature_length_10` is only two batches, so ramp-up and
drain dominate its wall-clock and it cannot yield a defensible capacity figure.
`feature_length_20` gives four batches, so saturation dominates.

Short-form corpora have enormous per-file overhead relative to their duration — `short_form_1`
is a 727 MB file holding 50 seconds — so their throughput figures must **not** be extrapolated.

## Running

```bash
cd scripts/cost-benchmark
python3 -m venv .venv && ./.venv/bin/pip install -r requirements.txt
cp config.example.json config.json   # then edit for your environment
export AWS_PROFILE=<profile>

./.venv/bin/python cost-benchmark preflight --test-type feature_length_10
./.venv/bin/python cost-benchmark baseline                    # instant snapshot
./.venv/bin/python cost-benchmark run   --run-id <id> --test-type feature_length_10
./.venv/bin/python cost-benchmark watch --run-id <id>
# wait >= 20 minutes past completion before collecting
./.venv/bin/python cost-benchmark collect --run-id <id>
./.venv/bin/python build_report.py --measurements runs/<id>/run-<id>.json
```

> **Important:** wait at least 20 minutes after the last material completes before collecting.
> EFS cleanup is a delayed job (`RemoveLocalFilesJob`, `wait: 15.minutes`), so stopping earlier
> hides the storage tail.

**Nothing has to stay running during the benchmark.** Node lifetimes are reconstructed
afterwards from CloudTrail `RunInstances`/`TerminateInstances`, so an expired SSO token, a
closed laptop or an interrupted `watch` costs nothing but time -- re-run `collect` and the
measurements come back in full. This replaced a 30-second poller that lost the node-hours of
three separate runs, each time leaving every other figure looking perfectly healthy.

Two consequences worth knowing:

- `collect` needs the run window, so it must run after the last material completes. It can run
  days later; CloudTrail Event History keeps 90 days.
- The **drain tail** is now explicit (`--tail-hours`, default 0.5). Karpenter consolidates 30
  seconds after a node empties, so a node still alive is still working -- usually this run's own
  cleanup. Nodes still alive when the tail expires are reported, because that case is ambiguous
  in both directions: still-working under-counts, become-the-new-floor over-counts. If runs are
  close together pass `--not-after <next run start>` so the tail cannot annex the next run's
  nodes.

Let Karpenter consolidate back to the idle floor before taking the baseline. Leftover nodes from
a previous run count as floor rather than burst, which gives the next run pre-warmed capacity and
understates its node-hours.

## Reading the result

`collect` writes a `validation` block alongside the measurement. Check it before trusting
anything:

| Field | Why it matters |
|---|---|
| `native_fingerprint_all` | If any material fell back to the legacy frame path it uploads every frame instead of ~10, moving S3 by orders of magnitude. Anything other than all-true invalidates the S3 figures. |
| `nat_bytes_total` | Should be near zero. A large value means source media did not come from the in-region bucket. |
| `rds_cpu_max_pct` | If the database saturated, it throttled the pipeline and depressed node-hours. |
| `cross_az_node_hours` | Nodes in a different AZ from RDS/Redis incur cross-AZ transfer the model does not price. |

Throughput is reported two ways. `method_slot_rate` is primary: concurrency × per-material
processing rate, immune to ramp-up and drain because it is derived per material.
`method_saturated_window` is the cross-check, measured only across the interval where every slot
was occupied. **If they disagree materially the run was never saturated and neither should be
trusted.** A `null` window figure means saturation never occurred — expected for any corpus with
fewer materials than the concurrency limit.
