# Operator Onboarding Reference (ServicePlanSpec)

Verified against working production specs (CNPG/postgres, KubeAI/vLLM) and
Omnistrate's operator spec template. **When something here conflicts with the
live schema or the docs, trust the schema/docs and update this file** — read them
with `omctl docs`, which needs no `omnistrate-ctl login` (network access is still required):

- `omctl docs json-schema service-plan` — the authoritative schema. The workflow
  machinery has no docs heading of its own, so read it from the schema:
  ```bash
  omctl docs json-schema service-plan -o json | jq '.["$defs"].SystemWorkflowsConfiguration'
  omctl docs json-schema service-plan -o json | jq '.["$defs"].WorkflowSpec, .["$defs"].DAGTask, .["$defs"].Template'
  omctl docs json-schema service-plan -o json | jq '.["$defs"].OperatorCRDConfiguration'
  ```
- `omctl docs plan-spec "operator crd"` — the prose reference for `operatorCRDConfiguration`
- `omctl docs plan-spec` — every other ServicePlanSpec section
- `omctl docs system-parameters` — the `$sys.*` variables used in CR templates
- `omctl docs search "<query>" --limit 15` — full-text across the guides
- `omctl docs validate --file <spec>.yaml` — validate the finished spec against the schema; run this before every build

Add `-o json` for machine-readable output.

Schema: `https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json`
— byte-identical to `omctl docs json-schema service-plan`; pin it in the spec
header comment for editor validation:

```yaml
# yaml-language-server: $schema=https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json
```

## 1. Spec skeleton

```yaml
name: <Service Plan Name>
tenancyType: CUSTOM_TENANCY
deployment:
  hostedDeployment:                 # your provider account (standard SaaS)
    awsAccountId: "<12-digit>"
    awsBootstrapRoleAccountArn: "arn:aws:iam::<acct>:role/omnistrate-bootstrap-role"
    gcpProjectId: "<project-id>"
    gcpProjectNumber: "<number>"
    gcpServiceAccountEmail: "bootstrap-...@<project>.iam.gserviceaccount.com"
    azureSubscriptionId: "<uuid>"
    azureTenantId: "<uuid>"
    nebiusTenantId: "tenant-..."
  # NOTE: BYOC is a SEPARATE plan/spec — one plan per deployment model. Do not
  # add byoaDeployment here alongside hostedDeployment. In the BYOC plan's own
  # spec, byoaDeployment always carries the AWS "Control Plane" account config,
  # whatever cloud the customers deploy into (ask which account is designated!).

features:                           # optional; Omnistrate-native features
  INTERNAL:
    logs:
  CUSTOMER:
    logs:

metering:                           # optional; usage export (BYOB / marketplaces)
  s3BucketARN: arn:aws:s3:::<bucket>   # schema-canonical: s3BucketArn
  s3BucketRegion: "<region>"

pricing:                            # optional; built-in dimensions only
  - dimension: replica              # cpu | memory | storage | replica | deploymentCell
    timeUnit: hour
    price: 0.10

billingProviders:                   # optional
  - name: stripe
    externalProductID: "<product>"
    enablePaywall: true
    isDefault: true

loadBalancers: {...}                # see §7

services:
  - name: <crResourceKey>           # the customer-facing operator-CRD resource
    ...
  - name: <helperResourceKey>       # optional: proxy / per-instance operator
    ...
```

Field names in `hostedDeployment` are lowerCamel, exactly as above. The platform
matches them case-insensitively, so an older spec using `AwsAccountId` still builds;
new specs should use the lowerCamel form so the schema pin validates cleanly.

**Dev/prod twins:** maintain `spec-dev.yaml` and `spec-prod.yaml` that are
identical EXCEPT the `deployment` account block and the metering bucket. Put a
comment at the top of each stating this contract. Releasing prod must be a
no-op on accounts (never remove an in-use account config from a released plan).

**Billing on operator plans (`CUSTOM_TENANCY`) requires a pod label.** Omnistrate
bills only pods carrying `omnistrate.com/include-customer-billing: "true"` on
this tenancy — set it on the **pod template** the operator generates (via the
CR's pod-template/labels field if the CRD exposes one, or the operator chart's
pod-labels value for the controller's own pods). Missing label = silent
zero-billing. Choosing between Stripe end-to-end billing and the metering export
(marketplaces, Chargebee, custom dimensions/aggregation), plus bucket setup and
exporter patterns: see the FDE skill's `BILLING_METERING_REFERENCE.md`.

## 2. Installing the operator and its CRDs

CRDs are cluster-scoped Kubernetes objects: a per-instance chart must never
own them (the second instance's install would conflict). CRDs always install
once per deployment cell via a custom amenity. What varies is where the
controller runs:

- **Cluster-scoped operator** (controller serves all namespaces — CNPG,
  most operators): the whole operator chart, CRDs included, installs
  once per cell as a `type: Helm` amenity (§2a).
- **Namespace-scoped operator** (controller watches only its own namespace —
  KubeAI pins its cache to `POD_NAMESPACE`): **hybrid** — CRDs via a
  `type: KubernetesManifest` amenity (or a crds-only Helm amenity), the
  operator itself per instance as a sibling service (§2b) with the chart's
  `crds.enabled: false`.

### 2a. Deployment-cell amenities (CRDs; whole cluster-scoped operators)

Amenities are declarative `customAmenities` entries in the deployment cell's
config template, managed with omnistrate-ctl:

```bash
omnistrate-ctl deployment-cell generate-config-template --cloud <cloud> > cell.yaml
# merge your customAmenities entry into cell.yaml, then:
omnistrate-ctl deployment-cell update-config-template --id <cell-id> -f cell.yaml
omnistrate-ctl deployment-cell apply-pending-changes -i <cell-id> --force
# verify on the cell: kubectl get crd <crd-name>   → Established=True
```

Cluster-scoped operator — full chart as a Helm amenity (note the PascalCase
property keys; pin it to cell system capacity so it never competes with
customer workloads):

```yaml
customAmenities:
  - name: cloudnative-pg
    description: CloudNativePG operator installed once per deployment cell.
    type: Helm
    properties:
      ChartName: cloudnative-pg
      ChartVersion: 0.28.2
      ChartRepoName: cnpg
      ChartRepoURL: https://cloudnative-pg.github.io/charts
      DefaultNamespace: cnpg-system
      ChartValues:
        priorityClassName: system-cluster-critical
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
                - matchExpressions:
                    - key: omnistrate.com/control-plane
                      operator: Exists
        tolerations:
          - key: CriticalAddonsOnly
            operator: Exists
```

CRDs only (the hybrid pattern for namespace-scoped operators):

```yaml
customAmenities:
  - name: kubeai-crd
    description: KubeAI models.kubeai.org CRD (cluster-wide; per-instance chart installs with crds=false)
    type: KubernetesManifest
    properties:
      manifests:
        - def:
            apiVersion: apiextensions.k8s.io/v1
            kind: CustomResourceDefinition
            metadata:
              name: models.kubeai.org
            spec:
              ...                # paste the full CRD from the operator release
```

**Every cell that can host an instance needs the amenity applied BEFORE an
instance lands there** — otherwise the CR apply fails with
`no matches for kind <Kind> in version <group/version>`.

### 2b. Namespace-scoped operator → hybrid: amenity CRDs + sibling service

The controller only watches its own namespace, so it must run inside each
instance's namespace. CRDs come from the §2a amenity; the operator itself is a
separate service the CR service depends on, installed per instance:

```yaml
services:
  - name: kubeaiOperator
    description: Operator + gateway, installed per instance (namespace-scoped).
    compute:
      instanceTypes:
        - name: t3.medium
          cloudProvider: aws
    network:
      ports: [8000]
    helmChartConfiguration:
      chartName: kubeai
      chartVersion: "0.23.2"
      chartRepoName: kubeai
      chartRepoURL: oci://ghcr.io/omnistrate/charts   # https and oci both work
      chartValues:
        crds:
          enabled: false        # CRDs are cluster-wide via the §2a amenity
        ...
  - name: kubeaiModel
    dependsOn:
      - kubeaiOperator          # operator up before the CR is applied
    operatorCRDConfiguration:
      helmChartDependencies: []
    systemWorkflows: {...}
```

### 2c. DEPRECATED: chart installs via helmChartDependencies

`operatorCRDConfiguration.helmChartDependencies` chart entries (the older
per-cell install method) are deprecated — do not add them in new specs; use
the §2a amenity instead. Keep the empty block, which is still required as the
marker that declares the service an operator-CRD resource:

```yaml
operatorCRDConfiguration:
  # template, supplementalFiles, readinessConditions, outputParameters are
  # also deprecated here — lifecycle lives in systemWorkflows.
  helmChartDependencies: []
```

You will still see chart entries in older specs (including Omnistrate's public
operator-spec-template) — copy their workflow anatomy, not their install
method.

## 3. systemWorkflows anatomy

Each verb holds an Argo-style workflow. Parameter threading is explicit at
every hop — a value skipped at any hop renders empty:

```
systemWorkflows.<verb>:
  outputParameters:            # optional; ONLY with a successCondition task
    <outName>: "$tasks.<taskName>.resource.status.<path>"
  workflow:
    entrypoint: <templateName>
    arguments.parameters:      # bind $sys/$var into named workflow params
      - name: namespace
        value: "{{ $sys.namespace }}"
    templates:
      - name: <templateName>   # the DAG
        inputs.parameters: [...]
        dag.tasks:
          - name: <taskName>          # lowercase alnum names
            template: <leafTemplate>
            dependencies: [<otherTask>]   # ordering within the DAG
            arguments.parameters: [...]   # re-thread inputs explicitly
      - name: <leafTemplate>   # exactly ONE k8s resource per leaf template
        inputs.parameters: [...]
        resource:
          action: apply | patch | delete
          successCondition: <cond>   # optional; blocks until true
          failureCondition: <cond>   # optional; fails fast
          manifest: |
            <single-document Kubernetes YAML with {{inputs.parameters.x}}>
```

### Condition syntax

Path-match expressions against the live resource, comma = AND. **The evaluator
supports ONLY flat dotted paths compared to numbers, booleans, or plain
(dot-free) string literals** — all verified live:

```yaml
successCondition: status.instances == {{inputs.parameters.replicaCount}}, status.readyInstances == {{inputs.parameters.replicaCount}}
failureCondition: status.phase == failed
successCondition: status.phase == completed        # plain string: works
successCondition: status.state == Succeeded        # plain string: works
successCondition: status.observedGeneration == 1   # numeric: works
successCondition: status.succeeded == 1            # batch/v1 Job gate: works
successCondition: status.clusterInfo.ready == true  # boolean + nested path: works
```

**Failure modes (all verified live):**
- **conditions[] array queries FAIL the workflow**:
  `status.conditions.#(type=="Ready").status == True` — this syntax appears
  in Omnistrate's own operator-spec-template but the evaluator rejects it and
  the create workflow terminates FAILED. Never gate on a conditions[] array;
  find a flat status field instead (`status.observedGeneration == 1` works
  for create on operators that only expose conditions).
- **Manifest drift makes the apply task hang FOREVER, gated or not.** The
  dataplane agent re-applies and diff-compares the manifest against the live
  object until they converge. Any field the CRD schema prunes (or an
  operator/webhook rewrites) never converges — typical case: a field the
  CRD dropped or relocated in a newer API version, so every create hangs at
  the apply task while the cluster itself is healthy. The tell is
  `generic CRD mismatch detected ... Missing in result` in the dp-agent
  logs (`kubectl logs -n dataplane-agent deploy/dp-agent`). Manifests must
  contain ONLY fields the target CRD version accepts verbatim — check the
  CRD schema, not the operator docs, when fields moved between versions.

Recovery in both cases: fix the spec, release a new version, then **delete
and recreate the instance** — an in-flight create blocks modify/upgrade
(`conflicting operation is already in progress`), but delete is accepted.

### outputParameters

Read from the resource object captured by a task **that has a
successCondition** (no successCondition ⇒ no captured object ⇒ any
`$tasks.X.resource.*` reference fails the workflow render — declare no
outputParameters at all in that case):

```yaml
create:
  outputParameters:
    status: "$tasks.applycluster.resource.status.phase"
    currentPrimary: "$tasks.applycluster.resource.status.currentPrimary"
    readyInstances: "$tasks.applycluster.resource.status.readyInstances"
```

### Complete create example (secret + CR, gated readiness)

```yaml
systemWorkflows:
  create:
    outputParameters:
      status: "$tasks.applycluster.resource.status.phase"
    workflow:
      entrypoint: create
      arguments:
        parameters:
          - name: namespace
            value: "{{ $sys.namespace }}"
          - name: instanceId
            value: "{{ $sys.instanceId }}"
          - name: username
            value: "{{ $var.username }}"
          - name: password
            value: "{{ $var.password }}"
          - name: replicaCount
            value: "{{ $var.replicaCount }}"
      templates:
        - name: create
          inputs:
            parameters:
              - name: namespace
              - name: instanceId
              - name: username
              - name: password
              - name: replicaCount
          dag:
            tasks:
              - name: createauthsecret
                template: apply-auth-secret
                arguments:
                  parameters:
                    - name: namespace
                      value: "{{inputs.parameters.namespace}}"
                    - name: username
                      value: "{{inputs.parameters.username}}"
                    - name: password
                      value: "{{inputs.parameters.password}}"
              - name: applycluster
                template: apply-cluster
                dependencies:
                  - createauthsecret
                arguments:
                  parameters:
                    - name: namespace
                      value: "{{inputs.parameters.namespace}}"
                    - name: instanceId
                      value: "{{inputs.parameters.instanceId}}"
                    - name: replicaCount
                      value: "{{inputs.parameters.replicaCount}}"
        - name: apply-auth-secret
          inputs:
            parameters:
              - name: namespace
              - name: username
              - name: password
          resource:
            action: apply
            manifest: |
              apiVersion: v1
              kind: Secret
              metadata:
                name: app-auth
                namespace: "{{inputs.parameters.namespace}}"
              type: kubernetes.io/basic-auth
              stringData:
                username: "{{inputs.parameters.username}}"
                password: "{{inputs.parameters.password}}"
        - name: apply-cluster
          inputs:
            parameters:
              - name: namespace
              - name: instanceId
              - name: replicaCount
          resource:
            action: apply
            successCondition: status.readyInstances == {{inputs.parameters.replicaCount}}
            failureCondition: status.phase == failed
            manifest: |
              apiVersion: postgresql.cnpg.io/v1
              kind: Cluster
              metadata:
                name: "{{inputs.parameters.instanceId}}"
                namespace: "{{inputs.parameters.namespace}}"
              spec:
                instances: {{inputs.parameters.replicaCount}}
                ...
```

Numeric CR fields take the parameter unquoted (`instances: {{...}}`); string
fields quoted. The CR name is `$sys.instanceId` so create and modify address
the same object.

## 4. Lifecycle verbs

| Verb | Trigger | Extra context variables | Typical shape |
|---|---|---|---|
| `create` | instance create | — | secrets → apply CR (successCondition = ready) |
| `modify` | instance modify | — | re-apply CR with new `$var` values; same `metadata.name` |
| `start` | instance start | — | `action: patch` — undo the quiesce (e.g. CNPG `cnpg.io/hibernation: "off"`) |
| `stop` | instance stop | — | `action: patch` — operator-native quiesce (CNPG hibernation `"on"`; other operators: pause/suspend field or replicas 0) |
| `delete` | instance delete | — | delete CR first, then secrets/aux objects (`dependencies` orders it) |
| `backup` | manual, periodic (`backupPeriodInHours`), before-delete (`snapshotBeforeDeletion`) | `$sys.snapshot.id`, `$sys.snapshot.time` | un-quiesce if needed (operators can't back up hibernated clusters) → apply Backup CR named `{{ $sys.snapshot.id }}` with `successCondition: status.phase == completed` |
| `restore` | restore API | `$sys.restore.snapshotId`, `$sys.restore.snapshotTime`, `$sys.restore.metadata.*`, `$sys.sourceInstanceId`, `$sys.targetInstanceId` | create NEW cluster named `{{ $sys.targetInstanceId }}` bootstrapped from the snapshot |
| `deleteBackup` | snapshot deletion / retention cleanup | `$sys.snapshot.id`, `$sys.snapshot.time` | delete the Backup CR |
| `failover` | Omnistrate failover action | `$var.failedReplicaId`, `$var.failedReplicaAction` | e.g. delete the failed pod, let the operator promote |

`addCapacity`/`removeCapacity` verbs also exist (patch the CR's instance
count) but are intentionally not covered here yet — scale via `modify` with a
replica-count parameter instead.

Backup verbs require the capability block on the CR service:

```yaml
capabilities:
  backupConfiguration:
    backupRetentionInDays: 7
    backupPeriodInHours: 24
    snapshotBeforeDeletion: true
```

Capability build-validations (verified live):
- Declaring `backupConfiguration` REQUIRES all three of `backup`, `restore`,
  and `deleteBackup` under systemWorkflows — the build fails otherwise.
- `backupConfiguration` is rejected on Nebius ("Nebius does not support
  backups") — exclude Nebius from plans that enable backups.
- `enableMultiZone` and `enableCustomZone` are mutually exclusive — offer
  user-selected AZs on a separate single-zone plan variant.

### Restore hand-off via snapshot metadata (proven pattern)

The backup workflow's `outputParameters` are recorded as snapshot metadata
and surface in the restore workflow as `$sys.restore.metadata.<key>`. Use
this to pass the backup's storage location to restore — e.g. export the
backup CR's `status.destination` as an outputParameter at backup time, and
consume `{{ $sys.restore.metadata.destination }}` in the restore CR's
backup-source field. Name the backup CR/Job `{{ $sys.snapshot.id }}`
so deleteBackup can address it later.

**Job-computed values (no backup CR to read).** `outputParameters` can only
read `$tasks.<task>.resource.status.*`, and a Job's status has no room for
custom values. When the backup is a Job (e.g. it drives the operator's backup
tool and learns a snapshot tag), install a tiny CRD as a cell amenity whose
`status` carries the value, have the Job write it (`kubectl patch
--subresource=status`), and gate a follow-up apply task on it:

```yaml
# amenity: a namespaced CRD with a status subresource
#   spec.versions[0].subresources.status: {}
#   status: {ready: boolean, snapshotTag: string, location: string}
- name: apply-snapshot-record
  resource:
    action: apply
    successCondition: status.ready == true          # the Job sets it
    manifest: |
      apiVersion: example.omnistrate.io/v1
      kind: SnapshotRecord
      metadata:
        name: "{{inputs.parameters.snapshotId}}"
        namespace: "{{inputs.parameters.namespace}}"
      spec: {}
# backup workflow:
outputParameters:
  snapshotTag: $tasks.recordsnapshot.resource.status.snapshotTag
```

The Job's ServiceAccount needs `get/create/patch` on the CRD and `patch` on
its `/status` subresource. Restore then reads
`{{ $sys.restore.metadata.snapshotTag }}`.

### Job-based verbs (operators without backup/restore CRs)

When the operator has no Backup/Restore CRs, or triggers backups via
CronJobs, implement the verbs as batch/v1 Jobs gated on
`successCondition: status.succeeded == 1` with
`failureCondition: status.failed > 2` (verified reliable). Rules learned live:
- **Pin a maintained multi-arch image.** `bitnami/kubectl` version tags are
  GONE (catalog migration) and fail NotFound; use `alpine/kubectl:<ver>`
  after verifying the tag on Docker Hub. Also set a `nodeSelector` for
  `kubernetes.io/arch` matching the target CLI/image.
- **CronJob-trigger pattern**: a kubectl Job runs
  `kubectl create job --from=cronjob/<name> run-<snapshotId>` then
  `kubectl wait --for=condition=complete`. Address the cronjob by its exact
  deterministic name — greps for "backup" can match unrelated cronjobs
  that happen to contain the word in their names.
- **Job pod templates are immutable.** A re-run workflow that apply-UPDATES
  an existing Job with a different template fails. To unstick a wedged verb
  in place: delete the Job and recreate it with the SAME NAME and a working
  template — the workflow's gate watches the name and passes when
  `status.succeeded == 1`.
- **Anything you set on the CR outside the spec is undone by the next
  `modify`,** which re-applies the full CR from the spec. A restart implemented
  by patching a field such as `spec.forceRedeploymentReason` gets silently
  reverted, and then re-triggers on later applies. Implement restart as a Job
  that deletes the operator's pods one at a time (waiting for each to be
  ready), not as a CR patch.
- **A failed deleteBackup wedges instance deletion**: the delete flow runs
  retention cleanup first, so a broken deleteBackup Job blocks the whole
  delete (workflow FAILED). Recovery: fix the underlying cause (e.g. a
  repository "expire" needs the repo's metadata to still exist), retry
  `instance delete` (allowed on FAILED), and if the workflow's own Job
  manifest is broken, replace the Job in place as above.

### modify: instance-type changes with node-local volumes

When the instance-type parameter changes, Omnistrate adds a node pool of the
new type, and the operator rolls its pods onto it. Pods whose PersistentVolume
is **node-local** (local NVMe / local SSD, `WaitForFirstConsumer` PVs bound to
one node) cannot follow: the re-created pod is pinned by its PV's node affinity
to a node of the old type. The modify workflow must therefore **replace** such
members (fresh volume on a new node, data re-streamed from replicas), one at a
time, using the operator's own replace mechanism. A reconcile Job that waits
for the rollout handles two cases:

- **Stranded:** the pod is `Pending` and its PV points at a node that is gone,
  cordoned, or not of the desired type. Trigger the operator's replace for that
  member.
- **Left behind on a healthy node of the wrong type:** after an interrupted
  change, a pod can start fine on an old-type node, so it never goes `Pending`.
  Once every member is ready, cordon that node and delete the pod; it goes
  `Pending` and the stranded path moves it.

Pass the desired type into the Job (`$var.<instanceTypeParam>`) and check
`node.kubernetes.io/instance-type` of each member's node. The Job only
finishes when every member is ready **and** on the desired type. This needs
2+ members and replication; refuse on a 1-member cluster.

### customWorkflows (provider-defined verbs)

```yaml
customWorkflows:
  - verb: switchPrimary
    displayName: Force switch primary
    description: Delete the current primary pod; the operator promotes a replica.
    scope:
      - fleet                      # who may invoke it
    apiParameters:
      - key: primaryPodName
        displayName: Primary Pod Name
        description: Current primary pod to delete.
        type: String
        required: true
    workflow: {...}                # same anatomy as systemWorkflows
```

## 5. apiParameters

```yaml
apiParameters:
  - key: replicaCount
    name: Replica Count            # display name
    description: Total instance count including primary.
    type: Float64                  # String | Float64 | Password | Boolean
    modifiable: true               # false ⇒ fixed at create (REQUIRED false for
                                   #   any param feeding metadata.name)
    required: false
    export: true                   # visible on the instance; false for secrets
    defaultValue: "3"              # ALWAYS a quoted string, even Float64
    limits:
      min: 1
      max: 9
  - key: engine
    type: String
    options:                       # enum
      - VLLM
      - OLlama
  - key: username
    type: String
    regex: "^[a-z_][a-z0-9_]{0,62}$"
  - key: nebiusPlatform
    type: String
    scope:
      cloudProviders: [nebius]     # param only exists on this cloud
```

Rules:
- Declare every param on the resource that `instance create` targets
  (`--resource <key>`). Params declared only on a dependency are dropped at
  create. Declaring the same key on both services yields one shared value
  (useful when the operator service's chartValues need `$var` from the CR
  service's create call).
- **Never use the key `replicaCount`.** The platform overrides a parameter
  with that key during `start` (observed rendering as 1). Use a
  product-specific key such as `memberCount`.
- **Adding a new `required` parameter breaks upgrades of existing
  instances.** The upgrade's modify workflow fails to render with
  `unresolved workflow input parameters: [$var.<key>]`, because instances
  created on an older version have no value for it. A follow-up
  `omctl instance modify <id> --param '{"<key>":"<value>"}'` on the new
  version is accepted and completes the rollout. Tell existing customers to
  set the parameter when they upgrade, or give it a safe `defaultValue`.
- Optional nested YAML (args lists, env maps, nodeSelector) can't be built
  conditionally in the manifest — pass a pre-composed, **pre-indented** block
  string param placed at the target indent column; empty string collapses the
  line:

```yaml
manifest: |
  ...
  spec:
    minReplicas: {{inputs.parameters.minReplicas}}
    {{inputs.parameters.modelArgsBlock}}
```

## 6. Variables

| Variable | Meaning |
|---|---|
| `$var.<key>` | API parameter value |
| `$sys.namespace` | per-instance namespace (`instance-<id>`) |
| `$sys.instanceId` | instance id — use as CR `metadata.name` |
| `$sys.deploymentCell.region` | cell region |
| `$sys.deploymentCell.publicSubnetIDs[*].id` | subnet ids |
| `$sys.compute.node.instanceType` | node instance type in play |
| `$sys.deployment.resourceID` | resource id (node-pool label value) |
| `$sys.network.externalClusterEndpoint` | external DNS endpoint |
| `$sys.snapshot.id`, `$sys.snapshot.time` | backup/deleteBackup context |
| `$sys.restore.snapshotId/.snapshotTime/.metadata.<k>` | restore context |
| `$sys.sourceInstanceId`, `$sys.targetInstanceId` | restore source/target |
| `$func.base64encode(x)` | e.g. secret `data:` values |

Concatenation needs `{{ }}`: `host: "reader-{{ $sys.network.externalClusterEndpoint }}"`.
Do not invent variables (`$sys.id` etc.). The authoritative list is one command
away — run it whenever you need a path that is not in the table above:

```bash
omctl docs system-parameters -o json          # full $sys.* schema
```

> **`docs system-parameters` does not cover workflow-context variables.** Its root
> exposes only `backup`, `compute`, `deployment`, `deploymentCell`, `id`, `network`,
> `storage`, `tenant`, `deterministicSeedValue`. `$sys.namespace`, `$sys.instanceId`,
> `$sys.restore.*`, `$sys.sourceInstanceId` and `$sys.targetInstanceId` are **real but
> absent from it**. Never drop a `$sys.*` path just because this command omits it —
> confirm with `omctl docs search "workflow context system parameters" --limit 15`.

(The MCP docs-search tool `mcp__ctl__docs_system_parameters` is an optional
alternative only when the user has asked to work through MCP.)

## 7. Networking

### L4 TCP LB + internal proxy (databases; CNPG pattern)

The LB needs a backend container listening on the port; operator pods usually
sit behind operator-created Services. Bridge with a tiny internal service:

```yaml
loadBalancers:
  https: []
  tcp:
    - name: postgres-writer
      description: Public TCP ingress for the writer endpoint.
      ports:
        - associatedResourceKeys: [postgresProxy]
          ingressPort: 5432
          backendPort: 5432

services:
  - name: postgresProxy
    internal: true
    image: alpine/socat:1.8.0.0
    command: [/bin/sh, -ec]
    args:
      - |
        INSTANCE_ID="$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)"
        socat TCP-LISTEN:5432,fork,reuseaddr TCP:"${INSTANCE_ID}-rw:5432" &
        wait
    compute:
      replicaCount: 1
      instanceTypes:
        - name: t4g.small
          cloudProvider: aws
    network:
      ports: [5432]
```

### L7 HTTPS LB onto a chart-created Service (KubeAI pattern)

> Confirm with `kubectl get ingress,svc -n <instance-id>` that this produced an
> Ingress or DNS record. In one observed Helm-plan case it produced neither,
> and a chart-created nginx Ingress using the per-instance
> `google-public-ca-tls` secret was needed. See the FDE skill's
> `HELM_ONBOARDING_REFERENCE.md` → "Exposing endpoints" → "Read this first".

```yaml
loadBalancers:
  https:
    - name: public-api
      description: TLS-terminated API endpoint.
      enableCustomDNS: true
      paths:
        - associatedResourceKey: kubeaiOperator
          targetKubernetesServiceName: kubeai   # MUST pin the chart's Service;
          path: /                               # omitted ⇒ Omnistrate synthesizes
          backendPort: 80                       # a backend from the resource key,
                                                # which the chart never creates
```

### endpointConfiguration (writer/reader style)

```yaml
endpointConfiguration:
  writer:
    host: "$sys.network.externalClusterEndpoint"
    ports: [5432]
    primary: true
    networkingType: PUBLIC
  reader:
    host: "reader-{{ $sys.network.externalClusterEndpoint }}"
    ports: [5432]
    primary: false
    networkingType: PUBLIC
```

> **A prefixed host MUST use `{{ }}`.** The bare form
> `$sys.network.externalClusterEndpoint` is interpolated only when it is the
> whole value; `grafana.$sys.network.externalClusterEndpoint` is stored and
> shown literally. The build passes, `list-endpoints` shows the literal text as
> `UNHEALTHY`, and a **create** then hangs indefinitely on Omnistrate's own
> "Monitoring" step (it probes the unresolvable host; observed for 40+ min
> with no events). Modify/upgrade workflows don't run that step, so the bug
> shows up only on fresh creates.

### Per-member LoadBalancer Services created by the operator

Some data services need every member reachable from outside, because
token- or partition-aware drivers connect to each member directly (ScyllaDB /
Cassandra, Kafka brokers). One shared L4 LB cannot serve that. Operators
usually support it natively: a LoadBalancer Service per member, and members
advertising the LB address to clients (ScyllaDB Operator
`exposeOptions.nodeService.type: LoadBalancer` +
`broadcastOptions.clients: ServiceLoadBalancerIngress`). Omnistrate does not
manage these LBs, so the spec must handle what it normally would:

- **DNS:** annotate each member Service with
  `external-dns.alpha.kubernetes.io/hostname` inside the instance's zone
  (e.g. `node-<n>.<zone>`, and the published `endpointConfiguration` host on
  member 0 as the contact point). The zone is
  `$sys.network.externalClusterEndpoint` minus its first label. Annotate from
  an ops Job after the Services exist; see the FDE skill's
  `HELM_ONBOARDING_REFERENCE.md` → "Exposing endpoints" for how the cell's
  external-dns picks records up.
- **Only the client ports reachable.** The operator's member Service
  typically carries *every* port (inter-node, JMX, metrics, agent APIs), and
  the cloud LB exposes all of them. Close the rest per cloud:

| | AWS (NLB, AWS Load Balancer Controller) | GCP (GKE external passthrough LB) |
|---|---|---|
| Restrict ports | A security group from a Terraform resource in the plan, allowing only client ports from `0.0.0.0/0`, attached with `service.beta.kubernetes.io/aws-load-balancer-security-groups`; also list only those ports in `network.ports` (the node security group) | GKE's `k8s2-*` firewall rules open every Service port to `0.0.0.0/0` at priority 1000. Add, from a Terraform resource, an allow rule for the cell's own ranges (priority 900) and a deny rule from `0.0.0.0/0` (priority 950) on the internal ports, targeting the plan's node tag `product-tier-<lowercased planId>-id` |
| Required Service settings | `loadBalancerClass: service.k8s.aws/nlb` in the operator's Service template: the controller sets it and it is immutable, so a mismatch leaves the CR `Degraded` forever | **`externalTrafficPolicy: Local`.** With `Cluster`, the LB also delivers to cell system nodes, which lack the plan tag, so the deny rule doesn't apply there and kube-proxy forwards the internal ports to the member. Observed: an internal port answering from the internet about half the time |
| Other | `load_balancing.cross_zone.enabled=true` (members may advertise one per-AZ address); `preserve_client_ip.enabled=false` if in-cell components call members through their LB (a preserved-IP NLB can't hairpin) | `cloud.google.com/l4-rbs: enabled` for backend-service LBs |

Terraform identity permissions: AWS needs EC2 security-group create/describe/
authorize/revoke/delete; GCP needs `roles/compute.securityAdmin` and
`roles/compute.networkViewer` (otherwise the apply fails on
`compute.networks.get`). Useful Terraform variables:
`$sys.deploymentCell.cloudProviderNetworkID`, `$sys.deploymentCell.cidrRange`,
`$sys.deploymentCell.gcp.projectID`. These Service settings are usually
immutable in the operator (`exposeOptions`), so a wrong value means
re-creating the instance. **Verify from outside the VPC after create** by
probing every port of every member several times; only the client ports may
connect.

## 8. Compute and node placement

Fixed type per cloud, or customer-selectable via a param. **Every entry provisions its own
node group** — including multiple entries sharing one `cloudProvider`, which is how one
resource backs several machine sizes (e.g. an always-on small pool plus a scale-from-zero
large pool). This is ServicePlanSpec behaviour; compose is the opposite, where the first
entry matching the cloud wins and same-cloud duplicates are ignored. Per-node-group settings
— `labels`, `taints`, `WarmPoolConfiguration.minimumNodesInPool` — go under each entry's
`configurationOverrides`; see
[`omnistrate-fde/HELM_ONBOARDING_REFERENCE.md` §Compute: instance types and node groups](../omnistrate-fde/HELM_ONBOARDING_REFERENCE.md#compute-instance-types-and-node-groups).

```yaml
compute:
  rootVolumeSizeGi: 50
  instanceTypes:
    - name: t3.medium              # fixed
      cloudProvider: aws
    - apiParam: gcpInstanceType    # customer-selectable
      cloudProvider: gcp
    - apiParam: nebiusInstanceType
      cloudProvider: nebius
      platform: cpu-e2             # Nebius needs preset + platform;
                                   # platform can be "$var.<param>"
    - apiParam: awsInstanceType
      cloudProvider: aws
      configurationOverrides:
        timeSlicingReplicas: 8     # GPU time-slicing (aws/gcp/nebius)
```

### Pinning operator-created pods to Omnistrate-managed node groups

Omnistrate schedules only the containers it creates itself (plain `image:`
services and charts it installs). Pods the OPERATOR stamps out from your CR
inherit nothing — without explicit pinning they land on cell system/shared
nodes, another instance's nodes, or fail to schedule. Every pod template the
operator renders MUST carry the affinity below.

**Step 1 — thread the placement values** into the workflow as parameters:

| Workflow argument | Value |
|---|---|
| `region` | `{{ $sys.deploymentCell.region }}` |
| `instanceType` | `{{ $sys.compute.node.instanceType }}` |
| `resourceId` | `{{ $sys.deployment.resourceID }}` |

> **Multi-instance-type resources: drop the `instanceType` term.**
> `$sys.compute.node.instanceType` resolves to a single type, so a `required` match on
> `node.kubernetes.io/instance-type` strands the workload on one of the resource's node
> groups. When the resource declares more than one `instanceTypes` entry, omit that key and
> rely on `omnistrate.com/resource` (`resourceId`), which every node group of the resource
> carries.

**Step 2 — render this required node affinity** into the CR wherever the
operator forwards pod placement:

```yaml
requiredDuringSchedulingIgnoredDuringExecution:
  nodeSelectorTerms:
    # Term 1: AWS/GCP/Azure — instance type is advertised as
    # node.kubernetes.io/instance-type
    - matchExpressions:
        - key: omnistrate.com/managed-by
          operator: In
          values: [omnistrate]
        - key: topology.kubernetes.io/region
          operator: In
          values: ["{{inputs.parameters.region}}"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["{{inputs.parameters.instanceType}}"]
        - key: omnistrate.com/resource
          operator: In
          values: ["{{inputs.parameters.resourceId}}"]
    # Term 2: Nebius — presets are advertised as nebius.com/resource-preset.
    # Terms are OR'd, so keeping both makes one manifest multi-cloud.
    - matchExpressions:
        - key: omnistrate.com/managed-by
          operator: In
          values: [omnistrate]
        - key: topology.kubernetes.io/region
          operator: In
          values: ["{{inputs.parameters.region}}"]
        - key: nebius.com/resource-preset
          operator: In
          values: ["{{inputs.parameters.instanceType}}"]
        - key: omnistrate.com/resource
          operator: In
          values: ["{{inputs.parameters.resourceId}}"]
```

What each label enforces:

| Label | Purpose |
|---|---|
| `omnistrate.com/managed-by: omnistrate` | only Omnistrate-provisioned worker nodes — keeps pods off cell system/control-plane capacity |
| `topology.kubernetes.io/region` | the deployment cell's region |
| `node.kubernetes.io/instance-type` / `nebius.com/resource-preset` | the paid instance type/preset the customer selected — **omit when the resource declares several `instanceTypes` entries**, or the workload is stranded on one of its node groups |
| `omnistrate.com/resource: <resourceID>` | resource identity — what separates one instance's nodes from another's under CUSTOM_TENANCY. Carried by **all** node groups of the resource, so it spans multi-instance-type resources. |

**Where to put it** depends on how the CRD forwards placement to pods — check
the operator's API: a dedicated affinity block (CNPG `spec.affinity.nodeAffinity`),
a nested pod-template path, or a flat
nodeSelector the operator merges (KubeAI `Model.spec.nodeSelector` /
`resourceProfiles.<name>.nodeSelector`). If the operator only exposes a flat
nodeSelector, use the single-cloud minimum:

```yaml
nodeSelector:
  omnistrate.com/managed-by: omnistrate
  node.kubernetes.io/instance-type: "{{inputs.parameters.instanceType}}"
```

**GPU node groups:** the extended-resource request is what confines pods to
GPU nodes (only they advertise it), and GPU nodes carry a device-plugin taint
that needs a toleration:

```yaml
requests:
  nvidia.com/gpu: 1        # or a MIG profile, e.g. nvidia.com/mig-1g.10gb
limits:
  nvidia.com/gpu: 1
tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule
```

**Multi-tenant packing (schedule-mode):** label the operator's pods
`omnistrate.com/schedule-mode: exclusive|shared` (e.g. via the CR's inherited
metadata) and add a preferred anti-affinity against `exclusive` pods — so
exclusive instances repel co-tenants while shared ones bin-pack:

```yaml
additionalPodAntiAffinity:               # CNPG spelling; adapt per operator
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
            - key: omnistrate.com/schedule-mode
              operator: In
              values: [exclusive]
        namespaceSelector: {}
        topologyKey: "{{inputs.parameters.topologyKey}}"
```

**The operator's auxiliary pods inherit the CR's placement.** Operators
often copy the member placement into per-member Jobs (cleanup, repair,
bootstrap). A hard pod anti-affinity meant as "one member per node" then also
repels those Jobs, and each one forces an extra node from the pool. Scope the
rule to the member pod type with `matchLabelKeys` on the operator's pod-type
label:

```yaml
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels: {scylla/cluster: "{{inputs.parameters.instanceId}}"}
      matchLabelKeys: [scylla-operator.scylladb.com/pod-type]   # adapt per operator
      topologyKey: kubernetes.io/hostname
```

For HA topologies expose placement knobs as params (topologyKey zone vs
hostname, anti-affinity preferred vs required, PDB on/off) so single-node dev
cells can still schedule.

**Mixed-architecture cells + operators without a placement API.** Cells run
arm64 AND amd64 node groups. If the operator's images are single-arch
and its pods carry no placement constraints,
they scatter onto arm64 nodes and fail with `no match for platform in
manifest` (ImagePullBackOff). Verify the operator's CRD actually FORWARDS a
placement field before relying on it — some CRDs silently ignore unknown
placement fields. If the operator has no placement API, that is
a vendor gap: the only mitigation is patching the operator-created
StatefulSet/Deployment out-of-band
(`kubectl patch sts <name> --type merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/arch":"amd64"}}}}}'`)
— not reproducible from the spec, so flag it to the operator vendor.

## 9. Build, deploy, iterate

```bash
# login
omnistrate-ctl login --email "$EMAIL" --password-stdin

# build + release (idempotent; re-run after every spec edit)
omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec \
  --product-name "<Service Name>" --environment Dev --environment-type Dev \
  --release-as-preferred

# create instance against the CR resource
omnistrate-ctl instance create --service "<Service Name>" --plan "<Plan>" \
  --environment Dev --cloud-provider aws --region ap-south-1 \
  --resource <crResourceKey> \
  --param '{"password":"...","replicaCount":3}' --output json

# inspect / lifecycle
omnistrate-ctl instance list --filter="service:<Service Name>,plan:<Plan>" --output json
omnistrate-ctl instance describe <instance-id> --output json
omnistrate-ctl instance stop|start|delete <instance-id> --output json
omnistrate-ctl upgrade create <instance-id> --version=preferred --output json
```

MCP equivalents (only on user request, when the ctl MCP server is connected):
`mcp__ctl__build` (spec-type ServicePlanSpec), `mcp__ctl__instance_create`,
`mcp__ctl__instance_describe deployment_status=true`, `mcp__ctl__workflow_list`,
`mcp__ctl__workflow_events`, `mcp__ctl__docs_*` searches. Verify exact tool
names/flags with `--help` — do not guess flags.

Debug loop: instance describe (deployment status) → workflow list/events for
the failed verb → live CR status + operator logs (kubectl) → fix spec →
re-build → re-deploy. The `omnistrate-sre` skill, if installed, provides the
systematic version.

## 10. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Workflow render fails referencing `$tasks.X.resource.*` | Task X has no `successCondition`, so no resource is captured. Remove the outputParameters or add a successCondition. |
| Only the first object of a manifest was created | Multi-doc manifest in one apply task — only doc #1 applies. One resource per template. |
| Param set at create arrives empty in the workflow | Param not declared on the resource `instance create` targeted; or a threading hop (dag task arguments / template inputs) missing. |
| Modify created a second CR instead of updating | CR name derives from a modifiable param. Name by `$sys.instanceId` or set the param `modifiable: false`. |
| Build error on a numeric defaultValue | Unquoted. `defaultValue: "3"`. |
| L7 LB 502 / no backend | `targetKubernetesServiceName` missing — Omnistrate synthesized a backend from the resource key. Pin the operator/chart Service name and its port. |
| Operator pods land on wrong/no nodes | CR doesn't pin operator-created pods to the managed node group — add the §8 affinity block; GPU nodes also need the taint toleration. |
| ImagePullBackOff: `no match for platform in manifest` | Single-arch image scheduled onto the wrong CPU architecture (mixed arm64/amd64 cells). Pin via the operator's placement field, or if the operator has none, see §8 mixed-architecture note. |
| Verb Job image NotFound (`bitnami/kubectl:...`) | Bitnami catalog migration removed version tags. Use a verified `alpine/kubectl` tag (§4 Job-based verbs). |
| Instance delete FAILED / stuck after a backup existed | Delete runs snapshot retention cleanup (deleteBackup) first; if that Job fails or its image is broken the delete wedges. See §4 Job-based verbs for in-place recovery; `instance delete` can be retried on a FAILED instance. |
| Second instance fails installing CRDs | Per-instance chart owns cluster-scoped CRDs. `crds.enabled=false` + cell amenity (§2a). |
| CR apply fails: `no matches for kind <Kind>` | The CRD amenity was never applied to that deployment cell. Apply it (§2a) to every cell that can host an instance. |
| Backup workflow hangs on hibernated cluster | Un-quiesce first inside the backup workflow, wait ready, then create the Backup CR. |
| HA replica pod stuck ContainerCreating with `Multi-Attach error` | The operator creates a cluster-SHARED PVC (e.g. a common archive/backup volume) that every replica mounts — needs an RWX StorageClass, which cells don't ship by default. Either configure an RWX class (EFS/Filestore) as cell infra, or reconfigure the operator to use object storage instead and omit the shared volume (e.g. drop shared archive/backup volumes in favor of an object-storage backup repository). Check the operator's per-replica volume topology BEFORE enabling HA. |
| create hangs forever at successCondition | Condition references a status field the operator never writes at this state (e.g. waiting on replicas with scale-to-zero). Check a live CR's actual status; drop or change the condition. |
| CR is ready on-cluster but the task never completes | Unsupported condition syntax: conditions[] array queries (`#(type=="Ready")`) and dotted string literals (`== 1.1.0`) never match. Use a flat path with a numeric or dot-free string value (§3). |
| Upgrade fails: `unresolved workflow input parameters: [$var.<key>]` | The new version added a `required` parameter that the instance never had. Run `omctl instance modify <id> --param '{"<key>":"..."}'` on the new version (§5). |
| Endpoint shows a literal `…$sys.network.externalClusterEndpoint` and is `UNHEALTHY`; create stuck on the "Monitoring" step | Prefixed endpoint host without `{{ }}` (§7). Fix the host, rebuild, and re-create the instance. |
| Delete task fails: `unsupported delete generic CRD flag` | Only `--ignore-not-found=true` is accepted in a delete task's `flags` (no `--cascade`, `--wait`, ...). |
| CR `Degraded`: `spec.loadBalancerClass: Invalid value: null: may not change once set` (AWS) | The AWS Load Balancer Controller set `service.k8s.aws/nlb` on the operator's Service. Declare the same class in the CR's Service template (§7 per-member LBs); immutable, so re-create the instance. |
| Internal ports of a per-member LB reachable from the internet (GCP), intermittently | `externalTrafficPolicy: Cluster` lets the LB land on untagged system nodes that your firewall rules don't cover. Use `Local` (§7 per-member LBs); immutable, so re-create the instance. |
| stop/backup rejected with "conflicting operation is already in progress" | Another workflow on the instance still holds the lock — including a backup workflow whose steps all succeeded but whose parent record stays RUNNING (observed platform behavior). List workflows for the instance and wait or escalate; retrying immediately won't help. |

---

## 11. Operators on customer-managed Kubernetes (BYOC-K8s)

An operator plan can target a customer-owned cluster (`byoaDeployment`, deployed
with `--cloud-provider byoc-onprem --region on-prem`). Everything above still
applies, but four assumptions that hold on hosted/BYOC cells break here, because
**Omnistrate provisions no infrastructure** in a cluster it does not own.

Read [`BYOC_K8S_REFERENCE.md`](../omnistrate-fde/BYOC_K8S_REFERENCE.md) in the
`omnistrate-fde` skill for the deployment model itself (onboarding flow, install
kit, egress allowlist, endpoints). The operator-specific deltas:

**1. CRD installation mutates a cluster you don't own.** Installing the operator's
CRDs is cluster-scoped. Confirm the customer accepts it and that the identity the
`dp-agent` runs as may create CRDs, ClusterRoles, and ClusterRoleBindings. Raise
this at intake — it is frequently the item that needs a customer security review.

**2. The customer may already run the same operator.** A shared CNPG, Strimzi, or
cert-manager install is common in enterprise clusters, and a second cluster-scoped
install will fight the incumbent over the same CRDs. The §2a pattern —
operator + CRDs as a **deployment-cell amenity**, per-instance resources as
namespaced CRs — is not merely preferred on BYOC-K8s, it is what makes coexistence
possible. Ask what is already installed before designing the install path.

**3. No cloud load balancer, no cloud StorageClass.** The §7 networking patterns
that request a `LoadBalancer` Service, and any CR field naming `gp3` /
`premium-rwo`, will hang on a customer cluster. Use ClusterIP plus the customer's
own ingress, and take the StorageClass name as an `apiParameter` (or rely on the
cluster default). A missing StorageClass leaves PVCs `Pending` and the
`successCondition` never fires — it looks like an operator bug and is not.

**4. Operator-managed backups need a customer-supplied target.** There is no
Omnistrate-provisioned S3 bucket on BYOC-K8s, so the §4 backup verbs must point the
operator's backup configuration (pgBackRest repo, Velero target, etc.) at an object
store the customer supplies as `apiParameters`. Decide this before promising
backup/restore verbs in a BYOC-K8s plan.

| BYOC-K8s pitfall | Correction |
|---|---|
| Assuming CRDs can be installed silently | Cluster-scoped change on customer infrastructure — get explicit agreement |
| Per-instance chart owning CRDs | `crds.enabled=false` + cell amenity (§2a); mandatory here, not optional |
| Ignoring an operator the customer already runs | Check first; collide and both reconcilers fight |
| `LoadBalancer` Service in the CR | ClusterIP + customer ingress |
| Hardcoded cloud StorageClass | `apiParameter` or cluster default |
| Backup verbs with no bucket | Customer-supplied object store via `apiParameters` |
