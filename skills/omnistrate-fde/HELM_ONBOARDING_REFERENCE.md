# Helm Chart Onboarding Reference

Verified against `resource-spec-samples/service-spec-helm.yaml` and the Omnistrate
documentation under `docs/build-guides/helm-charts-*` and `docs/getting-started/build-from-helm.md`.
When this file conflicts with the live schema or a docs search, trust the schema/docs.

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

Copied and adapted from `resource-spec-samples/service-spec-helm.yaml`.

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

Source: `docs/spec-guides/plan-spec.md` helm chart configuration schema section.

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
Source: `docs/build-guides/helm-charts-runtime-configuration.md`.

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

This is exactly how they appear in `resource-spec-samples/service-spec-helm.yaml`:

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

Common `$sys.*` paths used in the sample and docs:

| Path | Value |
|------|-------|
| `$sys.network.externalClusterEndpoint` | External DNS hostname for the load balancer |
| `$sys.network.internalClusterEndpoint` | Internal cluster DNS endpoint |
| `$sys.deploymentCell.region` | Deployment cell region (e.g. `us-east-1`) |
| `$sys.deploymentCell.cloudProviderName` | Cloud provider (`aws`, `gcp`, `azure`) |
| `$sys.compute.node.instanceType` | Instance type in play |
| `$sys.deployment.resourceID` | Resource ID (node-pool label value) |
| `$sys.id` | Unique identifier for the service instance |

### `$secret.*`

Reference secrets managed by Omnistrate:

```yaml
chartValues:
  auth:
    password: $secret.REDIS_PASSWORD
```

### Consuming Terraform outputs

Use `{{ $<terraformServiceName>.out.<key> }}` (with `{{ }}`) to reference outputs from a sibling Terraform service.
The variable root is the **Terraform service name** (camelCased, spaces dropped) as declared in `dependsOn`.
Source: `docs/build-guides/helm-charts-terraform.md`.

```yaml
chartValues:
  s3BucketARN: "{{ $dataInfraTerraform.out.s3_bucket_arn }}"
  dynamoDBTableARN: "{{ $dataInfraTerraform.out.dynamodb_table_arn }}"
```

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
Copied verbatim from `resource-spec-samples/service-spec-helm.yaml`:

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
`parameterDependencyMap` (parameter threading). Copied from `resource-spec-samples/service-spec-helm.yaml`
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

Source: `docs/spec-guides/plan-spec.md` L7 Load Balancer Path Configuration schema.

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
