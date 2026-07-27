---
name: omnistrate-fde
description: Guide users through onboarding any application onto the Omnistrate platform and turning it into a managed SaaS offering. Covers Docker Compose, Helm charts, Terraform/OpenTofu modules, Kustomize, and mixed stacks, across all deployment models - hosted (your cloud), BYOC (customer cloud accounts, incl. BYO-VPC and PrivateLink), BYOC-K8s (customer-managed Kubernetes, no infra provisioning), and air-gapped/on-prem installers. Also covers monetization - pricing, Stripe end-to-end billing, usage metering export, custom billing dimensions, and cloud-marketplace/Chargebee/Clazar integrations. Use when a customer/ISV wants to onboard, "SaaS-ify", productize, or offer their software as a managed service, asks about BYOC / bring-your-own-cloud / on-prem / air-gapped delivery, or asks how to charge, meter, or bill for it. For Kubernetes operator-based services (CRDs + controller) use omnistrate-operator; for designing an architecture from scratch use omnistrate-sa; for debugging failed instances use omnistrate-sre.
---

# Onboarding Services to Omnistrate

All commands use the `omnistrate-ctl` CLI (alias `omctl`) — install and authenticate with `omnistrate-ctl login` first. An Omnistrate MCP server exposes equivalent tools (`mcp__ctl__*`); use those only if the user explicitly asks to work through MCP.

## Overview

Omnistrate is a control plane that turns your existing artifact — a Docker
Compose file, a Helm chart, a Terraform/OpenTofu module, Kustomize overlays, or
a Kubernetes operator — into a multi-tenant, managed SaaS with automatic
provisioning, full lifecycle (create/modify/stop/backup/restore/upgrade), and
metering/billing. You bring the artifact; Omnistrate owns the substrate (node
pools, per-instance namespaces, storage, load balancers, TLS, DNS). Instances
can run in *your* cloud (hosted), in *your customers'* cloud accounts (BYOC), in
*your customers'* own Kubernetes clusters (BYOC-K8s, no infra provisioned by
you), or fully disconnected as an air-gapped installer. This skill is the
router: it runs the intake interview, picks the onboarding method and
deployment model, and drives the phased build-deploy-debug workflow using the
per-topic reference files in this directory.

**Core principle: never write Omnistrate spec YAML, field names, or CLI flags
from memory.** Untrained-knowledge Omnistrate specs are reliably wrong while
looking plausible. Every fragment must be copied from a reference file in this
directory or verified against the Omnistrate docs
(https://docs.omnistrate.com) and the JSON schema
(`https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json`).
The MCP docs-search tools (`mcp__ctl__docs_*`) are an optional alternative only
when the user has asked to work through MCP.

## Phase 0 — Intake (ALWAYS start here for new onboarding)

Ask these six questions in plain language, **one at a time**, adapting to what
the user already volunteered (skip anything already answered). No Omnistrate
jargon — translate their answers into platform concepts yourself. The target
user is an ISV who has never seen Omnistrate: they describe their product and
their customers' constraints in their own words, and you map those onto the
onboarding method (Decision Matrix) and deployment model (Q2).

**1. What does your product look like today?**
Docker Compose file / Helm chart / Terraform (or OpenTofu) module / Kustomize
overlays / Kubernetes operator (CRDs + controller) / plain container images /
nothing yet.
→ *Operator (CRDs + controller)* hands off to the **omnistrate-operator** skill.
→ *Nothing yet* (needs an architecture designed first) hands off to
**omnistrate-sa**.

**2. Where should instances run?** (multi-select — a service can offer several
models, but **each model becomes its own separate Plan**; never offer to build
a single plan serving multiple deployment models)
- *Your cloud account* → **hosted** deployment.
- *Your customers' cloud accounts* → **BYOC** (`byoaDeployment`). Probe for VPC
  constraints and no-public-egress requirements → **BYO-VPC** / **PrivateLink**.
  **Always ask explicitly: which AWS account config is designated as the
  "Control Plane" account?** The `byoaDeployment` account block uses that AWS
  account config no matter which cloud the customers deploy into (GCP/Azure/
  OCI/Nebius included) — never assume or silently default it
  (`DEPLOYMENT_MODELS_REFERENCE.md` §BYOC, Control Plane account rule).
  Then confirm **prod or dev**: *prod* → ask for the customer's cloud-account
  details (AWS account ID / GCP project ID + number / Azure subscription +
  tenant ID) **and the end-customer email**; *dev* → ask only for the
  cloud-account details — the subscription defaults to your logged-in user.
  Account onboarding flow + per-cloud bootstrap instructions:
  `DEPLOYMENT_MODELS_REFERENCE.md` §BYOC.
- *Your customers' existing Kubernetes clusters, you do NOT provision infra* →
  **BYOC-K8s** (deploys via a dataplane agent; customer owns the cluster). Uses
  the same `byoaDeployment` block — ask the same Control Plane account question.
- *Fully disconnected / no connectivity back to you* → **air-gapped installer**
  (`onPremDeployment`).

**3. Which clouds and regions?** (AWS / GCP / Azure / OCI / Nebius; regions).

**4. Lifecycle needs?** Backups, stop/start, scaling, upgrades. *Noted for later
phases — not implemented up front.*

**5. Private registries or private git repos?** Determines the auth setup steps
for images (compose/helm) and source (terraform/kustomize/helm).

**6. How do you charge for this — and who takes the payment?** (Stripe / a cloud
marketplace / an existing billing system like Chargebee / not billing yet.)
Follow up with **"what do you charge for?"** — the built-in dimensions are cpu,
memory, storage, replica, deploymentCell.
→ *Stripe **and** built-in dimensions suffice* → **end-to-end billing**.
→ *Any other provider (AWS/GCP/Azure Marketplace, Chargebee, Clazar, in-house),
**or** extra dimensions, **or** custom aggregation logic* → **custom metering**
(usage export + your own exporter).
→ *Not billing yet* → free tier; note it and move on.
*Recorded now, implemented in phase 6 — never in the first build.* Details:
`BILLING_METERING_REFERENCE.md`.

If the user cannot cleanly place Q2, map their words to a model with the
ISV-phrasing FAQ in `DEPLOYMENT_MODELS_REFERENCE.md` (e.g. "customers want it in
their own AWS" → BYOC; "they run EKS on-prem but allow egress" → BYOC-K8s;
"defense customer, no internet" → air-gapped).

## Deployment Models at a Glance

Intake Q2 selects one or more of these. Details, `deployment:` blocks, and
account-onboarding flows are all in `DEPLOYMENT_MODELS_REFERENCE.md` — this
table is only for steering the interview.

| Model | Runs in… | Who owns infra | Connectivity | Spec block |
|---|---|---|---|---|
| **Hosted** | your (provider) cloud account | you, via Omnistrate | standard control plane | `hostedDeployment` |
| **BYOC** (Account / BYO-VPC / PrivateLink) | the customer's cloud account | customer owns account, you operate | reverse/encrypted channel; PrivateLink = no public exposure | `byoaDeployment` |
| **BYOC-K8s** | the customer's own Kubernetes cluster | customer owns the cluster; you deploy workloads only | cluster opens **outbound** mTLS/gRPC to your control plane | `byoaDeployment` (deploy `--cloud-provider byoc-onprem`) |
| **Air-gapped** | wherever the customer runs the installer | customer runs and operates | **none** — self-contained artifact, no live link | `onPremDeployment` |

BYO-VPC and PrivateLink are BYOC variants selected at customer-account
onboarding, not separate spec blocks (they live within the BYOC plan). A
service can offer several models, but **each deployment model requires its own
separate Plan** — never combine `hostedDeployment` and `byoaDeployment` in one
plan, and never offer a single plan that serves multiple models. For every
`byoaDeployment` plan the account block carries the AWS **"Control Plane"
account** config irrespective of the customer's cloud — asked explicitly at
intake, never defaulted (`DEPLOYMENT_MODELS_REFERENCE.md` §BYOC).

## Decision Matrix

Pick the row for the user's artifact (intake Q1). The **deployment model**
(intake Q2) is orthogonal: **every** row also reads
`DEPLOYMENT_MODELS_REFERENCE.md` for the `deployment:` block and account setup.

| Artifact | Spec format | Build command | Guide |
|---|---|---|---|
| Docker Compose | compose + `x-omnistrate-*` | `omnistrate-ctl build --file <compose-file>` | `COMPOSE_ONBOARDING_REFERENCE.md` |
| Helm chart | ServicePlanSpec (`helmChartConfiguration`) | `omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec` | `HELM_ONBOARDING_REFERENCE.md` |
| Terraform / Kustomize | ServicePlanSpec (`terraformConfigurations` / `kustomizeConfiguration`) | same | `TERRAFORM_KUSTOMIZE_REFERENCE.md` |
| Operator (CRDs + controller) | ServicePlanSpec (`systemWorkflows`) | same | → **omnistrate-operator** skill (see Companion skills below) |
| Mixed (e.g. terraform infra + helm app) | ServicePlanSpec, multiple services with `dependsOn` | same | `HELM_ONBOARDING_REFERENCE.md` + `TERRAFORM_KUSTOMIZE_REFERENCE.md` |
| Any artifact, air-gapped target | ServicePlanSpec with `onPremDeployment` | same | `DEPLOYMENT_MODELS_REFERENCE.md` §Air-gapped (installer packages a Helm chart; non-Helm stacks must first be bundled into a chart) |
| Nothing yet (design first) | — | — | → hand off to **omnistrate-sa** |

ServicePlanSpec builds all share `--spec-type ServicePlanSpec`; the compose path
is the exception (plain `omnistrate-ctl build --file <compose-file>`, no `--spec-type`).
Exact flags and skeletons live in the per-format references — do not reconstruct
them here.

## Universal Workflow (method-agnostic)

Same six phases for every artifact and model. Per-phase commands are named
generically; copy the exact syntax from the format's reference.

**1. Verify accounts / prerequisites.** Confirm the *provider* cloud account is
READY before anything else: `omnistrate-ctl account list` /
`omnistrate-ctl account describe <account-name>`. Extract account IDs,
bootstrap role ARNs, project IDs for the `deployment:` block. For BYOC and
BYOC-K8s, verify the AWS **Control Plane** account config named at intake is
`READY` — its values are what go into `byoaDeployment`, whatever the customer's
cloud — and explain that *customer* accounts are onboarded later, at deploy
time — see `DEPLOYMENT_MODELS_REFERENCE.md` (§BYOC, §BYOC-K8s) for the customer
`account customer create` flows.

**2. Minimal spec, zero parameterization.** Hardcode everything: one cloud,
create/delete lifecycle only, no API parameters, no `$var.*`, no autoscaling.
Get a working deployment before adding anything. Build the deployment block from
`DEPLOYMENT_MODELS_REFERENCE.md` for the model(s) chosen in Q2 — **one plan per
model**: if several models were chosen, build and stabilize one plan first,
then author a separate plan per remaining model. The service body comes from
the format's reference.
*Exception (from the operator skill): CR-driven specs are parameter-driven from
day one, but still keep the parameter set minimal.*

**3. Build — then a review pit-stop.** The build must succeed before anything
is added.
- Compose: `omnistrate-ctl build --file <compose-file>`.
- Helm/Terraform/Kustomize/mixed: `omnistrate-ctl build -f spec.yaml --spec-type ServicePlanSpec ...`.
- **Pit-stop (required): review before deploying.** The build output prints
  links to the generated product — surface them from the actual output and
  STOP. Have the user review both sides: (a) the **service/plan page**
  (provider side) to sanity-check the generated architecture — resources,
  parameters, endpoints; and (b) the **Customer Portal** ("Access SaaS
  Product") to preview the exact UX their customers will get, including the
  exposed parameters. (`--interactive` builds prompt for Customer Portal
  access directly.) Proceed only after the user confirms, or adjust the spec
  and rebuild.

**4. Deploy one instance and debug until RUNNING.** `instance create` targeting
the main resource, then `instance describe`. For BYOC targets the customer
account must be onboarded and `READY` first — see
`DEPLOYMENT_MODELS_REFERENCE.md` §BYOC — then deploy with
`--customer-account-id`. Expect **2–3 iterations** — do not
stop at the first failure. Debug loop, in escalating order:
   1. `omnistrate-ctl instance describe <id> --deployment-status --output json`
      — find the failing resource.
   2. `omnistrate-ctl workflow list --instance-id <id>` then
      `omnistrate-ctl workflow events <workflow-id>` — locate the failed step;
      add `--resource-key` / `--detail` only for that step.
   3. `omnistrate-ctl instance debug <id>` — rendered helm values / terraform
      apply logs / operator CR status (kustomize has no rendered-artifact view:
      use workflow events + the tunnel).
   4. `omnistrate-ctl deployment-cell update-kubeconfig <cell-id> --kubeconfig
      /tmp/kc` + `kubectl logs` / `kubectl get` — live pod state. Never use
      aws/gcloud/az CLIs for cluster access; only the Omnistrate tunnel.
   The **omnistrate-sre** skill, if installed, extends this loop with
   per-resource-type and per-model failure catalogs.

**5. Customization discovery & parameterization.** Once the zero-param instance
is RUNNING, **proactively inspect** the artifact to recommend a customer-facing
parameter set — do not wait to be asked. For Helm, run `helm show values` /
`helm show readme` (or Artifact Hub); for terraform, read `variables.tf`; for
compose, inspect env vars/images. Classify every relevant value into three tiers
(**Tier 1** recommended customer-facing → `apiParameters`; **Tier 2**
optional/advanced → default to hardcoded; **Tier 3** platform/ISV-owned → never
expose), **present the tier table for approval**, and also surface external
dependencies: when a chart bundles a dependency with a working default, *suggest*
(never force) replacing it with a terraform-managed RDS/ElastiCache/S3. Then
implement approved Tier-1 parameters **one at a time** — rebuild + redeploy after
*each* change, never batch. See
`HELM_ONBOARDING_REFERENCE.md` §"Customization discovery" and §"External
dependencies", and `TERRAFORM_KUSTOMIZE_REFERENCE.md` §"Managed-service modules".

**6. Production hardening.** Split a prod Plan (accounts differ; spec otherwise
identical), add additional clouds, and additional deployment models (one plan
per model). For air-gapped targets the deliverable is the installer artifact
rather than a running instance — see `DEPLOYMENT_MODELS_REFERENCE.md`
§Air-gapped.
**Billing/metering lands here, not earlier** — implement the path chosen in
intake Q6: `pricing` + `billingProviders` for end-to-end Stripe billing, or the
`metering` export (+ your exporter) for marketplaces / non-Stripe providers /
custom dimensions. For `CUSTOM_TENANCY` plans (Helm, operator, Kustomize) the
`omnistrate.com/include-customer-billing: "true"` **pod label** is required or
usage silently bills zero. See `BILLING_METERING_REFERENCE.md`.

**7. Distribute & document.** Release the Plan
(`omnistrate-ctl build ... --release-as-preferred --release-description "..."`),
make the **prod environment Public**, configure the **Customer Portal** (custom
domain via CNAME, SMTP sender email, SSO identity providers), and optionally add
billing. **THEN generate the artifact pair** — `DEPLOYMENT_OVERVIEW.md` +
`deployment-overview.svg` — next to the ISV's spec files. The SVG is produced by
copying the base template `assets/omnistrate-architecture-base.svg` and applying
per-model, id-keyed edits (retitle the boundary, un-hide/label workloads and
managed services, fill customer parameters); the `.md` embeds it. Onboarding is
**not complete** until that pair is generated and the portal path is confirmed
(or, for air-gapped, the installer is delivered). See `DISTRIBUTION_REFERENCE.md`.

## Critical Rules

1. **Never write spec YAML, field names, or CLI flags from memory.** Copy from
   the reference files' verified fragments or verify against the Omnistrate docs
   (https://docs.omnistrate.com) / the JSON schema
   (`https://api.omnistrate.cloud/2022-09-01-00/schema/service-spec-schema.json`).
   Check the docs before every extension or field you add. (The MCP docs-search
   tools `mcp__ctl__docs_*` are an optional alternative only on user request.)
2. **Zero-parameterization first** (compose / helm / terraform / kustomize).
   Hardcode everything, get to RUNNING, then parameterize. *Operator-CR
   exception:* CR specs are parameter-driven from day one, set kept minimal.
3. **One change per build-deploy cycle.** Add one parameter or capability, then
   rebuild and redeploy to validate before the next.
4. **`defaultValue` is always a quoted string** — even for numeric types.
5. **Never modify the user's original artifact.** Create Omnistrate variants
   (e.g. `-omnistrate.yaml`, a `spec.yaml`) — leave the source untouched.
6. **The deployment model comes from intake Q2 — never silently default.** The
   old "ALWAYS use `hostedDeployment`" rule is gone. Ask Q2, then build the
   `deployment:` block from `DEPLOYMENT_MODELS_REFERENCE.md`.
7. **Field casing depends on context.** Compose uses lowerCamel
   (`awsBootstrapRoleAccountArn`); ServicePlanSpec uses UpperCamel
   (`AWSBootstrapRoleAccountArn`). Copy from the reference for the right context.

## Red Flags — STOP

| Thought | Reality |
|---|---|
| "Helm / Terraform / Kustomize isn't supported by this skill." | It is. Use `HELM_ONBOARDING_REFERENCE.md` / `TERRAFORM_KUSTOMIZE_REFERENCE.md`. |
| "This is an operator, I'll write the workflows here." | Hand off to **omnistrate-operator** — it owns `systemWorkflows`. |
| "I'll default to `hostedDeployment`." | Ask intake Q2 first. The model is a decision, not a default. |
| "I remember the field name / that ctl flag exists." | Grep the reference files; verify flags with `--help` or docs search. |
| "Air-gapped needs an always-on agent phoning home." | No. Air-gapped is a self-contained *installer* artifact — no live control-plane link (`onPremDeployment`). |
| "BYOC-K8s will provision the customer's nodes." | It won't. The customer owns the cluster and infra; Omnistrate only deploys workloads via the dataplane agent. |
| "I'll add all the parameters, then build once." | One change per build-deploy cycle. Batching hides which change broke it. |
| "I'll add a custom pricing dimension / a `marketplace:` block to the spec." | Neither exists. Only cpu/memory/storage/replica/deploymentCell are billable dimensions; everything else is the metering-export path (`BILLING_METERING_REFERENCE.md`). |
| "Billing is set up, so a CUSTOM_TENANCY Helm/operator plan will bill correctly." | Not without the `omnistrate.com/include-customer-billing: "true"` pod label — otherwise it silently bills zero. |
| "I'll parameterize before the first deploy." | Zero-parameterization first (operator-CR excepted). Get to RUNNING, then parameterize. |

## Reference Files

- **`COMPOSE_ONBOARDING_REFERENCE.md`** — Docker Compose path: `x-omnistrate-*`
  transformation, single vs multi-service (synthetic `noop` root), API
  parameters, compute/storage, load balancers, action hooks, build/debug.
- **`HELM_ONBOARDING_REFERENCE.md`** — Helm ServicePlanSpec:
  `helmChartConfiguration`, `runtimeConfiguration`, values templating, pod
  placement/affinity, multi-service `dependsOn`, endpoints, lifecycle.
- **`TERRAFORM_KUSTOMIZE_REFERENCE.md`** — Terraform (`terraformConfigurations`,
  git/local sources, execution identity, state, outputs) and Kustomize
  (`kustomizeConfiguration`, templating, workload affinity), plus combined
  terraform + helm/kustomize patterns.
- **`DEPLOYMENT_MODELS_REFERENCE.md`** — the orthogonal `deployment:` block and
  operational flows for hosted / BYOC (BYO-VPC, PrivateLink) / BYOC-K8s /
  air-gapped, plus customer-account onboarding, tenancy, and the ISV-phrasing
  FAQ. Read this for **every** onboarding path.
- **`BILLING_METERING_REFERENCE.md`** — FinOps: choosing end-to-end Stripe
  billing vs custom metering export, `pricing` dimensions, `billingProviders`,
  paywall/quota/invoices, the `metering` bucket export (policy, path layout,
  record schema, `last_success_export.json`, `externalPayerId`), custom
  dimensions + exporter patterns (Clazar recipe), marketplaces, the
  CUSTOM_TENANCY billing pod label, and `omnistrate-ctl cost` insights
  (workflow phase 6).
- **`DISTRIBUTION_REFERENCE.md`** — release states + `--release` /
  `--release-as-preferred` / `--release-description`, prod env visibility, the
  Customer Portal (domain/SMTP/SSO), subscriptions, optional pricing/billing, the
  ordered go-live checklist, per-model customer experience, and the
  `DEPLOYMENT_OVERVIEW.md` + `deployment-overview.svg` artifact pair — the SVG
  edit recipe over the base template in `assets/` (workflow phase 7).
Companion skills — separate installs; this skill is fully usable without them:

- **omnistrate-operator** — CRD + controller onboarding (`systemWorkflows`,
  lifecycle verbs); covers the operator row of the decision matrix. Without it,
  start from the public template:
  https://github.com/omnistrate-community/operator-spec-template.
- **omnistrate-sre** — extends the phase-4 debug loop with per-resource-type
  and per-model failure catalogs.

## Success Criteria

- Build succeeds with the chosen spec format.
- Instance reaches **RUNNING** with all resources healthy — **or**, for
  air-gapped targets, the installer artifact is produced.
- Started with zero parameterization (operator-CR excepted) and completed at
  least one deploy-debug-fix cycle.
- Every lifecycle/parameter addition validated by a rebuild + redeploy.
- The deployment model(s) match what the user chose in intake Q2.
- Recommended customization tiers were reviewed with the user (tier table
  presented; approved Tier-1 parameters implemented one per build-deploy cycle).
- The Plan is **released** and the **portal is reachable** (prod env public,
  domain/SMTP/SSO configured) — **or**, for air-gapped, the installer is delivered.
- The **`DEPLOYMENT_OVERVIEW.md`** + **`deployment-overview.svg`** artifact pair
  was generated (the SVG derived from `assets/omnistrate-architecture-base.svg`)
  next to the ISV's spec files.
- Every shipped spec fragment is traceable to a reference, sample, or the docs —
  nothing written from memory.
