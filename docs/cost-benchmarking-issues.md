# Cost benchmarking — issues and future work

Internal working log for the cost-benchmark tooling (`scripts/cost-benchmark/`). Captures
defects and oddities found while building the self-host cost model, so they get triaged into
tickets rather than lost in a chat transcript.

> **Internal only.** This file deliberately has no Freshservice frontmatter block, so it is not
> synced to the customer knowledge base. `docs/**` is also outside the `INCLUDE_PATHS` allowlist
> in `.github/workflows/sync-to-public.yml`, so it is not copied to the public
> `match-reference-architecture` repo either. Keep it that way.

## Issues found

Confidence is the author's, not a verdict. Nothing here has been triaged yet.

| # | Issue | Blocks benchmark? | Confidence | Notes |
|---|---|---|---|---|
| 1 | **Auto Mode NodeClass spreads nodes across both AZs**, defeating the reference architecture's single-AZ design. `availability_zone_name` pins RDS and ElastiCache but not compute; the `default` NodeClass selects both private subnets. A customer following our Terraform gets the cross-AZ node↔RDS/Redis charges the design intended to avoid. | No | High — verified live | Highest-value finding. **Check whether this originates in the upstream `tf-dt-eks` module before writing a ticket** — that decides whether it is a defect in our published reference architecture or local drift |
| 2 | **`materialProcessingCount` is identical across all sizing profiles.** `default=5` in `values.yaml:921`, not overridden in `small.yaml`/`medium.yaml`/`large.yaml`. It is the binding throughput constraint (`lib/material_processing/pipeline.rb:37-39`), so all three profiles share one throughput ceiling — medium buys a larger database and higher replica ceilings, not more throughput. | No | High — verified live | Significant: changes what "medium" means commercially, not just technically. Either the size files should scale it, or the docs should explain why not |
| 3 | **`workers:` block in `environment-sizes/*/*.yaml` is dead config when KEDA is enabled.** `sidekiq-worker.yaml:1` and `scaled-job.yaml:2` are mutually exclusive, so `medium.yaml`'s tuned `fingerprinter: 8500m` is silently ignored. Misleading to anyone sizing from that file. | No | High | Remove it, or document that it applies only when `kedaAutoScaling.enabled: false` |
| 4 | **Fingerprinter sidecar resources silently dropped on the non-KEDA path.** `sidekiq-worker.yaml:94` reads `.resource` (singular) but values define `workers.fingerprinter.fingerprinter.requests`. The key does not exist, so the sidecar renders BestEffort with no resources. | No | High | Looks like a straightforward typo bug |
| 5 | **`medium.yaml` header comment claims "2x baseline" but several values are lower than base** (e.g. `comparison-longform-data-generation` 6 → 4). | No | High | Comment/doc fix |
| 6 | **~36 orphaned unattached gp2 volumes (~470 GiB)** in the sandbox account. Unrelated to this work, but costing money and would pollute a naive EBS cost reading. | No | High | Env hygiene. **Check ownership before deleting anything** |
| 7 | **`storage.tmpStorage` is an `emptyDir` with `sizeLimit` commented out** while the app writes large files there — unbounded node-local ephemeral usage against an 80 GiB root volume. | No | Medium | Possible node-pressure eviction risk under load; may surface during a benchmark run |
| 8 | **No sweeper for orphaned EFS `storage/ingest_masters/*` directories.** `RemoveLocalFilesJob` is the only cleanup; if it exhausts its retries the files persist indefinitely. | No | Medium | Could inflate EFS cost over time in a real deployment |
| 9 | **No EFS lifecycle/IA policy configured.** Not a bug — the working set is transient, so IA would not help it — but worth confirming it is deliberate. | No | Low | Cost-optimisation question for the reference architecture |
| 10 | ~~**`generic-worker` and `web` lack `karpenter.sh/do-not-disrupt`.**~~ **CLOSED — not a problem.** The scaledJobs already set it (`templates/scaled-job.yaml:26`), so the long-running pipeline work is protected. `generic-worker` only runs small, short tasks, so a reschedule is cheap and safe; `web` affected tooling stability only, now handled by kubectl retries. No change needed. | No | Closed | Kept for the record so it is not re-raised |
| 11 | **Is `db.m5.4xlarge` the right size for the medium profile?** `feature_length_10` peaked at **99.3% CPU** on the drifted `db.t4g.medium`, which is why we resized to the reference spec. The open question runs both ways: if the properly-sized instance is barely touched, `medium.tfvars` may be specifying a database several times larger than the workload needs, and the baseline cost we quote customers is inflated accordingly. RDS is the *only* dimension that varies between small/medium/large (see #2), so getting it wrong matters disproportionately. | No | Medium — one data point | Compare RDS CPU/IOPS on the re-run against the 99.3% peak. Either answer is actionable: still saturated means medium is undersized; barely used means it is oversized |
| 12 | **`test-snicket-rc-us1` RDS drift.** Running `db.t4g.medium`/20 GB against `db.m5.large` in the environment's own tfvars and `db.m5.4xlarge` in `medium.tfvars`. Terraform state and reality have diverged. | Possibly | High — verified live | If the database saturates during a run it depresses measured node-hours and invalidates the result. `collect` captures RDS CPU/IOPS so we can tell |

## Future enhancements

Ideas parked deliberately, not oversights.

### 1. A customer-facing variant of the spreadsheet

The workbook is currently written for us. Before it goes to a customer it needs a pass to remove
internal vocabulary, most of which is meaningless or confusing outside the team:

- **Internal load-test suite names** — `feature_length_10` / `feature_length_20` appear on the
  Variable sheet header and in the Run Log. Replace with a plain description of the content
  profile ("10 feature-length files, 20 hours, 6.56 Mbit/s MXF").
- **Configuration variable names** — `MATERIAL_PROCESSING_COUNT` on the Result sheet and in the
  caveats. A customer needs the *concept* ("the system processes N titles concurrently, and this
  is tunable"), not the environment variable.
- **Implementation vocabulary** — KEDA, Karpenter, scaledJobs, NodeClass, replica ceilings.
- **Our environment's identity and drift** — `test-snicket-rc-us1`, the `db.t4g.medium`
  substitution, chart revisions, git SHAs. The *fact* that a substitution occurred is an honest
  caveat worth keeping; the internal hostnames are not.
- **The Run Log sheet as a whole** is provenance for us. Either drop it from the customer build
  or reduce it to a date and a content profile.

Suggested shape: a `--customer` flag on `build_report.py` producing a simplified variant from the
same data, so the internal and external workbooks cannot drift apart. Keep every *caveat* — they
protect us — and only strip the vocabulary.

### 2. Is `MATERIAL_PROCESSING_COUNT=5` leaving cost on the table?

**This is a costing question, not a performance-tuning one**, which is why it is
recorded here rather than waved off as scope creep. Baseline infrastructure cost is
fixed; throughput is not. Every extra content-minute the same cluster processes
spreads that fixed cost thinner, so concurrency moves the headline £/minute
directly. If the number we produce looks poor value, this is the first lever to
examine — before anyone concludes the product is expensive to run.

What we know:

- `MATERIAL_PROCESSING_COUNT` defaults to `default=5` and **no sizing profile
  overrides it** (issue #2), so small, medium and large share one throughput ceiling.
- At concurrency 5, `feature_length_10` pegged a `db.t4g.medium` (2 vCPU) at
  **99.3% CPU**. On the `db.m5.4xlarge` the reference architecture actually
  specifies (16 vCPU), the same workload should sit near single digits — implying
  substantial unused headroom.
- Per-material processing rate barely changed between a solo run and 5-way
  concurrency (~1.0x vs ~1.09x realtime), i.e. contention was almost nil at 5.
  That is consistent with there being room to go higher.

Proposed boundary, to keep this from turning into a tuning project: take the RDS
CPU figure from the `feature_length_10` re-run at concurrency 5. If it is low,
**estimate** the headroom and state it as a caveat on the spreadsheet ("measured at
concurrency 5, which used only N% of the database; higher concurrency would reduce
cost per minute"). Do **not** start a tune-measure-repeat loop.

A single confirmatory run at a higher concurrency — the owner's instinct is to aim
for roughly 75% database CPU — would turn that estimate into a measurement for
about one run's cost. That is a decision to take once the baseline numbers exist,
not before.

Note the interaction with issue #11: if the database turns out to be the binding
constraint at higher concurrency, then RDS sizing and throughput are the same
question, and `medium.tfvars` should be chosen to match a target concurrency rather
than picked independently.

### 3. Scale the benchmark database back down when the runs are finished

RDS was resized from `db.t4g.medium` to the medium reference spec
(`db.m5.4xlarge`, 50 GB → 200 GB) because `feature_length_10` pegged the smaller
instance at 99.3% CPU, which would have depressed the measured node-hours.

`db.m5.4xlarge` is roughly **$34/day** against ~$1.60/day for the `t4g.medium`, so
this is not something to leave running. Once the benchmark runs we need are
complete, scale it back:

```bash
AWS_PROFILE=<profile> aws rds modify-db-instance \
  --db-instance-identifier test-snicket-rc-us1 \
  --db-instance-class db.t4g.medium --apply-immediately
```

Note storage does **not** shrink — allocated storage stays at 50 GB once raised,
so that part is permanent (a few dollars a month).

Record the RDS CPU figures from the final run before scaling down; they are the
evidence for the sizing question in issue #11.

### 4. Move the sampler off-cluster entirely -- CLOSED, superseded

**Closed 2026-08-26: there is no sampler.** Node lifetimes are now reconstructed from
CloudTrail after the run (`cost_benchmark/cloudtrail.py`), so the question of where to put
a long-running poller no longer arises.

Worth recording why, because the reasoning generalises. The sampler was only ever
establishing one thing -- roughly when a node stopped existing. A node's interval *start*
was always its EC2 `LaunchTime`; samples only set the *end*, by noticing an absence. We
were polling every 30 seconds to approximate a termination timestamp AWS records exactly
and keeps for 90 days.

Three runs lost their node-hours to that poller (token expiry, eviction overwriting the
buffer, restart blind spots), and every one still produced a plausible number, because a
gap under-credits a node that terminated inside it. The bias only ran downward, flattering
the product on the figure quoted to customers.

Validated against four completed runs with the tail matched to the sampler's own effective
end, so only the source differed: the three clean runs agreed to within one poll interval
per node (-9 to -13s, the sampler rounding each node's end up), and the 33.8%-blind run
came out +9.8% -- exactly the truncation being recovered.

Also retired with it: the IRSA role, the eviction handling, `resume()`, the podAffinity
placement trick, and the observer-effect question about a measurement tool that ran inside
the thing it measured.

### 5. Package the in-cluster sampler properly -- CLOSED, superseded

**Closed 2026-08-26.** Moot for the same reason as item 4: there is nothing in-cluster left
to package. `baseline` is now a single `describe-instances` snapshot and `collect` reads
CloudTrail; neither needs a Helm chart, a ServiceAccount or an IAM role.

### 7. `system` nodepool hours are baseline, not marginal -- RESOLVED

Recorded because the double-count was invisible and worth not reintroducing.

EKS Auto Mode ships two built-in NodePools, both `app.kubernetes.io/managed-by: eks`
and written by the `eks-auto-mode` field manager -- we define none ourselves. Their
architecture requirements differ deliberately:

- `general-purpose`: `kubernetes.io/arch In [amd64]`
- `system`: `kubernetes.io/arch In [amd64, arm64]`

So Graviton `c6g` nodes in the system pool are AWS's design, **not** a misconfiguration
on our side, and they are cheaper than the x86 equivalent. The system pool is tainted
`CriticalAddonsOnly` and hosts exactly four pods: `efs-csi-controller` x2 and
`metrics-server` x2.

Those addons do not scale with video throughput, and the Baseline sheet already charges
an idle system node 24/7 (`Idle node (system)`, 1 x c6g.large, 730 h/month). Counting one
again as burst whenever it churned through a run therefore **billed the same capacity
twice**. It was 12-34% of measured burst node-hours -- 33.6% on one run and 0% on
another, which is churn rather than load response.

`analysis.BASELINE_NODEPOOLS` now classifies system-pool nodes as floor however recently
they launched. That last part matters: a node replaced mid-run is neither in
`baseline_node_ids` nor launched before the run started, so pool membership is the only
signal that catches it.

Effect on `feature_length_1`: burst 6.433 -> 5.159 node-hours, and **0.0536 -> 0.0430
node-hours per content-minute, a 20% reduction in the headline figure.**

### 9. Catalogue size breaks the run, it does not slow it -- 2026-08-29

Two `feature_length_10` runs on the fixed chart (rev 41), differing ONLY in the
comparison catalogue. The result was not the one being looked for.

| | isolated (0 peers) | shared org 4 (41 peers) |
|---|---|---|
| outcome | **10/10 complete**, 4h26m | **6/10, stalled** |
| per-material | 1.00x realtime | 0.92-1.28x, mean ~1.09x |
| cost | $0.0190 per content-minute | **no usable figure** |

**Processing speed was essentially unaffected** -- the six materials that finished ran
at the same rate as the isolated run. So the earlier null result on catalogue size
(7 vs 23 masters, no detectable effect on time) was right about time and wrong about
consequence. At 41 peers the effect appears as **failure**, not slowness.

**Mechanism.** Four `process-whole-media-compare` jobs were killed with
`DeadlineExceeded` (00:32:47, 01:11:57, 01:41:37, 01:41:47Z). That worker has
**0.75 CPU and `activeDeadlineSeconds: 600`** -- comparing one asset against 41 peers
does not fit in ten minutes. Each kill is an ungraceful worker death, so it lands in
the same poison-pill path as the OOM, and all four materials were left stranded in
`processing`, holding slots.

**This confirms the blast radius claim in sc-23907**: the defect is not about OOM
specifically. Any ungraceful death does it, and `activeDeadlineSeconds` is a second,
independent trigger already present on every compare/relate scaledJob.

**It also validates the reframing in item 8.** Fifteen scaledJobs cap at a 600s
deadline, so for them undersizing can only ever present as `DeadlineExceeded`, never as
a slow saturated pod. The watcher looking for saturation found **zero** hits in ten
hours; the deadline check found the real problem.

**Important caveat on severity.** The corpus is ten cutdowns of a single source, so
essentially every peer clears the containment threshold -- the worst possible fan-out.
A customer catalogue of diverse content would shortlist far fewer candidates per
ingest. This demonstrates the mechanism and that the sizing is too tight for large
comparable sets; it does not show that a typical 41-title library would fail.

**Consequence for the cost model:** the shared-catalogue variant cannot produce a
number on the current chart, so the quotable figure comes from the isolated run and
should be stated as such -- a greenfield floor, not a customer with an established
library.

### 8. Further pod tuning -- noted, deliberately not acted on

Observed during the 2026-08-28 `feature_length_10` runs, after sc-23908 raised
`compare-relate` to 2 CPU / 3Gi. **Recorded for later; do not tune before the cost
numbers exist**, because "faster" and "cheaper" are not the same lever here and the
model is what tells us which one we are pulling.

**`process-extract-frames` is the new CPU ceiling.** Two pods sat flat at
**2997m and 2999m against a 3000m limit** while `compare-relate` idled at 2m against
its new 2 cores. Fixing one bottleneck moved it. It is Burstable (requests 1, limits
3) so it does not over-reserve, and the run was fast enough that this may not be worth
touching.

**`compare-relate` is now over-provisioned, and that costs money.** Sized to 3Gi
against a measured 1083 MiB peak, and 2 CPU against observed usage of ~2m once it was
no longer the bottleneck. Because **requests equal limits**, that is a *reservation*:
2 cores x `maxReplicaCount: 10` is 20 cores Karpenter must physically provision. Live
during the run: **six nodes, two at 46% and 23%, four at 1-3%**. Nodes created to hold
reservations nobody is using. Setting requests below limits (Burstable) would let
Karpenter pack tighter while keeping the same OOM protection.

**The tension worth stating plainly:** raising limits removes throttling and makes runs
faster, which lowers cost per content-minute. Raising *requests* provisions more nodes,
which raises it. `compare-relate` currently does both at once. The cost model measures
the net effect, so decide after the numbers, not before.

**Two workers can structurally run long while under-resourced**, though neither
misbehaved in these runs:

- `ingest-download-media` -- 0.5 CPU, `activeDeadlineSeconds` 5400. Pulling ~8 GiB
  files, plausibly the long pole in ingest if it is CPU-bound rather than network-bound.
- `comparison-longform-data-generation` -- **no CPU limit or request at all**,
  deadline 6600. The opposite failure to `compare-relate`: it cannot be throttled, but
  it is invisible to the scheduler, so Karpenter provisions nothing for it.

**A framing note for the other 15 scaledJobs**, all of which have
`activeDeadlineSeconds: 600`: they cannot run for 10 minutes by construction. There,
undersizing appears as `DeadlineExceeded` job failures rather than slow pods, so that
is what to watch for.

### 11. EFS: elastic mode is correct -- the lever is I/O amplification

**Parked 2026-09-01, deliberately.** The investigation below is complete and the
conclusion is that no change is needed. Going further means measuring alternatives, and
AWS permits only one throughput-mode change per 24 hours, so an A/B is a two-day
exercise. Not worth it while the cost model is the priority -- but the two open levers
(provisioned mode above a volume threshold, and the 7x read amplification) are real, so
this is a park rather than a close.

EFS throughput is **~62% of measured variable cost**, more than all compute combined, so
it was worth checking whether the pricing mode was simply wrong. It is not.

**`throughput_mode = "elastic"` is deliberate and identical in both deployments** --
`terraform-utils-private/aws/tf-hosted-modules/tf-dt-efs/main.tf:14` (consumed by
`match-environment` at `tf-dt-efs/v1.0.7`) and
`sas-infra/terraform/modules/aws_eks/shared-efs-storage.tf:25`. An earlier claim that no
`throughput_mode` appeared in our Terraform was wrong: the grep covered
`match-environment` only, and the setting lives in the module repo.

**Bursting is not viable, and this is arithmetic rather than judgement.** Burst credit
accrues at 50 KiB/s per GiB *stored*, and the filesystem is small (~47 GiB) precisely
because media is transient:

| | |
|---|---|
| measured demand | 24.9 MiB/s mean |
| bursting baseline at 47 GiB | 2.27 MiB/s |
| credit needed for one run | ~350 GiB |
| maximum balance the filesystem can ever hold | 98 GiB |

One run needs 3.6x the maximum possible credit balance, so no amount of idle time helps.
Bursting could not complete a single `feature_length_10`.

**Provisioned only wins at sustained volume.** At $6.00/MiB/s-month against $14.47 of
elastic throughput per 1,200-content-minute run, break-even is ~10.4 runs/month at
25 MiB/s (~207 content-hours) or ~20.7 at 50 MiB/s. Worth modelling for SDVI, but it is a
**customer-volume decision, not a reference default** -- provisioned is a hard ceiling
that throttles when exceeded, and only *mean* throughput has been measured, so it cannot
be sized safely yet.

**Recommendation: leave the reference on elastic.** Add provisioned to the cost model as
a documented option with the crossover point.

#### The much larger prize is reading less

```
corpus on disk     55.0 GiB
EFS written        96.5 GiB   1.8x corpus
EFS read          289.2 GiB   5.3x corpus
total traffic     385.7 GiB   7.0x corpus   (329 MiB per content-minute)
```

**Every byte is read back roughly three times.** Elastic bills per GB moved, so halving
re-reads halves 62% of the variable cost -- a far bigger lever than any mode switch, and
an application question (caching, streaming rather than re-reading, keeping derived
artefacts local) rather than an infrastructure one.

#### Testing this costs more than it looks

AWS permits **one throughput-mode change per 24 hours**, so an A/B is a two-day exercise
minimum. Sizing provisioned also needs a peak measurement, which the tooling does not
capture -- `collect` records totals, not per-minute `MeteredIOBytes`.

Cheapest useful next step: re-run `feature_length_10` sampling EFS throughput per minute.
That yields peak versus mean (sizing provisioned properly) and shows where the 7x
amplification arises, while changing nothing.

Unrelated but noted: no EFS lifecycle/IA policy is configured. IA would reduce *storage*
cost, which is ~$0.09 per run against $14.47 of throughput -- not worth pursuing.

### 10. Design a repeatable hands-off load-test and cost-analysis harness

**Not now** -- captured while the lessons are fresh. This week produced a usable number,
but it took five attempts across four days, and almost every hour lost went to something
this design would remove.

#### Credentials -- the single biggest operational cost

Expired SSO killed three collects and one overnight run. Each time the fix was "log in
again", but only a human at a keyboard can do it, so an unattended run is only ever as
long as the session backing it.

**Short term:** raise the IAM Identity Center session duration for the `sas` session.
**Properly:** a scoped IAM role for the harness -- `cloudtrail:LookupEvents`,
`ec2:Describe*`, `cloudwatch:GetMetricStatistics`, `rds:Describe*`, `efs:Describe*`,
`pricing:GetProducts`, plus EKS auth. Read-only apart from the RDS resize the campaign
needs. That is what makes a multi-day campaign possible at all.

#### Stand the environment up per campaign, and tear it down

Terraform for the infrastructure, Helm from a **pinned chart ref**, both destroyed after.
Reasons drawn from this week rather than principle:

- The live env drifted from `snicketlabs-rc.yaml` (wrong image registry, missing pull
  secret) and nobody noticed until someone diffed it.
- Chart config changed **mid-run** twice, once while a benchmark was in flight.
- A fix we depended on lived on an unmerged branch, where a `helm upgrade` from `main`
  would silently revert it.
- The comparison catalogue accumulated across runs, so run N was never measuring the
  same system as run N-1.

A fresh environment per campaign makes each result attributable to a known chart version
and a known starting state, which is the only way the numbers stay comparable.

#### A dedicated sandbox account

Shared account 203960437845 meant `TerminateInstances` events from unrelated workloads
appeared as noise, cost data could not be trusted at account level, and someone else's
work could contend for capacity during a measurement. Isolation makes account-level
billing (CUR) usable, which is the authoritative cross-check we never got to run.

#### Measure retrospectively; keep nothing alive

The strongest architectural lesson. Three runs lost their node-hours to a live poller
(token expiry, pod eviction, restart blind spots) before CloudTrail replaced it. Prefer
sources AWS already keeps: CloudTrail for node lifetimes, CloudWatch for series, CUR for
authoritative cost, the application database for throughput. Nothing that has to survive
the run can be a dependency of the measurement.

Corollary: **the measurement must not perturb what it measures.** The reference
architecture ships no monitoring, so deploying Prometheus to observe a benchmark would
bill measurement overhead as product cost. That is also why `system` nodepool hours were
double-counted until caught.

#### Make every guardrail fail loudly

The recurring failure was never a crash -- it was a plausible-looking wrong number.
Each of these shipped only after it had already produced one:

- sampling gaps silently understating node-hours
- `content_minutes` counting materials that never completed (18% overstated output)
- a failed price fetch overwriting a good `prices.json` with one rate
- a stranded material holding a pipeline slot while throughput assumed full concurrency
- an auth failure reported as "CloudTrail is not logging"
- a notification tool reporting failure for messages it had actually delivered

Design rule: **a check that cannot fail is not a check.** Prefer refusing to produce a
number over producing one that needs a caveat nobody will read.

#### A test matrix, not a test

Corpus x concurrency x sizing profile, run unattended and compared automatically.
Specifically worth covering: content length (the failures were all long-form), catalogue
size (0 vs 41 peers changed pass/fail, not just cost), and `MATERIAL_PROCESSING_COUNT`,
which no sizing profile currently varies.

Corpus design needs thought. Ours is ten cutdowns of one source, so every candidate
clears the containment threshold -- worst-case fan-out, and not representative of a real
catalogue.

#### State the modelling choices as parameters

Drain tail, system-nodepool attribution, baseline versus variable split, catalogue size.
Each moved the headline figure materially and none is a fact about the system -- they are
choices. They belong in the report as named parameters, not buried in code.

#### It doubles as a soak test

sc-23907 (poison-pill stranding), sc-23908 (OOM, then deadline kills) and the
`generic-worker` KEDA misconfiguration were all found by running the product hard for
hours. A repeatable harness is a product-quality instrument as much as a costing one.

### 6. Fetch prices at generation time via the AWS SDK

`fetch_prices.py` currently shells out to the `aws` CLI as a separate manual step, writing
`prices.json`, which `build_report.py` then reads. That means a workbook can be generated from
stale rates without anyone noticing.

Enhancement: use **boto3** (`pricing` client) and let `build_report.py` refresh rates inline as
part of generation.

Trade-off to decide when we do it, rather than assume:

- Fetching inline guarantees fresh prices, but makes AWS credentials a hard requirement for
  building a spreadsheet, and makes builds non-reproducible — regenerating an old workbook would
  silently produce different numbers.
- Keeping `prices.json` checked in gives auditable, pinned, reproducible rates and offline
  builds, at the cost of needing a deliberate refresh.

Probably: fetch inline by default, still write `prices.json` as the audit record, and add
`--prices-from-file` to pin. Also stamp the fetch timestamp prominently on the Assumptions sheet
(it is already recorded there) and warn when the rates are older than, say, 30 days.

Note the one rate the Pricing API does not expose queryably — cross-AZ data transfer — is
declared in `STATIC_RATES` in `fetch_prices.py` with its source, and would still need that
treatment under the SDK.
