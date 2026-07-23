# Omnistrate Debugging Reference

This document provides detailed reference information for debugging Omnistrate deployments. See SKILL.md for the main debugging workflow.

## Table of Contents
1. [Tool Parameter Reference](#tool-parameter-reference)
2. [`instance debug` Output Anatomy](#instance-debug-output-anatomy)
3. [Failure-Pattern Catalog](#failure-pattern-catalog)
4. [BYOC / BYOC-K8s Connectivity Checklist](#byoc--byoc-k8s-connectivity-checklist)
5. [Failure Analysis Template](#failure-analysis-template)
6. [Complete Examples](#complete-examples)
7. [Tool Alternatives](#tool-alternatives)

## Tool Parameter Reference

### instance_describe
```bash
omctl instance describe <instance-id> [flags]
```
**Key Flags**:
- `--deployment-status`: Returns concise deployment status (recommended)
- `--resource-key <name>`: Filter to specific resource
- `--resource-id <id>`: Filter by resource ID
- `--output json`: JSON output for parsing

**Benefits of --deployment-status**:
- Focuses on deployment errors and pod statuses only
- Assumes resources without issues are healthy
- Significantly reduces token usage vs full describe

### workflow_list
```bash
omctl workflow list --service-id <id> --environment-id <id> [flags]
```
**Key Flags**:
- `--instance-id <id>`: Filter to specific instance
- `--limit <n>`: Limit results (default: 10, use 0 for no limit)
- `--start-date <RFC3339>`: Filter workflows after date
- `--end-date <RFC3339>`: Filter workflows before date

### workflow_events
```bash
omctl workflow events <workflow-id> --service-id <id> --environment-id <id> [flags]
```
**Summary View Flags** (Phase 1):
- `--output json`: JSON output

**Detail View Flags** (Phase 2):
- `--resource-key <name>`: Filter to specific resource
- `--step-types <types>`: Filter step types (comma-separated)
- `--detail`: Include full event details (use sparingly)
- `--since <RFC3339>`: Show events after time
- `--until <RFC3339>`: Show events before time

**Available Step Types**:
- Bootstrap
- Compute
- Deployment
- Network
- Storage
- Monitoring

### operations_events
```bash
omctl operations events [flags]
```
**Key Flags**:
- `--instance-id <id>`: Filter by instance
- `--start-date <RFC3339>`: Start time window
- `--end-date <RFC3339>`: End time window
- `--event-source-types <types>`: Filter event sources (comma-separated)

### instance debug
```bash
omnistrate-ctl instance debug <instance-id> [flags]
```
**Purpose**: Default starting point for Helm, Terraform, Compose, and Operator troubleshooting. Opens the instance resource dependency graph and surfaces resource-specific runtime detail (rendered artifacts, execution/apply logs, parameters, outputs, operation history, metrics metadata).
**Key Flags**:
- `--output json`: Non-interactive JSON output for automation (interactive TUI otherwise)

Related: `omnistrate-ctl instance dashboard <instance-id>` returns only the metrics dashboard metadata. If logs/metrics are absent, the relevant integration is not enabled (Compose: `x-customer-integrations`/`x-internal-integrations`; Helm/Terraform/Operator: `features.CUSTOMER`/`features.INTERNAL`).

### account customer describe
```bash
omnistrate-ctl account customer describe <customer-account-instance-id> [flags]
```
**Purpose**: Inspect a BYOC customer onboarding instance / account-config status. Continue deploying only when `account_status` is `READY`.
**Key Flags**:
- `-o json` / `--output json`: JSON output; `summary.accountConfigID` links to the backing account config used with `account describe <account-config-id>` (Actions -> Bootstrap for AWS CloudFormation).

### deployment-cell update-kubeconfig
```bash
omctl deployment-cell update-kubeconfig <cell-id> [flags]
```
**Purpose**: Secure mTLS reverse-tunnel access to ANY deployment cell (yours, a customer's, cross-cloud, cross-region). Replaces `aws eks update-kubeconfig` / `gcloud container clusters get-credentials` / `az aks get-credentials` — never use those. Standard tooling (kubectl, k9s, helm) works over the tunnel.
**Key Flags**:
- `--kubeconfig <path>`: Output path (default: /tmp/kubeconfig)
- `--role <role>`: Access role (default: cluster-reader, use cluster-admin for helm)
- `--customer-email <email>`: Required when the cell belongs to a customer (BYOC / BYOC-K8s)

## `instance debug` Output Anatomy

`omnistrate-ctl instance debug <instance-id>` shows the instance resource dependency graph; selecting a resource exposes different surfaces depending on its type. Use this table to know exactly which surface holds the evidence for a given failure.

| Resource type | Surfaces exposed | Use for |
|---------------|------------------|---------|
| **Compose** | App logs; deployment API parameters; deployment output parameters; workflow events | Container startup/health/dependency errors; confirming API params resolved to expected runtime values; confirming output params other resources expect |
| **Helm** | Helm install/upgrade **client logs**; app logs; **rendered chart values**; deployment API/output parameters; workflow events | Template rendering errors; hook/timeout/K8s-API validation failures; verifying rendered values match expected API/system params/defaults |
| **Terraform / OpenTofu** | **Progress**; **rendered `.tf` files** (post variable-substitution + param mapping); captured **`terraform plan` preview**; live **apply logs**; **Terraform output**; **operation history**; app logs; workflow events | Confirming rendered artifacts + intended plan; classifying apply errors; confirming outputs feed downstream resources; reviewing prior attempts/errors |
| **Operator** | App logs; deployment API parameters; deployment output parameters; **Operator CRD outputs**; workflow events | Confirming API params resolved to expected CR inputs; inspecting CRD outputs / exported output params; separating orchestration from reconciliation errors |
| **Kustomize** | No dedicated `instance debug` subcommand (rendered-artifact subcommands are Helm and Terraform only). Read substitution/rendering results from workflow events, and inspect **live rendered manifests via the cluster tunnel** (`kubectl get -o yaml`) | Substitution failures; wrong/missing values before touching the cluster |

Notes:
- **Terraform execution has no manual `plan` approval gate** — Omnistrate applies autonomously. The plan preview is captured for inspection, not approval.
- The **Metrics** tab (or `omnistrate-ctl instance dashboard <instance-id>`) shows Grafana dashboard metadata when metrics are enabled.
- If a surface is empty, the corresponding integration is likely disabled (see `instance debug` in the Tool Parameter Reference).

---

## Failure-Pattern Catalog

Each entry: **symptom → evidence location → fix.** Organized by resource type first, then by deployment model.

### By Resource Type

#### Helm
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Wrong app config / missing values | `instance debug` → rendered chart values | Correct API/system-parameter mapping; **publish a new Plan version** (restart re-uses old renders) |
| Hook / job failure, install timeout | `instance debug` → Helm client logs; live `Jobs`/hooks/`Services`/LB status via tunnel | Fix chart hook/job; tune `wait`/`waitForJobs`/`disableHooks`/`timeoutNanos` in `runtimeConfiguration` |
| Repeated create/upgrade/delete failures; stuck delete | Debug events + client logs (first-install failures auto-clean, so NOT in `helm list`); look for leftover CRDs/finalizers/namespaced resources | Remove stuck finalizers/CRDs; adjust `skipCRDs`/`upgradeCRDs`; republish if chart inputs changed |
| Platform shows DEPLOYING but release is fine | `helm status <release>` via `--role cluster-admin` tunnel | Often non-critical background jobs; confirm app is actually serving |

#### Terraform / OpenTofu
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Rendered `.tf` missing/wrong params, secrets, dependency outputs | `instance debug` → rendered Terraform files | Fix Plan spec / `parameterDependencyMap` / Git ref; **publish new Plan version** |
| Plan does not match intended resources | `instance debug` → `terraform plan` preview | Correct source/params; republish |
| Apply fails: IAM permission gap | `instance debug` → apply logs (permission/AccessDenied) | Grant permission on the execution identity; **restart workflow** (same artifacts still valid) |
| Apply fails: quota exceeded | apply logs (quota/limit) | Raise cloud quota; restart |
| Apply fails: SKU/region unavailable | apply logs (unavailable region/SKU) | Change SKU/region in params; if spec changed, republish |
| Apply fails: resource-name conflict | apply logs (already exists) | Resolve naming collision; restart or republish depending on whether the name is spec-driven |
| Provider auth failure (BYOC / control-plane / Nebius SA) | apply logs + provider config in `instance debug` | Fix provider credentials/config; retry |

**Restart vs publish rule:** transient/cloud-side with the *same* released artifacts still valid → **restart**. Changed Plan spec, `parameterDependencyMap`, Git branch/tag/commit, or any re-rendered artifact → **publish a new version**. A restart re-uses captured artifacts; only a moving branch head re-resolves on restart (pin to tag/commit for determinism).

#### Operator
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Workflow task failed (orchestration) | `instance debug` / workflow events for the operator resource | Fix task definition/targeting (namespace, resource name) |
| `successCondition` never met (readiness stalls) | Live CR `status.*` via tunnel; operator controller logs/events/status conditions | Confirm operator writes the referenced status path; correct the condition expression; fix the workload the CR manages |
| Output not resolved / `$tasks.X.resource.*` fails | Task definition | A task with **no `successCondition` captures no live status ⇒ no `outputParameters`**; add a `successCondition` to the apply task (readiness belongs in `successCondition`; outputs read `$tasks.<task>.resource.status.*`) |
| Controller crash-loop | Controller pod logs via tunnel | Fix operator deployment/RBAC; check CRD install |

#### Kustomize
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Substitution failure / unresolved values | Workflow events; live rendered yaml via tunnel (`kubectl get -o yaml`) | Fix parameter mapping; republish |
| Pod Pending: missing StorageClass/PVC | Rendered yaml + `kubectl get storageclass`/`get pvc` via tunnel | Ensure StorageClass exists on the cell (amenity or customer prerequisite) |

### By Deployment Model

#### Hosted
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Standard infra/app failure | Full progressive workflow (status → events → `instance debug` → tunnel) | Per resource-type branch — no extra connectivity boundary |

#### BYOC (customer cloud account)
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Customer account not `READY` | `account customer describe <id>` → `account_status`; `account describe <account-config-id>` | Complete cloud bootstrap (AWS CloudFormation via Actions -> Bootstrap) before deploying |
| BYO-VPC violations (nodes/pods can't start or pull) | Deployment-cell bootstrap debug events; VPC config | Enable DNS hostnames+resolution; add NAT gateway + private-subnet routes; subnet tags `kubernetes.io/role/internal-elb=1` (private) / `kubernetes.io/role/elb=1` (public) |
| PrivateLink connectivity failure | Bootstrap events; VPC endpoint + SG | Interface VPC endpoint to the Omnistrate PrivateLink service name; SG inbound TCP **8443–8506** from VPC CIDR; `--service-region` for cross-region (no private DNS) |

#### BYOC-K8s (customer-managed Kubernetes, `byoc-onprem`/`on-prem`)
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Instance never progresses; agent not connected | `kubectl -n dataplane-agent get deploy/dp-agent` via tunnel/customer context | Re-run install kit (`./install.sh --non-interactive`) or `account customer install-kit`; ensure agent Available |
| Image-pull / agent-connect failures | Pod events + agent logs | Open outbound egress to control-plane endpoints + image/Helm registries |
| Pod Pending: missing StorageClass | `kubectl get storageclass` via tunnel | Customer/amenity must pre-create required StorageClasses |
| Endpoint unreachable but instance healthy | `instance list-endpoints <id>` + customer network | **Customer-side**: ingress/LB/firewall/DNS routing — not a platform failure |

#### Air-gapped (on-prem installer)
| Symptom | Evidence location | Fix |
|---------|-------------------|-----|
| Install/validation failure | Action-hook logs (`VALIDATE`/`PRE_INSTALL`/`POST_INSTALL`/`BACKUP`, scope `CLUSTER`); `./install.sh` output | Fix the failing hook / cluster prerequisite (no live control-plane link — no `instance debug`/tunnel) |
| Need provider troubleshooting | Diagnostic bundle uploaded to provider; customer-granted temporary access | Analyze bundle; use temporary-access grant for remote support |
| Product stops working over time | License state | Disconnected licenses are **not rotated** and expire at their expiration date; images embedded via `INSTALLER_EMBED` |

---

## BYOC / BYOC-K8s Connectivity Checklist

Run these before deep-diving a BYOC or BYOC-K8s failure — most "stuck" instances are a connectivity/prereq gap, not an application bug.

**BYOC (customer cloud account):**
1. `account customer describe <customer-account-instance-id>` → `account_status` is `READY`. If not, the cloud bootstrap (CloudFormation for AWS; Cloud Shell/Terraform for GCP/Azure) has not completed in the customer account.
2. For BYO-VPC: DNS hostnames + resolution enabled; NAT gateway present with private-subnet routes; subnet tags correct (`internal-elb=1` private, `elb=1` public); public subnets auto-assign public IPv4.
3. For PrivateLink: interface VPC endpoint to the Omnistrate PrivateLink service name; SG inbound TCP `8443–8506` from the VPC CIDR; if the account is PrivateLink and you need K8s debug access, confirm `K8sDebugAccessEnabled` (removes the `block-k8s-api-proxy` NetworkPolicy in the `dataplane-agent` namespace).

**BYOC-K8s (customer-managed Kubernetes):**
1. Dataplane agent Available: `kubectl -n dataplane-agent get deploy/dp-agent` (installed as `deployment/dp-agent` in namespace `dataplane-agent`).
2. Outbound egress from cluster: control-plane endpoints reachable + image and Helm-chart registries reachable (no inbound to the cluster is required — the agent dials out over mTLS/gRPC).
3. Required StorageClasses exist if the Plan uses persistent volumes.
4. Cluster-level components (ingress controllers, cert-manager, monitoring) present as deployment-cell amenities or customer-installed prerequisites.
5. Endpoint path (ingress/LB/firewall/DNS) matches the endpoint exposure the Plan defines — this is **customer-owned**; a healthy instance with an unreachable endpoint is a customer-side routing issue.

---

## Failure Analysis Template

```markdown
## Instance: <instance-id>
## Overall Status: <status>
## Failed Resources:

### Resource: <name>
- **Status**: <status>
- **Health**: <health indicators>
- **Key Timeline Events**:

  HH:MM:SS ┬─── [symbol] [event description]
           │    [affected components]
           │
  HH:MM:SS ├─── [symbol] [event description]
           │    [affected components]
           │
  HH:MM:SS └─── [symbol] [final state]
                [summary]

- **Probable Cause**: <initial analysis>

---

## Root Cause Analysis

### Infrastructure Layer
- VM allocation status and constraints
- Node availability and taints
- Storage provisioning (PVC/PV status)

### Kubernetes Layer
- Pod scheduling decisions
- Container image pull status
- Resource requests vs available capacity

### Application Layer
- Container startup logs
- Probe failure reasons
- Service dependencies status
- Configuration/environment issues

### Dependency Chain
- Which resource failed first
- Cascading failure analysis
- Service interdependencies

## Recommended Actions

1. **Immediate**: <actions to stabilize>
2. **Resolution**: <steps to fix root cause>
3. **Validation**: <how to verify fix>
```

## Complete Examples

### Example 1: VM Allocation Failure (instance-a9x2m4pvqr)

**Step 1 - Deployment Status**:
```bash
omctl instance describe instance-a9x2m4pvqr --deployment-status --output json
```
Result: neo4j (deployment errors), rabbitmq (pod status issues)

**Step 2 - Workflow List**:
```bash
omctl workflow list --service-id s-k8Lp5Q2mX9 --environment-id se-YhVnRuWzLm \
  --instance-id instance-a9x2m4pvqr --output json
```
Result: workflow ID submit-create-instance-a9x2m4pvqr-1734567890123456

**Step 3 - Workflow Events Summary**:
```bash
omctl workflow events submit-create-instance-a9x2m4pvqr-1734567890123456 \
  --service-id s-k8Lp5Q2mX9 --environment-id se-YhVnRuWzLm --output json
```
Result: neo4j Deployment step failed, Network step timed out

**Step 4 - Workflow Events Detail** (for failed neo4j):
```bash
omctl workflow events submit-create-instance-a9x2m4pvqr-1734567890123456 \
  --service-id s-k8Lp5Q2mX9 --environment-id se-YhVnRuWzLm \
  --resource-key neo4j --step-types Deployment --detail --output json
```

**Root Cause**: VM allocation failures due to overly restrictive constraints (Availability Zone + Networking + VM Size). Pod scheduling failures (PVC not found, node taints). Network step timeout waiting for service endpoints.

**Timeline**:
```
14:23:15 ┬─── 🚀 Bootstrap, Compute, Deployment, Network, Storage started
         │
14:23:32 ├─── ✗ FailedScheduling
         │    pod/neo4j-0: PersistentVolumeClaim not found
         │
14:23:42 ├─── ⚡ TriggeredScaleUp
         │    Cluster autoscaler adding nodes
         │
14:28:51 ├─── ✗ FailedScheduling
         │    pod/neo4j-0: Node affinity issues after scale-up
         │
         │    [Multiple VM allocation retries]
         │
15:23:17 └─── ✗ Network step failed
              Timeout waiting for service endpoints (1h)
```

### Example 2: Application Syntax Error

**Step 1-3**: Deployment status shows DEPLOYING, workflow shows containers Running but probes failing

**Step 4 - Pod Logs**:
```bash
omctl deployment-cell update-kubeconfig hc-abc123 --kubeconfig /tmp/kubeconfig
kubectl logs app-pod-xyz -c service -n instance-eafmrkxbd --kubeconfig /tmp/kubeconfig
```

**Root Cause**: Python syntax error in application code:
```python
File "/app/v1/routers/user_router.py", line 92
  logger.info(f"Getting permissions for user_name: {user_info["username"]}")
                                                             ^^^^^^^^
SyntaxError: f-string: unmatched '['
```

Container starts but application fails to serve traffic, causing probe failures.

### Example 3: Helm Release Verification

**Step 1-3**: Instance shows DEPLOYING, workflow reports success, status unclear

**Step 4 - Helm Status**:
```bash
omctl deployment-cell update-kubeconfig hc-xyz789 --kubeconfig /tmp/kubeconfig --role cluster-admin
helm list -n instance-abc123 --kubeconfig /tmp/kubeconfig
helm status my-app -n instance-abc123 --kubeconfig /tmp/kubeconfig
```

Result: Helm shows "deployed", but background jobs failing (non-critical)

**Root Cause**: Deployment actually succeeded, non-critical background jobs causing platform to show DEPLOYING status. Application is accessible and functional.

## Tool Alternatives

| Primary Tool | Alternative Approach | When to Use | Trade-offs |
|-------------|---------------------|-------------|-----------|
| `workflow_events` (full) | `workflow_events` (summary + targeted detail) | Always | Summary safe, detail only when needed |
| `workflow_events` (any) | `operations_events` with filters | workflow_events exceeds tokens | Broader events, may need more filtering |
| `instance describe --deployment-status` | `instance debug <id>` | Need rendered artifacts / apply logs / CRD outputs, not just status | `instance debug` is richer per-resource; scope with `--output json` to manage tokens |
| Large time ranges | Multiple smaller time windows | Date ranges return too much data | More API calls but manageable data |
| Direct pod inspection | workflow/operations events | kubectl not available | Less direct, but still informative |

## Progressive Debugging Decision Tree

```
Start
  │
  ├─ instance_describe --deployment-status
  │    │
  │    ├─ Resources healthy? → Done
  │    │
  │    └─ Resources with issues? → Continue
  │         │
  │         ├─ workflow_list (get workflow IDs)
  │         │
  │         └─ workflow_events (summary)
  │              │
  │              ├─ Clear infrastructure failure?
  │              │    └─ workflow_events --detail (specific resource/step)
  │              │         └─ Report: VM allocation, networking, storage issues
  │              │
  │              ├─ Probe failures / DEPLOYING status?
  │              │    └─ deployment-cell update-kubeconfig + kubectl logs
  │              │         └─ Report: Application errors, dependencies, config issues
  │              │
  │              ├─ Helm resource with unclear status?
  │              │    └─ deployment-cell update-kubeconfig (cluster-admin) + helm status
  │              │         └─ Report: Actual deployment state, pod health, credentials
  │              │
  │              └─ Need broader context?
  │                   └─ operations_events (time-windowed)
  │                        └─ Report: Full event analysis
```

## Best Practices Summary

1. **Start Broad, Then Focus**: Use deployment status first, drill down to specifics
2. **Two-Phase Workflow Events**: Summary overview, then targeted detail
3. **Time-bound Queries**: Use RFC3339 timestamps to limit response sizes
4. **Resource Prioritization**: Core infrastructure → Application services → Support services
5. **Timeline Visualization**: ASCII charts for pod event progression
6. **Progressive Investigation**: Each step informs the next, avoid gathering unnecessary data
7. **Kubectl as Last Resort**: Use when API tools don't provide conclusive evidence
8. **Helm for Definitive Status**: Verify actual deployment state vs platform reports

## Common Root Causes by Symptom

### "DEPLOYING" with Running Pods
- Application startup failures (syntax errors, import issues)
- Database/service dependencies unavailable
- Configuration missing or incorrect
- Non-critical background jobs failing (Helm)

### "FAILED" Status
- VM allocation constraint failures
- PersistentVolumeClaim provisioning issues
- Node affinity/taint mismatches
- Image pull errors
- Resource quota exceeded

### Probe Failures (HTTP 503)
- Application not listening on expected port
- Application startup taking longer than probe timeout
- Database connection failures during startup
- Memory pressure causing OOM during init
- Network policies blocking health check endpoints

### Cascading Failures
- Core service (database/queue) failure affecting dependent services
- Network connectivity issues preventing service-to-service communication
- Shared resource exhaustion (storage, memory) affecting multiple pods
