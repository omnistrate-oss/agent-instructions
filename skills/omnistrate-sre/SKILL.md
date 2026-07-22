---
name: omnistrate-sre
description: Systematically debug failed or stuck Omnistrate instance deployments across all resource types (Docker Compose containers, Helm releases, Terraform/OpenTofu, Kustomize, Kubernetes operator CRs) and all deployment models (hosted, BYOC customer accounts, BYOC-K8s customer-managed clusters, air-gapped). Progressive workflow - deployment status, workflow events, rendered-artifact debug, live cluster access - that finds root causes while avoiding token limits. Use for FAILED/DEPLOYING instances, probe failures, terraform apply errors, helm release issues, operator CR reconciliation problems, and BYOC agent/connectivity issues.
---

# Debugging Omnistrate Deployments

## When to Use This Skill
- Instance deployments showing FAILED or DEPLOYING (stuck) status
- Resources with unhealthy pod statuses or deployment errors
- Startup/readiness probe failures (HTTP 503, timeouts)
- Helm releases with unclear or failed deployment states
- Terraform/OpenTofu apply errors (IAM, quota, SKU/region, naming conflicts)
- Operator custom-resource (CR) reconciliation stalls (`successCondition` never met)
- Kustomize substitution / missing StorageClass failures
- BYOC agent or connectivity problems (account not `READY`, dataplane agent down, egress blocked)
- Need to identify the root cause of any deployment failure

IMPORTANT! DO NOT USE THE AWS CLI / AZURE CLI / GCLOUD CLI TO CONFIGURE ACCESS TO THE KUBERNETES CLUSTER AT ANY STEP.
OMNISTRATE PROVIDES A REMOTE TUNNELING FEATURE (`deployment-cell update-kubeconfig`, described below) AND THESE STEPS STRICTLY WORK ONLY WITH THAT APPROACH. This applies to hosted, BYOC, and BYOC-K8s clusters alike — the secure mTLS reverse tunnel replaces cloud-provider CLIs and bastion hosts entirely.

## How the surfaces relate (read before you dig)
Three views describe the same deployment; use each for a different layer:
- **Workflow events** — orchestration context: which stage (bootstrap/storage/network/compute/deployment/monitoring) ran, transitions, and the high-level error the workflow captured.
- **`instance debug`** — resource-level detail: rendered artifacts, execution/apply logs, parameters, outputs, operation history, metrics metadata.
- **Live cluster/cloud state** — final confirmation of what actually landed (pods, helm releases, CRs).

If the workflow UI and `instance debug` disagree, trust `instance debug` for resource-level failure details and use workflow events to understand which execution attempted them.

## Progressive Debugging Workflow

### 1. Get Deployment Status
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_instance_describe`
**Flags**: `--deployment-status --output json`

Extract:
- Overall instance status
- Resources with deployment errors or unhealthy pod statuses
- The **resource type** of each failing resource (Compose / Helm / Terraform / Kustomize / Operator) — this decides which resource-type branch below applies

**Key Benefit**: Returns concise status, significantly reduces token usage vs full describe.

### 2. Identify Workflows and Analyze Events (Two-Phase)
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_workflow_list`
**Flags**: `--instance-id <id> --output json` — extract workflow IDs, types, start/end times for failed deployments.

**Phase 1 - Summary (Always Start Here)**:
```bash
omctl workflow events <workflow-id> --service-id <id> --environment-id <id> --output json
```
Extract:
- All resources with workflow step status (failed/in-progress/success)
- Step duration analysis and event count patterns
- The specific failed/stuck step and which stage (Bootstrap/Compute/Deployment/Network/Storage/Monitoring) it belongs to

**Phase 2 - Detail (Only for Failed Steps)**:
```bash
omctl workflow events <workflow-id> --service-id <id> --environment-id <id> \
  --resource-key <name> --step-types <type> --detail --output json
```
Use parameters:
- `--resource-key`: Target specific resource
- `--step-types`: Filter to specific step (Bootstrap, Compute, Deployment, Network, Storage, Monitoring)
- `--detail`: Include full event details (use sparingly — token-heavy)
- `--since/--until`: Time-bound queries

Extract from detail view: WorkflowStepDebug error messages, VM allocation failures/constraints, pod scheduling issues, container readiness failures.

**Pod Event Timeline**: Create ASCII visualizations showing deployment progression:
```
HH:MM:SS ┬─── ✗ FailedScheduling
         │    pod/app-0: Insufficient memory
         │
HH:MM:SS ├─── ⚡ TriggeredScaleUp
         │    nodegroup-1: adding 2 nodes
         │
HH:MM:SS ├─── 📥 Pulling image:latest
         │    (duration: 2m15s)
         │
HH:MM:SS └─── ✅ Started
              3/3 pods Running
```
Symbols: ✗ failed, ✅ success, ⚡ autoscaler, 💾 storage, 📥 image, 🚀 runtime, ⚠️ warning

### 3. Rendered-Artifact Debug (`instance debug`)
**Command**: `omnistrate-ctl instance debug <instance-id>` (interactive TUI; add `--output json` for automation)
**When**: template rendering errors, terraform failures, parameter-substitution doubts, or when workflow events point at a resource but not a cause. This is the **default starting point for Helm, Terraform, Compose, and Operator** troubleshooting after status/events narrow the scope.

`instance debug` surfaces the instance resource dependency graph and, per resource type:

| Resource type | What `instance debug` shows |
|---------------|-----------------------------|
| **Compose** | App logs, deployment API parameters, deployment output parameters, workflow events |
| **Helm** | Helm install/upgrade client logs, app logs, **rendered chart values**, deployment API/output parameters, workflow events |
| **Terraform** | Progress, **rendered `.tf` files**, Terraform output, live **apply logs**, **plan previews**, app logs, operation history, workflow events |
| **Operator** | App logs, deployment API parameters, deployment output parameters, **Operator CRD outputs**, workflow events |

Kustomize has no dedicated `instance debug` subcommand (the rendered-artifact subcommands are Helm and Terraform only). Read Kustomize substitution/rendering results from the workflow events and, when needed, from the **live rendered manifests via the cluster tunnel** (step 4) — `kubectl get -o yaml` the deployed objects — before making changes.

If you only need metrics dashboard metadata: `omnistrate-ctl instance dashboard <instance-id>`. (If logs/metrics are missing, confirm the integration is enabled: Compose uses `x-customer-integrations`/`x-internal-integrations`; Helm/Terraform/Operator use `features.CUSTOMER`/`features.INTERNAL`.)

### 4. Live Cluster Access (Omnistrate Remote Tunneling)
**When**: Resource DEPLOYING with probe failures; containers Running but not Ready; the previous step's response is too large; or no conclusive evidence yet.

**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_deployment-cell_update-kubeconfig` + kubectl

```bash
omctl deployment-cell update-kubeconfig <cell-id> --kubeconfig /tmp/kubeconfig
kubectl get pods -n <instance-id> --kubeconfig /tmp/kubeconfig
kubectl logs <pod-name> -c service -n <instance-id> --kubeconfig /tmp/kubeconfig --tail=50
```
For a customer-owned cell (BYOC / BYOC-K8s), add `--customer-email <customer@example.com>`. Default role is `cluster-reader` (read-only, cluster-wide); pass `--role cluster-admin` for helm operations.

Look for: database connection failures, application syntax/runtime errors (Python SyntaxError, Java compilation errors), service-dependency failures, configuration issues.

**HARD RULE (repeat):** never `aws eks update-kubeconfig`, `gcloud container clusters get-credentials`, or `az aks get-credentials`. The tunnel above is the only supported cluster-access path across every deployment model.

---

## Branch by Resource Type
Determine the failing resource's type from step 1, then follow the matching branch.

### Helm
Start from `instance debug` (rendered values + Helm client logs), then verify live state with cluster-admin kubeconfig:
```bash
omctl deployment-cell update-kubeconfig <cell-id> --kubeconfig /tmp/kubeconfig --role cluster-admin
helm list -n <instance-id> --kubeconfig /tmp/kubeconfig
helm status <release-name> -n <instance-id> --kubeconfig /tmp/kubeconfig
```
- **Rendered values wrong** → parameter/system-parameter mapping issue: fix the mapping and publish a new Plan version (a restart re-uses the old rendered artifacts).
- **Hook / job / timeout errors** → read Helm client logs; check `Jobs`, hooks, `Services`, load balancers stuck pending.
- **Stuck deletes / repeated create failures** → look for leftover **CRDs, finalizers, or namespaced resources**; first-install failures auto-clean, so the evidence is in the **debug events / client logs**, not in `helm list`.
- **Lifecycle mismatch** → tune runtime flags via `runtimeConfiguration`: `wait`, `waitForJobs`, `disableHooks`, `skipCRDs`, `upgradeCRDs`, `timeoutNanos` (see Helm Charts Runtime Configuration).

### Terraform / OpenTofu
Omnistrate runs Terraform/OpenTofu autonomously — there is **no manual `terraform plan` approval gate**. Read the plan preview and apply logs from `instance debug` (step 3):
1. Confirm rendered `.tf` files contain the expected system parameters, API parameters, secrets, and dependency outputs.
2. Confirm the captured `terraform plan` matches the resources you expected to create/update/delete.
3. Classify the apply failure: **IAM permission gap on the execution identity** / **quota** / **SKU-region availability** / **resource-name conflict** / invalid networking inputs / provider-credential problem (BYOC, control-plane-targeted, Nebius SA).

**Fix rule:**
- Transient / cloud-side issue with the *same* released artifacts still valid → **restart the workflow**.
- Changed Plan spec, `parameterDependencyMap`, Git branch/tag/commit, or any artifact that must be re-rendered → **publish a new Plan version** and trigger a fresh workflow. (A restart re-uses the artifacts captured for that workflow; only a moving branch head resolves anew on restart. Pin to a tag/commit for deterministic behavior.)

### Operator
`instance debug` for the operator resource shows app logs, API parameters, CRD outputs, and workflow events. For reconciliation problems:
1. Separate **Omnistrate orchestration errors** (workflow task failures) from **operator reconciliation errors** (the controller itself).
2. **`successCondition` never met** → compare the condition expression against the **LIVE CR status fields**: use the tunnel to inspect the CR, operator controller logs, events, and status conditions directly.
   ```bash
   # add --customer-email <email> only for a customer-owned cell (BYOC / BYOC-K8s), per step 4
   omctl deployment-cell update-kubeconfig <cell-id> --kubeconfig /tmp/kubeconfig
   kubectl get <crd-kind> -n <instance-id> -o yaml --kubeconfig /tmp/kubeconfig   # inspect status.*
   kubectl logs deploy/<operator-controller> -n <operator-namespace> --kubeconfig /tmp/kubeconfig
   ```
   Confirm the operator actually writes the status path the `successCondition` references, and that the workflow targets the intended namespace/resource name.
3. **No `successCondition` ⇒ no `outputParameters`.** A task without a `successCondition` captures no live status, so referencing `$tasks.X.resource.*` in outputs fails. For the authoring rules (systemWorkflows, successCondition/outputParameters design) see `../omnistrate-operator/SKILL.md`.

### Kustomize
Treat like Terraform/Helm rendering: read the **rendered yaml via `instance debug`** first.
- **Substitution failures** → rendered manifests show unresolved/wrong parameter values; fix the mapping and publish a new version.
- **Missing StorageClass / PVC** → the manifest references a StorageClass that does not exist on the target cell (common on BYOC-K8s); the pod stays Pending. Confirm the StorageClass exists (`kubectl get storageclass` via the tunnel) or add it as a deployment-cell amenity / customer prerequisite.

---

## Branch by Deployment Model
The resource-type branch tells you *what* failed; the deployment model tells you *where the boundary of your control is*. See `../omnistrate-fde/DEPLOYMENT_MODELS_REFERENCE.md` for the full model definitions.

### Hosted
Default flow above — infra is in your (provider) account and Omnistrate controls it end to end. No extra connectivity boundary.

### BYOC (customer cloud account)
Deployed in the customer's own AWS/GCP/Azure/OCI/Nebius account; Omnistrate reverses the connection (no inbound to the customer).
- **Customer account not `READY`** → bootstrap/trust incomplete. For AWS the customer must run the CloudFormation bootstrap before the backing account config becomes `READY`:
  ```bash
  omnistrate-ctl account customer describe <customer-account-instance-id>       # check account_status
  omnistrate-ctl account customer describe <customer-account-instance-id> -o json  # copy summary.accountConfigID
  omnistrate-ctl account describe <account-config-id>                            # Actions -> Bootstrap
  ```
- **BYO-VPC requirement violations** (bring-your-own VPC via `cloud_provider_native_network_id`): DNS hostnames + DNS resolution enabled; public NAT gateway with private-subnet routes for image pulls; private-subnet tag `kubernetes.io/role/internal-elb=1` and public-subnet tag `kubernetes.io/role/elb=1`.
- **PrivateLink** (zero public exposure): interface VPC endpoint targeting the Omnistrate PrivateLink service name; security-group inbound TCP **8443–8506** from the VPC CIDR; do not enable private DNS for cross-region endpoints (pass `--service-region`).

### BYOC-K8s (customer-managed Kubernetes, `byoc-onprem` / `on-prem`)
The customer owns the cluster, nodes, storage, routing, and endpoint exposure; Omnistrate does **not** provision nodes. Debug the boundary:
- **Dataplane agent health** — the agent runs in the customer cluster and opens outbound mTLS/gRPC to your control plane. Verify it:
  ```bash
  kubectl -n dataplane-agent get deploy/dp-agent --kubeconfig /tmp/kubeconfig
  ```
  (Adoption/onboarding installs it as `deployment/dp-agent` in the `dataplane-agent` namespace.) If the agent is not Available, the instance cannot progress.
- **Outbound egress** — pods must resolve and reach your control-plane endpoints plus required image and Helm-chart registries. Blocked egress shows as image-pull/agent-connect failures.
- **Missing StorageClasses** — required StorageClasses must pre-exist if the Plan uses persistent volumes; otherwise PVCs stay Pending.
- **Endpoint exposure is customer-owned** — ingress, load balancer, firewall, and DNS routing are on the **customer side**. Instance-level success with an unreachable endpoint means the routing/firewall/DNS path is the customer's to fix, not a platform failure.

### Air-gapped (on-prem installer)
No live control-plane link — you cannot use `instance debug` or the remote tunnel against a disconnected environment. Work from what the installer produces locally:
- **Action-hook logs** (`VALIDATE` / `PRE_INSTALL` / `POST_INSTALL` / `BACKUP`, scope `CLUSTER`) and **installer output** (`./install.sh` run).
- **Diagnostic bundles** collected locally and securely uploaded to the provider.
- **Temporary-access grants**: the customer can grant temporary, secure access to their environment so support can troubleshoot without compromising the air-gap.
- Remember offline constraints: no live telemetry, no online license rotation (a disconnected license expires at its expiration date), images pushed at install time via `INSTALLER_EMBED`.

---

## Common Failure Patterns

### Infrastructure Constraints (all models)
- VM allocation failures with restrictive constraints (AZ + Network + Size)
- PersistentVolumeClaim not found / StorageClass missing
- Node taints/affinity issues

### Container Lifecycle
- Back-off restarting failed container
- ProcessLiveness: UNHEALTHY
- Image pull failures (on BYOC-K8s/air-gapped, suspect registry egress or embed config)

### Probe Failures
- Startup/readiness probe HTTP 503
- Database connectivity timeouts
- Application syntax errors preventing startup
- Service dependency unavailability

### Per-Resource-Type
- **Helm**: rendered-value mismatch, stuck hook/job, leftover CRDs/finalizers on delete
- **Terraform**: IAM gap / quota / SKU-region / naming conflict on apply; wrong rendered `.tf`
- **Operator**: `successCondition` vs live CR status mismatch; missing status path; controller crash-loop
- **Kustomize**: unresolved substitution; missing StorageClass

### Per-Model
- **BYOC**: account not `READY` (bootstrap/trust); VPC requirement violations; PrivateLink SG/endpoint
- **BYOC-K8s**: `dp-agent` down; egress blocked; missing StorageClass; customer-side endpoint routing
- **Air-gapped**: action-hook/installer failures; expired offline license; embed/registry issues

## Resource Prioritization
1. Core infrastructure: databases, message queues, storage
2. Application services: web servers, APIs
3. Support services: monitoring, logging

## Response Management
- Always use `--output json`
- If token limit exceeded: add more specific filters, use smaller time windows, target specific resources with `--resource-key`, avoid `--detail` until you know the failed step
- Provide analysis in template format (see Failure Analysis Template in OMNISTRATE_SRE_REFERENCE.md)

## Reference
See OMNISTRATE_SRE_REFERENCE.md for:
- Detailed tool parameter documentation
- `instance debug` output anatomy per resource type
- Failure-pattern catalog (by resource type, then by model): symptom → evidence location → fix
- BYOC / BYOC-K8s connectivity checklist
- Complete failure analysis template, examples, and tool alternatives
