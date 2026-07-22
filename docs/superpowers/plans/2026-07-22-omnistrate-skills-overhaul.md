# Omnistrate Skills Overhaul Implementation Plan

> **For agentic workers:** Execute this plan task-by-task, with an independent review after each task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Overhaul the Omnistrate onboarding and debugging skills so an Omnistrate-naive ISV is guided from any artifact type (compose, helm, terraform, kustomize, operator) to any deployment model (hosted, BYOC, BYOC-K8s, air-gapped) with doc-verified instructions.

**Architecture:** `omnistrate-fde/SKILL.md` becomes a lean router (intake interview → decision matrix → phased workflow) backed by four reference files carrying all syntax. `omnistrate-sre` gains per-resource-type and per-deployment-model debug branches. `omnistrate-sa` gains deployment-model discovery and multi-format handoffs. `omnistrate-operator` gets cross-links only.

**Tech Stack:** Markdown skill files (Claude Code skill format: YAML frontmatter `name` + `description`, body ≤500 lines preferred, references loaded on demand). Sources of truth for all content: `/Users/aloknikhil/ows-ws/documentation/docs/`, `/Users/aloknikhil/ows-ws/resource-spec-samples/`, `/Users/aloknikhil/ows-ws/operator-spec-template/`.

**Approved spec:** `docs/superpowers/specs/2026-07-22-omnistrate-skills-overhaul-design.md` (read it before starting any task).

## Global Constraints

- Repo: `/Users/aloknikhil/ows-ws/agent-instructions`, branch `skills-overhaul-multi-usecase`. All paths below relative to repo root unless absolute.
- **Never write Omnistrate YAML/CLI content from memory.** Every YAML fragment, field name, CLI flag, and `$sys.*` path in a shipped skill must be copied from a file under `/Users/aloknikhil/ows-ws/documentation/docs/`, `/Users/aloknikhil/ows-ws/resource-spec-samples/`, `/Users/aloknikhil/ows-ws/operator-spec-template/`, or an existing skill file. When a plan fragment below conflicts with the source file, the source file wins.
- Git commits: author as the user only. **NEVER add any Claude/AI attribution or Co-Authored-By trailer** (user's global CLAUDE.md).
- Field-casing rule: compose `x-omnistrate-service-plan.deployment` uses lowerCamel (`awsAccountId`); ServicePlanSpec samples use UpperCamel (`AwsAccountId`, and the operator template uses `AWSBootstrapRoleAccountArn`). Always show which context a fragment belongs to; verify casing by grep before shipping.
- Skill frontmatter: `name` must equal the directory name (`omnistrate-fde`, `omnistrate-sre`, `omnistrate-sa`); `description` must state when-to-use triggers AND when-not-to-use routing.
- Do not modify: `skills/omnistrate-mcp-readonly/`, `skills/omnistrate-operator/OPERATOR_ONBOARDING_REFERENCE.md`, `LICENSE`.
- SKILL.md files stay lean (router/workflow/rules); syntax blocks live in reference files. No content duplicated between SKILL.md and its references.

---

### Task 1: Create `DEPLOYMENT_MODELS_REFERENCE.md`

**Files:**
- Create: `skills/omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md`

**Interfaces:**
- Produces: reference file linked from Task 4 SKILL.md as `DEPLOYMENT_MODELS_REFERENCE.md`, from Task 5/6/7/8 by the same relative name. Section anchors other tasks link to: `#choosing-a-deployment-model`, `#hosted`, `#byoc-customer-cloud-account`, `#byoc-k8s-customer-managed-kubernetes`, `#air-gapped--on-prem-installer`, `#cross-cutting-concerns`.

- [ ] **Step 1: Read the primary sources**

Read in full:
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/deployment-models.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/byoc-overview.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/byoc-deployment.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/usecases/byoc-onprem.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/air-gapped-overview.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/air-gapped-helm-charts.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/runtime-guides/licensing-protection.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/operate-guides/adopt-deployment-cells.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/operate-guides/byoc-cloud-accounts.md`
- Skim: `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/tenancy-types.md`, `/Users/aloknikhil/ows-ws/documentation/docs/runtime-guides/customer-networks.md`, `/Users/aloknikhil/ows-ws/documentation/docs/operate-guides/deployment-cell-amenities.md`, `/Users/aloknikhil/ows-ws/documentation/docs/getting-started/onboarding/aws.md`

- [ ] **Step 2: Write the file with this exact section structure**

```markdown
# Omnistrate Deployment Models Reference

(scope line: read this for the `deployment:` block, account setup, and
per-model operational flows; onboarding methods live in the sibling
references)

## Choosing a Deployment Model
(plain-language chooser table: Model | One-line definition | Who manages
infra | Connectivity | Typical buyer — rows: Hosted, BYOC-Account,
BYO-VPC, BYOC PrivateLink, BYOC-K8s, Air-gapped)
(ISV-phrasing FAQ table mapping quotes like "customers want it in their
own AWS" → BYOC; "they run OpenShift on-prem but allow egress" → BYOC-K8s;
"defense customer, no internet" → air-gapped; "just host it for me" → Hosted)
(note: models are not mutually exclusive — one plan may declare both
hostedDeployment and byoaDeployment)

## Hosted
### Provider account prerequisites (per cloud: AWS bootstrap role via
CloudFormation/Terraform, GCP, Azure; `omnistrate-ctl account create`,
`account describe`, READY state)
### Spec syntax — compose context (lowerCamel fields)
### Spec syntax — ServicePlanSpec context (UpperCamel fields + casing warning)
### Tenancy interaction (OMNISTRATE_MULTI_TENANCY / OMNISTRATE_DEDICATED_TENANCY
for compose; CUSTOM_TENANCY for helm/terraform/kustomize/operator)

## BYOC (customer cloud account)
### What the customer experiences (portal self-serve account connect)
### Spec syntax (byoaDeployment, both contexts; multi-model example)
### Onboarding a customer account — assisted CLI (aws/gcp/azure flag sets)
### Deploying into a customer account (--customer-account-id)
### BYO-VPC (cloud_provider_native_network_id + VPC requirements table)
### PrivateLink (--private-link, VPC endpoint requirements, --service-region)
### Account tags → $sys.deploymentCell.accountTags

## BYOC-K8s (customer-managed Kubernetes)
### What it is / what Omnistrate does NOT manage
### Target-cluster prerequisites (table from byoc-onprem.md)
### Onboarding flow (account customer create --cluster-name → install kit
→ install.sh → describe until READY)
### Deploying (--cloud-provider byoc-onprem --region on-prem)
### Local testing (k3d/k3s installer flags)
### Spec implications (INTERNAL endpoints, internalClusterEndpoint)
### Limitations (outbound required — NOT air-gapped; one onboarding
instance per cluster)

## Air-gapped / On-prem Installer
### Concept (installer artifact; disconnected end of spectrum; boundaries)
### Spec syntax (requirements.k8sVersion, onPremDeployment fields)
### Installer tools (onPremInstallerTools.helperUserScript, $file syntax)
### Action hooks (scope CLUSTER; VALIDATE/PRE_INSTALL/POST_INSTALL/BACKUP
+ when-they-run table)
### Container images (INSTALLER_EMBED, registry copy)
### Licensing + diagnostics in disconnected mode
### Minimal end-to-end example

## Cross-cutting Concerns
### Licensing protection (compose x-customer-integrations.licensing;
ServicePlanSpec features.CUSTOMER.licensing; /var/subscription/ mount;
Go/Java SDKs; validation checklist)
### Adopted deployment cells (provider fleet — NOT a customer model;
omctl deployment-cell adopt flow; $sys.deploymentCell.isImported)
### Deployment cell amenities (once-per-cell components; conditional on
account tags / isImported)
### Custom networks (features.CUSTOM_NETWORKS — hosted-only)
```

Populate every section with fragments copied from the Step 1 sources. Load-bearing fragments that MUST appear (copy from the cited source, then re-verify):

Compose-context deployment block (source: `build-guides/compose-spec.md` ~lines 501–519):
```yaml
x-omnistrate-service-plan:
  deployment:
    hostedDeployment:
      awsAccountId: "<AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
      gcpProjectId: "<GCP_PROJECT_ID>"
      gcpProjectNumber: "<GCP_PROJECT_NUMBER>"
      gcpServiceAccountEmail: "<GCP_SA_EMAIL>"
```

ServicePlanSpec-context deployment block (source: `/Users/aloknikhil/ows-ws/operator-spec-template/spec.yaml` header — copy exact casing from that file):
```yaml
deployment:
  hostedDeployment:
    AwsAccountId: "<AWS_ACCOUNT_ID>"
    AWSBootstrapRoleAccountArn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role"
```

BYOC assisted onboarding (source: `build-guides/byoc-deployment.md` ~lines 90–143):
```bash
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --customer-email=<customer@example.com> \
  --aws-account-id=<CUSTOMER_AWS_ACCOUNT_ID>
# GCP: --gcp-project-id / --gcp-project-number / --gcp-service-account-email
# Azure: --azure-subscription-id / --azure-tenant-id
# PrivateLink: append --private-link
```

BYOC-K8s flow (source: `usecases/byoc-onprem.md` ~lines 80–197):
```bash
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --cluster-name=<customer-cluster-name> \
  --cluster-description="..."
tar xf byoc-onprem-install-kit-<account-config-id>.tar
./install.sh --non-interactive
omnistrate-ctl account customer describe <customer-account-instance-id>
omnistrate-ctl instance create ... \
  --cloud-provider=byoc-onprem --region=on-prem \
  --customer-account-id=<customer-account-instance-id> --wait
```

Air-gapped spec header (source: `build-guides/air-gapped-helm-charts.md` ~lines 22–44):
```yaml
name: My Application
deployment:
  requirements:
    k8sVersion: ">=1.30.0"
  onPremDeployment:
    AwsAccountId: '<your-aws-account-id>'
    AwsBootstrapRoleAccountArn: 'arn:aws:iam::<your-aws-account-id>:role/omnistrate-bootstrap-role'
```

- [ ] **Step 3: Verify every fragment against its source**

For each YAML fragment/CLI command in the new file, grep the cited source and confirm exact field names/flags exist:
```bash
grep -rn "byoc-onprem" /Users/aloknikhil/ows-ws/documentation/docs/usecases/byoc-onprem.md | head
grep -n "private-link\|customer-account-id\|cluster-name" /Users/aloknikhil/ows-ws/documentation/docs/build-guides/byoc-deployment.md /Users/aloknikhil/ows-ws/documentation/docs/usecases/byoc-onprem.md
grep -n "onPremDeployment\|INSTALLER_EMBED\|helperUserScript\|PRE_INSTALL" /Users/aloknikhil/ows-ws/documentation/docs/build-guides/air-gapped-*.md
grep -n "AwsAccountId\|AWSBootstrapRoleAccountArn\|awsAccountId" /Users/aloknikhil/ows-ws/operator-spec-template/spec.yaml /Users/aloknikhil/ows-ws/documentation/docs/build-guides/compose-spec.md | head -20
grep -n "deployment-cell adopt\|PENDING_ADOPTION\|isImported" /Users/aloknikhil/ows-ws/documentation/docs/operate-guides/adopt-deployment-cells.md /Users/aloknikhil/ows-ws/documentation/docs/operate-guides/deployment-cell-amenities.md
```
Expected: every grep returns matches; any fragment whose field/flag is not found must be corrected from the source or deleted.

- [ ] **Step 4: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md
git commit -m "Add deployment models reference (hosted/BYOC/BYOC-K8s/air-gapped)"
```

---

### Task 2: Create `HELM_ONBOARDING_REFERENCE.md`

**Files:**
- Create: `skills/omnistrate-fde/HELM_ONBOARDING_REFERENCE.md`

**Interfaces:**
- Consumes: `DEPLOYMENT_MODELS_REFERENCE.md` (Task 1) — link to it for the `deployment:` block instead of repeating it.
- Produces: reference linked from Task 4 SKILL.md as `HELM_ONBOARDING_REFERENCE.md`.

- [ ] **Step 1: Read the primary sources**

- `/Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-helm.yaml` (entire file — the canonical skeleton)
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-overview.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-runtime-configuration.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-customize.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-chart-layered-values.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/getting-started/build-from-helm.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-troubleshooting.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/spec-guides/plan-spec.md` (helmChartConfiguration schema section)

- [ ] **Step 2: Write the file with this section structure**

```markdown
# Helm Chart Onboarding Reference

## When you are on this path
(you have an existing helm chart; spec format is ServicePlanSpec;
tenancyType: CUSTOM_TENANCY; build with --spec-type ServicePlanSpec)

## Minimal working skeleton
(complete spec copied/adapted from service-spec-helm.yaml: name,
deployment → link DEPLOYMENT_MODELS_REFERENCE.md, one service with
helmChartConfiguration, network.ports, hardcoded chartValues)

## helmChartConfiguration fields
(chartName / chartVersion / chartRepoName / chartRepoURL / chartValues /
authProvider for private repos / artifactRelativePath for local charts)

## runtimeConfiguration
(full field table with defaults: wait, waitForJobs, timeoutNanos,
disableHooks, skipCRDs, upgradeCRDs, recreate, resetValues, reuseValues,
resetThenReuseValues, disableReconciliation(debug only))

## Templating chart values
($var.* — must be declared in apiParameters; $sys.* paths used in the
sample: $sys.network.externalClusterEndpoint, $sys.deploymentCell.region;
$secret.*; consuming terraform outputs {{ $tfSvc.out.key }}; quoting and
{{ }} concatenation rules; NOTE which forms appear bare vs wrapped in the
sample file — follow the sample)

## Pod placement (CRITICAL)
(chart-created pods are not auto-placed; nodeAffinity block copied from
service-spec-helm.yaml — topology.kubernetes.io/region with
$sys.deploymentCell.region, omnistrate.com/schedule-mode podLabels;
chartAffinityControl: enableInjection / enableSharedHost)

## Multi-service plans
(dependsOn + parameterDependencyMap, copied from the Redis→Postgres
pattern in service-spec-helm.yaml)

## Exposing endpoints
(LoadBalancer service annotations external-dns hostname →
$sys.network.externalClusterEndpoint; endpointConfiguration;
plan-level loadBalancers.https paths with targetKubernetesServiceName
pinned to the CHART-created Service name)

## Lifecycle semantics
(create=install, modify=upgrade + values-reset/reuse flags,
delete=uninstall; first-install failure cleanup; auto-reconciliation)

## Build, deploy, iterate
(omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec
--product-name ... --environment ... --environment-type ...
--release-as-preferred; instance create with --resource and --param;
debugging → omnistrate-sre skill)

## Common mistakes
(unpinned chart versions; parameters referenced in chartValues but not
declared in apiParameters; missing affinity → pods on shared nodes;
targetKubernetesServiceName omitted → synthesized nonexistent backend)
```

- [ ] **Step 3: Verify fragments**

```bash
grep -n "chartName\|chartVersion\|chartRepoName\|chartRepoURL\|authProvider" /Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-helm.yaml /Users/aloknikhil/ows-ws/documentation/docs/spec-guides/plan-spec.md | head -20
grep -n "waitForJobs\|timeoutNanos\|upgradeCRDs\|resetThenReuseValues\|disableReconciliation" /Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-runtime-configuration.md
grep -n "schedule-mode\|nodeAffinity\|deploymentCell.region" /Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-helm.yaml
grep -n "parameterDependencyMap" /Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-helm.yaml
```
Expected: all matches found. Confirm whether `$sys.*` in chartValues appears bare or `{{ }}`-wrapped in the SAMPLE and make the reference match the sample.

- [ ] **Step 4: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-fde/HELM_ONBOARDING_REFERENCE.md
git commit -m "Add helm chart onboarding reference"
```

---

### Task 3: Create `TERRAFORM_KUSTOMIZE_REFERENCE.md`

**Files:**
- Create: `skills/omnistrate-fde/TERRAFORM_KUSTOMIZE_REFERENCE.md`

**Interfaces:**
- Consumes: `DEPLOYMENT_MODELS_REFERENCE.md` (Task 1) — link for `deployment:` block.
- Produces: reference linked from Task 4 SKILL.md as `TERRAFORM_KUSTOMIZE_REFERENCE.md`.

- [ ] **Step 1: Read the primary sources**

- `/Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-kustomize-terraform.yaml` (canonical skeleton)
- `/Users/aloknikhil/ows-ws/resource-spec-samples/terraform-spec/` (main.tf, variables.tf, output.tf)
- `/Users/aloknikhil/ows-ws/resource-spec-samples/terraform-private-module-spec/main.tf`
- `/Users/aloknikhil/ows-ws/resource-spec-samples/e2etestv2/original/kustomize/kustomization.yaml` and `/Users/aloknikhil/ows-ws/resource-spec-samples/e2etest/kustomize/kustomization.yaml`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/terraform-overview.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/terraform-params-outputs.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/terraform-multi-cloud.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/getting-started/build-from-terraform.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/getting-started/build-from-kustomize.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-terraform.md` (combined pattern)

- [ ] **Step 2: Write the file with this section structure**

```markdown
# Terraform & Kustomize Onboarding Reference

## When you are on this path
(cloud infra via terraform/OpenTofu, k8s manifests via kustomize, or
both; ServicePlanSpec; CUSTOM_TENANCY)

## Terraform
### Minimal skeleton (service with terraformConfigurations.
configurationPerCloudProvider.<aws|gcp|azure|oci|nebius>; internal: true
for infra services)
### Source configuration (terraformPath + gitConfiguration
{repositoryUrl, reference refs/tags/..., accessToken incl. {{env:VAR}}}
OR artifactRelativePath for local)
### Execution identity & IAM (terraformExecutionIdentity per cloud;
auto-created identities need permissions granted; Nebius trio:
serviceAccountID/publicKeyID/privateKeyPEM via $secret)
### State management (Omnistrate-managed; backend blocks stripped —
never author one)
### Templating inside .tf ({{ $sys.deploymentCell.region }},
{{ $sys.deploymentCell.cloudProviderNetworkID }},
{{ $sys.deploymentCell.publicSubnetIDs[0].id }}, {{ $sys.id }},
{{ $var.* }}; variablesValuesFileOverride .tfvars form)
### Private modules (git::https://{{ $sys.deployment.
terraformPrivateModuleGitAccessTokens.token }}@github.com/...)
### Outputs (requiredOutputs + exported; consuming via
{{ $svc.out.key }} / nested .field / [0]; outputs as endpoints)
### Control-plane-side resources (deploymentTarget.account: ControlPlane)
### Multi-cloud parity (same output names per cloud)

## Kustomize
### Minimal skeleton (type: kustomize service; kustomizeConfiguration
{kustomizePath, gitConfiguration}; compute.instanceTypes per cloud;
network.ports)
### Templating kustomization.yaml (namespace "{{ $sys.id }}";
configMapGenerator literals with {{ $var.* }} and terraform outputs;
secretGenerator; remote bases pinned by ref)
### Workload manifests (nodeAffinity omnistrate.com/resource =
{{ $sys.deployment.resourceID }}; PVC naming {{ $sys.id }}-pvc)

## Combining terraform + kustomize/helm
(dependsOn chain; e2etestv2 pattern: terraform infra (internal) →
kustomize consumer reading $terraformChild.out.*)

## Build, deploy, iterate
(same ctl commands as helm reference; debugging → omnistrate-sre;
restart-vs-new-version rule preview)

## Common mistakes
(backend block authored; unpinned git refs in prod; output referenced
before dependsOn declared; missing execution-identity permissions)
```

- [ ] **Step 3: Verify fragments**

```bash
grep -n "configurationPerCloudProvider\|terraformPath\|terraformExecutionIdentity\|gitConfiguration" /Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-kustomize-terraform.yaml
grep -rn "terraformPrivateModuleGitAccessTokens" /Users/aloknikhil/ows-ws/resource-spec-samples/terraform-private-module-spec/
grep -n "kustomizePath\|type: kustomize" /Users/aloknikhil/ows-ws/resource-spec-samples/service-spec-kustomize-terraform.yaml
grep -n '\$sys.id\|\$var.username\|out\.' /Users/aloknikhil/ows-ws/resource-spec-samples/e2etest/kustomize/kustomization.yaml /Users/aloknikhil/ows-ws/resource-spec-samples/e2etestv2/original/kustomize/kustomization.yaml
grep -n "requiredOutputs\|variablesValuesFileOverride\|ControlPlane" /Users/aloknikhil/ows-ws/documentation/docs/build-guides/terraform-*.md /Users/aloknikhil/ows-ws/documentation/docs/spec-guides/plan-spec.md | head -20
```
Expected: all found; correct/delete anything unmatched.

- [ ] **Step 4: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-fde/TERRAFORM_KUSTOMIZE_REFERENCE.md
git commit -m "Add terraform and kustomize onboarding reference"
```

---

### Task 4: Rewrite `omnistrate-fde/SKILL.md` as the universal router

**Files:**
- Modify: `skills/omnistrate-fde/SKILL.md` (full rewrite)

**Interfaces:**
- Consumes: `DEPLOYMENT_MODELS_REFERENCE.md`, `HELM_ONBOARDING_REFERENCE.md`, `TERRAFORM_KUSTOMIZE_REFERENCE.md` (Tasks 1–3), existing `COMPOSE_ONBOARDING_REFERENCE.md`; sibling skills `../omnistrate-operator/SKILL.md`, `../omnistrate-sre/SKILL.md`, `../omnistrate-sa/SKILL.md`.
- Produces: frontmatter `name: omnistrate-fde`; the intake/matrix structure Tasks 6–8 cross-link.

- [ ] **Step 1: Write the new SKILL.md**

Frontmatter (exact):
```yaml
---
name: omnistrate-fde
description: Guide users through onboarding any application onto the Omnistrate platform and turning it into a managed SaaS offering. Covers Docker Compose, Helm charts, Terraform/OpenTofu modules, Kustomize, and mixed stacks, across all deployment models - hosted (your cloud), BYOC (customer cloud accounts, incl. BYO-VPC and PrivateLink), BYOC-K8s (customer-managed Kubernetes, no infra provisioning), and air-gapped/on-prem installers. Use when a customer/ISV wants to onboard, "SaaS-ify", productize, or offer their software as a managed service, or asks about BYOC / bring-your-own-cloud / on-prem / air-gapped delivery. For Kubernetes operator-based services (CRDs + controller) use omnistrate-operator; for designing an architecture from scratch use omnistrate-sa; for debugging failed instances use omnistrate-sre.
---
```

Body structure (≈300–400 lines):

```markdown
# Onboarding Services to Omnistrate

## Overview
(what Omnistrate does in 4 sentences for a naive ISV: control plane that
turns your artifact into a multi-tenant SaaS with provisioning, lifecycle,
billing; you bring compose/helm/terraform/kustomize/operator; instances
run in your cloud, customers' clouds, customers' k8s, or air-gapped)

## Phase 0 — Intake (ALWAYS start here for new onboarding)
(the 5 questions from the spec §4.2, asked one at a time, plain language,
skip any already answered; Q2 lists the four models with one-line
explanations and notes multi-select)

## Decision Matrix
(the artifact × format × guide table from spec §4.3, including operator →
invoke omnistrate-operator skill, "nothing yet" → omnistrate-sa;
deployment model is orthogonal → DEPLOYMENT_MODELS_REFERENCE.md always)

## Universal Workflow
(6 phases from spec §4.4: verify accounts → minimal zero-param spec →
build → deploy+debug until RUNNING (delegate omnistrate-sre; expect 2-3
cycles) → parameterize one at a time → production hardening. Per-phase
ctl/MCP commands: account_list/account_describe; build commands per
format; instance create/describe; keep them format-agnostic, pointing
into references for syntax)

## Critical Rules
(never write spec YAML from memory — copy from references/samples/docs;
docs search before every extension/field: mcp__ctl__docs_* and the JSON
schema URL https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json;
zero-parameterization first with the operator-CR exception; defaultValue
always quoted; never modify the user's original artifact; one change per
build-deploy cycle; deployment model chosen by intake — never silently
default)

## Red Flags — STOP
(table, adapted from omnistrate-operator SKILL.md style: "helm/terraform
isn't supported" → it is, use the references; "I'll default to
hostedDeployment" → ask intake Q2; "I remember the field name" → grep the
sample; "air-gapped needs an agent" → no, it's an installer; "BYOC-K8s
will provision nodes" → it won't, customer owns infra)

## Reference Files
(one-line index of the four references + operator skill + sre skill)

## Success Criteria
(build succeeds; instance RUNNING with healthy resources — or installer
artifact produced for air-gapped; every lifecycle addition validated by
rebuild+redeploy; specs doc-traceable)
```

Content rules: no YAML syntax blocks in SKILL.md beyond the decision-matrix table — syntax lives in references. Keep the compose-specific "CRITICAL RULES" (zero-parameterization, dual definition, etc.) out of SKILL.md if already in COMPOSE_ONBOARDING_REFERENCE.md; move any that aren't (verify by diff) into that reference in Task 5.

- [ ] **Step 2: Verify routing and links**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions/skills/omnistrate-fde
ls DEPLOYMENT_MODELS_REFERENCE.md HELM_ONBOARDING_REFERENCE.md TERRAFORM_KUSTOMIZE_REFERENCE.md COMPOSE_ONBOARDING_REFERENCE.md
grep -c "not yet supported\|Future Support\|not supported" SKILL.md
```
Expected: all four files exist; grep count is 0 (no leftover "unsupported" claims).

- [ ] **Step 3: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-fde/SKILL.md
git commit -m "Rewrite omnistrate-fde as universal onboarding router"
```

---

### Task 5: Update `COMPOSE_ONBOARDING_REFERENCE.md`

**Files:**
- Modify: `skills/omnistrate-fde/COMPOSE_ONBOARDING_REFERENCE.md`

**Interfaces:**
- Consumes: `DEPLOYMENT_MODELS_REFERENCE.md` (Task 1); old `SKILL.md` content (git show `main:skills/omnistrate-fde/SKILL.md`) for compose rules that must not be lost in the Task 4 rewrite.

- [ ] **Step 1: Fold in compose-only content displaced from SKILL.md**

Diff the old SKILL.md against the reference:
```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git show main:skills/omnistrate-fde/SKILL.md > /tmp/old-fde-skill.md
```
Any compose-specific rule present in `/tmp/old-fde-skill.md` but absent from `COMPOSE_ONBOARDING_REFERENCE.md` moves into the reference — specifically check for: image-registry auth flow (`x-omnistrate-image-registry-attributes` + secret setup walkthrough), synthetic root (`omnistrate/noop`) pattern, dual parameter definition, autoscaling-vs-replicaCountAPIParam conflict, `{{ }}` concatenation, cross-service `depends_on` references, backup/load-balancer placement rules, phased parameterization (Phase 1/2/3).

- [ ] **Step 2: Replace the deployment-model section with a pointer**

Remove any `hostedDeployment`/`byoaDeployment`/`onPremDeployment` explanatory duplication; keep ONE compose-syntax example block and add: "Model selection, account setup, BYOC/BYOC-K8s/air-gapped flows: see `DEPLOYMENT_MODELS_REFERENCE.md`."

- [ ] **Step 3: Verify**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions/skills/omnistrate-fde
grep -n "DEPLOYMENT_MODELS_REFERENCE" COMPOSE_ONBOARDING_REFERENCE.md
grep -n "x-omnistrate-image-registry-attributes\|omnistrate/noop\|parameterDependencyMap" COMPOSE_ONBOARDING_REFERENCE.md | head
```
Expected: pointer present; compose rules present.

- [ ] **Step 4: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-fde/COMPOSE_ONBOARDING_REFERENCE.md
git commit -m "Fold compose rules into compose reference; point at deployment models reference"
```

---

### Task 6: Overhaul `omnistrate-sre` (SKILL.md + reference)

**Files:**
- Modify: `skills/omnistrate-sre/SKILL.md` (rewrite)
- Modify: `skills/omnistrate-sre/OMNISTRATE_SRE_REFERENCE.md` (extend)

**Interfaces:**
- Consumes: `../omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md` (link for model context); troubleshooting docs.
- Produces: debug workflow that Task 4's SKILL.md and omnistrate-operator link to by path `../omnistrate-sre/SKILL.md`.

- [ ] **Step 1: Read the debugging sources**

- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/terraform-troubleshooting.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/helm-charts-troubleshooting.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/build-guides/operators-troubleshooting.md`
- `/Users/aloknikhil/ows-ws/documentation/docs/operate-guides/troubleshooting.md` (if present; else skip)
- `/Users/aloknikhil/ows-ws/documentation/docs/usecases/byoc-onprem.md` (limitations + agent sections)
- `/Users/aloknikhil/ows-ws/documentation/docs/usecases/air-gapped.md` (diagnostics section)
- Current `skills/omnistrate-sre/SKILL.md` + reference (already in repo)
- Verify `omnistrate-ctl instance debug` exists and capture its real flags: `grep -rn "instance debug" /Users/aloknikhil/ows-ws/documentation/docs/ | head`

- [ ] **Step 2: Rewrite SKILL.md**

Frontmatter (exact):
```yaml
---
name: omnistrate-sre
description: Systematically debug failed or stuck Omnistrate instance deployments across all resource types (Docker Compose containers, Helm releases, Terraform/OpenTofu, Kustomize, Kubernetes operator CRs) and all deployment models (hosted, BYOC customer accounts, BYOC-K8s customer-managed clusters, air-gapped). Progressive workflow - deployment status, workflow events, rendered-artifact debug, live cluster access - that finds root causes while avoiding token limits. Use for FAILED/DEPLOYING instances, probe failures, terraform apply errors, helm release issues, operator CR reconciliation problems, and BYOC agent/connectivity issues.
---
```

Body keeps the existing progressive core and adds (structure):

```markdown
## Progressive Debugging Workflow
1. Instance status (--deployment-status)          [existing]
2. Workflow list + events, summary → detail       [existing, incl. timeline art]
3. Rendered-artifact debug: omnistrate-ctl instance debug <id>   [NEW]
   (what it returns per resource type: rendered helm values /
   terraform plan+apply logs + rendered .tf / kustomize yaml /
   operator CR manifests; when to use: template rendering errors,
   terraform failures, parameter substitution doubts)
4. Live cluster access via deployment-cell update-kubeconfig      [existing]
   (KEEP the hard rule: never use aws/gcloud/az CLIs for cluster access)

## Branch by Resource Type
### Helm (helm list/status via cluster-admin kubeconfig [existing];
stuck deletes → leftover CRDs/finalizers/namespaced resources;
first-install failures auto-clean → look in debug events not helm list;
wait/timeout tuning via runtimeConfiguration)
### Terraform (read apply logs from instance debug; classify: IAM
permission gap on execution identity / quota / SKU-region availability /
naming conflict; fix rule: transient → restart workflow, spec/artifact
change → publish new plan version)
### Operator (workflow task failures; successCondition never met →
compare against LIVE CR status fields; operator controller logs;
NO-successCondition ⇒ no outputParameters rule; link
../omnistrate-operator/SKILL.md)
### Kustomize (substitution failures; missing StorageClass/PVC;
rendered yaml via instance debug)

## Branch by Deployment Model
### Hosted (default flow above)
### BYOC (customer account not READY → bootstrap/trust incomplete;
account customer describe; VPC requirement violations: DNS attrs,
NAT gateway, subnet ELB tags; PrivateLink endpoint/SG ports 8443-8506)
### BYOC-K8s (dataplane agent health: kubectl -n dataplane-agent get
deploy/dp-agent; outbound egress to control plane + registries;
missing StorageClasses; endpoint exposure is customer-owned — routing/
firewall/DNS failures are on the customer side)
### Air-gapped (no live control-plane link: work from action-hook logs,
installer output, diagnostic bundles; temporary-access grants for
remote troubleshooting)

## Common Failure Patterns  [existing categories + new per-type ones]
## Response Management       [existing --output json / filter guidance]
## Reference                 [pointer]
```

- [ ] **Step 3: Extend OMNISTRATE_SRE_REFERENCE.md**

Add sections: `instance debug` output anatomy (per resource type); failure-pattern catalog organized by resource type then model (each entry: symptom → evidence location → fix); BYOC/BYOC-K8s connectivity checklist; keep existing tool parameter docs and the failure analysis template.

- [ ] **Step 4: Verify**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions/skills/omnistrate-sre
grep -n "instance debug" SKILL.md OMNISTRATE_SRE_REFERENCE.md
grep -n "dataplane-agent\|byoc-onprem" SKILL.md
grep -c "AWS CLI\|aws cli\|gcloud\|az " SKILL.md   # hard rule retained
grep -rn "instance debug" /Users/aloknikhil/ows-ws/documentation/docs/ | head -3   # command exists in docs
```
Expected: new content present; cluster-access hard rule retained; `instance debug` traceable to docs (if NOT found in docs, replace with the documented equivalent found in Step 1 and note the actual command).

- [ ] **Step 5: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-sre/
git commit -m "Overhaul sre skill: per-resource-type and per-deployment-model debugging"
```

---

### Task 7: Update `omnistrate-sa` (SKILL.md + reference)

**Files:**
- Modify: `skills/omnistrate-sa/SKILL.md`
- Modify: `skills/omnistrate-sa/SOLUTIONS_ARCHITECT_REFERENCE.md`

**Interfaces:**
- Consumes: Task 4's decision matrix (mirror it in the handoff section); `DEPLOYMENT_MODELS_REFERENCE.md`.

- [ ] **Step 1: Read current files fully** (`skills/omnistrate-sa/SKILL.md` — 1153 lines, `SOLUTIONS_ARCHITECT_REFERENCE.md` — 1060 lines). Preserve existing structure; this is a targeted update, not a rewrite.

- [ ] **Step 2: Update SKILL.md**

1. Frontmatter: `name: omnistrate-sa`; extend description: architecture design for SaaS on Omnistrate including deployment-model selection (hosted/BYOC/BYOC-K8s/air-gapped); output may be a compose spec OR a ServicePlanSpec skeleton recommendation.
2. Interview section: add a "Deployment model discovery" block EARLY (before technology selection): who are the customers (segment/industry); data-sovereignty or compliance demands; do any customers require their own cloud account, their own cluster, or fully disconnected operation; connectivity constraints. Map answers → models via a short table + link `../omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md`.
3. Output-format decision: new section — compose (default for plain containers) vs helm path (stack already ships a chart) vs terraform (cloud managed services in the architecture) vs operator (operator-managed data infra) — with the consequence for the handoff artifact.
4. Handoff section: route per format — compose → `omnistrate-fde` compose path; helm/terraform/kustomize → `omnistrate-fde` + named reference; operator → `omnistrate-operator`; ALWAYS name the chosen deployment model(s) in the handoff summary.

- [ ] **Step 3: Update SOLUTIONS_ARCHITECT_REFERENCE.md**

Add one section: "Deployment model implications for architecture" — per model: networking (public endpoints vs INTERNAL vs installer-defined), licensing (required for BYOC/air-gapped), backup (S3-style object store availability differs on-prem), upgrade agility (fleet-managed vs customer-approved vs installer-shipped). Source: `deployment-models.md`, `byoc-overview.md`, `air-gapped-overview.md`, `licensing-protection.md`.

- [ ] **Step 4: Verify**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions/skills/omnistrate-sa
grep -n "BYOC\|air-gapped\|byoc-onprem\|DEPLOYMENT_MODELS_REFERENCE" SKILL.md SOLUTIONS_ARCHITECT_REFERENCE.md | head
grep -n "name: omnistrate-sa" SKILL.md
```
Expected: matches in both files; frontmatter updated.

- [ ] **Step 5: Commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add skills/omnistrate-sa/
git commit -m "Teach sa skill deployment-model discovery and multi-format handoffs"
```

---

### Task 8: Light-touch `omnistrate-operator` cross-links

**Files:**
- Modify: `skills/omnistrate-operator/SKILL.md` (small edits only)

**Interfaces:**
- Consumes: `../omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md`, Task 4 router.

- [ ] **Step 1: Make exactly three edits**

1. In "Phase 1 — Minimal spec" (the `deployment.hostedDeployment` sentence): append "— deployment model selection and BYOA/BYOC/air-gapped variants: see `../omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md`."
2. In "Not this skill" routing: change "compose-based onboarding → `omnistrate-fde`" to "compose/helm/terraform/kustomize onboarding → `omnistrate-fde` (the universal onboarding router)".
3. In "Phase 5 — Production" where "BYOA variants if offered" appears: add the same reference-file pointer.

Do NOT touch anything else (rules, red flags, reference file).

- [ ] **Step 2: Verify**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
grep -n "DEPLOYMENT_MODELS_REFERENCE" skills/omnistrate-operator/SKILL.md
git diff --stat skills/omnistrate-operator/   # expect: 1 file, small +/- counts
```

- [ ] **Step 3: Commit**

```bash
git add skills/omnistrate-operator/SKILL.md
git commit -m "Cross-link operator skill to deployment models reference and router"
```

---

### Task 9: Update repo-level docs (`README.md`, `AGENTS.md`, `CLAUDE.md`)

**Files:**
- Modify: `README.md`, `AGENTS.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: final skill set from Tasks 1–8.

- [ ] **Step 1: Read all three files, then update**

1. `README.md`: replace the skill list/description with the new map and add the decision tree: artifact type (compose/helm/terraform+kustomize/operator/nothing-yet) × deployment model (hosted/BYOC/BYOC-K8s/air-gapped) → skill + reference. State plainly that helm/terraform/kustomize/operators and all four deployment models are supported.
2. `AGENTS.md` and `CLAUDE.md`: same routing expressed as agent guidance (which skill to invoke for which request shape); keep any unrelated existing content.

- [ ] **Step 2: Verify**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
grep -c "not yet supported\|Future Support" README.md AGENTS.md CLAUDE.md skills/omnistrate-fde/SKILL.md
grep -n "BYOC-K8s\|air-gapped" README.md
```
Expected: first grep = 0 per file; second has matches.

- [ ] **Step 3: Commit**

```bash
git add README.md AGENTS.md CLAUDE.md
git commit -m "Update repo docs with new skill map and decision tree"
```

---

### Task 10: Doc-verification audit + skill-quality pass (final gate)

**Files:**
- Modify: any file from Tasks 1–9 where an issue is found

**Interfaces:**
- Consumes: everything shipped in Tasks 1–9.

- [ ] **Step 1: Traceability audit**

For EVERY YAML fragment and CLI command in the five touched skill directories, confirm the source exists. Mechanical sweep:
```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
# every ctl subcommand used:
grep -rhoE "omnistrate-ctl [a-z-]+ [a-z-]+|omctl [a-z-]+ [a-z-]+" skills/ | sort -u
# for each line above, confirm it appears in docs or Makefiles:
#   grep -rn "<subcommand>" /Users/aloknikhil/ows-ws/documentation/docs/ /Users/aloknikhil/ows-ws/*/Makefile
# every $sys path used:
grep -rhoE '\$sys\.[a-zA-Z.\[\]0-9_\"]+' skills/omnistrate-fde skills/omnistrate-sre skills/omnistrate-sa | sort -u
# confirm each against documentation/docs (system parameters page or usage in samples)
```
Fix or delete anything untraceable. Pay special attention to: deployment-block casing per context; `runtimeConfiguration` field names; every flag on `account customer create` and `instance create`.

- [ ] **Step 2: Consistency + quality pass**

Checklist:
1. Cross-links resolve: `grep -rhoE "\.\./[a-z-]+/[A-Z_]+\.md|[A-Z_]+_REFERENCE\.md" skills/ | sort -u` → `ls` each.
2. Frontmatter `name:` equals directory name for fde/sre/sa; descriptions contain the routing sentences.
3. No duplicated syntax blocks between any SKILL.md and its references.
4. No placeholder text: `grep -rn "TBD\|TODO\|coming soon\|not yet implemented" skills/` → expect 0 relevant hits.
5. Spec success-criteria walkthrough (spec §13): trace each of the four journeys through the shipped files (helm×BYOC+air-gapped; compose×hosted; terraform+kustomize×hosted; operator×BYOC; anything×BYOC-K8s) — confirm every step of each journey has concrete instructions, and note the file+section where each step lands.

- [ ] **Step 3: Fix anything found, then commit**

```bash
cd /Users/aloknikhil/ows-ws/agent-instructions
git add -A skills/ && git commit -m "Doc-verification audit fixes" || echo "nothing to fix"
```

- [ ] **Step 4: Final review request**

Run `git log --oneline main..HEAD` and `git diff --stat main..HEAD`; summarize for the user and request review (merge/PR decision is the user's).
