# Omnistrate Deployment Models Reference

Read this for the `deployment:` block, cloud-account setup, and the per-model
operational flows (hosted / BYOC / BYOC-K8s / air-gapped). Onboarding *methods*
(how you author the spec for compose / helm / terraform / operator) live in the
sibling references: `COMPOSE_ONBOARDING_REFERENCE.md`, `HELM_ONBOARDING_REFERENCE.md`,
`TERRAFORM_KUSTOMIZE_REFERENCE.md`, and (in the operator skill)
`OPERATOR_ONBOARDING_REFERENCE.md`.

Every YAML field, CLI flag, and `$sys.*` path below is copied from the Omnistrate
docs / spec templates. When something here conflicts with the live schema or a docs
search, trust the schema/docs and update this file.

**Field-casing rule (load-bearing):** the *same* fields are cased differently by
context. Always know which context a fragment belongs to:

| Context | Deployment block lives at | Field casing | Example |
|---------|---------------------------|--------------|---------|
| Compose (`x-omnistrate-service-plan`) | `x-omnistrate-service-plan.deployment` | lowerCamel | `awsAccountId`, `awsBootstrapRoleAccountArn` |
| ServicePlanSpec (helm/terraform/kustomize/operator) | root `deployment` | UpperCamel (with `AWS` acronym uppercased in the ARN field) | `AwsAccountId`, `AWSBootstrapRoleAccountArn` |
| Air-gapped ServicePlanSpec (`onPremDeployment`) | root `deployment.onPremDeployment` | UpperCamel (`Aws` prefix on *both* fields) | `AwsAccountId`, `AwsBootstrapRoleAccountArn` |

---

## Choosing a Deployment Model

Omnistrate lets a single Plan target the full spectrum of infrastructure — the
model is chosen at deploy/onboarding time, not baked into the application. The
supported models decide *where* tenants are placed:

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

> **Models are not mutually exclusive.** One Plan may declare both
> `hostedDeployment` and `byoaDeployment` — so you can offer the same product as
> hosted SaaS *and* into customer accounts. The customer picks the model at
> subscription/onboarding time.

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

Source: `x-omnistrate-service-plan.deployment.hostedDeployment` in the compose spec.

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

Source: `operator-spec-template/spec.yaml` header. The deployment block is at the
**root** (not under `x-omnistrate-service-plan`) and fields are UpperCamel:

```yaml
deployment:
  hostedDeployment:
    AwsAccountId: "<AWS_ACCOUNT_ID>"
    AWSBootstrapRoleAccountArn: "arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role"
```

> **Casing warning:** the ARN field is `AWSBootstrapRoleAccountArn` (acronym
> `AWS` fully uppercased), while the account-ID field is `AwsAccountId`. This is
> exactly as it appears in the operator spec template — do not "normalize" it.
> Note this differs from the air-gapped `onPremDeployment` block, which uses
> `AwsBootstrapRoleAccountArn` (see [Air-gapped](#air-gapped--on-prem-installer)).

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

### Spec syntax (`byoaDeployment`, both contexts; multi-model example)

Same `byoaDeployment` block serves BYOC-Account, BYO-VPC, BYOC PrivateLink, and
BYOC-K8s — the variant is chosen at onboarding, not in the spec.

Compose context (lowerCamel):

```yaml
x-omnistrate-service-plan:
  name: 'My Product - BYOC'
  deployment:
    byoaDeployment:
      awsAccountId: "<AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

ServicePlanSpec / Plan-spec context, root-level. The Omnistrate BYOC-deployment
guide shows this block with **lowerCamel** fields (`awsAccountId`,
`awsBootstrapRoleAccountArn`) — matching the compose block, and unlike the
UpperCamel `hostedDeployment` in the operator spec template. Copy each block from
the source for the spec type you are authoring rather than assuming a global rule:

```yaml
name: My Product - BYOC
deployment:
  byoaDeployment:
    awsAccountId: "<AWS_ACCOUNT_ID>"
    awsBootstrapRoleAccountArn: arn:aws:iam::<AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

Multi-model — offer the same plan as hosted *and* BYOC by declaring both blocks:

```yaml
x-omnistrate-service-plan:
  deployment:
    hostedDeployment:
      awsAccountId: "<PROVIDER_AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<PROVIDER_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
    byoaDeployment:
      awsAccountId: "<PROVISIONER_AWS_ACCOUNT_ID>"
      awsBootstrapRoleAccountArn: arn:aws:iam::<PROVISIONER_AWS_ACCOUNT_ID>:role/omnistrate-bootstrap-role
```

### Onboarding a customer account — assisted CLI (aws/gcp/azure flag sets)

Customers can self-serve via the portal, or you can onboard on their behalf. The
assisted CLI flow differs only by the cloud-provider flag set:

```bash
# AWS
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --customer-email=<customer@example.com> \
  --aws-account-id=<CUSTOMER_AWS_ACCOUNT_ID>

# GCP: --gcp-project-id / --gcp-project-number / --gcp-service-account-email
# Azure: --azure-subscription-id / --azure-tenant-id
# PrivateLink: append --private-link
```

Full flag sets per provider:

```bash
# GCP account
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --customer-email=<customer@example.com> \
  --gcp-project-id=<CUSTOMER_GCP_PROJECT_ID> \
  --gcp-project-number=<CUSTOMER_GCP_PROJECT_NUMBER> \
  --gcp-service-account-email=<CUSTOMER_GCP_SA_EMAIL>

# Azure account
omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --customer-email=<customer@example.com> \
  --azure-subscription-id=<CUSTOMER_AZURE_SUBSCRIPTION_ID> \
  --azure-tenant-id=<CUSTOMER_AZURE_TENANT_ID>
```

For AWS the customer-facing bootstrap (CloudFormation) must run in the customer
account before the backing account config becomes `READY`; use `--skip-wait` on
create, then find the backing config and complete bootstrap:

```bash
omnistrate-ctl account customer describe <customer-account-instance-id> -o json
# copy summary.accountConfigID, then:
omnistrate-ctl account describe <account-config-id>   # Actions -> Bootstrap
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

### Target-cluster prerequisites

| Requirement | Details |
|-------------|---------|
| Kubernetes cluster | A working cluster with a supported Kubernetes version |
| `kubectl` access | The operator running the install kit must target the intended cluster context |
| Pod networking | CNI and pod-to-pod networking must work |
| DNS and egress | Pods must resolve and reach your control-plane endpoints and required registries |
| Storage | Required StorageClasses must exist if the Plan uses persistent volumes |
| Endpoint path | Ingress, load balancer, firewall, and DNS routing must match the endpoint exposure your Plan defines |

Cluster-level components (ingress controllers, cert-manager, monitoring, etc.)
should be configured as deployment-cell amenities or pre-installed by the customer.

### Onboarding flow

Passing `--cluster-name` (instead of an account flag like `--aws-account-id`)
selects the BYOC On-Premise path. `account customer create` downloads the install
kit into the current directory.

```bash
mkdir -p dp-install-kit && cd dp-install-kit

omnistrate-ctl account customer create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --cluster-name=<customer-cluster-name> \
  --cluster-description="Customer production Kubernetes cluster"

# Extract the kit and confirm kubectl targets the right cluster, then install the agent:
tar xf byoc-onprem-install-kit-<account-config-id>.tar
./install.sh --non-interactive

# The onboarding instance is NOT immediately READY. After the agent connects,
# poll until account_status is READY:
omnistrate-ctl account customer describe <customer-account-instance-id>
```

To re-download the kit for an existing onboarding instance:
`omnistrate-ctl account customer install-kit <customer-onboarding-instance-id>`.

### Deploying (`--cloud-provider byoc-onprem --region on-prem`)

```bash
omnistrate-ctl instance create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --version=latest --resource=<resource-name> \
  --cloud-provider=byoc-onprem --region=on-prem \
  --customer-account-id=<customer-account-instance-id> \
  --param-file=./params.json --wait
```

`byoc-onprem` / `on-prem` are fixed CLI identifiers — pass them verbatim.

### Local testing (k3d / k3s installer flags)

The same install kit can spin up a local test cluster (skip these flags in
production — the customer installs into their existing cluster):

```bash
# Fully local smoke test:
./install.sh --create-k3d-cluster <cluster-name> --non-interactive

# Single-node K3s advertising a public IP (to validate a PUBLIC endpoint Plan):
PUBLIC_IP=<node-public-ip>
./install.sh --create-k3s-cluster <cluster-name> \
  --k3s-node-external-ip "${PUBLIC_IP}" --non-interactive
```

### Spec implications (INTERNAL endpoints, `internalClusterEndpoint`)

For a customer cluster you typically expose the product on an **internal**
endpoint using the `$sys.network.internalClusterEndpoint` system variable:

```yaml
services:
  - name: postgresChart
    network:
      ports:
        - 5432
    endpointConfiguration:
      postgresEndpoint:
        host: "$sys.network.internalClusterEndpoint"
        ports:
          - 5432
        primary: true
        networkingType: INTERNAL
```

For a public endpoint Plan, use `$sys.network.externalClusterEndpoint` with
`networkingType: PUBLIC` instead.

### Limitations

- The customer cluster must have **outbound** connectivity to your control plane — BYOC-K8s is **NOT** for air-gapped environments (use the air-gapped installer instead).
- Each customer onboarding instance maps to **one** Kubernetes cluster.
- Endpoint reachability depends on the customer's DNS, firewall, load balancer, and routing.

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
control-plane access. The installer supports at most **one Helm chart resource**
and **one image registry** per Plan; bundle multiple charts into an umbrella chart.

### Spec syntax (`requirements.k8sVersion`, `onPremDeployment` fields)

Source: `air-gapped-helm-charts.md`. The `onPremDeployment` block uses UpperCamel
with an `Aws` prefix on **both** fields (note: `AwsBootstrapRoleAccountArn`, *not*
`AWSBootstrapRoleAccountArn` — this differs from the hosted ServicePlanSpec block):

```yaml
name: My Application
deployment:
  requirements:
    k8sVersion: ">=1.30.0"   # optional: minimum K8s version on the target cluster
  onPremDeployment:
    # AWS account that hosts the installer artifacts
    AwsAccountId: '<your-aws-account-id>'
    AwsBootstrapRoleAccountArn: 'arn:aws:iam::<your-aws-account-id>:role/omnistrate-bootstrap-role'
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
    AwsAccountId: '<your-aws-account-id>'
    AwsBootstrapRoleAccountArn: 'arn:aws:iam::<your-aws-account-id>:role/omnistrate-bootstrap-role'
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
SDKs assume the license is there. SDKs: Go
(`omnistrate-oss/omnistrate-licensing-sdk-go`) and Java
(`omnistrate-oss/omnistrate-licensing-sdk-java`).

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
omctl login

omctl deployment-cell adopt \
  --cloud-provider aws \
  --description "adopted cluster" \
  --id "cluster-1" \
  --region us-east-1 \
  --customer-email alok+drprod@omnistrate.com

# Installs the agent (extract cluster-1.tar and apply the manifests per the kit README),
# then check status until it leaves PENDING_ADOPTION:
omctl deployment-cell status --id cluster-1
```

`PENDING_ADOPTION` means the cluster is registered but waiting for the agent to
install and connect. An adopted/imported cell reports `$sys.deploymentCell.isImported`
= `true`, which you can use to condition amenities.

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
