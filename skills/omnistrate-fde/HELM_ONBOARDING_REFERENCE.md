# Helm Chart Onboarding Reference

Based on the Omnistrate documentation (https://docs.omnistrate.com; the MCP
docs-search tools `mcp__ctl__docs_*` are an optional alternative when the user
has asked to work through MCP). When this file conflicts with the live schema or
the docs, trust the schema/docs.

Schema pin (add as the first line of your spec for editor validation):

```yaml
# yaml-language-server: $schema=https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json
```

---

## When you are on this path

- You have an existing Helm chart (public or private repo, or local artifact).
- Spec format: **ServicePlanSpec** (not Docker Compose).
- Build flag: `--spec-type ServicePlanSpec`.
- Tenancy declared inside your chart; set `tenancyType: CUSTOM_TENANCY` if required.
- When an instance stays failed, follow the debug loop in SKILL.md workflow phase 4.

---

## Minimal working skeleton

For the `deployment:` block (account IDs, `hostedDeployment` vs `byoaDeployment`, field casing,
cloud-account prerequisites) see [DEPLOYMENT_MODELS_REFERENCE.md](DEPLOYMENT_MODELS_REFERENCE.md)
([choosing a model](DEPLOYMENT_MODELS_REFERENCE.md#choosing-a-deployment-model),
[hosted](DEPLOYMENT_MODELS_REFERENCE.md#hosted),
[BYOC customer account](DEPLOYMENT_MODELS_REFERENCE.md#byoc-customer-cloud-account)).

```yaml
name: Redis Server
deployment:
  hostedDeployment:               # see DEPLOYMENT_MODELS_REFERENCE.md for all models
    AwsAccountId: "<AWS_ACCOUNT_ID>"
    AwsBootstrapRoleAccountArn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role"

services:
  - name: Redis Cluster
    compute:
      instanceTypes:
        - apiParam: instanceType
          cloudProvider: aws
        - apiParam: instanceType
          cloudProvider: gcp
    network:
      ports:
        - 6379
    helmChartConfiguration:
      chartName: redis
      chartVersion: 19.6.2
      chartRepoName: bitnami
      chartRepoURL: https://charts.bitnami.com/bitnami
      chartValues:
        master:
          persistence:
            enabled: false
          service:
            type: LoadBalancer
            annotations:
              external-dns.alpha.kubernetes.io/hostname: $sys.network.externalClusterEndpoint
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 150m
              memory: 256Mi
        replica:
          persistence:
            enabled: false
          replicaCount: $var.numReplicas
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 150m
              memory: 256Mi
    apiParameters:
      - key: numReplicas
        description: Number of Replicas
        name: Replica Count
        type: Float64
        modifiable: true
        required: false
        export: true
        defaultValue: "1"
      - key: instanceType
        description: Instance Type
        name: Instance Type
        type: String
        modifiable: true
        required: false
        export: true
        defaultValue: "t4g.small"
```

---

## helmChartConfiguration fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chartName` | string | Yes (repo-backed) | Name of the Helm chart. For local artifacts, read from `Chart.yaml`. |
| `chartVersion` | string | Yes (repo-backed) | Version of the chart. Pin this — unpinned versions cause drift. |
| `chartRepoName` | string | Yes (repo-backed) | Name of the chart repository. |
| `chartRepoURL` | string | Yes (repo-backed) | URL of the chart repository. Supports `https://` and `oci://` prefixes. |
| `artifactRelativePath` | string | No | Relative path to a local chart directory or `.tar.gz` / `.tgz`. Use with `omnistrate-ctl build`. Do NOT combine with `chartRepoName` / `chartRepoURL`. |
| `chartValues` | object | No | Values to override the chart defaults. Supports `$var.*`, `$sys.*`, `$secret.*` references (see Templating section). |
| `layeredChartValues` | array | No | Alternative to `chartValues` for conditional/multi-cloud values. Mutually exclusive with `chartValues`. |
| `chartAffinityControl` | object | No | Controls automatic affinity injection. Default: injection enabled. See Pod placement section. |
| `authProvider` | object | No | Username and password for private chart repositories. **Omit for private Amazon ECR OCI repos** — Omnistrate resolves short-lived ECR credentials via AWS IAM. |
| `runtimeConfiguration` | object | No | Helm runtime flags (wait, timeout, hooks, CRDs, upgrade strategy). See runtimeConfiguration section. |
| `namespace` | string | No | Override the Kubernetes namespace. Supports `$var.*` and `$sys.*`. |
| `releaseName` | string | No | Override the Helm release name. Supports `$var.*` and `$sys.*`. |

### Private Amazon ECR OCI repos

```yaml
helmChartConfiguration:
  chartName: redis
  chartVersion: 22.0.7
  chartRepoName: private-ecr-charts
  chartRepoURL: oci://<AWS_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/<ECR_REPOSITORY_PATH>
  # authProvider: omit — Omnistrate resolves ECR credentials at deploy time
```

Keep `EnableECRHelmChartPull=true` in the ISV account's CloudFormation stack.

### Local chart artifact

```yaml
helmChartConfiguration:
  artifactRelativePath: charts/redis      # relative to `omnistrate-ctl build` CWD
  chartValues:
    replica:
      replicaCount: 1
```

Run `omnistrate-ctl build` from the workspace root that contains the artifact path.
`chartName`, `chartRepoName`, and `chartRepoURL` are not needed — Omnistrate reads metadata from `Chart.yaml`.

---

## runtimeConfiguration

Nested under `helmChartConfiguration.runtimeConfiguration`. All fields optional with sensible defaults.

| Field | Type | Default | Helm flag equivalent | When to use |
|-------|------|---------|----------------------|-------------|
| `wait` | bool | `false` | `--wait` | Wait for all pods/PVCs/Services to be ready before marking install successful. |
| `waitForJobs` | bool | `false` | `--wait-for-jobs` | Wait for all Jobs to complete. Requires `wait: true`. |
| `timeoutNanos` | uint64 | `300000000000` (5 min) | `--timeout` | Max time per Kubernetes operation. Common values: 1 min = `60000000000`, 10 min = `600000000000`, 30 min = `1800000000000`. |
| `disableHooks` | bool | `false` | `--no-hooks` | Skip pre/post install/upgrade/delete hooks. Use to bypass failing hooks during troubleshooting. |
| `skipCRDs` | bool | `false` | `--skip-crds` | Skip CRD installation. Use when CRDs are managed separately. |
| `upgradeCRDs` | bool | `false` | — | Upgrade CRDs on Helm operations. Test thoroughly before enabling in production. |
| `resetValues` | bool | `false` | `--reset-values` | On upgrade, reset to chart defaults (drops all previous values). Mutually exclusive with `reuseValues` and `resetThenReuseValues`. |
| `reuseValues` | bool | `false` | `--reuse-values` | On upgrade, merge previous values with new overrides. Mutually exclusive with `resetValues` and `resetThenReuseValues`. |
| `resetThenReuseValues` | bool | `false` | `--reset-then-reuse-values` | On upgrade, reset to chart defaults, then apply previous values, then apply new overrides. |
| `recreate` | bool | `false` | `--force` (similar) | Force replacement of resources. Can cause service interruption. |
| `disableReconciliation` | bool | `false` | — | **Debug only.** Disable steady-state drift correction after the release is created. Not a blanket no-retry switch; initial install and in-flight actions can still retry. |

Complete example:

```yaml
helmChartConfiguration:
  chartName: redis
  chartVersion: 24.1.0
  chartRepoName: bitnamicharts
  chartRepoURL: oci://registry-1.docker.io/bitnamicharts
  runtimeConfiguration:
    wait: true
    waitForJobs: true
    timeoutNanos: 600000000000   # 10 minutes
    disableHooks: false
    skipCRDs: false
    upgradeCRDs: true
    resetValues: false
    reuseValues: true
    resetThenReuseValues: false
    recreate: false
    disableReconciliation: false
```

---

## Templating chart values

### Variable forms — bare vs `{{ }}` (CRITICAL)

**In `chartValues`**, `$var.*` and `$sys.*` appear **bare** (no `{{ }}`).
**Concatenation and `layeredChartValues` scopes** require `{{ }}`.

This is exactly how they must appear:

```yaml
# Bare — correct in chartValues
chartValues:
  replica:
    replicaCount: $var.numReplicas          # bare $var
  master:
    service:
      annotations:
        external-dns.alpha.kubernetes.io/hostname: $sys.network.externalClusterEndpoint  # bare $sys
  primary:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
              - key: topology.kubernetes.io/region
                operator: In
                values:
                - $sys.deploymentCell.region    # bare $sys

# {{ }} needed for concatenation or scope keys in layeredChartValues
endpointConfiguration:
  admin:
    host: admin-{{ $sys.network.internalClusterEndpoint }}   # concatenation — needs {{ }}

layeredChartValues:
  - scope:
      "{{ $sys.deploymentCell.cloudProviderName }}": "aws"   # scope key — needs {{ }}
    values:
      ...
```

### `$var.*` — API parameters

Any `$var.<key>` reference must be declared in `apiParameters` on the same service.
Parameters declared only on a dependency are not available at the chart-values rendering stage.

```yaml
chartValues:
  replica:
    replicaCount: $var.numReplicas   # must be in apiParameters with key: numReplicas
```

### `$sys.*` — system parameters

Common `$sys.*` paths:

| Path | Value |
|------|-------|
| `$sys.network.externalClusterEndpoint` | External DNS hostname for the load balancer |
| `$sys.network.internalClusterEndpoint` | Internal cluster DNS endpoint |
| `$sys.deploymentCell.region` | Deployment cell region (e.g. `us-east-1`) |
| `$sys.deploymentCell.cloudProviderName` | Cloud provider (`aws`, `gcp`, `azure`) |
| `$sys.compute.node.instanceType` | Instance type in play |
| `$sys.deployment.resourceID` | Resource ID (node-pool label value) |
| `$sys.id` | Unique identifier for the service instance |

### `$secret.*` vs customer `Password` parameters (credential wiring)

There are **two distinct credential mechanisms** — pick based on *who owns the value*.

**`$secret.<name>` — ISV / environment-level secrets.** A `$secret.<name>` value is a
name/value pair the ISV defines **per environment type** (Dev/Stage/Prod) in the
Omnistrate console (or via `omnistrate-ctl secret create --name <name> --value <v>
--environment-type PROD`). It is **not** collected from the customer — the same
secret resolves for every instance in that environment type. Use it for ISV-owned
credentials the customer never sees (a shared registry token, an ISV service API
key, a fixed backend password). Referenced **bare** in `chartValues`:

```yaml
# $secret.<name> — ISV-owned, created once per environment type in the console
chartValues:
  auth:
    password: $secret.dbPassword          # value set by ISV via console/CLI, not the customer
```

**`type: Password` apiParameter (via `$var.<key>`) — customer-supplied credentials.**
When the *customer* supplies the credential at instance-create time, declare a
`type: Password` apiParameter and reference it as `$var.<key>` in `chartValues`.
Password-typed values are stored securely and masked in outputs
(use the `password` API param type for any user-facing sensitive inputs):

```yaml
# $var.<key> — customer-supplied, collected at create time
chartValues:
  auth:
    password: $var.adminPassword           # bare $var in chartValues
apiParameters:
  - key: adminPassword
    name: Admin Password
    description: Admin password for the instance
    type: Password
    modifiable: false
    required: true
    export: false
```

**Which to use:** customer-facing credential → `type: Password` apiParameter +
bare `$var.<key>`. ISV-owned / shared / environment-level credential → `$secret.<name>`
(created out-of-band in the console per environment type). They are **separate
mechanisms**: a `$secret.<name>` reference does not auto-populate from a Password
apiParameter — if a chart value must come from the customer, wire it as `$var.<key>`,
not `$secret.<name>`.

### Consuming Terraform outputs

Use `{{ $<terraformServiceName>.out.<key> }}` (with `{{ }}`) to reference outputs from a sibling Terraform service.
The variable root is the **Terraform service name** (camelCased, spaces dropped) as declared in `dependsOn`.

```yaml
chartValues:
  s3BucketARN: "{{ $dataInfraTerraform.out.s3_bucket_arn }}"
  dynamoDBTableARN: "{{ $dataInfraTerraform.out.dynamodb_table_arn }}"
```

---

## Customization discovery — building the recommended parameter set

Once the instance first reaches **RUNNING** with zero parameterization, do NOT
wait for the user to ask "what should we expose?" — **proactively inspect the
chart** and recommend a customer-facing parameter set. This is a build step, not
an optional extra.

### 1. Enumerate the chart's surface

```bash
# Full default values (the complete customization surface)
helm show values <repo>/<chart> --version <ver>
# Human-readable notes on what those values do
helm show readme <repo>/<chart> --version <ver>
```

If `helm` is not available (or the chart is not in an added repo), fetch from
Artifact Hub — the package page links the values schema and defaults:

```
https://artifacthub.io/packages/helm/<org>/<chart>
```

For a local chart artifact, read `values.yaml` and `README.md` from the chart
directory directly.

### 2. Classify every relevant value into three tiers

Present this as a table you fill in for the user (one row per value that matters).
Do NOT try to expose everything — most chart values stay hardcoded.

| Tier | What belongs here | How it maps in the spec |
|------|-------------------|-------------------------|
| **Tier 1 — Recommended customer-facing** | Credentials/auth; instance sizing; replica count; storage size; product version (where safe to change); TLS enablement; customer-relevant feature toggles | Becomes an `apiParameter`, wired into `chartValues` via `$var.<key>` |
| **Tier 2 — Optional / advanced** | Tuning knobs (memory policies, JVM opts); extra config blocks; metrics exporters; plugin lists | Offer to the user, but **default to hardcoding** in `chartValues` |
| **Tier 3 — Never expose (platform- or ISV-owned)** | Node affinity/placement; `storageClass`; image registry/repository overrides; service `type`/annotations; subchart wiring internals; clustering topology internals | Keep out of `apiParameters` entirely — Omnistrate or you own these |

**Why Tier 3 is never exposed:**

- **Node affinity / placement** is Omnistrate-owned — exposing it lets a customer
  break scheduling onto managed nodes (see Pod placement section below).
- **`storageClass`, image registry/repository** overrides break the managed
  substrate and image-pull path.
- **Service `type` / annotations** are how Omnistrate wires endpoints, DNS, and
  load balancers — exposing them breaks endpoint provisioning.
- **Subchart wiring / clustering topology internals** are internal contracts; a
  customer changing them produces an unsupported deployment.

### 3. Per-parameter mapping guidance

For each Tier-1 value, choose the right `apiParameters` properties. Property
semantics:

| Property | Type | Use it for |
|----------|------|-----------|
| `key` | string | Unique key referenced as `$var.<key>` in `chartValues` (same service) |
| `name` | string | Display name shown in the Customer Portal |
| `description` | string | Customer-facing explanation |
| `type` | string | `String`, `Float64`, `Boolean`, `Password`, `Json` (see valid `type` values below) |
| `required` | boolean | If `false`, `defaultValue` is **mandatory** |
| `defaultValue` | string | Always a **quoted string**, even for numeric/boolean types |
| `export` | boolean | If `true`, returned on the describe call (customer can read it back) |
| `modifiable` | boolean | If `true`, can be changed on a running instance (`helm upgrade`) |
| `options` | array | Finite set of allowed values (dropdown) — numbers/strings/JSON |
| `labeledOptions` | object | Labeled key→value choices when the display label differs from the value |
| `limits` | object | Numeric min/max (or string length) bounds |
| `regex` | string | Validation pattern (string types only) |
| `tabIndex` | integer | Display order — lower first; put the most important parameters first |
| `scope` | object | Restrict to specific `CloudProviders` (e.g. an AWS-only knob) |

Concrete choices:

- **Secrets / credentials** → `type: Password`, `modifiable: false`, `export: false`.
- **Finite choices** (engine mode, log level) → `options` or `labeledOptions`.
- **Numeric bounds** (replica count, storage GiB) → `limits` (min/max).
- **Formats** (usernames, DB names) → `regex` (e.g. `^[a-z0-9_]{8,32}$`).
- **Live-safe values only** get `modifiable: true`; anything whose change would
  need a re-provision stays `modifiable: false`.
- **`export: true`** only for values the customer must read back (endpoints,
  usernames) — never for passwords.
- Order with `tabIndex` so the most important parameter appears first.

**Valid `type` values:**
`boolean`, `string`, `password`, `float64`, `bytes`, `json`, `any`, `resource`. The
tables above use title-case (`String`, `Float64`, `Password`, `Json`)
and the parser accepts both; keep casing consistent within a spec.

#### Kubernetes resource-quantity values (`8Gi`, `500m`, `2`)

Chart values like `storageSize: 8Gi` or CPU limits (`500m`) are **quantity strings**,
not plain numbers. Model them as `type: String` (or `type: string`) with either
`options` for a fixed menu or a `regex` to validate the suffix — **not** `Float64`
(a `Float64` produces `8`, which breaks PVC/quantity parsing). Reference the value
**bare** in `chartValues`; do **not** append the unit with `{{ }}` concatenation
inside `chartValues` (bare-only rule above — `"{{ $var.sizeInt }}Gi"` is invalid in
`chartValues`). Put the whole quantity, unit included, in the parameter value:

```yaml
apiParameters:
  - key: storageSize
    name: Storage Size
    description: Persistent volume size (Kubernetes quantity, e.g. 8Gi)
    type: String
    modifiable: false          # PVC resize is not automatic on helm upgrade — see below
    required: false
    export: true
    defaultValue: "8Gi"
    options:                   # fixed menu — or drop options and use a regex
      - "8Gi"
      - "16Gi"
      - "32Gi"
    # regex alternative (when you want a free field): regex: "^[0-9]+Gi$"
chartValues:
  primary:
    persistence:
      size: $var.storageSize   # bare; the whole "8Gi" flows through
```

`options` applies to number, string, and JSON types.

#### Storage-size parameters on PVC-backed charts → `modifiable: false`

A `helm upgrade` (Omnistrate's `modify`) does **not** resize existing PVCs — Kubernetes
only expands a PVC when its StorageClass has `allowVolumeExpansion: true` **and** the
volume is patched, which a chart value change does not perform. Default any
storage-size parameter to `modifiable: false` unless the chart's own README documents
online volume expansion for that value. Setting `modifiable: true` produces a silent
no-op (or error) on modify. (No platform doc prescribes a helm PVC-resize path;
verify chart-native resize support in the chart README before relaxing this.)

#### Structured / JSON parameters (`type: json`)

`type: json` is **a JSON-formatted string** (a `json` value is a JSON formatted
string). The customer supplies JSON text;
it is not a YAML block. A config blob that is authored as YAML (e.g. a Jenkins JCasC
block) must be **pre-serialized to JSON** by the customer to be passed through a
`type: json` parameter. A `type: json` parameter:

```yaml
apiParameters:
  - key: extraConfig
    name: Extra Config
    description: Structured config (JSON)
    type: json
    modifiable: true
    required: false
    export: false
```

> **Limitation note (not platform-documented):** there is no worked example of a
> `type: json` value injected into a nested `chartValues` object, nor of accepting
> verbatim YAML. Advanced JSON-schema-driven UI validation for `json` parameters is
> explicitly **not supported** today. If a chart needs a large structured config blob, prefer
> hardcoding it in `chartValues`; expose it as `type: json` only if the customer
> genuinely must override it, and verify the injection behavior at build time.

#### `$var.*` inside YAML list items

The bare-form rule ("`$var.*` appears bare in `chartValues`") applies to scalar
values. **`$var.<key>` used as a YAML *list element*** (e.g.
`users: [ $var.username ]`) is not an established pattern. Treat this as unverified: **verify at build** by rendering
`instance debug` and checking the value resolves in the list, or side-step it by
passing the list as a single `type: json` value, or by pre-creating the resource the
chart references (e.g. `existingSecret`) — do not assume list-element interpolation
works without confirming.

### 4. Process rule

Present the tier table for approval **first**. Then implement the approved
Tier-1 parameters **one at a time** — one parameter per build-deploy cycle, per
the one-change-per-cycle rule in SKILL.md. Do not batch multiple new parameters
into a single build.

---

## External dependencies — chart defaults vs managed cloud services

Many charts bundle their own dependencies: a `postgresql` subchart, a bundled
`redis`, a `minio` for object storage, or in-cluster PVCs. Detect these before
recommending a parameter set:

- **Subchart entries** in `Chart.yaml` (`dependencies:` list).
- **`<dep>.enabled` toggles** in values (e.g. `postgresql.enabled: true`).
- **`externalDatabase`-style value blocks** (host/port/user/password fields that
  point the chart at an out-of-cluster service).

When the chart provides a **working default** for the dependency, present a
**SUGGESTION — never force**. Two options:

- **Option A (default): keep the chart-bundled dependency in-cluster.** Simplest;
  no extra cloud cost, no extra IAM. Good for dev/test and lower tiers. The data
  lives on cluster PVCs.
- **Option B (suggested for production tiers): replace it with a
  terraform-managed cloud service** — RDS for PostgreSQL/MySQL, ElastiCache for
  Redis/Memcached, S3 for object storage. Wire it in via an `internal: true`
  terraform service, `dependsOn`, and `{{ $<tfService>.out.<key> }}` in
  `chartValues`: disable the subchart (mechanism varies — see below) and set the
  chart's external-endpoint values from terraform outputs.

**Decision factors** to walk through with the user:

- **Durability / SLA** — managed services carry provider durability + backup SLAs;
  in-cluster PVCs do not.
- **Backup story** — RDS/ElastiCache snapshots vs. chart-managed backups.
- **Cost** — managed services add per-hour cost and possibly cross-AZ egress.
- **Egress** — traffic between the cluster and the managed service may cross AZ.
- **BYOC implication** — terraform runs in **whichever account the deployment
  model targets** (your account for hosted; the customer's account for BYOC), so
  the managed service and its cost land there too.

### Model applicability (which option is available per deployment model)

Option B (terraform-managed cloud services) is **not** available on every model:

| Deployment model | Option B (terraform-managed RDS/ElastiCache/S3)? | What to do |
|------------------|--------------------------------------------------|------------|
| **Hosted** | Yes — terraform runs in your provider account | A or B (B for prod tiers) |
| **BYOC (account)** | Yes — terraform runs in the customer's cloud account (their cost) | A or B |
| **BYOC-K8s** (`byoc-onprem`) | **No** — there is no ISV cloud account for terraform to target; Omnistrate provisions no cloud infra | **Option A** (chart-bundled in-cluster) is the right call. If the customer wants a managed DB, that is the *customer's own* affair outside the plan. |
| **Air-gapped** (`onPremDeployment`) | **No** — no cloud services are reachable in a disconnected site | **Option A is mandatory.** State this so the ISV doesn't waste time evaluating B. |

### Umbrella charts — subchart-disable mechanisms and multiple replacements

The `<dep>.enabled: false` toggle is only *one* of several conventions. **Discover the
chart's documented mechanism** from its `values.yaml`/README rather than assuming a
toggle — common patterns:

| Mechanism | Example | Seen in |
|-----------|---------|---------|
| `<dep>.enabled: false` | `postgresql.enabled: false` | Bitnami subcharts |
| `<dep>.install: false` | `redis.install: false` | some umbrella charts |
| Setting an external host toggles off the bundled one | `global.psql.host: <rds-host>` disables GitLab's internal postgres | GitLab |
| `externalDatabase.*` / `externalRedis.*` block | fill host/port/user/password to point out-of-cluster | Bitnami apps |

There is no single platform rule — always confirm the toggle in the chart's own docs.

**Multiple simultaneous replacements** (umbrella chart replacing RDS + ElastiCache +
S3 at once): a **single** internal terraform service can carry all three — its outputs
are namespaced by output key, so `{{ $infra.out.db_endpoint }}`,
`{{ $infra.out.redis_endpoint }}`, `{{ $infra.out.bucket_name }}` all read from one
service. Splitting into several internal services also works; prefer one when the
resources share a lifecycle. For **many buckets** (GitLab needs several named buckets),
use standard terraform `for_each` over a bucket-name set in the S3 module — see
[TERRAFORM_KUSTOMIZE_REFERENCE.md § S3 (object storage)](TERRAFORM_KUSTOMIZE_REFERENCE.md#s3-object-storage).

### Charts that require pre-existing Kubernetes Secrets at install time

Some charts (e.g. GitLab) expect certain `Secret` objects to already exist in the
namespace before `helm install` runs, rather than accepting the credential inline.

- **Prefer a chart value that accepts the credential inline** (`auth.password`,
  `externalDatabase.password`, an `existingSecret: ""` left empty so the chart creates
  its own) — wire it as `$var.<key>` / `$secret.<name>` per the Templating section.
  This avoids the pre-create problem entirely and is the first thing to look for.
- If the chart **strictly requires a pre-existing Secret**, Omnistrate can deploy
  `Secret` objects to a cell via **cell amenities** (`customAmenities` of
  `type: KubernetesManifest`, i.e. Kubernetes Secrets as
  cell amenities) — but that installs **once per deployment cell**, not per instance,
  so it fits shared/static secrets, not per-instance customer credentials.

> **Limitation note (no per-instance pre-install-secret primitive documented):**
> there is no documented Omnistrate mechanism that creates a **per-instance**
> Kubernetes Secret from a customer parameter *before* `helm install`. If a chart
> demands a per-instance pre-existing Secret and exposes no inline-credential value,
> treat it as a plan-design constraint: raise it with the ISV, run a docs search for a
> current mechanism, or require the chart to be adjusted to accept inline credentials.
> Do not invent a PRE_INSTALL secret-creation hook for the standard (non-air-gapped)
> Helm path — `actionHooks` are documented only for the air-gapped installer
> (`DEPLOYMENT_MODELS_REFERENCE.md` §Air-gapped).

### Worked pattern — disable bundled subchart, point at terraform-managed RDS

The chart bundles PostgreSQL via a `postgresql` subchart. Disable it and feed the
chart's `externalDatabase` block from a terraform service named `dbInfra`
(the terraform module + outputs live in
[TERRAFORM_KUSTOMIZE_REFERENCE.md](TERRAFORM_KUSTOMIZE_REFERENCE.md#managed-service-modules-for-chart-dependencies-rds--elasticache--s3)):

```yaml
services:
  - name: dbInfra              # internal terraform service — provisions RDS
    internal: true
    # terraformConfigurations: ... (see TERRAFORM_KUSTOMIZE_REFERENCE.md)

  - name: App
    dependsOn:
      - dbInfra
    helmChartConfiguration:
      chartName: my-app
      chartVersion: 1.4.2
      chartRepoName: myrepo
      chartRepoURL: https://charts.example.com
      chartValues:
        postgresql:
          enabled: false                                   # disable the bundled subchart
        externalDatabase:
          host: "{{ $dbInfra.out.db_endpoints_1 }}"        # terraform output ({{ }} for concatenation-safe consumption)
          port: 5432
          user: "appuser"
          database: "appdb"
          password: $secret.APP_DB_PASSWORD
```

The `{{ $<tfService>.out.<key> }}` form (with `{{ }}`) is the correct way to
consume a sibling terraform output in `chartValues` — see the Templating section
above. Copy the RDS / ElastiCache / S3 terraform module code from
[TERRAFORM_KUSTOMIZE_REFERENCE.md § Managed-service modules for chart
dependencies](TERRAFORM_KUSTOMIZE_REFERENCE.md#managed-service-modules-for-chart-dependencies-rds--elasticache--s3).

> **RDS endpoint is `host:port`, not host-only.** `aws_db_instance.endpoint`
> resolves to `hostname:5432` (host **and** port). A chart's `externalDatabase.host`
> usually wants the **host only**, with `port` as a separate field. Output the
> `address` attribute (`aws_db_instance.<name>.address` = host only) when the chart
> needs host-only — see [TERRAFORM_KUSTOMIZE_REFERENCE.md § RDS](TERRAFORM_KUSTOMIZE_REFERENCE.md#rds-postgresql--mysql).
> Passing the full `endpoint` into a host-only field yields a malformed connection
> string (e.g. a broken JDBC URL).

#### Threading a customer credential into the terraform service (Helm param → terraform variable)

When the **same** credential must reach both the chart (in `chartValues`) and the
sibling terraform service (as an RDS master password, say), declare a `type: Password`
apiParameter on the **customer-facing Helm service** and thread it into the terraform
service with `parameterDependencyMap`. This is the documented direction — the
consuming (parent) service declares the parameter and maps it onto the dependency; the
terraform service consumes it via `{{ $var.<key> }}` in `variablesValuesFileOverride`:

```yaml
services:
  - name: App                     # customer-facing helm service
    dependsOn:
      - dbInfra
    apiParameters:
      - key: dbPassword
        name: Database Password
        description: Password for the managed database
        type: Password
        modifiable: false
        required: true
        export: false
        parameterDependencyMap:
          dbInfra: dbPassword      # thread this value into the dbInfra terraform service
    helmChartConfiguration:
      chartValues:
        externalDatabase:
          password: $var.dbPassword   # same value the chart uses

  - name: dbInfra
    internal: true
    apiParameters:
      - key: dbPassword
        name: Database Password
        description: Password for the managed database
        type: Password
        modifiable: false
        required: true
        export: false
    terraformConfigurations:
      configurationPerCloudProvider:
        aws:
          terraformPath: /terraform/aws
          variablesValuesFileOverride: |
            db_password = "{{ $var.dbPassword }}"    # {{ }} inside .tfvars override
          gitConfiguration:
            reference: refs/tags/v1.0.0
            repositoryUrl: https://github.com/your-org/infra-repo.git
```

The customer supplies `dbPassword` once (on the App service); `parameterDependencyMap`
threads it to `dbInfra` so the RDS master password and the chart's `externalDatabase.password`
are guaranteed to match. Note only the parent can reference the child's parameters
(only parent resources can refer to child resources).

---

## Licensing — mounting the subscription-license secret in a Helm chart

Licensing (BYOC / air-gapped enforcement) is configured and explained in
[DEPLOYMENT_MODELS_REFERENCE.md § Licensing protection](DEPLOYMENT_MODELS_REFERENCE.md#licensing-protection).
For **Helm** services the platform does **not** auto-mount the license: the generated
secret `service-plan-subscription-license` must be mounted at `/var/subscription/`
inside the workload, because the validation SDKs assume the secret is
mounted under `/var/subscription/`.

Most charts expose generic `extraVolumes` / `extraVolumeMounts` values (or per-role
variants like `primary.extraVolumes`) to add a volume without editing templates. The
**chart-supporting** pattern is to mount the secret as a volume there:

```yaml
chartValues:
  # keys are chart-specific (extraVolumes / primary.extraVolumes / etc.) — verify in `helm show values`
  extraVolumes:
    - name: subscription-license
      secret:
        secretName: service-plan-subscription-license   # platform-generated license secret name
  extraVolumeMounts:
    - name: subscription-license
      mountPath: /var/subscription/                      # SDK-expected mount path
      readOnly: true
```

> **Limitation note (chart-specific value keys):** `extraVolumes` / `extraVolumeMounts`
> are common but not universal, and their exact path (top-level vs. `primary.*` /
> `controller.*`) is **chart-specific**. Confirm the chart exposes them via
> `helm show values <repo>/<chart>`; if a chart offers no extra-volume value, mounting
> the license requires a chart change. Verify the secret name
> (`service-plan-subscription-license`) and mount path (`/var/subscription/`) before shipping.

---

## Pod placement (CRITICAL)

**Chart-created pods are NOT auto-placed by Omnistrate.** Omnistrate schedules only
containers it creates itself. Pods the Helm chart stamps out have no placement constraints
unless you provide them in `chartValues`.

### Option A: Automatic affinity injection (default, recommended)

Omnistrate automatically injects node affinity and pod anti-affinity into all Kubernetes
workload resources (Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs, Pods)
rendered by your chart. No manual affinity rules are needed.

Injection is controlled by `chartAffinityControl` under `helmChartConfiguration`:

```yaml
helmChartConfiguration:
  chartName: redis
  chartVersion: 24.1.0
  chartRepoName: bitnami
  chartRepoURL: https://charts.bitnami.com/bitnami
  chartAffinityControl:
    enableInjection: true    # default: true
    enableSharedHost: true   # default: true; set false to enforce strict anti-affinity
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enableInjection` | boolean | `true` | Enables automatic injection of node affinity and pod anti-affinity rules. |
| `enableSharedHost` | boolean | `true` | When `false`, enforces strict pod anti-affinity so pods land on separate hosts. |

Omnistrate merges its injected rules with any existing affinity in your chart values — your
custom logic is preserved. Injection includes: `omnistrate.com/managed-by` (targets
Omnistrate-managed nodes), `topology.kubernetes.io/region` (deployment region),
`omnistrate.com/resource` (per-resource node group), `omnistrate.com/version` (node pool version),
and `omnistrate.com/schedule-mode: exclusive` pod label.

### Option B: Manual affinity (disable injection; full control)

Disable injection and specify affinity rules directly in `chartValues`.
Known-good example:

```yaml
helmChartConfiguration:
  chartAffinityControl:
    enableInjection: false
  chartValues:
    master:
      podLabels:
        omnistrate.com/schedule-mode: exclusive
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                - key: omnistrate.com/managed-by
                  operator: In
                  values:
                  - omnistrate
                - key: topology.kubernetes.io/region
                  operator: In
                  values:
                  - $sys.deploymentCell.region
                - key: node.kubernetes.io/instance-type
                  operator: In
                  values:
                  - $sys.compute.node.instanceType
                - key: omnistrate.com/resource
                  operator: In
                  values:
                  - $sys.deployment.resourceID
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: omnistrate.com/schedule-mode
                operator: In
                values:
                - exclusive
            namespaceSelector: {}
            topologyKey: kubernetes.io/hostname
```

Labels and their purpose:

| Label | Purpose |
|-------|---------|
| `omnistrate.com/managed-by: omnistrate` | Only Omnistrate-provisioned worker nodes — keeps pods off cell system/control-plane capacity |
| `topology.kubernetes.io/region` | The deployment cell's region |
| `node.kubernetes.io/instance-type` | The customer-selected instance type |
| `omnistrate.com/resource: <resourceID>` | The per-resource node group — separates instances under CUSTOM_TENANCY |

> **Tip:** You do NOT need to disable injection to add custom affinity rules.
> Omnistrate merges; only Omnistrate-specific rules not already present are appended.

---

## Multi-service plans

When one service depends on another, use `dependsOn` (ordering) and
`parameterDependencyMap` (parameter threading). Known-good example
(Redis → Postgres pattern):

```yaml
services:
  - name: Redis Cluster
    dependsOn:
    - Postgres Database
    # ...
    apiParameters:
      - key: postgresUsername
        description: Postgres Username
        name: Postgres Username
        type: String
        modifiable: false
        required: false
        export: true
        defaultValue: "postgres"
        parameterDependencyMap:
          Postgres Database: postgresUsername    # maps to key in the dependency
      - key: postgresPassword
        description: Postgres Password
        name: Postgres Password
        type: Password
        modifiable: false
        required: true
        export: true
        parameterDependencyMap:
          Postgres Database: postgresPassword
      - key: postgresDatabase
        description: Postgres Database
        name: Postgres Database
        type: String
        modifiable: false
        required: false
        export: true
        defaultValue: "postgres"
        parameterDependencyMap:
          Postgres Database: postgresDatabase

  - name: Postgres Database
    # ...
    apiParameters:
      - key: postgresUsername
        description: Postgres Username
        name: Postgres Username
        type: String
        modifiable: true
        required: true
        export: true
      - key: postgresPassword
        description: Postgres Password
        name: Postgres Password
        type: String
        modifiable: true
        required: true
        export: true
      - key: postgresDatabase
        description: Postgres Database
        name: Postgres Database
        type: String
        modifiable: true
        required: true
        export: true
```

Rules:
- `dependsOn` declares creation ordering — Postgres is created before Redis.
- `parameterDependencyMap` threads the dependency's exported parameter values into the dependent service.
- The key in `parameterDependencyMap` is the dependency service name; value is the parameter key on that service.

---

## Exposing endpoints

### LoadBalancer service with external-dns (per-instance hostname)

In `chartValues`, set a LoadBalancer annotation pointing to `$sys.network.externalClusterEndpoint` (bare, no `{{ }}`):

```yaml
chartValues:
  master:
    service:
      type: LoadBalancer
      annotations:
        external-dns.alpha.kubernetes.io/hostname: $sys.network.externalClusterEndpoint
```

### endpointConfiguration (surfaces connectivity to customers)

`endpointConfiguration` does NOT create the Kubernetes Service, Ingress, or DNS record —
it describes the connectivity details Omnistrate surfaces to customers via the portal and API.

```yaml
services:
  - name: Redis Cluster
    endpointConfiguration:
      cluster:
        host: "$sys.network.externalClusterEndpoint"
        ports:
          - 6379
        primary: true
        networkingType: PUBLIC
      admin:
        host: admin-{{ $sys.network.internalClusterEndpoint }}   # {{ }} needed for concatenation
        ports:
          - 8888
        primary: false
        networkingType: PRIVATE
```

Keep the `host` values aligned with the DNS records your chart creates via `external-dns` annotations
or cloud load balancer annotations. Endpoint information appears only after the underlying
Kubernetes resources are provisioned and the host/IP is resolvable.

**`networkingType` values.** The field is a free string in the schema
(`EndpointConfiguration.networkingType`); the two values used across the Omnistrate docs are:

| Value | Meaning | Host variable to pair it with |
|-------|---------|-------------------------------|
| `PUBLIC` | Reachable over the public internet via a platform-managed LB/DNS | `$sys.network.externalClusterEndpoint` |
| `INTERNAL` | Reachable only inside the deployment cell / cluster network (no public exposure) | `$sys.network.internalClusterEndpoint` |

INTERNAL uses `internalClusterEndpoint`; PUBLIC uses `externalClusterEndpoint`.
Choose `INTERNAL` for operator/admin ports
(e.g. a management UI) and any endpoint that should not be internet-reachable;
`PUBLIC` for the client-facing endpoint. (`PRIVATE` appears in some examples as a
synonym for internal-only exposure; prefer `INTERNAL`,
and confirm with a docs search if a chart or plan needs another value.)

**`network.ports` semantics.** `services[].network.ports` is a list of ports and
port ranges that the platform opens
for the service. List the ports the service must actually serve/expose; do **not** list
purely cluster-internal ports (e.g. Erlang distribution/epmd, inter-broker ports) that
should never be externally reachable. `endpointConfiguration` then surfaces the
customer-relevant subset with per-endpoint `networkingType`.

### Plan-level L7 HTTPS load balancer

Use `loadBalancers.https` with `targetKubernetesServiceName` pinned to the **exact name** of the
Kubernetes Service created by the chart. Omitting it causes Omnistrate to synthesize a backend
name from the resource key — that Service does not exist and the LB fails.

```yaml
loadBalancers:
  https:
    - name: public-api
      description: TLS-terminated HTTPS endpoint.
      enableCustomDNS: true
      paths:
        - associatedResourceKey: Redis Cluster       # the service name in the spec
          targetKubernetesServiceName: redis-master   # MUST match the chart-created K8s Service name
          path: /
          backendPort: 6379
```

### Plan-level L4 TCP load balancer (`loadBalancers.tcp`)

For **TCP** services (Kafka 9092, PostgreSQL 5432, Redis 6379, RabbitMQ AMQP 5672) an
L7 HTTPS LB does not apply — use `loadBalancers.tcp`. Each entry has a `name`,
`description`, and a `ports` list; each port maps an external `ingressPort` to a
`backendPort` on the resource(s) named in `associatedResourceKeys`:

```yaml
loadBalancers:
  tcp:
    - name: amqp
      description: Public TCP ingress for AMQP.
      ports:
        - associatedResourceKeys:
            - RabbitMQ Cluster        # the service name(s) in the spec
          ingressPort: 5672           # external port on the LB
          backendPort: 5672           # port the chart's Service/pod listens on
```

| Field | Level | Meaning |
|-------|-------|---------|
| `name` / `description` | LB | Identify the L4 LB |
| `ports[].associatedResourceKeys` | port | Array of spec service names this port routes to |
| `ports[].ingressPort` | port | External port exposed on the load balancer |
| `ports[].backendPort` | port | Backend port on the associated resource |

Note the L4 port schema uses `associatedResourceKeys` (plural, an array) and has no
`targetKubernetesServiceName`, unlike the L7 `paths` schema which uses
`associatedResourceKey` (singular) + `targetKubernetesServiceName`.

**Mixed TCP + HTTP** (e.g. RabbitMQ AMQP 5672 + management UI 15672): declare both
blocks under `loadBalancers` — `tcp` for the wire protocol port, `https` for the HTTP
UI (with `targetKubernetesServiceName` pinned to the chart's UI Service). A worked
`loadBalancers` with both `https: []` and a `tcp` list appears in the operator skill's
`OPERATOR_ONBOARDING_REFERENCE.md` §Networking (same schema; that pattern also bridges
the LB to operator/chart Services with a small internal proxy service where the chart's
own Service isn't directly LB-addressable).

### Stateful TCP clusters (per-broker / per-pod external addressing)

Omnistrate provides a **cluster-level** endpoint (`$sys.network.externalClusterEndpoint`)
and the plan-level TCP LB above — this is sufficient for single-node TCP services and
for internal (in-cluster) consumers of a multi-node cluster.

**Per-pod stable external hostnames are chart-specific, not platform-provided.** A
multi-broker Kafka (or any cluster where each pod must advertise its own externally
reachable address, e.g. `advertised.listeners`) needs each broker to have a distinct
stable external hostname. There is **no `$sys.*` variable for a per-pod/per-ordinal
external hostname**, and inventing one is wrong. The supported path is the **chart's own
external-access values**: for the Bitnami Kafka chart that is the `externalAccess.*`
block (one LoadBalancer Service per broker) plus its `listeners`/advertised-listener
overrides; other charts expose equivalent per-replica external-access settings. Enable
the chart's per-broker external access, let it create one Service per pod, and let the
chart populate each broker's advertised listener.

> **Limitation note (not platform-documented):** the exact chart values for per-pod
> external hostnames vary by chart and are not an Omnistrate platform feature. Discover
> them from the chart's own `values.yaml`/README (`helm show values <repo>/<chart>`),
> and verify the advertised addresses resolve externally with a docs search + a
> `instance debug` render before relying on them. Do not fabricate per-pod endpoint
> syntax; for internal-only consumers, a bootstrap endpoint against the headless
> Service is sufficient without per-pod external addressing.

### Discovering chart-created Service names (before pinning `targetKubernetesServiceName`)

`loadBalancers.https.paths[].targetKubernetesServiceName` and endpoint hosts must match
the **exact** Kubernetes Service names the chart creates. Enumerate them offline (no
live cluster needed) by rendering the chart and grepping for Services:

```bash
helm template <release> <repo>/<chart> --version <ver> | grep -A2 'kind: Service'
```

Read the `metadata.name` of each Service in the output — those are the exact names to
pin. For Bitnami charts this surfaces names like `<release>-primary`, `<release>-read`,
`<release>-headless`, etc. Do this before wiring `endpointConfiguration.host` or any
`targetKubernetesServiceName`, so a reader/replica endpoint is not left as a guess.

---

## Lifecycle semantics

| Operation | Helm action | Notes |
|-----------|-------------|-------|
| Instance create | `helm install` | First-install failure triggers automatic cleanup (no stuck pending/failed release). |
| Instance modify | `helm upgrade` | Values are re-rendered with updated `$var.*` parameters. Behavior governed by `resetValues` / `reuseValues` / `resetThenReuseValues` flags. |
| Instance delete | `helm uninstall` | Release and chart-created resources are removed. |
| Auto-reconciliation | drift detection + re-apply | Omnistrate's dataplane agent reconciles expected vs actual state. Disable with `disableReconciliation: true` (debug only). |

**First-install failure cleanup:** if the initial `helm install` fails, Omnistrate immediately cleans up
the release to ensure a clean slate for retry.

**modify = upgrade + values handling:** the `resetValues`, `reuseValues`, and `resetThenReuseValues`
flags control whether previous values are preserved or discarded on upgrade. Default (all false)
is `helm upgrade` with no explicit values flag — chart defaults for unchanged keys.

---

## Lifecycle: backups and stop/start for Helm services

The intake often flags "backups matter" or "stop/start" for stateful charts
(databases, Vault, Kafka). What the platform documents for **Helm** services is
narrower than for compose/operator services — be honest about the boundary.

### Backups — what IS and ISN'T documented for Helm

`capabilities.backupConfiguration` (`backupRetentionInDays`, `backupPeriodInHours`,
`snapshotBeforeDeletion`) is a sibling of `helmChartConfiguration` on a service in the
schema, so the **field is accepted** on a Helm service. But its behavior is only
demonstrated and described for **Docker Compose**
(`x-omnistrate-capabilities.backupConfiguration`) and **operators**
(where it pairs with `systemWorkflows`). There is
**no documented volume-snapshot backup behavior for a plain Helm
chart's PVCs.** Do not promise Omnistrate-managed PVC snapshots for a Helm service
without confirming via a docs search / a live test — treat platform-managed backup for
plain Helm as **unverified**.

Schema-accepted shape (compose/operator-documented fields):

```yaml
services:
  - name: Postgres
    capabilities:
      backupConfiguration:
        backupRetentionInDays: 7
        backupPeriodInHours: 24
        snapshotBeforeDeletion: true
    helmChartConfiguration:
      # ...
```

### Chart-native backup to an S3 bucket (the recommended path for database charts)

For database-style charts the durable, chart-supported path is the chart's own backup
mechanism (pgBackRest/WAL-G for PostgreSQL, `mysqldump`/xtrabackup sidecars for MySQL,
Vault's raft snapshot API, etc.) pointed at an **S3 bucket you provision with the
terraform S3 module** — the same internal terraform service pattern used for external
dependencies. Provision the bucket (see
[TERRAFORM_KUSTOMIZE_REFERENCE.md § S3 (object storage)](TERRAFORM_KUSTOMIZE_REFERENCE.md#s3-object-storage)
and the **S3 as a backup target** variant there), then feed the bucket name/ARN into
the chart's backup values via `{{ $<tfService>.out.<key> }}`:

```yaml
services:
  - name: backupBucket
    internal: true
    # terraformConfigurations: ... S3 module (TERRAFORM_KUSTOMIZE_REFERENCE.md)

  - name: Postgres
    dependsOn:
      - backupBucket
    helmChartConfiguration:
      chartValues:
        backup:                                  # chart-specific key — verify in `helm show values`
          enabled: true
          s3:
            bucket: "{{ $backupBucket.out.name }}"
            region: $sys.deploymentCell.region
```

> **Limitation note (chart-specific):** the `backup.*` value keys above are illustrative
> — the exact keys (and whether the chart supports S3 backup at all) are **chart-specific**.
> Discover them from `helm show values <repo>/<chart>` / the chart README before wiring;
> if the chart has no native S3 backup, that requires a chart sidecar or a separate
> capability, which is out of scope for a plain-Helm spec. In **BYOC** the bucket lands
> in the customer account (terraform runs there); in **BYOC-K8s / air-gapped** there is
> no ISV cloud target for the terraform S3 module — use in-cluster/chart-native storage
> or the customer's own object store instead (see § External dependencies model box).

### Stop / start for Helm services — not platform-documented

`omnistrate-ctl instance stop` / `instance start` exist as CLI verbs (see the Build,
deploy, iterate section), but **what stop/start does to a Helm-deployed workload
(scale StatefulSet to 0? suspend the release? snapshot PVCs?) is not documented in the
Helm reference or the docs surface reviewed here.** Do not assert a specific mechanism.
If an ISV needs defined stop/start semantics for a stateful chart, check the Omnistrate
docs (https://docs.omnistrate.com) to confirm current behavior, or consider the operator path — the
`omnistrate-operator` skill documents an operator-native quiesce mechanism for stop/start
(e.g. a hibernation annotation) that a plain Helm chart does not have.

---

## Build, deploy, iterate

```bash
# Login
omnistrate-ctl login --email "$EMAIL" --password-stdin

# Build and release (idempotent — re-run after every spec edit)
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file spec.yaml \
  --product-name "RedisHelm" \
  --environment Dev \
  --environment-type Dev \
  --release-as-preferred

# Create instance (target the main resource; pass params as JSON)
omnistrate-ctl instance create \
  --service "RedisHelm" \
  --plan "Redis Server" \
  --environment Dev \
  --cloud-provider aws \
  --region us-east-1 \
  --resource "Redis Cluster" \
  --param '{"numReplicas":"2","instanceType":"t4g.small"}' \
  --output json

# Lifecycle operations
omnistrate-ctl instance list --output json
omnistrate-ctl instance describe <instance-id> --output json
omnistrate-ctl instance stop <instance-id> --output json
omnistrate-ctl instance start <instance-id> --output json
omnistrate-ctl instance delete <instance-id> --output json

# Inspect Helm-specific debug info (rendered values, client logs, K8s resources)
omnistrate-ctl instance debug <instance-id>
```

For local chart artifacts, run `omnistrate-ctl build` from the directory containing the
`artifactRelativePath` target:

```bash
cd my-service
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file spec.yaml \
  --product-name "RedisHelm" \
  --release-as-preferred
```

**Debug loop:** instance describe (deployment status) → `instance debug <id>` for Helm
client logs and rendered values → fix spec → re-build → re-deploy.
For the full escalating loop (workflow events → tunnel), see SKILL.md workflow
phase 4; the `omnistrate-sre` skill, if installed, adds per-failure catalogs.

---

## Common mistakes

| Mistake | Effect | Fix |
|---------|--------|-----|
| Unpinned `chartVersion` | Unexpected chart upgrades on rebuild; config drift | Pin to an exact version (e.g. `19.6.2`) |
| `$var.<key>` in `chartValues` but key not in `apiParameters` | Build error or empty value at deploy | Declare every referenced key in `apiParameters` on the same service |
| Missing affinity (injection disabled; no manual rules) | Pods land on cell system/shared nodes, wrong instance's nodes, or fail to schedule | Leave injection enabled (default) or add the full manual affinity block (see Pod placement) |
| `targetKubernetesServiceName` omitted from `loadBalancers.https.paths` | Omnistrate synthesizes a backend name from the resource key; that K8s Service does not exist → 502 | Pin `targetKubernetesServiceName` to the exact chart-created Service name |
| `$var.*` or `$sys.*` wrapped in `{{ }}` inside `chartValues` | Rendering failure or literal `{{ }}` passed to Helm | Use bare form in `chartValues`: `$var.numReplicas`, `$sys.deploymentCell.region` |
| `{{ }}` omitted in `endpointConfiguration.host` concatenation | Literal string with `$sys.*` token, not the resolved value | Use `{{ }}` when concatenating: `host: "reader-{{ $sys.network.externalClusterEndpoint }}"` |
| `chartValues` and `layeredChartValues` both set | Build validation error | They are mutually exclusive; choose one per service |
| `authProvider` set for private Amazon ECR OCI repo | ECR credential resolution may fail or conflict | Omit `authProvider` for ECR OCI repos; Omnistrate resolves ECR credentials via IAM |
| `artifactRelativePath` combined with `chartRepoName`/`chartRepoURL` | Ambiguous artifact source; build error | Use one or the other, never both |
