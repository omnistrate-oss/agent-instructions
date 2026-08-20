# BYOC-K8s Reference (customer-managed Kubernetes)

Use this reference when the deployment target is a Kubernetes cluster **the
customer already owns and operates** — EKS/AKS/GKE, OpenShift, Rancher, k3s,
bare-metal, or edge — and that cluster is allowed **outbound** network access to
your control plane.

Core rule: BYOC-K8s is a **BYOC plan** (`deployment.byoaDeployment`) deployed with
`--cloud-provider byoc-onprem --region on-prem`. Omnistrate provisions **no
infrastructure** here — no nodes, no VPC, no load balancer, no StorageClass. It
deploys and operates *workloads* in a cluster it does not own, through the
dataplane agent.

Second core rule: **the spec must be a ServicePlanSpec.** Docker Compose is not a
BYOC-K8s path. A compose spec with `byoaDeployment` validates, builds, produces a
plan with `tenancy_type: BYOA`, and is accepted by `instance create
--cloud-provider byoc-onprem` — then never deploys, leaving the instance in
`DEPLOYING` with **its namespace never created** and no error anywhere. An empty
instance namespace on `byoc-onprem` is the signature of a compose spec, not of a
cluster, agent or amenity fault. Bundle the workload into a Helm chart first
(`HELM_ONBOARDING_REFERENCE.md`).

Deployment-model selection (which of hosted / BYOC-Account / BYO-VPC /
PrivateLink / BYOC-K8s / air-gapped to offer) lives in
`DEPLOYMENT_MODELS_REFERENCE.md`. This file is the operational depth for BYOC-K8s
once that choice is made.

---

## The two "bring your own Kubernetes" paths — do not conflate them

Both put an Omnistrate `dp-agent` into a cluster you do not own. They are not the
same feature and are not interchangeable.

| | **BYOC-K8s** (`byoc-onprem`) | **Adopted deployment cell** |
|---|---|---|
| What it is | A **customer-facing deployment model** | A **provider-fleet operation** |
| Unit of onboarding | One customer onboarding instance per customer cluster | One deployment cell per cluster |
| Command | `omctl account customer create --cluster-name ...` | `omctl deployment-cell adopt --id ... --cloud-provider ... --region ...` |
| Bound to | A service + environment + **plan** | Your fleet (optionally attributed to a customer via `--customer-email`) |
| Customer subscribes and self-serves | Yes | No |
| Covered in | This file, §Onboarding onward | This file, §Adopted deployment cells |

If the user says "our customers bring their own cluster and subscribe to our
service" → BYOC-K8s. If they say "we already run clusters we want Omnistrate to
schedule onto" → adopted cell. Ask when it is ambiguous; do not default.

---

## BYOC-K8s vs air-gapped — the disambiguation that matters most

This is the single most common modelling error. Both involve "the customer's own
Kubernetes" and both involve running a script in that cluster, but they are
opposite ends of the connectivity spectrum and share almost no mechanics.

| | **BYOC-K8s** | **Air-gapped installer** |
|---|---|---|
| Spec block | `deployment.byoaDeployment` | `deployment.onPremDeployment` |
| Control-plane link | **Live** — persistent outbound mTLS/gRPC | **None** after install |
| What the customer runs | **Install kit** — installs the `dp-agent` only | **Installer artifact** — installs the whole product |
| Who deploys the workload | Your control plane, through the agent | The installer script, locally |
| Instance create | `--cloud-provider byoc-onprem --region on-prem` | `--onprem-platform <EKS\|GKE\|AKS\|OpenShift\|Generic>` — and **no** `--cloud-provider` / `--region` |
| Day-2 ops (upgrade, stop/start, backup) | Through your control plane | Re-run the installer / customer-side |
| `instance debug` + `deployment-cell update-kubeconfig` tunnel | **Available** | Not available (no live link) |
| Native logs (`features.INTERNAL.logs.provider: native`) | **Supported** | **Not supported** — cannot reach CloudWatch Logs |
| `VALIDATE` / `PRE_INSTALL` action hooks for cluster preconditions | **Not** the documented mechanism | The documented mechanism |
| Images | Pulled from registries at deploy time (needs egress) | Optionally embedded via `INSTALLER_EMBED` |
| Reference | This file | `ONPREM_INSTALLER_REFERENCE.md` |

> The deciding question is never "is it their Kubernetes?" — it is **"can that
> cluster hold an outbound connection to your control plane?"** Yes → BYOC-K8s.
> No → air-gapped. A customer who *could* allow egress but has not yet decided is
> a BYOC-K8s customer with a firewall ticket, not an air-gapped customer.

---

## Plan spec: the `byoaDeployment` block

BYOC-K8s is configured as a BYOC plan, so its `byoaDeployment` block still carries
provider-side AWS account values even though Omnistrate provisions no AWS infra
in the customer's cluster:

```yaml
name: BYOC OnPrem PostgreSQL
deployment:
  byoaDeployment:
    awsAccountId: '<aws-account-id>'
    awsBootstrapRoleAccountArn: 'arn:aws:iam::<aws-account-id>:role/omnistrate-bootstrap-role'
```

These are the values of the AWS account designated as the **"Control Plane"
account** — the same rule that applies to every `byoaDeployment` variant (see
`DEPLOYMENT_MODELS_REFERENCE.md` §BYOC). Omnistrate uses it to anchor trust and
host generated artifacts (the install kit, chart/registry access). It is
**required by the schema** for a BYOC plan. Ask the user which account that is;
never invent a placeholder.

> **Casing.** The schema spells these `awsAccountId` / `awsBootstrapRoleAccountArn`
> (lowerCamel) — confirmed via `omctl docs plan-spec "Deployment schema"`. Some
> published examples show `AwsAccountId` / `AwsBootstrapRoleAccountArn`; the
> platform decodes through `encoding/json` and matches case-insensitively, so both
> build. Write lowerCamel.

**One plan per deployment model.** A BYOC-K8s plan is a separate plan/spec from
your hosted plan and from your air-gapped plan. Never put `hostedDeployment`,
`byoaDeployment`, or `onPremDeployment` blocks together in one spec.

### Omit `compute` entirely

The minimal skeleton in `HELM_ONBOARDING_REFERENCE.md` leads with
`compute.instanceTypes` carrying `cloudProvider: aws` / `gcp` and a default like
`t4g.small`. On BYOC-K8s **no nodes are provisioned**, so cloud instance types are
meaningless — do not copy them into a `byoc-onprem` plan. `compute` is not
required (`ResourceConfiguration` requires only `name`); a plan omitting it
validates, builds, and deploys. Verified end-to-end.

---

## Trust and connectivity model

The `dp-agent` runs inside the customer cluster and opens **outbound** mTLS/gRPC
connections to your control plane. The same outbound-agent pattern carries the
Manager Service, Infra Metadata Manager, and Monitoring Service channels.

Consequences worth stating explicitly to a security reviewer:

- **The Kubernetes API server is never exposed.** The customer does not open
  inbound firewall rules, does not publish the API server, and does not hand you
  credentials. All control traffic is agent-initiated from inside the cluster.
- **Application traffic is separate from control-plane traffic.** The customer
  decides independently whether product endpoints are private-only, reachable over
  a corporate network, or exposed publicly.
- **Debug access reuses the same channel.** `omctl deployment-cell update-kubeconfig`
  tunnels over the agent connection — no cloud-provider CLI, no bastion. See the
  `omnistrate-sre` skill.

### Egress allowlist to hand the customer

The cluster needs outbound HTTPS to:

| Destination | Why | Needed by |
|---|---|---|
| `*.omnistrate.cloud` | Control-plane / agent connection; without it nothing deploys | Agent install |
| `ghcr.io` | The dataplane agent chart itself is `oci://ghcr.io/omnistrate/dataplane-agent-chart` | **Agent install — before any plan workload exists** |
| `get.helm.sh` | Only if `helm` is not already installed on the operator's machine | Agent install |
| `registry.k8s.io`, `quay.io`, `docker.io`, `ghcr.io` | Deployment-cell amenity images (external-dns, cert-manager, prometheus, grafana, headlamp, dcgm-exporter) | Amenity install |
| Container image registries used by **your plan** | Image pulls at deploy time — images are **not** pre-embedded on BYOC-K8s | Instance deploy |
| Helm chart registries / OCI repos used by **your plan** | Chart pulls at deploy time | Instance deploy |
| Regional AWS CloudWatch Logs endpoint | **Only if** the plan enables native logs — see §Native logs | Runtime |

The first three rows are needed **before your plan is ever involved**, so a
firewall ticket scoped only to your product's registries will fail at agent
install. Add your plan's actual registries to the generic list above — image-pull
failures on BYOC-K8s are almost always a missing allowlist entry.

### What lands in the customer's cluster automatically

Once the agent connects, the control plane installs the deployment-cell amenity
stack into the customer's cluster **without further prompting**. A real run
produced 8 Helm releases across 6 new namespaces within ~4 minutes:

| Release | Namespace |
|---|---|
| `cert-manager` (installs cluster-scoped CRDs) | `cert-manager-ns` |
| `external-dns` | `external-dns-ns` |
| `nginx-reverse-proxy` (cluster-wide ingress controller) | `nginx-reverse-proxy-ns` |
| `prometheus-server` (kube-prometheus-stack) | `observability-ns` |
| `grafana` + `grafana-postgres` (Grafana with its own PostgreSQL) | `observability-ns` |
| `nvidia-dcgm-exporter` (installed even with no GPUs present) | `observability-ns` |
| `headlamp` | `headlamp-ns` |

Plus a `monitoring-endpoints` namespace. That one is **not an amenity and cannot
be trimmed** — it is applied as raw manifests, independent of the template, and
holds a 2-replica `endpoint-monitoring-agent` Deployment plus a secret and a
configmap. Together with `dp-agent` it is the irreducible platform footprint on a
customer cluster.

**Disclose the amenity list at intake.** A security reviewer evaluating "you only
deploy workloads in our cluster" will ask about cluster-scoped CRDs and a
cluster-wide ingress controller, and being surprised by it late is how BYOC-K8s
deals stall.

You can cut this to **zero amenities** — see the next section.

---

## Trimming the amenity footprint (BYOC-K8s cells only)

Deployment-cell config templates are scoped **per cloud provider**, and
`byoc-onprem` is a first-class provider for them. That scoping *is* the
BYOC-K8s-only condition — you do not need a `disable:` expression, and your
AWS/GCP/Azure/Nebius cells are structurally untouched:

```bash
omctl deployment-cell generate-config-template --cloud byoc-onprem --output tmpl.yaml
# edit tmpl.yaml down to the minimum set, then:
omctl deployment-cell update-config-template --environment GLOBAL --cloud byoc-onprem -f tmpl.yaml
omctl deployment-cell describe-config-template --cloud byoc-onprem      # confirm it took
```

**Trim with `disable: "true"`, keeping every entry in the list.** Deleting entries
looks like the obvious move and is wrong — the API rejects deletion of Cert
Manager, and every "empty" form is a silent no-op. Verified on the live platform:

| Form | Result |
|---|---|
| `disable: "true"` on an entry | **Works.** Round-trips through `describe-config-template` and the raw API |
| Deleting the Cert Manager entry | **Rejected** — `amenity 'Cert Manager' cannot be removed, it is a required managed amenity` |
| Deleting the other six entries | Accepted — but `disable` is simpler and uniform |
| `skip: true` | **Silently ignored.** `Skip` is an internal-only field, absent from the CLI's Amenity struct *and* from the public OpenAPI schema (`[DependsOn, Description, Disable, IsManaged, Name, Properties, Type]`). The YAML key is dropped at parse time and the amenity installs normally |
| `managedAmenities: []`, `null`, `customAmenities: []`, a 0-byte file | **Silent no-ops** on the org template. (The CLI's `Configuration file is empty - removing all amenities` message applies only to the per-cell `--id` path) |

`disable` takes a **rendered expression**, so a literal must be the quoted string
`"true"` — it is parsed with `strconv.ParseBool`, and a value that renders to a
non-boolean is a hard error. Disabled amenities are filtered out by
`removeDisabledAmenities` before the reconciler builds its map, so
`ShouldInstallManagedAmenity` then returns false via `!exists`.

> After **every** template update, re-read with `describe-config-template`. Between
> the silent no-ops and the dropped `skip` key, "Successfully updated organization
> template" is not evidence that anything changed.

### Start here: zero amenities, and no endpoints in the spec

The amenity floor and the plan spec are **coupled**. External DNS is only needed
because an `endpointConfiguration` creates an endpoint that must become healthy
before the Monitoring workflow step completes. A plan that declares **no**
`endpointConfiguration` has no endpoint to monitor, so it needs no DNS record, so
it needs no External DNS amenity.

So the smallest working starting point is an **all-disabled** template paired with
a spec that declares no endpoints — the same zero-first philosophy this skill
applies to API parameters:

```yaml
# byoc-onprem GLOBAL amenity template — zero amenities.
# Apply BEFORE onboarding the cluster (see the bootstrap-only rule below).
# Keep all seven entries LISTED — the API blocks removing Cert Manager, but
# disabling it is allowed. `disable` suppresses installation.
managedAmenities:
    - name: Observability Prometheus
      description: Observability Prometheus
      type: Helm
      disable: "true"
    - name: External DNS
      description: External DNS
      type: Helm
      disable: "true"
    - name: Cert Manager
      description: Cert Manager
      type: Helm
      disable: "true"
    - name: Nginx Ingress Controller
      description: Nginx Ingress Controller
      type: Helm
      disable: "true"
    - name: Cost Insight Prometheus
      description: Cost Insight Prometheus
      type: Helm
      disable: "true"
    - name: NVIDIA DCGM Exporter
      description: NVIDIA DCGM Exporter
      type: Helm
      disable: "true"
    - name: Headlamp
      description: Headlamp Kubernetes Dashboard
      type: Helm
      disable: "true"
```

This drops **all 7** amenities. Pair it with a spec that has **no
`endpointConfiguration` block and no endpoint monitoring**, and install with
`./install.sh --non-interactive --skip-nginx-validation` — validated with **no
LoadBalancer present on the cluster at all**.

Measured result on a real cell — no `cert-manager-ns`, **zero CRDs cluster-wide**,
`dp-agent` the only platform Helm release, and the workload RUNNING in ~32 s:

```
STEP Bootstrap    success   20:11:07Z -> 20:11:30Z  (23s)
STEP Deployment   success   20:11:11Z -> 20:11:30Z  (19s)
STEP Monitoring   success   20:11:30Z -> 20:11:30Z  (0s)
```

Nothing timed out at bootstrap waiting for an amenity that never installs.

> **Version dependency — check this if it hangs.** Older control planes run an
> unconditional `CreateCertificate` step that needs the
> `certificates.cert-manager.io` CRD. On such a build a zero-amenity cell **hangs
> forever in the Deployment step**, retrying `CreateCertificate` with no fast-fail
> while the pod sits `1/1 Running` — and it fires even with no
> `endpointConfiguration`. Both behaviours were observed on the same account hours
> apart, so this is a platform-version boundary, not a config difference. If you
> see that hang, re-onboard with **Cert Manager enabled** (drop its `disable`
> line); that intermediate floor is separately validated and reaches RUNNING in
> ~3 min.

The canonical first spec — validated end-to-end, reached RUNNING in 2m17s:

```yaml
name: byock8s-min
deployment:
  byoaDeployment:
    awsAccountId: '<control-plane-aws-account-id>'
    awsBootstrapRoleAccountArn: 'arn:aws:iam::<id>:role/omnistrate-bootstrap-role'

services:
  - name: podinfo
    network:
      ports:
        - 9898
    helmChartConfiguration:
      chartName: podinfo
      chartVersion: 6.14.1
      chartRepoName: podinfo
      chartRepoURL: https://stefanprodan.github.io/podinfo
      chartValues:
        service:
          type: ClusterIP
```

`network.ports` is fine to keep — **only `endpointConfiguration` has to go**. Note
there is no `compute` block either (no nodes are provisioned; see §Omit `compute`).

> **Why this works, measured.** With no endpoint declared, the Monitoring workflow
> step ran **0 seconds** (`15:34:44Z → 15:34:44Z`) — it has no DNS record to wait
> on. The same plan *with* an endpoint, on a cell that has External DNS, spent 9s
> in Monitoring. Endpoint DNS resolution is the only blocking work that step does,
> which is exactly why a no-endpoint plan needs no External DNS.

**Then add capability only when the user asks for it**, in this order:

| The user wants… | Add to the template | Add to the spec |
|---|---|---|
| TLS certificates for endpoints | **Cert Manager** (drop its `disable` line) | — |
| A reachable INTERNAL endpoint | **External DNS** | `endpointConfiguration` + the `external-dns.alpha.kubernetes.io/internal-hostname` annotation (§Endpoints) |
| A PUBLIC endpoint / web UI | **+ Nginx Ingress Controller** (and a real LoadBalancer) | `networkingType: PUBLIC` on `externalClusterEndpoint` |
| Metrics + dashboards | **+ Observability Prometheus** | `features.CUSTOMER.metrics` |
| GPU metrics | **+ NVIDIA DCGM Exporter** (needs Prometheus) | — |
| A cluster UI | **+ Headlamp** (needs External DNS + Cert Manager + Nginx) | — |

Adding amenities to a **live** cell works; removing them does not. So starting
small and growing is the safe direction — starting big and trimming is not.
Validated: adding External DNS to a running Cert-Manager-only cell
(`--sync-with-template` → `1 → 2 amenities`, then `apply-pending-changes --force`)
had external-dns Running on the cluster **~40 s later**, after which an
endpoint-bearing instance reached RUNNING with a HEALTHY endpoint.

### The `CreateCertificate` hang (older control planes)

**Zero amenities is not a working configuration.** This was tested directly: with
all seven disabled, the cell onboarded cleanly and reached READY, the target
footprint was achieved exactly (only `dp-agent` + `monitoring-endpoints`, no CRDs
at all) — and then **no workload could ever deploy**.

The instance stuck in the **Deployment** step, on `CreateCertificate`, retrying
forever with no fast-fail:

```
STEP Bootstrap    success      19:34:43 -> 19:34:46
STEP Deployment   in-progress  19:34:46 -> (never)
   19:35:10 CreateHelmPackage  Completed
   19:35:43 CreateCertificate  Running | activity StartToClose timeout, retry checking.
   19:38:23 CreateCertificate  Running | activity StartToClose timeout. Previous failed... Retry checking.
```

The pod was `1/1 Running` in-cluster the whole time. Root cause: no
`certificates.cert-manager.io` CRD exists, so `CreateCertificate` can never
succeed. It never reaches Monitoring.

**This fires even with no `endpointConfiguration`** — `network.ports` alone is
enough to trigger certificate creation.

**On current builds this is fixed**: `CreateCertificate` no longer runs, and the
same zero-amenity cell reaches RUNNING in ~32 s. Both behaviours were observed on
the same account hours apart, so treat it as a platform-version boundary. The
diagnostic shape is worth remembering because it is so misleading — agent
connected, account READY, pod `1/1 Running`, and the instance permanently
`DEPLOYING` with no error. If you hit it, re-onboard with **Cert Manager enabled**
(drop its `disable` line); that intermediate floor is separately validated and
reaches RUNNING in ~3 min.

### Disable Cert Manager, never delete it

The API rejects *deleting* the Cert Manager entry, in
`commons/model/common/common.go` inside `ValidateManagedAmenitiesList`:

```go
if !isBYOCOnPrem {                       // a byoc-onprem exemption exists in source
    for name := range currentMap {
        if _, exists := pendingMap[name]; !exists {
            if name == constants.ManagedAmenityCertManagerName {
                err = errors.Errorf("amenity '%s' cannot be removed, it is a required managed amenity", name)
```

The `isBYOCOnPrem` exemption is present in source but **was not live** at last
test — deletion still returns that error. Do not depend on it.

You do not need to: **`disable: "true"` is not a removal**, so the guard never
fires, and a disabled Cert Manager is not installed. That is why the recommended
template keeps all seven entries listed — and it means this guidance works on both
sides of that rollout.

### What is actually irreducible

Two things land on the customer's cluster regardless of the template:

| Component | Namespace | Notes |
|---|---|---|
| `dp-agent` | `dataplane-agent` | Installed by the install kit, not as an amenity |
| `endpoint-monitoring-agent` | `monitoring-endpoints` | 2 replicas, image `ghcr.io/omnistrate/endpoint-monitor-agent`; applied as **raw manifests**, not a Helm release; not an amenity, not disableable |

So "zero amenities" means two platform workloads and **zero CRDs** — not an empty
cluster. Use that pair, not "nothing", when describing the footprint to a customer
security reviewer.

### Three rules this mechanism will break on

**1. If the plan declares endpoints, External DNS is mandatory.** Dropping it while
an `endpointConfiguration` exists leaves the instance hung in Monitoring
**forever**: Bootstrap and Deployment both `success`, pod `1/1 Running`, in-cluster
`curl .../healthz` returning 200, the Service carrying the correct annotation —
and the endpoint `UNHEALTHY` because `dig` finds no record. Installing external-dns
was the only subsequent change; its first reconcile picked up the pre-existing
Service, created the record, and the instance went RUNNING within ~90 s. It
recovered on its own, no redeploy. **Keep the template and the spec in step: no
endpoints ⇒ no External DNS; endpoints ⇒ External DNS.**

**2. Every "empty" form, and `skip: true`, fail silently.** `managedAmenities: []`,
a null list, `customAmenities: []`, and even a 0-byte file all print
`Successfully updated organization template` and change **nothing** — you get a
success message and the full 7-amenity stack. `skip: true` is worse: it parses
without complaint and is discarded, because `Skip` exists only internally and is
absent from both the CLI struct and the public API schema. Use `disable: "true"`
and always re-read with `describe-config-template`.

**3. The allow-list only takes effect at cell bootstrap.** Set the reduced
template **before** onboarding the cluster. On an already-connected cell,
*additions* reconcile in ~40–90 s but **removals do not happen at all** — the sync
workflow reports `SUCCESS` while the Helm release sits untouched at revision 1.
There is no supported way to retro-trim a live cell; re-onboard instead.

### Syncing a template to an already-connected cell (additions only)

```bash
omctl deployment-cell update-config-template --id <hc-id> --sync-with-template
omctl deployment-cell apply-pending-changes  --id <hc-id> --force
```

> **Getting `<hc-id>` right.** `deployment-cell list` displays a BYOC-K8s cell as
> `byoc-onprem-instance-<...>`, and passing that returns
> `forbidden: not authorized to describe cluster`. Get the real `hc-*` id from the
> instance:
> ```bash
> omctl instance describe <instance-id> -o json | jq -r .deploymentCellID
> ```

### `disable:` is install-time only

`disable:` decides whether an amenity gets **installed**; it does not uninstall one
that already exists. Setting `disable: "true"` on an already-installed amenity
leaves it running. That is why the template must be set **before** onboarding —
and why the growth direction (enable more later) works while the trim direction
(disable something already installed) does not.

Two further notes on the expression itself:

- It is a rendered expression parsed with `strconv.ParseBool`, so a literal must be
  the **quoted string** `"true"`. Anything that renders to a non-boolean is a hard
  error, not a silent skip.
- The idiom `disable: $sys.deploymentCell.isImported` **does not fire on BYOC-K8s**:
  a cell onboarded via `account customer create` + install kit reports
  `isImported: false`. That flag distinguishes *adopted* cells, not customer-owned
  ones.

---

## Target-cluster prerequisites

| Requirement | Details | Enforced |
|---|---|---|
| Kubernetes cluster | A working cluster on a supported Kubernetes version | — |
| `kubectl` access | The operator running the install kit must target the intended cluster context | — |
| `helm` **v3.12+** | On the machine running the install kit | Kit README |
| Pod networking | CNI and pod-to-pod networking must work | — |
| DNS and egress | Pods must resolve and reach the destinations in the allowlist above | Agent connect |
| **A LoadBalancer implementation** | The installer provisions an nginx reverse-proxy amenity and **hard-fails** without one (MetalLB, ServiceLB, cloud LB controller…) | **Install-time preflight** |
| **Ports 80 and 443 free** | Not already reserved on the cluster | **Install-time preflight** |
| **IngressClass `nginx` unowned** | Fails if `nginx` exists and is not owned by the Omnistrate nginx reverse-proxy release | **Install-time preflight** |
| Storage | Required StorageClasses must **already exist** if the plan uses persistent volumes | Runtime (PVCs stay Pending) |
| Endpoint path | Ingress, load balancer, firewall, and DNS routing must match the endpoint exposure the plan defines | Runtime |

> **"Omnistrate provisions no infrastructure" applies to your plan's workloads, not
> to the agent install.** The install kit's preflight requires working LoadBalancer
> support, free ports 80/443, and an unowned `nginx` IngressClass before it will
> proceed. Run `./install.sh --validate-only` first — it checks access, RBAC, ports,
> and LB support in one command and will catch all three before you commit to an
> install.
>
> All three exist to serve the **Nginx Ingress amenity**. If the plan only exposes
> INTERNAL endpoints, drop that amenity (§Trimming the amenity footprint) and pass
> `--skip-nginx-validation`; the LoadBalancer / ports / IngressClass requirements
> then genuinely do not apply. The preflight is unconditional, so the flag is still
> required.

### Surfacing prerequisites to the customer

These are the customer's responsibility and the plan **cannot auto-provision them**
on a cluster Omnistrate does not own. Two mechanisms, in order of preference:

1. **Deployment-cell amenities** — for anything installable once per cell
   (ingress controller, cert-manager, monitoring, logging, custom Helm packages).
   This is the supported way to get cluster-level components in place.
2. **Customer Portal onboarding instructions + the deployment overview** — for
   hard preconditions you cannot install for them.

> The `VALIDATE` / `PRE_INSTALL` `actionHooks` that assert cluster preconditions
> are documented for the **air-gapped installer** path, **not** for BYOC-K8s. So on
> BYOC-K8s a missing prerequisite surfaces as a stuck instance, not a clean
> pre-flight error. State hard requirements loudly in onboarding instructions —
> e.g. *"a default StorageClass must exist, or PVCs stay Pending and the instance
> never reaches RUNNING."* If you need a per-instance precondition check on
> BYOC-K8s, run `omctl docs search` for a current mechanism before assuming one
> exists.

---

## Onboarding a customer cluster

One customer onboarding instance represents **one** Kubernetes cluster. Passing
`--cluster-name` (instead of a cloud-account flag such as `--aws-account-id`) is
what selects the BYOC On-Premise path.

`account customer create` **automatically downloads the install kit into the
current directory**, so create a working directory first.

```bash
mkdir -p dp-install-kit && cd dp-install-kit

omnistrate-ctl account customer create \
  --service=<service-name> \
  --environment=<environment-name> \
  --plan=<plan-name> \
  --cluster-name=<customer-cluster-name> \
  --cluster-description="Customer production Kubernetes cluster"
```

| Flag | When |
|---|---|
| `--cluster-name` | **Required** — selects the BYOC On-Premise path |
| `--cluster-description` | Optional label |
| `--cluster-region` | Optional onboarding region / location label; **defaults to `on-prem`** |
| `--customer-email` | **Production** — onboards on the end customer's subscription. Omit in dev and the command uses the calling user's subscription |

Save the returned onboarding instance ID (e.g. `instance-abc123`). The command
**does not wait** for the instance to become `READY` — it cannot, because nothing
has been installed in the cluster yet.

Then install the agent, with `kubectl` pointed at the intended cluster. The kit
tarball is named `byoc-onprem-install-kit-<account-config-id>.tar` and extracts
**flat** — `install.sh` lands in the current directory, not a subdirectory:

```bash
tar xf byoc-onprem-install-kit-<account-config-id>.tar
kubectl config current-context          # confirm this is the intended cluster
./install.sh --validate-only            # preflight: access, RBAC, ports, LB support
./install.sh --non-interactive
```

The installer creates the dataplane-agent resources only. Amenities and product
workloads are installed later, by your control plane, over the agent connection —
see §What lands in the customer's cluster automatically.

Poll until the account configuration reports `READY`. The status is at
**`.summary.account_status`** — a top-level `.account_status` does not exist, and
polling for it silently never matches:

```bash
omnistrate-ctl account customer describe <customer-account-instance-id> \
  -o json | jq -r '.summary.account_status'
```

States you will see: **`VERIFYING`** → **`READY`** (and later
**`READY_TO_OFFBOARD`** during teardown — see §Offboarding). Expect roughly
**5–10 minutes** from agent install to `READY`; the amenity stack takes a further
~4 minutes after that.

### Handing the install to a real customer

The kit's `result_params.byoc_onprem_install_command` is a one-liner that
downloads, extracts, and installs in a single step — this is what belongs in an
ISV's customer runbook rather than the manual tarball dance:

```bash
bash -c 'd=$(mktemp -d) && curl -fsSL "https://api.omnistrate.cloud/2022-09-01-00/account-setup/byoc-onprem?account_config_id=<account-config-id>" | tar -xf - -C "$d" && bash "$d/install.sh"'
```

To re-download the kit later (reinstall, recovery, a rebuilt cluster):

```bash
omnistrate-ctl account customer install-kit <customer-onboarding-instance-id>
omnistrate-ctl account customer install-kit <id> --output-path /tmp/kit.tar   # optional path
```

---

## Deploying an instance

```bash
omnistrate-ctl instance create \
  --service=<service-name> --environment=<environment-name> \
  --plan=<plan-name> --version=latest --resource=<resource-name> \
  --cloud-provider=byoc-onprem --region=on-prem \
  --customer-account-id=<customer-account-instance-id> \
  --wait                                  # --param-file=./params.json if the plan takes parameters
```

`byoc-onprem` and `on-prem` are fixed identifiers — pass them verbatim.
`--customer-account-id` takes the **onboarding instance ID** (`instance-...`) from
the previous step, not a cloud account number. `--param-file` is optional — a
zero-parameterization plan needs no params file.

> **`--cloud-provider=byoc-onprem` is accepted — the help text is stale.**
> Verified end-to-end (2026-08): the command is accepted without warning and the
> value is echoed back (`cloud_provider: byoc-onprem`, `region: on-prem`), even
> though `omnistrate-ctl instance create --help` still enumerates
> `aws|gcp|azure|nebius`. The same CLI treats `byoc-onprem` as a first-class
> provider elsewhere — `account customer create` returns
> `cloudProvider: byoc-onprem` and `omctl workflow list` prints it too. Do not
> "correct" a spec or command away from `byoc-onprem` on the strength of the help
> enum.

Do **not** pass `--onprem-platform` here. That flag selects the *air-gapped*
installer path and is mutually exclusive with `--cloud-provider` / `--region`.

---

## Local testing without a customer cluster

The same install kit can create a throwaway cluster. Production customers install
into their existing cluster and skip these flags entirely.

```bash
# Fully local smoke test (k3d):
./install.sh --create-k3d-cluster <cluster-name> --non-interactive

# Single-node k3s advertising a public IP, to validate a PUBLIC endpoint plan:
PUBLIC_IP=<node-public-ip>
./install.sh --create-k3s-cluster <cluster-name> \
  --k3s-node-external-ip "${PUBLIC_IP}" --non-interactive
```

For any other local distribution (kind, minikube, Docker Desktop, an existing dev
cluster), there is no dedicated flag — create the cluster yourself, point
`kubectl` at it, and run the plain `./install.sh --non-interactive`. That is the
same path a real customer takes, and is the better rehearsal.

> **A stock `kind` cluster fails the preflight.** kind ships no LoadBalancer
> implementation, so the nginx reverse-proxy check hard-fails:
> `LoadBalancer validation failed: a temporary LoadBalancer service on ports 80
> and 443 did not receive an address.` Two ways through, and the second is
> usually better:
>
> 1. Install **MetalLB** (or `cloud-provider-kind`) first — the plain command then
>    succeeds.
> 2. **Drop the Nginx Ingress amenity** (see §Trimming the amenity footprint) and
>    run `./install.sh --non-interactive --skip-nginx-validation`. Validated: with
>    the amenity omitted and that flag set, **no LoadBalancer implementation is
>    needed at all** — the cell reaches READY and serves a working INTERNAL-endpoint
>    instance.
>
> The preflight itself is **unconditional** — it does not consult the org template,
> so disabling the amenity does not relax the check; you still need the flag. But
> the underlying LoadBalancer requirement is an *nginx-amenity* requirement, not a
> cell requirement. The same applies to any bare cluster with no LB controller.

### install.sh flags worth knowing

| Flag | Effect |
|---|---|
| `--validate-only` | Preflight only — access, RBAC, ports, LB support. **Run this first.** |
| `--non-interactive` | Suppress prompts. **Interactive is the default on a TTY**, so unattended scripts that omit this will block |
| `-i` / `--interactive` | Force prompts |
| `--skip-nginx-validation` | Bypass the LoadBalancer/ingress preflight (see warning above) |
| `--create-k3d-cluster` / `--create-k3s-cluster` / `--k3s-node-external-ip` | Test-cluster creation, as above |

Env equivalents exist for the same options: `BYOC_ONPREM_K3D_CLUSTER`,
`BYOC_ONPREM_K3S_CLUSTER`, `BYOC_ONPREM_K3S_NODE_EXTERNAL_IP`,
`BYOC_ONPREM_SKIP_NGINX_VALIDATION`, `BYOC_ONPREM_PROXY_WAIT_SECONDS`,
`BYOC_ONPREM_INTERACTIVE`.

---

## Endpoints

Omnistrate provisions **no cloud load balancer** on a customer-managed cluster.
The customer owns ingress, DNS, and endpoint exposure. This changes how endpoints
are modelled.

### Start with no endpoints at all

**Do not put an `endpointConfiguration` block — or any endpoint monitoring — in the
first BYOC-K8s spec you build.** Declaring an endpoint creates something that must
become *healthy* before the instance can reach RUNNING, and on BYOC-K8s that health
depends on the customer's DNS, the External DNS amenity, and a correct
chart-specific annotation. Every one of those is a way for a first deployment to
hang with no error message.

Get the workload deploying first with no endpoints. This is the same
zero-parameterization discipline this skill applies elsewhere: prove the simple
thing works, then add surface area deliberately.

**Add endpoints when the user asks for a reachable endpoint** — and when you do,
add the External DNS amenity in the same change (§Trimming the amenity footprint).
The rest of this section is for that step.

### CRITICAL: `endpointConfiguration` does not create the DNS record

`endpointConfiguration` **declares** a hostname; it does not publish one. The
record is created by the cell's `external-dns`, which only acts on a Service that
carries an external-dns annotation. Omit the annotation and you get the worst
possible failure mode, confirmed on a real run:

- the Deployment workflow step goes **green**,
- the pod is **Running** and the Helm release **deployed**,
- the endpoint sits **UNHEALTHY**, and
- the **Monitoring step never completes** — the instance hangs in `DEPLOYING`
  indefinitely with nothing in any log saying why.

On BYOC-K8s the annotation must be **`internal-hostname`**, not `hostname`:

```yaml
      chartValues:
        service:
          type: ClusterIP
          annotations:
            external-dns.alpha.kubernetes.io/internal-hostname: $sys.network.internalClusterEndpoint
```

`external-dns.alpha.kubernetes.io/hostname` — the annotation shown in the
LoadBalancer/PUBLIC examples in `HELM_ONBOARDING_REFERENCE.md` — **does not work
for a ClusterIP Service**. The cell runs external-dns without
`--publish-internal-services`, so it skips ClusterIP Services annotated with
plain `hostname`. `internal-hostname` is what publishes a ClusterIP.

This is the single most common way a BYOC-K8s plan silently fails. Adding the
annotation took a hung instance to `RUNNING` in 90 seconds.

> **Do not assume the Service annotation is the only route — check the cell's
> actual sources.** A cell observed in 2026-08 ran external-dns with **both**
> `--source=service` **and** `--source=ingress`, so an **Ingress** also gets its
> host published automatically. Read the flags rather than trusting this file:
>
> ```bash
> kubectl get deploy -n external-dns-ns \
>   -o jsonpath='{.items[0].spec.template.spec.containers[0].args}' | tr ',' '\n'
> ```
>
> Look for `--source=...` (which object kinds publish records) and
> `--domain-filter=...` (**records are only created for hostnames under this
> domain** — an Ingress host outside the filter is silently ignored). When
> `--source=ingress` is present, the Ingress route in §HTTP/HTTPS applications is
> simpler and needs no Service annotation at all.

### Internal (the common case)

```yaml
services:
  - name: podinfo
    network:
      ports:
        - 9898
    endpointConfiguration:
      podinfoEndpoint:
        host: "$sys.network.internalClusterEndpoint"
        ports:
          - 9898
        primary: true
        networkingType: INTERNAL
    helmChartConfiguration:
      chartName: podinfo
      chartVersion: 6.14.1
      chartRepoName: podinfo
      chartRepoURL: https://stefanprodan.github.io/podinfo
      chartValues:
        service:
          type: ClusterIP
          annotations:
            external-dns.alpha.kubernetes.io/internal-hostname: $sys.network.internalClusterEndpoint
```

The `service.type` / `service.annotations` value paths are **chart-specific** —
confirm with `helm show values`. What generalises is: ClusterIP + the
`internal-hostname` annotation carrying `$sys.network.internalClusterEndpoint` +
an INTERNAL `endpointConfiguration` on the same value.

### Public

Use `$sys.network.externalClusterEndpoint` with `networkingType: PUBLIC`. This
only resolves to something usable if the customer has actually arranged external
exposure (e.g. the k3s `--k3s-node-external-ip` case above, or their own LB).

### HTTP/HTTPS applications

For a web application (Harbor, GitLab, webhook.site, an admin UI), plan-level
`loadBalancers.https` expects a platform-managed cloud LB and is **not** the
mechanism here. There are two routes. **Prefer the Ingress route** — it is
simpler, needs no customer-supplied hostname, and yields a working *public*
HTTPS URL.

#### Route A (preferred): chart-created Ingress on the cell's nginx amenity

Available when the cell has the **Nginx Ingress Controller** amenity and
external-dns runs with **`--source=ingress`** (verify both — see the box in
§CRITICAL above). The amenity's controller is a `LoadBalancer` Service holding
the node's public IP, so it is already the cluster's public entry point; a bare
`curl http://<node-ip>/` returning **404** confirms it is answering and merely
has no matching Ingress yet.

1. Keep the app's Service **ClusterIP** — no Service annotation needed on this
   route.
2. Have the chart create an **Ingress** whose host is
   `$sys.network.externalClusterEndpoint` and whose `ingressClassName` matches
   the amenity's IngressClass (`nginx`). Creating the Ingress is what triggers
   external-dns to publish the public DNS record.
3. Declare a **PUBLIC** `endpointConfiguration` on the same hostname.
4. Add TLS by referencing the platform-provisioned certificate secret — see
   §TLS below. Public HTTPS costs one `tls:` block.

```yaml
services:
  - name: webhooksite
    network:
      ports:
        - 80
    endpointConfiguration:
      webhookEndpoint:
        host: "$sys.network.externalClusterEndpoint"
        ports:
          - 80
        primary: true
        networkingType: PUBLIC
    helmChartConfiguration:
      chartName: webhook-site
      chartVersion: 0.2.1
      chartRepoName: my-charts
      chartRepoURL: oci://ghcr.io/<org>/charts
      chartValues:
        ingress:
          enabled: true
          className: nginx
          host: $sys.network.externalClusterEndpoint   # bare $sys — whole value
          tls:
            enabled: true
            secretName: google-public-ca-tls          # see §TLS
```

The `ingress.*` value paths are **chart-specific** — that example assumes a chart
that exposes them. What generalises: ClusterIP Service + an Ingress whose host is
`$sys.network.externalClusterEndpoint` under the cell's `--domain-filter`, plus a
PUBLIC `endpointConfiguration` on the same value.

#### Route B: customer's pre-existing ingress, hostname supplied by the customer

Use when the cell has **no** nginx amenity, external-dns lacks
`--source=ingress`, or the customer insists on routing through their own
controller with their own DNS.

1. Set the chart's Service type to **ClusterIP** — **and annotate it** per the
   section above.
2. Let the **customer's own ingress controller** route to that ClusterIP.
3. Surface the endpoint as **INTERNAL** on `$sys.network.internalClusterEndpoint`,
   and take the externally-resolvable hostname as a **customer-supplied `String`
   apiParameter** — no `$sys.*` value can resolve to the customer's own ingress
   hostname.

```yaml
services:
  - name: harborChart
    apiParameters:
      - key: externalURL
        name: External URL
        description: The URL customers use to reach the app via their own ingress/DNS
        type: String
        modifiable: true
        required: true
        export: true
    network:
      ports:
        - 8080
    endpointConfiguration:
      internal:
        host: "$sys.network.internalClusterEndpoint"
        ports:
          - 8080
        primary: true
        networkingType: INTERNAL
    helmChartConfiguration:
      chartName: harbor
      chartVersion: 1.15.0
      chartRepoName: harbor
      chartRepoURL: https://helm.goharbor.io
      chartValues:
        expose:
          type: clusterIP        # chart-specific key — no platform cloud LB on BYOC-K8s
          clusterIP:
            annotations:
              external-dns.alpha.kubernetes.io/internal-hostname: $sys.network.internalClusterEndpoint
        externalURL: $var.externalURL
```

> `expose.type` and `externalURL` are **Harbor's** value keys, and Harbor nests
> Service annotations under `expose.clusterIP.annotations` — other charts differ.
> Confirm the annotation path with `helm show values <chart>` and check the
> rendered Service (`kubectl get svc -n <instance-id> -o jsonpath='{..annotations}'`)
> before concluding the plan is correct.

---

## TLS

**Omnistrate provisions a publicly-trusted certificate for every instance on a
BYOC-K8s cell, automatically, whether or not your plan uses it.** Public HTTPS
therefore costs one `tls:` block in the chart — you do not need cert-manager
annotations, an ACME issuer of your own, or a customer-supplied certificate.

Note that elsewhere in this file cert-manager appears only as a *hazard* (§The
`CreateCertificate` hang). That is a real failure mode on older control planes,
but it is not the whole story: on current builds the same machinery is what hands
you free public TLS.

### What the cell provides

Observed on a live `byoc-onprem` cell (2026-08), created by the platform at
**instance deploy time** without anything in the plan asking for it:

| Object | Value |
|---|---|
| ClusterIssuers (cluster-scoped) | `google-public-ca`, `google-public-ca-http`, `selfsigned`, `zerossl-prod` — all `READY=True` |
| `Certificate` | `google-public-ca`, in the **instance's own namespace**, `READY=True` |
| Secret it writes | `google-public-ca-tls` (`kubernetes.io/tls`; keys `tls.crt`, `tls.key`, `tls-combined.pem`) |
| Issuer on the wire | `C=US, O=Google Trust Services, CN=WR1` — trusted by default system trust stores |
| SAN | `*.instance-<instance-id>.hc-<cell>.on-prem.byoc-onprem.<org>.cloud` |
| Duration / renewal | 2160h (90d), `renewBefore` 360h, `rotationPolicy: Always` |

Two properties make this directly usable:

- The SAN **wildcard covers the endpoint host.** The endpoint Omnistrate
  generates is `r-<resource-id>.instance-<id>.hc-<cell>...`, and `r-<resource-id>`
  is a single label under the wildcard's parent domain.
- The secret is created **in the instance namespace**, which is where the Ingress
  lives — nginx only reads TLS secrets from its own namespace.

Confirm on a running instance before relying on the name:

```bash
kubectl get clusterissuer
kubectl get certificate,secret -n <instance-id> --field-selector type=kubernetes.io/tls
kubectl get secret google-public-ca-tls -n <instance-id> \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  openssl x509 -noout -issuer -dates -ext subjectAltName
```

### Wiring it up

Reference the secret from the Ingress the chart creates (Route A in
§HTTP/HTTPS applications):

```yaml
      chartValues:
        ingress:
          enabled: true
          className: nginx
          host: $sys.network.externalClusterEndpoint
          tls:
            enabled: true
            secretName: google-public-ca-tls
        # Anything the app renders links from must switch scheme too, or it will
        # advertise http:// URLs from an https:// site:
        app:
          appUrl: "https://{{ $sys.network.externalClusterEndpoint }}"
```

`ingress.*` paths are chart-specific; what generalises is *an Ingress with a
`tls` entry whose `secretName` is the platform-provisioned secret and whose host
matches the certificate's wildcard*.

Verify from **outside** the cluster, without `-k` — `-k` hides exactly the
failure you are testing for:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://<endpoint>/          # expect 200
echo | openssl s_client -connect <endpoint>:443 -servername <endpoint> 2>/dev/null \
  | openssl x509 -noout -issuer -dates
curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://<endpoint>/   # expect 301 -> https
```

nginx adds the HTTP→HTTPS redirect itself once a `tls` block exists; you do not
configure it.

### Failure mode: a healthy certificate nobody serves

**Omitting the `tls` block does not error.** The Certificate is `READY`, the
secret exists, the endpoint is HEALTHY, the instance reaches `RUNNING` — and
nginx serves **plain HTTP**, because nothing told it which secret to present. The
only symptom is that `https://<endpoint>` fails or falls back to the ingress
controller's default self-signed certificate while `http://` works fine.

Do not conclude "this cell has no TLS" from that. Check for the Certificate
first. Related trap: if the plan's rendered `appUrl`/`APP_URL`-style value still
says `http://`, the app will hand users insecure links even after TLS works.

---

## Storage

There is no Omnistrate-provisioned storage on BYOC-K8s. Any PVC the plan creates
binds against a **StorageClass the customer already has**.

- Do not hardcode cloud-specific StorageClass names (`gp3`, `premium-rwo`) in a
  BYOC-K8s plan — they will not exist on OpenShift or bare metal.
- Either rely on the cluster's default StorageClass, or expose the StorageClass
  name as an `apiParameter` so the customer supplies theirs.
- A missing or non-default StorageClass is the most common BYOC-K8s failure: PVCs
  stay `Pending`, pods never schedule, the instance never reaches RUNNING. See the
  `omnistrate-sre` skill.

---

## Rollouts on customer clusters (capacity, not Helm)

Customer clusters are frequently small — a single node is normal for BYOC-K8s
evaluations — and the **Kubernetes default rolling-update strategy deadlocks a
single-replica Deployment on a full node.** This surfaces as a stuck Helm
operation and is routinely misdiagnosed as a platform or agent fault.

The rounding is the whole problem. With `replicas: 1`:

| Default | 25% of 1 | Effect |
|---|---|---|
| `maxSurge: 25%` | rounds **up** to 1 | a second pod *must* be created before the old one goes |
| `maxUnavailable: 25%` | rounds **down** to 0 | the old pod *may not* be removed to make room |

On a node with no spare capacity both cannot hold: the replacement pod is
unschedulable, the old pod may not be evicted, and the upgrade waits forever.

**Diagnostic signature** — all four together mean capacity, not Helm:

```
kubectl get pods -n <instance-id>        # new pod Pending, old pod still Running
kubectl describe pod <new-pod> -n <ns>   # FailedScheduling: Insufficient cpu, Insufficient memory
helm history <release> -n <ns>           # latest revision stuck "pending-upgrade"
kubectl logs -n dataplane-agent deploy/dp-agent | grep "not ready"
#   -> "Deployment is not ready: <ns>/<name>. 0 out of 1 expected pods are ready"
```

That dp-agent line is **correct reporting, not an error** — it is blocked on the
scheduler. Check node pressure before touching anything else:

```bash
kubectl describe node | sed -n '/Allocated resources:/,/Events:/p'
```

Requests near 100% (observed: `cpu 1850m (92%)`, `memory 3756Mi (98%)` on a
2-vCPU/4 GiB node carrying only the amenity floor plus one small app) mean no
replacement pod will ever schedule.

**Fix — make replacement surge-free** in the chart's Deployment:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0          # never need capacity for an extra pod
      maxUnavailable: 1    # allowed to remove the old pod first
```

Costs a few seconds of downtime per upgrade and always converges. Verified: the
identical upgrade that hung indefinitely completed in ~90s with `maxSurge: 0`.

**To unstick a live one** without waiting out `timeoutNanos`, delete the **old**
pod so the replacement can schedule; the rollout then completes and the Helm
release leaves `pending-upgrade`. Prefer this over `helm rollback` — the platform
owns the release.

Two related habits for customer clusters:

- **Keep requests low.** The deployment-cell amenities alone can consume most of
  a small node's allocatable CPU. Requests are what the scheduler reserves, so
  over-requesting blocks upgrades even when actual usage is tiny.
- **`runtimeConfiguration.wait: true` makes this visible rather than silent** —
  the instance stays `DEPLOYING` instead of reporting success over a half-applied
  release. Keep it on, and treat a long `DEPLOYING` as a scheduling question
  first.

---

## Native logs

BYOC-K8s supports native log collection **for Helm resources**. With
`features.INTERNAL.logs.provider: native`, Omnistrate deploys a per-instance
OpenTelemetry collector that ships workload logs to CloudWatch Logs.

```yaml
features:
  INTERNAL:
    logs:
      provider: native
```

Non-obvious facts, all confirmed via `omctl docs plan-spec "Features schema"`:

- Logs land in **the Hosted SaaS Provider's AWS account** — *not* the customer's
  cloud, and regardless of what the dataplane cloud is. On BYOC-K8s the customer
  has no cloud account at all, and it still works.
- **No cloud credentials are needed on the customer cluster** beyond the standard
  agent install. Omnistrate supplies the collector with scoped, temporary AWS
  credentials that can write only to that instance's log groups and stream prefix.
- Keep **`ExpandBoundaryForAWSServiceIntegrations=true`** in that AWS account's
  generated CloudFormation stack, or the credentials cannot be issued. If the
  account was onboarded before this parameter existed, update the stack.
- This is independent of **`EnableECRHelmChartPull=true`** (needed when the plan
  pulls a Helm OCI chart from the provider's private ECR). A plan using both
  capabilities needs both flags.
- The cluster needs an **HTTPS path to the regional CloudWatch Logs endpoint** —
  public egress, or private routed connectivity to a CloudWatch Logs interface VPC
  endpoint via VPN/Direct Connect. Add it to the egress allowlist.
- **Not available air-gapped**, by definition — no path to CloudWatch.
- Omitting `provider` (`logs: {}`) keeps Omnistrate-managed logs. Removing
  `provider: native` switches back.
- Related but distinct: for *hosted* Helm deployments, native logging is currently
  supported only when the instance is deployed on AWS.

---

## Kubernetes operators on BYOC-K8s

An operator-based plan can target `byoc-onprem`, but the customer-owned cluster
changes the assumptions. See the `omnistrate-operator` skill for `systemWorkflows`
and CRD authoring; the BYOC-K8s-specific constraints are:

- **CRD installation is cluster-scoped.** Installing the operator's CRDs mutates
  cluster-wide state in a cluster you do not own. Confirm the customer accepts
  this, and that the identity the agent runs as may create CRDs and
  ClusterRoles/ClusterRoleBindings.
- **Watch for operator collisions.** If the customer already runs the same
  operator (a shared CNPG or Strimzi install), a second cluster-scoped install
  will fight it. Prefer installing the operator once as a **deployment-cell
  amenity** and letting per-instance resources be namespaced CRs.
- **No cloud LB, no cloud storage.** Operator CRs that request a `LoadBalancer`
  Service or a cloud-specific StorageClass will hang. Set ClusterIP and a
  customer-supplied StorageClass as above.
- **Operator-managed backups need a customer-side target.** There is no
  Omnistrate-provisioned S3 bucket; point the operator's backup config at an
  object store the customer supplies as an `apiParameter`.

---

## Verification and day-2 operations

From your control plane:

```bash
omnistrate-ctl instance describe <instance-id>
omnistrate-ctl instance list-endpoints <instance-id>
omnistrate-ctl instance dashboard <instance-id>
```

> **Two CLI shapes that waste time if you guess.** Instance status lives at
> **`.consumptionResourceInstanceResult.status`**, not `.status` — a poll loop
> using `.status // "?"` prints `?` forever against a perfectly healthy instance.
> And `account customer describe` takes the instance ID **positionally**, not via
> `--id`. (`omctl service delete` also has no `--yes` flag.)
>
> ```bash
> omnistrate-ctl instance describe <id> -o json | jq -r .consumptionResourceInstanceResult.status
> ```

Inside the customer cluster — **the instance ID is the namespace**:

```bash
kubectl get all -n <instance-id>
helm list -n <instance-id>
```

The Helm **release name is the spec's service name** (e.g. `podinfo`), not the
instance ID — only the namespace carries the instance ID. Namespaces are reclaimed
automatically on `instance delete`.

A populated namespace with a healthy pod but a `DEPLOYING` instance almost always
means the endpoint DNS record was never published — see §CRITICAL under
§Endpoints. An empty namespace with a healthy agent points at the workflow or plan
instead.

Use the customer's own `kubectl` context, or tunnel in with
`omctl deployment-cell update-kubeconfig <cell-id> --customer-email <email>`
(never a cloud-provider CLI — see the `omnistrate-sre` skill).

Lifecycle continues to run through your control plane — the customer keeps using
their own cluster tooling in parallel:

```bash
omnistrate-ctl instance version-upgrade <instance-id> --target-version=<version>
omnistrate-ctl instance stop <instance-id>
omnistrate-ctl instance delete <instance-id>
```

### Offboarding a customer cluster (the step everyone misses)

Deleting the onboarding instance does **not** finish the job on its own, and the
failure is silent. `account customer delete` returns `deleted: true` and its
workflow reports `SUCCESS`, but the instance then sits in `DELETING` indefinitely
because the agent is still running in the customer's cluster. The only visible
signal is in the JSON:

```json
{ "instance_status": "DELETING", "account_status": "READY_TO_OFFBOARD" }
```

`READY_TO_OFFBOARD` means *"uninstall the agent, then ask me again"*. The correct
sequence is:

```bash
omnistrate-ctl account customer delete <onboarding-instance-id>

# in the customer cluster:
helm uninstall dp-agent --namespace dataplane-agent
kubectl delete namespace dataplane-agent

# then RE-ISSUE the delete — the first call does not finalize:
omnistrate-ctl account customer delete <onboarding-instance-id>
```

It reaches `GONE` within ~30 seconds of the second call. The uninstall command is
also in the kit README and in `result_params.byoc_onprem_uninstall_command`.

This blocks more than the account: `omctl service delete` refuses while a
`DELETING` instance exists (`cannot delete service: 1 active deployment
instance(s) still exist`). Note also that **`omctl service delete` takes the
service *name*, not the service ID** — passing `s-...` returns `service not
found` even though `service list` displays that ID.

---

## Adopted deployment cells

Adoption integrates an **existing** Kubernetes cluster into your fleet as a
managed deployment cell. This is a **provider-fleet operation**, not a customer
deployment model — see the disambiguation table at the top of this file.

```bash
omctl deployment-cell adopt \
  --cloud-provider aws \
  --region us-east-1 \
  --id cluster-1 \
  --description "adopted cluster" \
  --customer-email customer@example.com     # optional; omit to adopt under the logged-in user
```

`--cloud-provider`, `--region`, and `--id` are required. The command registers the
cluster, reports `PENDING_ADOPTION`, and downloads an agent installation kit
(`<id>.tar`) into the current directory.

Complete adoption by installing the agent per the kit's README:

```bash
mkdir kit && cp cluster-1.tar kit && cd kit && tar -xf cluster-1.tar
# point kubectl at the target cluster first, then:
kubectl apply -f ./ns.yaml && \
  kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/dataplane-agent --timeout=60s
kubectl apply -f ./cluster-role-binding.yaml -f ./deployment.yaml \
  -f ./dp-agent-tls.yaml -f ./priority-class.yaml -f ./sa.yaml
kubectl -n dataplane-agent wait deployment/dp-agent --for=condition=Available --timeout=60s
```

Then check status and, when finished with the cell, deregister it:

```bash
omctl deployment-cell status --id cluster-1 [--customer-email <email>]
omctl deployment-cell delete --id cluster-1 --customer-email <email> [--force]
```

Notes that catch people out:

- `PENDING_ADOPTION` means registered but waiting for the agent to connect —
  it is the normal intermediate state, not an error.
- `HEALTH_STATUS` stays `UNKNOWN` until adoption completes.
- `--customer-email` is **optional** on `adopt` but **required** on `delete`.
- Different organizations may reuse the same cell `--id`.
- Deletion is permanent; uninstall the agent from the cluster separately, per the
  kit README.

An adopted/imported cell reports `$sys.deploymentCell.isImported: true`, which is
useful for suppressing amenities that only make sense on Omnistrate-provisioned
cells:

```yaml
      - name: aws-load-balancer-controller
        disable: $sys.deploymentCell.isImported     # skip on adopted clusters
```

> **This does not work on BYOC-K8s.** A cell onboarded through
> `account customer create` + install kit reports **`isImported: false`**, verified
> on a live cell — an amenity guarded by `disable: $sys.deploymentCell.isImported`
> installs normally there. `isImported` distinguishes *adopted* cells, not
> customer-owned ones. To suppress amenities on BYOC-K8s cells, use the
> per-cloud-provider template (§Trimming the amenity footprint).

---

## Limitations

- The cluster **must** have outbound connectivity to your control plane. BYOC-K8s
  is not for air-gapped environments — use `ONPREM_INSTALLER_REFERENCE.md`.
- Each customer onboarding instance maps to **one** Kubernetes cluster.
- Omnistrate provisions no nodes, storage, load balancers, or DNS.
- Endpoint reachability depends entirely on the customer's DNS, firewall, load
  balancer, and routing.
- There is no ISV cloud account for a Terraform resource to target, so
  cloud-managed dependencies (RDS, Cloud SQL) are not available from the plan —
  bundle the dependency into the chart, or have the customer supply a connection
  string as an `apiParameter`.

---

## Pitfalls

| Pitfall | Correction |
|---|---|
| **Using a Docker Compose spec for BYOC-K8s** | It validates, builds, produces a `BYOA` plan, and `instance create` is accepted — then never deploys and the instance namespace is never created. BYOC-K8s is ServicePlanSpec-only. An empty instance namespace means the spec format, not the cluster. |
| Debugging an empty instance namespace as an agent/amenity/egress problem | Check the spec format first. A connected agent and `READY` account with a namespace that was never created points at compose. |
| **Assuming no TLS because the endpoint serves HTTP** | The cell auto-provisions a Google-Trust-Services `Certificate` per instance (`google-public-ca` → secret `google-public-ca-tls`). Serving HTTP just means the Ingress has no `tls` block. See §TLS. |
| Verifying HTTPS with `curl -k` | `-k` suppresses exactly the trust failure you are testing. Verify without it. |
| Leaving an app's `APP_URL`-style value on `http://` after enabling TLS | The app then advertises insecure links from an HTTPS site. Switch the scheme in the same change. |
| Trusting this file's external-dns `--source` list | Read the deployment's actual args. A cell was observed with **both** `--source=service` and `--source=ingress`; the Ingress route is simpler where available. |
| An Ingress host outside external-dns's `--domain-filter` | No record is created, silently. The host must sit under the filtered domain. |
| **Default rolling-update strategy on a single-replica Deployment** | Deadlocks on a full node: `maxSurge 25%` rounds up to 1, `maxUnavailable 25%` rounds down to 0. Set `maxSurge: 0` / `maxUnavailable: 1`. See §Rollouts. |
| Reading `Deployment is not ready: 0 out of 1 expected pods are ready` as a dp-agent fault | It is accurate reporting of a blocked scheduler. Check `describe node` for requests near 100%. |
| **ClusterIP Service with no external-dns annotation** | **The #1 silent failure.** Endpoint stays UNHEALTHY, Monitoring never completes, instance hangs in `DEPLOYING` with a green Deployment step and a Running pod. Add `external-dns.alpha.kubernetes.io/internal-hostname`. |
| Using the `hostname` annotation on a ClusterIP Service | Use `internal-hostname` — plain `hostname` is skipped without `--publish-internal-services`. |
| Copying `compute.instanceTypes` into a BYOC-K8s plan | Omit `compute` — no nodes are provisioned. |
| Assuming `account customer delete` finishes the job | It stalls at `READY_TO_OFFBOARD`. Uninstall the agent, then re-issue the delete. |
| Polling `.account_status` | The field is `.summary.account_status`. |
| Running `install.sh` on a cluster with no LoadBalancer | Preflight hard-fails. Install MetalLB, or `--skip-nginx-validation`. Use `--validate-only` first. |
| Scoping the firewall ticket to your product's registries only | `ghcr.io` and `*.omnistrate.cloud` are needed before your plan is ever involved. |
| Promising "we only deploy workloads in your cluster" | The amenity stack installs 8 releases incl. cluster-scoped CRDs and an ingress controller. Disclose at intake. |
| Passing a service ID to `omctl service delete` | It takes the service **name**. |
| Declaring `endpointConfiguration` in the **first** BYOC-K8s spec | Start with no endpoints; add them (with the External DNS amenity) only when the user asks for a reachable endpoint. |
| **Endpoints in the spec but no External DNS amenity** | Instance hangs in Monitoring forever — same symptom as a missing annotation. Keep template and spec in step. |
| Trimming amenities with `managedAmenities: []`, null, or a 0-byte file | Silent no-ops that report success. Keep all 7 entries and set `disable: "true"`. |
| Using `skip: true` to disable an amenity | Silently dropped — `Skip` is internal-only, not in the CLI struct or public API. Use `disable: "true"`. |
| Unquoted `disable: true` | `disable` is a rendered expression parsed with `ParseBool`; use the quoted string `"true"`. |
| **Deleting** the Cert Manager entry | Rejected by the API. `disable: "true"` is not a removal and works. |
| Instance stuck in Deployment on `CreateCertificate` | Older control plane; that step needs the cert-manager CRD. Re-onboard with Cert Manager enabled. |
| Passing `ac-*` to `--customer-account-id` or `account customer describe` | Both take the **onboarding instance ID** (`instance-*`); `ac-*` gives a misleading `custom account config not found`. |
| Trying to remove an amenity from a live cell | Only additions reconcile; removals report SUCCESS and do nothing. Set the template **before** onboarding. |
| `disable: $sys.deploymentCell.isImported` to skip amenities on BYOC-K8s | `isImported` is `false` there. Use a `--cloud byoc-onprem` template. |
| Passing the `byoc-onprem-instance-*` id to `deployment-cell` commands | Use the `hc-*` id from `instance describe -o json \| jq -r .deploymentCellID`. |
| Treating BYOC-K8s as air-gapped | `byoaDeployment` + live agent, not `onPremDeployment`. See the table above. |
| Treating air-gapped as BYOC-K8s | `onPremDeployment` + `--onprem-platform`, no `--cloud-provider`/`--region`. |
| Expecting Omnistrate to provision nodes/LB/StorageClass | It provisions nothing. The customer owns all infrastructure. |
| Hardcoding `gp3` / `premium-rwo` StorageClasses | Use the cluster default or an `apiParameter`. |
| Using `loadBalancers.https` for a web app | ClusterIP + customer ingress + INTERNAL endpoint + `externalURL` parameter. |
| Passing a cloud account number to `--customer-account-id` | It takes the **onboarding instance ID** (`instance-...`). |
| Expecting `account customer create` to return `READY` | It does not wait — the agent has not been installed yet. Poll `account customer describe`. |
| Running `account customer create` outside a working directory | It downloads the install kit into the current directory. |
| Combining deployment blocks in one spec | One plan per deployment model, always. |
| Assuming `VALIDATE`/`PRE_INSTALL` hooks gate BYOC-K8s prerequisites | They are the air-gapped mechanism. Use amenities + portal instructions. |
| Enabling native logs without `ExpandBoundaryForAWSServiceIntegrations=true` | The collector cannot get credentials. |
| Confusing adopted cells with BYOC-K8s | Fleet operation vs customer deployment model. |
