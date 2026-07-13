---
name: omnistrate-operator
description: Use when onboarding a Kubernetes operator-based service (CRDs + controller, e.g. CloudNativePG, Strimzi, KubeAI, ECK) onto the Omnistrate platform; when writing or reviewing an Omnistrate ServicePlanSpec with systemWorkflows; or when an operator/Helm+CR deployment must become a managed SaaS offering with create/modify/stop/backup/restore lifecycle. For Docker-Compose services use omnistrate-fde; for debugging failed instances use omnistrate-sre.
---

# Onboarding Kubernetes Operators to Omnistrate

## Overview

An operator integration is a **ServicePlanSpec** (NOT a Docker-Compose spec — no
`x-omnistrate-*` tags). Omnistrate owns the substrate: node pools, per-instance
namespace, storage, load balancers, TLS, DNS. The operator owns the application.
The spec's job is to map Omnistrate lifecycle verbs (create, modify, stop,
delete, backup, restore, ...) onto Kubernetes custom-resource manipulations,
expressed as Argo-workflow DAGs under `systemWorkflows`.

**Core principle: never write spec YAML from memory.** Untrained-knowledge
Omnistrate specs are reliably wrong in structure, field names, and variable
syntax while looking plausible. Every block you write must be copied from a
known-good example (see Canonical Examples) or verified against docs/schema
(`https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json`,
`mcp__ctl__docs_*` search tools when available).

## When to Use

- "Integrate operator X with Omnistrate" / "offer X as managed SaaS" where X is
  operator-managed (CNPG, Strimzi, ECK, KubeAI, RabbitMQ operator, ...)
- Writing/extending a ServicePlanSpec: `systemWorkflows`, `customWorkflows`,
  `operatorCRDConfiguration`, `helmChartConfiguration`
- Adding lifecycle verbs (stop/start, backup/restore, failover) to an existing
  operator-backed plan

**Not this skill:** compose-based onboarding → `omnistrate-fde`; architecture
design from scratch → `omnistrate-sa`; deployed-instance failure debugging →
`omnistrate-sre`.

## Decision Guide (answer these before writing YAML)

**1. How do the operator and its CRDs install?**

CRDs are cluster-scoped Kubernetes objects. Regardless of how the operator
itself is scoped, CRDs install once per deployment cell via a custom amenity —
never owned by a per-instance chart (the second instance would conflict).

| Operator scoping | Pattern |
|---|---|
| Cluster-scoped (one controller serves all namespaces, e.g. CNPG) | Deployment-cell amenity: the full operator chart as a `customAmenities` entry (`type: Helm`) applied via `omnistrate-ctl deployment-cell` config — operator and CRDs install once per cell |
| Namespace-scoped (controller watches only its own namespace, e.g. KubeAI) | **Hybrid:** CRDs via a deployment-cell amenity (`type: KubernetesManifest`, or a crds-only Helm amenity); the operator itself as a sibling service with `helmChartConfiguration` (chart `crds.enabled=false`) that the CR service `dependsOn` — chart installs per instance |

**Deprecated:** installing operator charts via
`operatorCRDConfiguration.helmChartDependencies`. Do not add chart entries
there in new specs — keep `helmChartDependencies: []` purely as the marker
that declares the service an operator-CRD resource. Older specs (including
Omnistrate's public operator spec template) still carry chart entries; copy
their workflow anatomy, not their install method.

**2. Can readiness be gated on the CR's status?**

- CR has reliable status fields (phase/conditions/readyReplicas) →
  `successCondition`/`failureCondition` on the apply task, and workflow-level
  `outputParameters` reading `$tasks.<task>.resource.status.*`.
- Nothing waitable (e.g. scale-to-zero autoscaling: 0 replicas at create) → NO
  `successCondition`, and therefore **NO `outputParameters` at all** —
  referencing `$tasks.X.resource.*` without a successCondition fails the
  workflow render. Surface state via live CR reads instead.

**3. How does traffic reach it?**

- TCP protocol (databases) → `loadBalancers.tcp` + a tiny internal proxy
  service (socat) that bridges LB ports to the operator's Services
- HTTP → `loadBalancers.https` with `targetKubernetesServiceName` **pinned to
  the chart/operator-created Service name** — omit it and Omnistrate
  synthesizes a backend from the resource key, which never exists
- Stable client endpoints (writer/reader) → `endpointConfiguration`

## Workflow

**Phase 0 — Gather facts.** CRD group/version/kind; the status fields the
operator actually writes (get a live CR or read its API reference); Helm chart
coordinates; operator scoping (question 1 above); the operator-native
quiesce mechanism for stop/start (e.g. CNPG `cnpg.io/hibernation` annotation);
verify cloud accounts (`mcp__ctl__account_list` / `omnistrate-ctl account list`).

**Phase 1 — Minimal spec.** Header (`name`, `tenancyType: CUSTOM_TENANCY`,
`deployment.hostedDeployment` with real account values — field casing matters:
`AWSBootstrapRoleAccountArn`), one CR service, operator install per decision 1,
`systemWorkflows` with **create and delete only**. Declare only the API
parameters the CR manifest genuinely needs — unlike compose onboarding, the CR
is parameter-driven from day one, but keep the set minimal and hardcode
everything else. Single cloud provider.

**Phase 2 — Build, deploy, debug until RUNNING.**
```bash
omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec \
  --product-name "<name>" --environment Dev --environment-type Dev \
  --release-as-preferred
omnistrate-ctl instance create --service "<name>" --plan "<plan>" \
  --environment Dev --cloud-provider aws --region <region> \
  --resource <crResourceKey> --param '<json>' --output json
omnistrate-ctl instance describe <instance-id> --output json
```
Iterate build → deploy → fix; expect 2-3 cycles. For failures, follow
`omnistrate-sre` (workflow events, then live CR/pod state).

**Phase 3 — Add lifecycle verbs one at a time**, re-building and re-deploying
after each: `modify` (re-apply CR with new `$var` values), `stop`/`start`
(operator-native quiesce via `action: patch`), `addCapacity`/`removeCapacity`,
`backup`/`restore`/`deleteBackup` (+ `capabilities.backupConfiguration`),
`failover`, then provider-defined `customWorkflows`. Syntax for each verb and
its context variables: see the reference.

**Phase 4 — Networking and endpoints** per decision 3.

**Phase 5 — Production.** Split dev/prod twin specs that differ ONLY in
`deployment` accounts and the metering bucket (state this in a header comment
and keep them in sync); add `metering`, `billingProviders`, per-cloud
`instanceTypes` via `apiParam`, node-affinity pinning to Omnistrate-managed
nodes, BYOA variants if offered.

## Critical Rules

1. **`systemWorkflows` is the lifecycle mechanism.** `template`,
   `supplementalFiles`, `readinessConditions`, `outputParameters` directly
   under `operatorCRDConfiguration` are DEPRECATED — do not use them, do not
   invent JSONPath readiness polling. Readiness lives in `successCondition`;
   outputs live in workflow-level `outputParameters`.
2. **Stop/start/delete do nothing you didn't author.** There is no platform
   magic that scales down an operator's CR — write the workflow (delete = CR +
   secrets teardown; stop = the operator's own hibernation/pause mechanism).
3. **One Kubernetes resource per workflow template.** Argo
   `resource: action: apply` applies only the FIRST document of a multi-doc
   manifest (confirmed live — the rest silently vanish). N resources = N
   templates = N dag tasks.
4. **No successCondition ⇒ no outputParameters.** The task captures no live
   resource object, so any `$tasks.X.resource.*` reference fails the render.
5. **Declare every parameter on the resource that `instance create` targets.**
   A param declared only on a dependency service is silently dropped at create.
   Same key on two services = one shared instance value.
6. **The param that names the CR (`metadata.name`) must be
   `modifiable: false`** — otherwise modify re-applies under a new name and
   orphans the old CR. Prefer `{{ $sys.instanceId }}` as the CR name.
7. **`defaultValue` is always a quoted string**, even for Float64.
8. **Only documented variables exist**: `$sys.*`, `$var.*`, `$func.*` — the
   real vocabulary is tabled in the reference (`$sys.instanceId`,
   `$sys.namespace`, `$sys.deploymentCell.region`, ...). `$sys.id` does not
   exist. Concatenation requires `{{ }}`.
9. **Thread every template input explicitly.** Workflow `arguments.parameters`
   → entrypoint template `inputs` → dag task `arguments` → leaf template
   `inputs`. Verbose, but any skipped hop renders empty.
10. **Optional nested YAML in a CR** (args lists, env maps, nodeSelector):
    inject as a pre-composed, pre-indented block parameter that collapses when
    empty — Argo templating has no conditionals.
11. **Operator-created pods do NOT inherit Omnistrate placement.** Omnistrate
    schedules only the containers it creates itself. Every pod template the
    operator stamps out from your CR must carry node affinity pinning it to
    the instance's Omnistrate-managed node group (`omnistrate.com/managed-by`,
    region, instance type, `omnistrate.com/resource` — exact block in
    reference §8), or pods land on system/shared nodes or fail to schedule.
    GPU node groups additionally need the extended-resource request and the
    `nvidia.com/gpu` taint toleration. Cells mix arm64 and amd64 nodes:
    single-arch operator images without placement fail with `no match for
    platform in manifest` — verify the operator's CRD actually forwards a
    placement field BEFORE onboarding (some operators have none; that's a
    vendor gap, see reference §8).

## Red Flags — STOP, you are hallucinating

| Thought | Reality |
|---|---|
| "I know the Omnistrate spec schema from training" | You know a plausible-looking wrong one. Copy from a canonical example. |
| "readinessConditions will gate RUNNING" | Deprecated. Use `successCondition` on the apply task. |
| "Stop will just scale the workload down" | Only if you author a stop workflow using the operator's quiesce mechanism. |
| "I'll put all the manifests in one apply task" | Only the first doc applies. Split them. |
| "Outputs are templated strings on the resource" | Outputs are workflow `outputParameters` from `$tasks.*.resource.status.*`, gated on successCondition. |
| "The operator's pods will schedule fine by default" | Omnistrate places only containers it creates. Pin operator-created pods to the managed node group via CR affinity (reference §8). |
| "I'll install the operator via helmChartDependencies" | Deprecated. Cluster-scoped → cell amenity; namespace-scoped → hybrid (amenity CRDs + sibling service). |
| "This ctl flag probably exists" | Verify with `--help` or docs search before using it. |

## Canonical Examples & Reference

Full syntax — spec skeleton, operator/CRD install patterns, every lifecycle
verb with context variables, apiParameters, system-variable table, networking,
node placement/affinity, troubleshooting: **OPERATOR_ONBOARDING_REFERENCE.md**
(this directory). The reference embeds complete, copyable blocks distilled
from working production specs (CNPG/postgres, KubeAI/vLLM) — start from those.

Public sources to verify against:
- Omnistrate operator spec template —
  https://github.com/omnistrate-community/operator-spec-template — a full
  CNPG lifecycle example (create/modify/start/stop/addCapacity/removeCapacity/
  delete/backup/restore/deleteBackup/failover + customWorkflows). NOTE: it
  still installs CNPG via the deprecated `helmChartDependencies`; copy its
  workflow anatomy, not its install method.
- Service-spec JSON schema (URL above) and the Omnistrate docs
  (https://docs.omnistrate.com/), or `mcp__ctl__docs_*` search when the ctl
  MCP server is connected.

## Success Criteria

- Build succeeds; instance reaches RUNNING with the CR reconciled by the
  operator (verify via live CR status, not just instance status)
- Every declared lifecycle verb exercised at least once against a live
  instance (modify, stop→start, delete leaves nothing orphaned in the
  namespace)
- Dev and prod specs differ only in accounts + metering bucket
