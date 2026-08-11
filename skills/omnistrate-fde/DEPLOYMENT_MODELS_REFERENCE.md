# Omnistrate Deployment Models Reference

Read this for the `deployment:` block, cloud-account setup, and the per-model
operational flows (hosted / BYOC / BYOC-K8s / air-gapped). Onboarding *methods*
(how you author the spec for compose / helm / terraform / operator) live in the
sibling references: `COMPOSE_ONBOARDING_REFERENCE.md`, `HELM_ONBOARDING_REFERENCE.md`,
`TERRAFORM_KUSTOMIZE_REFERENCE.md`, and (in the operator skill)
`OPERATOR_ONBOARDING_REFERENCE.md`.

Every YAML field, CLI flag, and `$sys.*` path below is drawn from the Omnistrate
documentation. **When something here conflicts with the live schema or the docs,
trust the schema/docs and update this file** — read them with `omctl docs`, which
needs no `omnistrate-ctl login` (network access is still required):

- `omctl docs compose-spec "x-omnistrate-service-plan"` — the compose `deployment:`
  block, plus `.deployment.hostedDeployment` / `.deployment.byoaDeployment` for the
  per-model variants
- `omctl docs plan-spec "deployment"` · `omctl docs plan-spec "deployment target"` —
  the ServicePlanSpec equivalents
- `omctl docs json-schema service-plan` — schema-canonical casing, including
  `$defs.Deployment` and `$defs.OnPremDeployment` (see the casing rule below)
- `omctl docs system-parameters` — the `$sys.*` paths
- `omctl docs search "byoc privatelink" --limit 15` — per-model operational guides

Add `-o json` for machine-readable output. (The MCP docs-search tools
`mcp__ctl__docs_*` are an optional alternative only when the user has asked to work
through MCP.)

**Field casing:** the account fields are **lowerCamel in every context** — compose and
ServicePlanSpec alike. Confirm straight from the schema rather than from memory:

```bash
omctl docs json-schema service-plan -o json | jq '.["$defs"].Deployment, .["$defs"].OnPremDeployment'
```

| Context | Deployment block lives at | Example |
|---------|---------------------------|---------|
| Compose (`x-omnistrate-service-plan`) | `x-omnistrate-service-plan.deployment` | `awsAccountId`, `awsBootstrapRoleAccountArn` |
| ServicePlanSpec — `hostedDeployment` / `byoaDeployment` | root `deployment` | `awsAccountId`, `awsBootstrapRoleAccountArn` |
| ServicePlanSpec — air-gapped `onPremDeployment` | root `deployment.onPremDeployment` | `awsAccountId`, `awsBootstrapRoleAccountArn` |

> Older specs and some published examples use UpperCamel (`AwsAccountId`,
> `AWSBootstrapRoleAccountArn`). Those still build — the platform decodes specs
> through `encoding/json`, which matches field names case-insensitively — but write
> lowerCamel in new specs so the editor pin and `omctl docs validate` both pass.
> `omctl docs validate --file <spec>.yaml` is the quickest way to confirm.

---

## Choosing a Deployment Model

Omnistrate lets the same application target the full spectrum of
infrastructure — the model is not baked into the application, but **every
deployment model requires its own separate Plan** (see the one-plan-per-model
rule below). The supported models decide *where* tenants are placed:

| Model | One-line definition | Who manages infra | Connectivity | Typical buyer |
|-------|---------------------|-------------------|--------------|---------------|
| **Hosted** | Deployed in *your* (SaaS/PaaS provider) cloud account | You (via Omnistrate) | Standard control plane over the internet | Startups; fully-managed SaaS where data can live in your account |
| **BYOC-Account** | Deployed in the customer's own cloud account (AWS/GCP/Azure/OCI/Nebius) | You operate; customer owns the account | Encrypted control channel (TLS/OAuth/mTLS), reverse connection — no inbound to customer | Enterprises with data-sovereignty needs and committed cloud spend |
| **BYO-VPC** | BYOC into an *existing* customer VPC/VNet instead of a fresh one | You operate; customer owns network | Customer-approved private routes, endpoints, egress controls | Customers with centralized firewall/egress governance |
| **BYOC PrivateLink** | BYOC with zero public exposure; control traffic over AWS PrivateLink | You operate; customer owns account+network | All control traffic over PrivateLink; no public endpoint | Regulated finance/government with no-public-egress policies |
| **BYOC-K8s** | Deployed into a customer-*managed* Kubernetes cluster (cloud, bare-metal, edge, on-prem) | Customer owns the K8s runtime; you deploy/operate workloads | Cluster opens **outbound** mTLS/gRPC to your control plane | Customers standardizing on EKS/AKS/GKE/OpenShift/Rancher/k3s |
| **Air-gapped** | A self-contained installer artifact the customer runs locally | Customer runs & operates; you ship the artifact | **No live control-plane connection**; signed artifacts transferred offline | Defense/regulated customers with disconnected networks |

BYOC-Account, BYO-VPC, BYOC PrivateLink, and BYOC-K8s are the four variants of
"BYOC Anywhere." All four use the same `byoaDeployment` spec block; the variant
is selected at customer-account onboarding time. Air-gapped is the disconnected
end of the same spectrum and uses a different spec block (`onPremDeployment`).

### ISV-phrasing FAQ

Map how ISVs describe their need to the right model:

| ISV says… | Model |
|-----------|-------|
| "Just host it for me — I don't want to deal with cloud accounts." | **Hosted** |
| "My customers want it running in their own AWS/GCP/Azure account." | **BYOC-Account** |
| "They insist on deploying into their existing VPC with their routes and egress rules." | **BYO-VPC** |
| "They have a no-public-egress policy — nothing can be reachable from the internet." | **BYOC PrivateLink** |
| "They run OpenShift / EKS on-prem but the cluster is allowed outbound egress." | **BYOC-K8s** |
| "Defense customer, air-gapped, no internet at all." | **Air-gapped** |
| "They have committed cloud spend / GPU reservations they want to use." | **BYOC-Account** (or BYOC-K8s for their own GPU cluster) |

> **One Plan per deployment model.** A service can offer several models — e.g.
> the same product as hosted SaaS *and* into customer accounts — but **each
> deployment model requires its own separate Plan**: a hosted plan, a BYOC
> plan, a BYOC-K8s plan, an air-gapped plan. Never combine deployment blocks
> (`hostedDeployment` + `byoaDeployment`, etc.) in a single plan spec, and
> never offer to build one plan that serves multiple models. The customer
> picks the model by subscribing to the corresponding plan. (BYO-VPC and
> PrivateLink are the exception in the sense that they are not separate plans:
> they are variants *within* a BYOC plan, selected at customer-account
> onboarding.)

---

## Hosted

Deployed in your (provider) account — the most common model, giving customers a
fully-managed experience. (Note: if you host the dataplane in **Omnistrate's**
account instead of yours, you incur additional infrastructure charges.)

### Provider account prerequisites

Before a hosted (or BYOC provisioner) account can be used, register it and
complete the cloud bootstrap so it reaches `READY`. AWS uses a CloudFormation
stack; GCP/Azure use a Terraform module / Cloud Shell script.

```bash
# 1. Register the account config. AWS needs --skip-wait because the account
#    stays non-READY until you run the bootstrap in AWS.
omnistrate-ctl account create aws-hosted \
  --aws-account-id 123456789012 \
  --skip-wait

# 2. Open the bootstrap action (CloudFormation for AWS; Terraform/Cloud Shell
#    for GCP/Azure). In the account TUI: Actions -> Bootstrap, press `o` to open
#    the CloudFormation URL (or "Bootstrap (No LB)" for the no-load-balancer flow).
omnistrate-ctl account describe aws-hosted

# 3. Re-run describe until the account status is READY.
omnistrate-ctl account describe aws-hosted
```

An AWS account config is region-agnostic once `READY`: the same config works
across supported AWS regions; pick the region at deploy time with `--region`.

### Spec syntax — compose context (lowerCamel fields)

The deployment block lives under `x-omnistrate-service-plan.deployment.hostedDeployment`:

```yaml
x-omnistrate-service-plan:
  deployment:
    hostedDeployment:
      awsAccountId: "<AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
      gcpProjectId: "<GCP_PROJECT_ID>"
      gcpProjectNumber: "<GCP_PROJECT_NUMBER>"
      gcpServiceAccountEmail: "<GCP_SA_EMAIL>"
      azureSubscriptionId: '<AZURE_INFO>'
      azureTenantId: '<AZURE_INFO>'
```

Configure only the cloud providers you plan to support. OCI is **not** supported
in compose specs — use a ServicePlanSpec with `CUSTOM_TENANCY` for OCI.

### Spec syntax — ServicePlanSpec context (UpperCamel fields + casing warning)

In a ServicePlanSpec the deployment block is at the
**root** (not under `x-omnistrate-service-plan`) and fields are UpperCamel:

```yaml
deployment:
  hostedDeployment:
    awsAccountId: "<AWS_ACCOUNT_ID>"
    awsBootstrapRoleAccountArn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role"
```

> **Casing warning:** schema-canonically the ARN field is
> `awsBootstrapRoleAccountArn` (acronym `AWS` fully uppercased) while the
> account-ID field is `awsAccountId` — this is the form in the live schema, and it
> is what the editor validator expects.
> The `onPremDeployment` block uses the **same** canonical casing (see
> [Air-gapped](#air-gapped--on-prem-installer)). Official examples also spell the
> ARN field `awsBootstrapRoleAccountArn`; the parser accepts it, but do not use
> that variant in a new spec.

### Tenancy interaction

The tenancy type declares how tenants share infrastructure:

| Tenancy type | Where it's used | Meaning |
|--------------|-----------------|---------|
| `OMNISTRATE_MULTI_TENANCY` | Docker Compose spec | Instances from different tenants share infra with logical isolation (bin-packing) |
| `OMNISTRATE_DEDICATED_TENANCY` | Docker Compose spec | Each tenant deployment gets its own dedicated infrastructure stack (VMs) |
| `CUSTOM_TENANCY` | Helm / Terraform / OpenTofu / Kustomize / operator (ServicePlanSpec) | Tenancy is defined inside your components, not controlled by Omnistrate |

```yaml
# Compose:
x-omnistrate-service-plan:
  tenancyType: 'OMNISTRATE_DEDICATED_TENANCY'
```

`CUSTOM_TENANCY` is not valid in compose specs — it is only used by the Plan/
ServicePlanSpec for helm/terraform/kustomize/operator deployments.

---

## BYOC (customer cloud account)

BYOC ("Bring Your Own Cloud") deploys and manages your software inside the
customer's own cloud account while you keep full operational control through the
Omnistrate control plane. Omnistrate reverses the connection (no inbound to the
customer account) and secures it with TLS/OAuth/mTLS.

### What the customer experiences

Customers can self-serve from your **Customer Portal**: it walks them through the
cloud-specific setup (CloudFormation for AWS; Cloud Shell / Terraform for
GCP/Azure) and tracks the account status. Responsibilities split three ways:

- **Customer account owner** — runs onboarding in their account, approves IAM/identity, owns quotas and org policies.
- **SaaS provider (you)** — enable BYOC for the plan, guide/assist onboarding, operate instances.
- **Omnistrate** — provides onboarding artifacts, bootstraps the deployment cell, orchestrates lifecycle.

Account lifecycle: customer connects the account → the **first** instance in a
given account+region bootstraps the deployment cell for that location → later
instances in the same account+region reuse that cell → the account can only be
offboarded after all its instances are deleted.

### Spec syntax (`byoaDeployment`, both contexts; one plan per model)

The same `byoaDeployment` *syntax* serves BYOC-Account, BYO-VPC, BYOC
PrivateLink, and BYOC-K8s. BYO-VPC and PrivateLink are variants **within** a
BYOC plan, chosen at customer-account onboarding; BYOC-K8s is a separate
deployment model and gets its **own plan** (deployed with
`--cloud-provider byoc-onprem`) — see the one-plan-per-model rule above.

> **Control Plane account rule (every BYOC variant).** Irrespective of which
> cloud(s) the customers deploy into — AWS, GCP, Azure, OCI, or Nebius — the
> account configuration in `byoaDeployment` is always an **AWS** account config:
> the AWS account the provider has designated as the **"Control Plane" account**
> (registered with `omnistrate-ctl account create`, bootstrapped to `READY`).
> Do **not** put GCP/Azure/OCI/Nebius fields in `byoaDeployment`, and do **not**
> use the customer's account here — the customer's cloud enters the picture
> later, at customer-account onboarding (`account customer create
> --gcp-project-id ...` etc.) and at deploy time (`--cloud-provider`). During
> intake, **explicitly ask the user which AWS account config is their designated
> Control Plane account** — never assume one or silently reuse another account
> config.

Compose context (lowerCamel):

```yaml
x-omnistrate-service-plan:
  name: 'My Product - BYOC'
  deployment:
    byoaDeployment:
      # Always the AWS "Control Plane" account — even for GCP/Azure/OCI customers
      awsAccountId: "<CONTROL_PLANE_AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<CONTROL_PLANE_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

ServicePlanSpec / Plan-spec context, root-level. Write **lowerCamel**
(`awsAccountId`, `awsBootstrapRoleAccountArn`) — that is what
`omctl docs plan-spec "Deployment schema"` publishes and what
`omctl docs validate` checks against. Some published BYOC On-Premise examples
show UpperCamel (`AwsAccountId` / `AwsBootstrapRoleAccountArn`); those build too,
because the platform decodes through `encoding/json` and matches
case-insensitively — but do not author fresh specs that way.

```yaml
name: My Product - BYOC
deployment:
  byoaDeployment:
    # Always the AWS "Control Plane" account — even for GCP/Azure/OCI customers
    awsAccountId: "<CONTROL_PLANE_AWS_ACCOUNT_ID>"
    awsBootstrapRoleAccountArn: arn:aws:iam::<CONTROL_PLANE_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

Offering hosted *and* BYOC? Build **two separate plans** — one plan per
deployment model. Never declare both blocks in one plan, and never offer the
user a single plan that serves multiple models:

```yaml
# Plan 1 — hosted (its own spec / plan)
x-omnistrate-service-plan:
  name: 'My Product - Hosted'
  deployment:
    hostedDeployment:
      awsAccountId: "<PROVIDER_AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<PROVIDER_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

```yaml
# Plan 2 — BYOC (separate spec / plan)
x-omnistrate-service-plan:
  name: 'My Product - BYOC'
  deployment:
    byoaDeployment:
      # AWS "Control Plane" account — may equal the hosted account, but ask
      awsAccountId: "<CONTROL_PLANE_AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<CONTROL_PLANE_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

### Onboarding a customer account — assisted CLI (aws/gcp/azure flag sets)

Customers can self-serve via the portal, or you can onboard on their behalf.
**Before running anything, confirm the target environment with the user — prod
(a real customer) or dev (testing the BYOC flow yourself):**

| Target | What to ask the user for | Subscription |
|---|---|---|
| **Prod** | The customer's cloud-account details (per-cloud list below) **and the end-customer email** | Pass `--customer-email=<end-customer>` (or `--subscription-id`) so the account is onboarded on the customer's subscription |
| **Dev** | Only the cloud-account details of the test account | Omit `--customer-email` — the command uses the **calling (logged-in) user's subscription** by default |

Cloud-account details to collect, per provider:

| Cloud | Details |
|---|---|
| AWS | account ID |
| GCP | project ID + project number |
| Azure | subscription ID + tenant ID |

The create command differs only by the cloud-provider flag set. Use
`--skip-wait` — the customer-side bootstrap must run before the account can
become `READY`. Append `--customer-email=<end-customer@example.com>` in prod,
and `--private-link` for PrivateLink accounts:

```bash
# AWS
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> \
  --aws-account-id=<CUSTOMER_AWS_ACCOUNT_ID> \
  --skip-wait

# GCP account
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> \
  --gcp-project-id=<CUSTOMER_GCP_PROJECT_ID> \
  --gcp-project-number=<CUSTOMER_GCP_PROJECT_NUMBER> \
  --skip-wait

# Azure account
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> \
  --azure-subscription-id=<CUSTOMER_AZURE_SUBSCRIPTION_ID> \
  --azure-tenant-id=<CUSTOMER_AZURE_TENANT_ID> \
  --skip-wait
```

### Presenting the per-cloud onboarding instructions (`account describe`)

The bootstrap instructions the customer (prod) or you (dev) must execute live
in the backing account config. Surface them **from the command output — never
from memory**:

```bash
omnistrate-ctl account customer describe <customer-account-instance-id> -o json
# copy summary.accountConfigID, then:
omnistrate-ctl account describe <account-config-id>
```

In the account TUI select **Actions -> Bootstrap**, then relay the instructions
per cloud:

- **AWS** — open (`o`) or copy (`c`) the CloudFormation URL and run the stack in
  the customer account. A **Bootstrap (No LB)** entry exists for the alternate
  flow without the load-balancer policy.
- **GCP** — copy the Cloud Shell command and run it in the target customer
  project.
- **Azure** — copy the Azure Cloud Shell command and run it in the target
  customer subscription.

In prod, send these instructions to the end customer and wait for them to
complete the bootstrap; in dev, execute them yourself against the test account.
Then poll until the account reaches `READY`:

```bash
omnistrate-ctl account customer describe <customer-account-instance-id>
```

Common BYOA lifecycle commands:

```bash
omnistrate-ctl account customer list [flags]
omnistrate-ctl account customer describe <customer-account-instance-id>
omnistrate-ctl account customer update <customer-account-instance-id> [flags]
omnistrate-ctl account customer delete <customer-account-instance-id>
```

### Deploying into a customer account (`--customer-account-id`)

Once the account is `READY`, deploy instances into it by passing the customer
onboarding instance ID as `--customer-account-id`:

```bash
omnistrate-ctl instance create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --version=latest --resource=<resource-name> \
  --cloud-provider=aws --region=us-east-1 \
  --customer-account-id=<customer-account-instance-id> \
  --param-file=./params.json --wait
```

### BYO-VPC (`cloud_provider_native_network_id` + VPC requirements table)

A BYOC customer can bring their own VPC instead of letting Omnistrate create one.
At instance-create time the customer sets their VPC ID as the value of the
`cloud_provider_native_network_id` input parameter.

VPC requirements (AWS standard):

| # | Requirement | Details |
|---|-------------|---------|
| 1 | **DNS settings** | Enable DNS hostnames and DNS resolution on the VPC |
| 2 | **NAT Gateway** | Public NAT gateway for pulling container images; private subnet route tables must route to it |
| 3 | **Public subnet auto-assign IP** | Public subnets must have auto-assign public IPv4 address enabled |
| 4 | **Subnet tags** | Private subnets: `kubernetes.io/role/internal-elb` = `1`. Public subnets: `kubernetes.io/role/elb` = `1` |

### PrivateLink (`--private-link`, VPC endpoint requirements, `--service-region`)

BYOC PrivateLink adds a zero-public-exposure guarantee: all control-plane traffic
flows over AWS PrivateLink; the customer's cluster has no public endpoint. It is a
**per-account** setting selected at onboarding time — no spec changes required.

```bash
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --customer-email=<customer@example.com> \
  --aws-account-id=<CUSTOMER_AWS_ACCOUNT_ID> \
  --private-link
```

If Omnistrate should be allowed to create the VPC/subnets/NAT/VPCE itself, also
pass `--allow-create-new-cloud-native-network` (or enable "Allow new cloud-native
network creation" in the portal). Otherwise the customer must bring their own VPC
that satisfies the imported-VPC requirements:

| # | Requirement | Details |
|---|-------------|---------|
| 1 | **VPC & subnet tags** | Tag VPC and workload subnets with `omnistrate.com/managed-by` = `omnistrate` (also the subnet selector for node placement) |
| 2 | **DNS** | Enable `enableDnsSupport` and `enableDnsHostnames` |
| 3 | **Egress** | Outbound internet via NAT Gateway, Transit Gateway, or VPN (for Helm/chart pulls during bootstrap) |
| 4 | **Management VPC Endpoint** | Interface VPC Endpoint targeting the PrivateLink service name Omnistrate provides; tag `Name` = `omnistrate-byoc-private-vpce-<provisioner-hc-id>`; SG inbound TCP `8443–8506` from the VPC CIDR |
| 5 | **Cross-region** | If the customer's VPC and the PrivateLink service are in different AWS regions, pass `--service-region` to `aws ec2 create-vpc-endpoint`. Do **not** enable private DNS for cross-region interface endpoints |

### Account tags → `$sys.deploymentCell.accountTags`

Cloud accounts carry free-form key/value tags stored on the account config. Every
deployment cell in the account exposes them as the `$sys.deploymentCell.accountTags`
system parameter, which can steer conditional amenities and chart values. Set with
comma-separated `key=value` via `--tags`:

```bash
# Tag your own account at onboarding time
omnistrate-ctl account create my-account --aws-account-id=123456789012 \
  --tags "env=prod,team=platform"

# Tag a customer BYOA account (flows to the backing account config)
omnistrate-ctl account customer create --service <service> --environment <environment> \
  --plan <byoa-plan> --aws-account-id=<customer-account> --tags "tier=enterprise"

# Update REPLACES the whole tag set (not a merge) — include every tag to keep
omnistrate-ctl account update my-account --tags "env=prod,omnistrate.com/cost-center=cc-1234"
```

Tag keys with dots/slashes (e.g. `omnistrate.com/cost-center`) must be referenced
with bracket notation: `$sys.deploymentCell.accountTags["omnistrate.com/cost-center"]`.

---

## BYOC-K8s (customer-managed Kubernetes)

### What it is / what Omnistrate does NOT manage

BYOC On-Premise lets a customer bring an **existing** Kubernetes cluster and use
it as the deployment target. Omnistrate treats this target as the `byoc-onprem`
provider with the `on-prem` region. The customer owns the K8s cluster, nodes,
storage, network routing, and endpoint exposure; your generated control plane
operates deployments in that cluster via the product dataplane agent.

Omnistrate does **not** provision nodes here — the customer-managed cluster is the
deployment target. This is different from air-gapped: in BYOC-K8s the customer
stays **connected** to your control plane.

#### `byoaDeployment` account fields for a pure BYOC-K8s plan

BYOC-K8s is configured as a BYOC deployment Plan, and you set up the provider side
the same way you would for other BYOC Plans. Its `byoaDeployment` block therefore
still carries the provider `awsAccountId` + `awsBootstrapRoleAccountArn` — even
though Omnistrate provisions no AWS infra in the customer's cluster.

These are the **provider-side** account values of the AWS **"Control Plane"
account** (see the Control Plane account rule in §BYOC — it applies to every
`byoaDeployment` variant, including this one), which Omnistrate uses to anchor
trust and host generated artifacts (install kit, chart/registry access); they
are **required by the spec schema** for a BYOC plan. Use the real designated
Control Plane account values — ask the user which account that is; do not treat
the block as a throwaway placeholder.

> **Casing.** `omctl docs plan-spec "Deployment schema"` gives both fields as
> lowerCamel (`awsAccountId`, `awsBootstrapRoleAccountArn`) — write those. Some
> published BYOC On-Premise examples show `AwsAccountId` / `AwsBootstrapRoleAccountArn`;
> the platform decodes through `encoding/json` and matches case-insensitively, so
> those build too. See the casing table at the top of this file.

### Choosing it

| Signal | Read |
|---|---|
| "We run OpenShift / EKS / Rancher and the cluster can reach the internet" | BYOC-K8s |
| "We have a cluster but it is fully disconnected" | **Air-gapped**, not BYOC-K8s (see §Air-gapped) |
| "We want you to create the cluster in our AWS account" | **BYOC-Account**, not BYOC-K8s |
| "We already run clusters we want Omnistrate to schedule onto" | **Adopted deployment cell** — a fleet operation, not a customer model |

The deciding question is never "is it their Kubernetes?" — it is **"can that
cluster hold an outbound connection to your control plane?"**

### Limitations

- The customer cluster must have **outbound** connectivity to your control plane — BYOC-K8s is **NOT** for air-gapped environments (use the air-gapped installer instead).
- Each customer onboarding instance maps to **one** Kubernetes cluster.
- Omnistrate provisions no nodes, storage, load balancers, or DNS.
- Endpoint reachability depends on the customer's DNS, firewall, load balancer, and routing.
- No ISV cloud account exists for a Terraform resource to target, so cloud-managed dependencies (RDS, Cloud SQL) are unavailable from the plan.

> **Depth lives in [`BYOC_K8S_REFERENCE.md`](BYOC_K8S_REFERENCE.md).** Read it before
> building a BYOC-K8s plan. It covers the trust/egress model and the customer
> allowlist, target-cluster prerequisites and how to surface them, the full
> onboarding flow (`account customer create --cluster-name`, install kit, `READY`
> gate), deploy flags, local testing, endpoint patterns including HTTP apps behind
> customer ingress, storage, native logs, operators on customer-managed clusters,
> verification and day-2 ops, adopted cells, and the canonical **BYOC-K8s vs
> air-gapped** disambiguation table.

---

## Air-gapped / On-prem Installer

### Concept (installer artifact; disconnected end of spectrum; boundaries)

An air-gapped installer is a self-contained deployment package Omnistrate builds
from your Plan spec, containing your Helm chart, container images (optionally
embedded), config templates, and lifecycle scripts. The customer downloads the
artifact and runs it against their cluster — including networks with no internet.

Air-gapped is the **disconnected end** of the BYOC Anywhere spectrum. It is *not*
a live control-plane connection: the customer owns the connectivity, update,
support, and operational-evidence boundaries. Do not assume live telemetry,
remote debugging, online license checks, automatic image pulls, or continuous
control-plane access. Modern installer Plans can include multiple Helm chart
resources and multiple image registry copy resources. Model each Helm release as
its own `services[]` entry, and model each source registry or repository copy
path as its own internal image sync service. For complex graphs, read
`ONPREM_INSTALLER_REFERENCE.md`.

### Spec syntax (`requirements.k8sVersion`, `onPremDeployment` fields)

Schema-canonically `onPremDeployment` uses
the **same** casing as `hostedDeployment` — `awsAccountId` +
`awsBootstrapRoleAccountArn`. The block below spells the ARN field
`awsBootstrapRoleAccountArn`; the parser accepts
that variant, but the editor validator expects `awsBootstrapRoleAccountArn`, so
prefer the canonical form in a fresh spec:

```yaml
# variant casing awsBootstrapRoleAccountArn (parser-accepted).
# Schema-canonical form: awsBootstrapRoleAccountArn.
name: My Application
deployment:
  requirements:
    k8sVersion: ">=1.30.0"   # optional: minimum K8s version on the target cluster
  onPremDeployment:
    # AWS account that hosts the installer artifacts
    awsAccountId: '<your-aws-account-id>'
    awsBootstrapRoleAccountArn: 'arn:aws:iam::<your-aws-account-id>:role/omnistrate-bootstrap-role'
```

### Installer tools (`onPremInstallerTools.helperUserScript`, `$file` syntax)

Inject reusable bash functions shared across all action hooks via
`onPremInstallerTools.helperUserScript` — inline, or referenced from a file with
the `$file` template:

```yaml
  onPremInstallerTools:
    helperUserScript: |
      #!/bin/bash
      log_error() {
        echo "Error: $1" > /tmp/error.log
      }
```

```yaml
  onPremInstallerTools:
    helperUserScript: |
      {{ $file:./custom_scripts/helper.sh }}
```

### Action hooks (scope `CLUSTER`; VALIDATE / PRE_INSTALL / POST_INSTALL / BACKUP)

Action hooks run shell commands at lifecycle points, under `services[].actionHooks`
with `scope: CLUSTER`:

```yaml
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: "echo 'Running validation checks...'"
      - scope: CLUSTER
        type: PRE_INSTALL
        commandTemplate: "echo 'Preparing environment...'"
      - scope: CLUSTER
        type: POST_INSTALL
        commandTemplate: "echo 'Post-install configuration...'"
      - scope: CLUSTER
        type: BACKUP
        commandTemplate: "echo 'Creating backup...'"
```

| Hook Type | When it runs |
|-----------|--------------|
| `VALIDATE` | Before and after installation to verify the cluster meets requirements |
| `PRE_INSTALL` | After validation but before Helm install/upgrade |
| `POST_INSTALL` | After Helm install/upgrade completes successfully |
| `BACKUP` | Before upgrades to snapshot the current state |

Longer scripts can be pulled from a file: `commandTemplate: | {{ $file:./custom_scripts/validate.sh }}`.

### Container images (`INSTALLER_EMBED`, registry copy)

For air-gapped clusters with no internet, use an internal image-sync service
(`internal: true`) owning `containerImagesRegistryCopyConfiguration`, with the main
service declaring `dependsOn` on it. The `pullMode` controls the transfer:

| Mode | Behavior |
|------|----------|
| `INSTALLER_EMBED` | Images are downloaded at **build time** and packaged into the installer artifact; pushed to the target registry at install time. **No internet needed during install.** Use for air-gapped. |
| `RUNTIME_PULL` | Images are pulled from source and pushed to target at **install/upgrade time**. Requires network access to both registries. |

```yaml
    containerImagesRegistryCopyConfiguration:
      pullMode: "{{ $var.pullMode }}"
      pullSource:
        registryURL: "docker.io"
        repositoryName: "my-org"
        credentials:
          username: "{{ $secret.REGISTRY_USERNAME }}"
          password: "{{ $secret.REGISTRY_PASSWORD }}"
      pushTarget:
        registryURL: "{{ $var.privateRegistryUrl }}"
        repositoryName: "my-org"
```

Optionally use `autoDiscoverImagesTag` in `helmChartConfiguration` to auto-discover
images from the chart's `Chart.yaml` annotations rather than listing them manually.

**Both `internal: true` on the image-sync service AND `dependsOn` on the main service
are required** — `internal: true` keeps the sync service out of the customer-facing
portal (`internal` defines whether the Resource can be created by customers or is an
internal resource used by other Resources), and `dependsOn` guarantees images are
mirrored before the chart installs.
Minimal two-service shape:

```yaml
services:
  - name: imageSync                    # image mirror — must be internal
    internal: true
    containerImagesRegistryCopyConfiguration:
      pullMode: "{{ $var.pullMode }}"
      pullSource:
        registryURL: "docker.io"
        repositoryName: "my-org"
      pushTarget:
        registryURL: "{{ $var.privateRegistryUrl }}"
        repositoryName: "my-org"

  - name: MyApp                         # the chart — waits for the mirror
    dependsOn:
      - imageSync
    helmChartConfiguration:
      chartName: my-app
      chartVersion: 1.0.0
      chartRepoName: my-repo
      chartRepoURL: https://charts.example.com/
```

Omitting `internal: true` surfaces the image-sync service as a customer-creatable
resource in the portal (confusing); omitting `dependsOn` lets the chart install before
images are mirrored.

For installers with multiple Helm releases, multiple registries, shared private
registry parameters, runtime prerequisite detection, action hooks, or operator
runbooks, use `ONPREM_INSTALLER_REFERENCE.md`. Do not flatten a complex installer into one
giant chart only to work around obsolete limitation guidance.

### Licensing + diagnostics in disconnected mode

Air-gapped operations must account for offline updates, mirrored repositories,
controlled artifact transfer, **signed offline licenses**, local diagnostics, and
support bundles that do not leak customer data. License enforcement works
**offline** via the Omnistrate SDK (the CA/intermediary certs are baked into the
SDK) — but a disconnected deployment will not get its license rotated, so the
license expires at its expiration date. See
[Cross-cutting Concerns → Licensing protection](#cross-cutting-concerns).

### Minimal end-to-end example

```yaml
name: My Application
deployment:
  requirements:
    k8sVersion: ">=1.30.0"
  onPremDeployment:
    awsAccountId: '<your-aws-account-id>'
    awsBootstrapRoleAccountArn: 'arn:aws:iam::<your-aws-account-id>:role/omnistrate-bootstrap-role'
  onPremInstallerTools:
    helperUserScript: |
      #!/bin/bash
      log_error() {
        echo "Error: $1" > /tmp/error.log
      }

services:
  - name: MyApp
    apiParameters:
      - name: releaseName
        key: releaseName
        type: String
        required: false
        modifiable: false
        export: true
        defaultValue: "my-app"
      - name: namespace
        key: namespace
        type: String
        required: false
        modifiable: false
        export: true
        defaultValue: "my-app"
      - name: adminPassword
        key: adminPassword
        type: Password
        required: true
        modifiable: false
        export: true
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: "echo 'Validate hook'"
      - scope: CLUSTER
        type: PRE_INSTALL
        commandTemplate: "echo 'Pre-install hook'"
      - scope: CLUSTER
        type: POST_INSTALL
        commandTemplate: "echo 'Post-install hook'"
      - scope: CLUSTER
        type: BACKUP
        commandTemplate: "echo 'Backup hook'"
    helmChartConfiguration:
      chartName: my-app
      chartVersion: 1.0.0
      chartRepoName: my-repo
      chartRepoURL: https://charts.example.com/
      releaseName: "{{ $var.releaseName }}"
      namespace: "{{ $var.namespace }}"
```

Build and release the installer:

```bash
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file installer-spec.yaml \
  --product-name "My Application Air-Gapped Installer" \
  --release \
  --release-description "v1.0.0 initial release"
```

---

## Cross-cutting Concerns

### Licensing protection

Licensing ensures only subscribed users can run your software — critical for
BYOC/BYOA and on-prem where the software runs outside your account. Omnistrate
generates a cryptographically signed license file (default **7-day** expiration,
auto-renewed while the subscription is valid) and provides validation SDKs.

Compose context — enable under `x-customer-integrations`:

```yaml
x-customer-integrations:
  licensing:
    # optional - defaults to 7 days
    licenseExpirationInDays: 7
    # optional - identifier used to add extra security on validation - defaults to product tier id
    productPlanUniqueIdentifier: '[product plan unique id]'
```

ServicePlanSpec context — enable under `features.CUSTOMER`:

```yaml
features:
  CUSTOMER:
    licensing:
      # optional - defaults to 7 days
      licenseExpirationInDays: 7
      # optional - identifier used to add extra security on validation - defaults to product tier id
      productPlanUniqueIdentifier: '[product plan unique id]'
```

Mounting: for compose, Omnistrate mounts the secret and sets env vars
automatically. For **Helm / Operator**, the generated secret
`service-plan-subscription-license` must be mounted at `/var/subscription/` — the
SDKs assume the license is there. SDKs:
Go (`omnistrate-oss/omnistrate-licensing-sdk-go`) and Java
(`omnistrate-oss/omnistrate-licensing-sdk-java`).

For a **Helm** chart, mount it through the chart's `extraVolumes` / `extraVolumeMounts`
values (most charts expose these — the keys are **chart-supporting**, not a platform
field; verify with `helm show values` and use per-role variants like `primary.extraVolumes`
if the chart namespaces them):

```yaml
chartValues:
  extraVolumes:
    - name: subscription-license
      secret:
        secretName: service-plan-subscription-license   # platform-generated license secret name
  extraVolumeMounts:
    - name: subscription-license
      mountPath: /var/subscription/                      # SDK-expected path
      readOnly: true
```

See [HELM_ONBOARDING_REFERENCE.md § Licensing](HELM_ONBOARDING_REFERENCE.md#licensing--mounting-the-subscription-license-secret-in-a-helm-chart)
for the same snippet with the chart-specific caveats.

Validation checklist (what a single SDK `ValidateLicense` call verifies):

1. Certificate chain valid (Let's Encrypt CA baked into the SDK — works offline).
2. License signature valid.
3. License not expired.
4. Organization ID + Product Plan ID match the license.
5. `INSTANCE_ID` env var matches the license (automatic for containers; must be injected for Helm/Kustomize/operators).

On failure, take an enforcement action: restricted mode, license-violation
warning, or shut down. Enforcement runs offline, so even a disconnected
deployment stops working once the (un-rotated) license expires.

### Adopted deployment cells (provider fleet — NOT a customer model)

Adopting a deployment cell integrates an **existing** Kubernetes cluster into
Omnistrate's cellular architecture as a managed deployment target. This is a
**provider-fleet** operation, not a customer deployment model — if you want a
managed *customer* experience on a customer-owned cluster, use
[BYOC-K8s](#byoc-k8s-customer-managed-kubernetes) instead.

```bash
omctl deployment-cell adopt \
  --cloud-provider aws \
  --region us-east-1 \
  --id "cluster-1" \
  --description "adopted cluster" \
  --customer-email customer@example.com     # optional; omit to adopt under the logged-in user

# Installs the agent (extract cluster-1.tar and apply the manifests per the kit README),
# then check status until it leaves PENDING_ADOPTION:
omctl deployment-cell status --id cluster-1
```

`PENDING_ADOPTION` means the cluster is registered but waiting for the agent to
install and connect. An adopted/imported cell reports `$sys.deploymentCell.isImported`
= `true`, which you can use to condition amenities.

Full flow — required vs optional flags, the agent-install manifest sequence,
deregistration, and the traps (`--customer-email` optional on `adopt` but required
on `delete`; `HEALTH_STATUS` stays `UNKNOWN` until adoption completes) — is in
[`BYOC_K8S_REFERENCE.md` §Adopted deployment cells](BYOC_K8S_REFERENCE.md#adopted-deployment-cells).

### Deployment cell amenities (once-per-cell components)

Amenities are cluster-wide components (Helm charts or Kubernetes manifests)
installed **once per deployment cell** rather than per instance — monitoring
stacks, CSI drivers, ingress controllers, shared operators, policy controllers,
CRDs. Omnistrate installs a baseline set (Observability/Grafana stack, Kubernetes
Dashboard, External DNS, Cert Manager, Nginx Ingress, Cluster Autoscaler, cloud-
specific CSI drivers) by default per cloud provider.

Amenities can be made conditional with a top-level `disable` expression, commonly
keyed off account tags or adoption status:

```yaml
managedAmenities:
  - name: Nginx Ingress Controller
    description: HTTP/HTTPS traffic routing and load balancing
    type: Helm
    disable: $sys.deploymentCell.isImported          # skip on adopted clusters

customAmenities:
  - name: gpu-metrics-exporter
    description: GPU metrics exporter
    type: Helm
    disable: $sys.deploymentCell.accountTags["skip-gpu-monitoring"]   # skip via account tag
    properties:
      # ...
```

A `disable` expression that references a tag key not present on the account fails
the amenity sync — set the tag (`"true"`/`"false"`) on **every** account you
condition on.

**Templates are scoped per cloud provider**, and that scoping is usually a better
lever than a `disable` expression. `generate-config-template` / `update-config-template`
take `--cloud aws|azure|gcp|nebius|byoc-onprem`, and a cell is seeded from the
template matching **its own** cloud provider — so a `--cloud byoc-onprem` template
reaches BYOC-K8s cells and nothing else. Three caveats, all verified on live cells:

- Trim with **`disable: "true"`** on the entry, keeping all entries in the list.
  Deleting entries, `managedAmenities: []`, a null list, a 0-byte file, and
  `skip: true` are all silent no-ops or rejections — `Skip` is an internal-only
  field absent from the public API. Always re-read with `describe-config-template`.
- **Disable Cert Manager, never delete it.** Deletion is rejected
  (`it is a required managed amenity`); `disable: "true"` is not a removal, so it
  works. All seven disabled is a validated configuration on current builds. On
  older control planes it hangs every instance in the Deployment step on
  `CreateCertificate` — if you see that, re-enable Cert Manager.
- The allow-list only applies at **cell bootstrap**. On a live cell, additions
  reconcile but **removals do not** — the sync reports SUCCESS and the release stays.
- `$sys.deploymentCell.isImported` is **`false`** on a BYOC-K8s cell onboarded via
  the install kit, so the idiom above does not fire there.

For BYOC-K8s, start with **all seven disabled** and a spec that declares no
endpoints, then add External DNS (and an `endpointConfiguration`) when the user
asks for a reachable endpoint — see
[`BYOC_K8S_REFERENCE.md` §Trimming the amenity footprint](BYOC_K8S_REFERENCE.md#trimming-the-amenity-footprint-byoc-k8s-cells-only).

### Custom networks (`features.CUSTOM_NETWORKS` — hosted-only)

Custom Networks let customers define network partitioning on a dedicated stack
while the service stays deployed in **your** (provider) account — giving
per-customer isolation and private network paths while keeping the service
self-served. This is a **hosted-only** feature: BYOC already provides isolation by
deploying directly in the customer account.

```yaml
# Compose:
x-omnistrate-service-plan:
  features:
    CUSTOM_NETWORKS:
```

```yaml
# ServicePlanSpec:
features:
  CUSTOM_NETWORKS:
```

Cannot be modified once the Plan is created; enabling it can significantly raise
infrastructure cost (one host cluster per customer network). Use RFC1918 address
space (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`).
