# Omnistrate Skills Overhaul: Multi-Method Onboarding + Deployment Models

**Date:** 2026-07-22
**Status:** Approved
**Scope:** `skills/omnistrate-fde`, `skills/omnistrate-sre`, `skills/omnistrate-sa`, `skills/omnistrate-operator` (light touch), repo-level docs

## 1. Problem

The current skills only guide Docker-Compose onboarding into a hosted deployment.
`omnistrate-fde/SKILL.md` explicitly tells users that Helm, Terraform, Kustomize,
and Operators are "not supported" and links them away to public docs. Nothing
guides an ISV through BYOC, BYOC on a customer-managed Kubernetes cluster, or
air-gapped/on-prem delivery. `omnistrate-sre` debugs generic workflow events but
knows nothing about terraform logs, helm release state, `omctl instance debug`,
dataplane-agent connectivity, or air-gapped support boundaries.

Target user: **a customer/ISV who has no idea how Omnistrate works.** The skills
must be their guiding workflow — they describe their product and their customers'
constraints in their own words; the skills translate into Omnistrate concepts,
spec formats, and CLI flows.

## 2. Approved decisions

| Decision | Choice |
|---|---|
| Architecture | Router + references: `omnistrate-fde` becomes the universal onboarding entry point with per-topic reference files; `omnistrate-operator` stays as the operator deep-dive |
| Kustomize | Included as a supported path (shares ServicePlanSpec + git artifact flow with terraform) |
| `omnistrate-sa` | Full update: deployment-model discovery in the interview, non-compose architecture outputs, correct handoffs |
| Validation | Doc-verified authoring: every YAML fragment, field name, and CLI command must be traceable to `~/ows-ws/documentation`, `~/ows-ws/resource-spec-samples`, or `~/ows-ws/operator-spec-template`. No live deployments required. |

## 3. File inventory

```
skills/
├── omnistrate-fde/
│   ├── SKILL.md                            REWRITE  — universal intake → decision matrix → phased workflow
│   ├── COMPOSE_ONBOARDING_REFERENCE.md     UPDATE   — stays compose-only; align deployment-model section
│   ├── HELM_ONBOARDING_REFERENCE.md        NEW      — ServicePlanSpec + helmChartConfiguration
│   ├── TERRAFORM_KUSTOMIZE_REFERENCE.md    NEW      — terraformConfigurations + kustomizeConfiguration
│   └── DEPLOYMENT_MODELS_REFERENCE.md      NEW      — hosted / BYOC / BYOC-K8s / air-gapped setup + ops
├── omnistrate-operator/
│   ├── SKILL.md                            LIGHT    — cross-links to router + deployment models reference
│   └── OPERATOR_ONBOARDING_REFERENCE.md    UNCHANGED (unless a cross-link is needed)
├── omnistrate-sre/
│   ├── SKILL.md                            REWRITE  — progressive workflow + per-resource-type and per-model branches
│   └── OMNISTRATE_SRE_REFERENCE.md         UPDATE   — new tool docs (instance debug), failure catalogs
└── omnistrate-sa/
    ├── SKILL.md                            UPDATE   — deployment-model discovery, multi-format outputs, handoffs
    └── SOLUTIONS_ARCHITECT_REFERENCE.md    UPDATE   — deployment-model requirement patterns

README.md                                   UPDATE   — skill map + decision tree
AGENTS.md / CLAUDE.md                       UPDATE   — routing guidance for agents
```

## 4. `omnistrate-fde/SKILL.md` (router)

### 4.1 Frontmatter description
Must trigger on: onboarding to Omnistrate, SaaS-ify an app, BYOC / bring your own
cloud, air-gapped, on-prem, customer-managed Kubernetes/BYOK, helm chart
onboarding, terraform onboarding, kustomize, "offer X as a managed service".
Must direct operators (CRDs + controller) to `omnistrate-operator` and failed
instances to `omnistrate-sre`.

### 4.2 Phase 0 — Intake interview (plain language, no Omnistrate jargon)
Ask, one at a time, adapting to what the user already volunteered:

1. **What does your product look like today?**
   compose file / helm chart / terraform module / kustomize overlays /
   k8s operator (CRDs + controller) / plain container images / nothing yet.
   "Nothing yet" → hand off to `omnistrate-sa`.
2. **Where should instances run?** (multi-select; one plan can offer several)
   - *Your cloud account* → hosted deployment
   - *Your customers' cloud accounts* → BYOC (`byoaDeployment`); probe for
     VPC constraints and no-public-egress requirements (→ BYO-VPC / PrivateLink)
   - *Your customers' existing Kubernetes clusters, you don't provision infra*
     → BYOC-K8s (`--cloud-provider byoc-onprem`, dataplane agent)
   - *Fully disconnected / no connectivity to you* → air-gapped installer
     (`onPremDeployment`)
3. **Which clouds and regions?**
4. **Lifecycle needs:** backups, stop/start, scaling, upgrades — noted for later
   phases, not implemented up front.
5. **Private registries / private git repos?** — determines auth setup steps.

### 4.3 Decision matrix

| Artifact | Spec format | Build command | Guide |
|---|---|---|---|
| Docker Compose | compose + `x-omnistrate-*` | `build_compose` / `omnistrate-ctl build -f <file>` | COMPOSE_ONBOARDING_REFERENCE.md |
| Helm chart | ServicePlanSpec (`helmChartConfiguration`) | `omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec` | HELM_ONBOARDING_REFERENCE.md |
| Terraform / Kustomize | ServicePlanSpec (`terraformConfigurations` / `kustomizeConfiguration`) | same | TERRAFORM_KUSTOMIZE_REFERENCE.md |
| Operator (CRDs) | ServicePlanSpec (`systemWorkflows`) | same | → invoke `omnistrate-operator` skill |
| Mixed (e.g. terraform infra + helm app) | ServicePlanSpec, multiple services with `dependsOn` | same | HELM + TERRAFORM_KUSTOMIZE references |
| Any artifact, air-gapped target | ServicePlanSpec with `onPremDeployment` | same | DEPLOYMENT_MODELS_REFERENCE.md §Air-gapped |

Deployment model (from intake Q2) is orthogonal: every path reads
DEPLOYMENT_MODELS_REFERENCE.md for the `deployment:` block and account setup.

### 4.4 Universal phased workflow (method-agnostic)
1. **Verify accounts / prerequisites** — provider cloud account READY
   (`account list`/`describe`); for BYOC/BYOC-K8s explain that *customer*
   accounts are onboarded later, at deploy time.
2. **Minimal spec, zero parameterization** — hardcode everything; single cloud;
   create/delete lifecycle only. (Exception, carried from operator skill: CR
   specs are parameter-driven from day one but keep the set minimal.)
3. **Build** — must succeed before anything else is added.
4. **Deploy one instance and debug until RUNNING** — expect 2–3 iterations;
   delegate failure analysis to `omnistrate-sre`.
5. **Add parameters/lifecycle one at a time** — rebuild + redeploy after each.
6. **Production hardening** — prod plan (accounts differ, spec otherwise
   identical), metering/billing, additional clouds, additional deployment models.

### 4.5 Critical rules (carried over + generalized)
- Never write Omnistrate spec YAML from memory; copy from the reference files'
  verified fragments or search docs (`mcp__ctl__docs_*`, JSON schema URL).
- Zero-parameterization first (compose/helm/terraform); one change per
  build-deploy cycle.
- `defaultValue` always a quoted string.
- Never modify the user's original artifact; create Omnistrate variants.
- Deployment model defaults to `hostedDeployment` **only after asking Q2** —
  the old skill's "ALWAYS use hostedDeployment" rule is replaced by the intake.

## 5. `DEPLOYMENT_MODELS_REFERENCE.md` (new)

### 5.1 Chooser table
Model × who-manages-infra × connectivity/agent × licensing × typical buyer, with
one-sentence plain-language definitions. Models: Hosted, BYOC-Account, BYO-VPC,
BYOC PrivateLink, BYOC-K8s, Air-gapped, (contrast: Adopted cells = provider's own
fleet, not a customer model).

### 5.2 Hosted
- Bootstrap flows per cloud (AWS CloudFormation/Terraform role, GCP, Azure) —
  from `getting-started/onboarding/*.md`.
- `hostedDeployment` YAML in BOTH syntaxes with the casing warning:
  - compose (`x-omnistrate-service-plan.deployment.hostedDeployment`):
    `awsAccountId`, `awsBootstrapRoleAccountArn`, `gcpProjectId`, ...
  - ServicePlanSpec: samples use `AwsAccountId`, `AWSBootstrapRoleAccountArn`,
    `GcpProjectId`, ... — copy from `resource-spec-samples` / operator template.
- Tenancy interaction (`OMNISTRATE_MULTI_TENANCY`, `OMNISTRATE_DEDICATED_TENANCY`,
  `CUSTOM_TENANCY` for helm/terraform/kustomize/operators).

### 5.3 BYOC (customer cloud account)
- `byoaDeployment` YAML (both syntaxes); note it can coexist with
  `hostedDeployment` in one plan (multi-model).
- Customer account onboarding: portal self-serve; assisted
  `omnistrate-ctl account customer create` for AWS/GCP/Azure with exact flags.
- Deploying: `instance create ... --customer-account-id <id>`.
- BYO-VPC: `cloud_provider_native_network_id` input param + VPC requirements
  table (DNS attrs, NAT, subnet tags `kubernetes.io/role/elb|internal-elb`).
- PrivateLink: `--private-link` flag, VPC endpoint requirements (tags, ports
  8443–8506, `--service-region`).
- Account tags → `$sys.deploymentCell.accountTags` for conditional amenities.
- Licensing protection: config in compose (`x-customer-integrations.licensing`)
  and ServicePlanSpec (`features.CUSTOMER.licensing`), license mount at
  `/var/subscription/`, SDKs, INSTANCE_ID validation.

### 5.4 BYOC-K8s (customer-managed cluster, no infra management)
- What it is: customer brings the cluster; Omnistrate deploys/operates via a
  dataplane agent over outbound mTLS/gRPC; k8s API never exposed.
- Target-cluster prerequisites table (kubectl context, CNI, DNS/egress to control
  plane + registries, StorageClasses, ingress/endpoint path).
- Flow: `account customer create --cluster-name ... --cluster-description ...`
  → downloads install kit → `tar xf ... && ./install.sh --non-interactive`
  → poll `account customer describe` until READY
  → `instance create --cloud-provider byoc-onprem --region on-prem
     --customer-account-id ...`.
- Local testing: `./install.sh --create-k3d-cluster` / `--create-k3s-cluster`.
- Re-download kit: `account customer install-kit <id>`.
- Limitations: requires outbound connectivity (NOT air-gapped); one onboarding
  instance per cluster; endpoint reachability is customer-owned.
- Spec implication: endpoints typically `networkingType: INTERNAL` /
  `$sys.network.internalClusterEndpoint`; no cloud-infra amenities.

### 5.5 Air-gapped / on-prem installer
- Concept: self-contained installer artifact (chart + images + config + lifecycle
  scripts); the disconnected end of the spectrum — no live control-plane link;
  customer owns update/support boundaries.
- Spec: `deployment.requirements.k8sVersion`, `onPremDeployment` (artifact-hosting
  AWS account + bootstrap role ARN), `onPremInstallerTools.helperUserScript`
  (incl. `{{ $file:... }}`), `actionHooks` (scope CLUSTER; VALIDATE, PRE_INSTALL,
  POST_INSTALL, BACKUP) with when-they-run table.
- Images: `INSTALLER_EMBED` pull mode for fully-offline; registry-copy mechanism
  for private-registry targets.
- Licensing in disconnected mode; diagnostics (bundles, temporary access).
- Full minimal example (Supabase pattern from `air-gapped-helm-charts.md`).

### 5.6 Cross-cutting
- Adopted deployment cells (`omctl deployment-cell adopt`, install kit,
  `PENDING_ADOPTION`→`READY`, `$sys.deploymentCell.isImported`) — clearly framed
  as "provider's own fleet", contrasted with BYOC-K8s.
- Deployment cell amenities (once-per-cell components; conditional via account
  tags / isImported).
- Custom networks (`features.CUSTOM_NETWORKS`) — hosted-only feature.
- Model-selection FAQ mapping common ISV phrasings to models ("our customers
  want it in their AWS" → BYOC; "they run OpenShift on-prem but allow egress" →
  BYOC-K8s; "defense customer, no internet" → air-gapped).

## 6. `HELM_ONBOARDING_REFERENCE.md` (new)

- ServicePlanSpec skeleton for a helm service (from `service-spec-helm.yaml`):
  name/deployment/services[].helmChartConfiguration + compute/network/
  apiParameters/endpointConfiguration.
- `helmChartConfiguration` fields: chartName/chartVersion/chartRepoName/
  chartRepoURL, `chartValues`, `authProvider` (private repos),
  `artifactRelativePath` (local charts).
- `runtimeConfiguration` table: wait, waitForJobs, timeoutNanos, disableHooks,
  skipCRDs, upgradeCRDs, recreate, resetValues, reuseValues,
  resetThenReuseValues, disableReconciliation (debug only).
- Values templating: `$var.*`, `$sys.*` (bare in values per samples;
  `{{ }}` for concatenation), `$secret.*`, terraform outputs
  `{{ $tfService.out.key }}`; quoting rules.
- Placement: node affinity on `topology.kubernetes.io/region` /
  `omnistrate.com/*` labels in chartValues (chart pods are NOT auto-placed);
  `chartAffinityControl` (enableInjection / enableSharedHost).
- Multi-service: `dependsOn` + `parameterDependencyMap` (Redis+Postgres sample).
- Networking: LoadBalancer service annotations
  (`external-dns.alpha.kubernetes.io/hostname: $sys.network.externalClusterEndpoint`),
  `endpointConfiguration`, plan-level `loadBalancers` with
  `targetKubernetesServiceName` pinned to chart-created Services.
- Lifecycle semantics: install/upgrade/uninstall mapping, first-install failure
  cleanup, reconciliation.
- Build/deploy/debug commands; troubleshooting pointers → sre skill.

## 7. `TERRAFORM_KUSTOMIZE_REFERENCE.md` (new)

### Terraform
- `terraformConfigurations.configurationPerCloudProvider.<cloud>` fields:
  `terraformPath`, `gitConfiguration` (repositoryUrl, reference,
  accessToken incl. `{{env:VAR}}`), `artifactRelativePath` (local),
  `terraformExecutionIdentity`, Nebius auth trio, `variablesValuesFileOverride`,
  `cliConfigFileOverride`, `requiredOutputs` (+`exported`).
- Rules: Omnistrate owns state (no `backend` blocks — stripped); auto-created
  execution identities per cloud need permissions granted; `internal: true` for
  infra services; `deploymentTarget.account: ControlPlane` for provider-side
  resources; pin git refs to tags/SHAs for prod.
- Templating inside `.tf`: `{{ $sys.deploymentCell.* }}`, `{{ $sys.id }}`,
  `{{ $var.* }}`; private modules via
  `git::https://{{ $sys.deployment.terraformPrivateModuleGitAccessTokens.token }}@github.com/...`.
- Outputs → consumers: `{{ $svc.out.key }}`, nested `.field`, array `[0]`;
  outputs as endpoints.

### Kustomize
- `kustomizeConfiguration`: `kustomizePath`, `gitConfiguration`; service
  `type: kustomize` where samples use it.
- kustomization.yaml templating: `namespace: "{{ $sys.id }}"`,
  configMapGenerator literals with `$var.*` and terraform outputs,
  secretGenerator, remote bases with pinned refs.
- Workload manifests: node affinity on `omnistrate.com/resource` =
  `{{ $sys.deployment.resourceID }}`; PVC naming `{{ $sys.id }}-pvc`.

### Combined patterns
- terraform (internal) → kustomize/helm consumer via `dependsOn`; multi-cloud
  parity (same output names per cloud); e2etestv2 as the canonical worked example.

## 8. `omnistrate-sre` overhaul

Keep the progressive core (describe → workflow list → events summary → events
detail → tunnel/kubectl). Add:

1. **New step: `omctl instance debug <instance-id>`** — rendered artifacts per
   resource type (helm values, terraform plan/apply logs + rendered `.tf`,
   kustomize YAML, operator CRs) — positioned after workflow events, before
   tunneling.
2. **Per-resource-type branches:**
   - Helm: release status via cluster-admin kubeconfig, stuck deletes (leftover
     CRDs/finalizers), first-install auto-cleanup semantics, wait/timeout tuning.
   - Terraform: cloud-provider errors in apply logs (IAM, quota, naming, SKU),
     restart-workflow vs publish-new-version decision rule, output validation.
   - Operator: workflow task failures, successCondition mismatches vs actual CR
     status fields, operator controller logs, CR events.
   - Kustomize: substitution/rendering failures, missing StorageClass/PVC.
3. **Per-deployment-model branches:**
   - BYOC: customer account not READY (bootstrap/trust failures), agent
     connectivity, VPC requirement violations (subnet tags, NAT), PrivateLink
     endpoint misconfig.
   - BYOC-K8s: dataplane agent pod health in `dataplane-agent` namespace,
     outbound egress blocked, missing StorageClasses, endpoint exposure is
     customer-owned.
   - Air-gapped: what you cannot see remotely; action-hook logs, diagnostic
     bundles, temporary access grants.
4. Keep the hard rule: never use cloud CLIs to reach clusters — only
   `deployment-cell update-kubeconfig` tunneling.
5. Reference file gains: instance-debug output anatomy, expanded failure
   pattern catalog organized by resource type and model.

## 9. `omnistrate-sa` full update

- Interview adds deployment-model discovery early (customer segments,
  data-sovereignty/compliance, connectivity constraints, air-gapped demands) —
  these shape architecture before technology selection.
- Output format decision: compose remains default for plain-container designs;
  recommend helm/terraform/operator ServicePlanSpec when the stack already ships
  that way or needs cloud managed services; document the handoff artifact for
  each (compose spec vs ServicePlanSpec skeleton + notes).
- Handoff section routes: compose → fde compose path; helm/terraform/kustomize →
  fde + respective reference; operators → omnistrate-operator; and always names
  the chosen deployment model(s) in the handoff.
- Reference file: add a deployment-model requirements section (per-model
  implications for networking, licensing, backup, upgrade agility).

## 10. Light-touch updates

- `omnistrate-operator/SKILL.md`: point Phase 1 deployment block at
  DEPLOYMENT_MODELS_REFERENCE.md (BYOA/BYOC variants for operator plans);
  mention the fde router as the entry point for non-operator artifacts.
- `README.md`: new skill map with the decision tree (artifact × model → skill).
- `AGENTS.md` / `CLAUDE.md`: same routing in agent-facing terms.
- `omnistrate-fde/COMPOSE_ONBOARDING_REFERENCE.md`: replace its deployment-model
  section with a pointer to DEPLOYMENT_MODELS_REFERENCE.md; content otherwise
  intact.

## 11. Validation plan (doc-verified authoring)

1. While authoring: every YAML fragment / CLI command copied from a named source
   file (documentation page, sample spec, template, or existing skill) — carry
   the source path in an authoring worksheet (not shipped in the skills).
2. Final review pass: re-open each shipped fragment and confirm it against its
   source; delete anything untraceable. Specifically re-verify:
   - deployment block field casing per syntax context,
   - every `omnistrate-ctl` flag against docs (no invented flags),
   - `$sys.*` paths against the system-parameters doc,
   - runtimeConfiguration field names/defaults against plan-spec.md.
3. Skill-quality pass per `superpowers:writing-skills`: description triggers,
   progressive disclosure (SKILL.md lean, syntax in references), no duplicated
   content between SKILL.md and references, red-flags tables preserved.

## 12. Out of scope

- `omnistrate-mcp-readonly` (unchanged).
- Live deployment testing of authored specs.
- New skills beyond the existing five.
- Rewriting `OPERATOR_ONBOARDING_REFERENCE.md`.

## 13. Success criteria

- An Omnistrate-naive ISV with a helm chart + "customers want it in their own
  AWS account, some air-gapped" can be routed, without external docs, to: a
  `byoaDeployment` ServicePlanSpec plan AND an `onPremDeployment` installer
  plan, with account onboarding and debug flows for both.
- Same for: compose × hosted, terraform+kustomize × hosted, operator × BYOC,
  anything × BYOC-K8s.
- `omnistrate-fde` no longer claims helm/terraform/kustomize/operators are
  unsupported.
- `omnistrate-sre` can drive debugging for all four resource types and knows the
  BYOC/BYOC-K8s/air-gapped failure surfaces.
- Every fragment in the shipped skills is doc-traceable.
