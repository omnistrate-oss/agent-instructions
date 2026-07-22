## Skill Routing Guide

Use the table below to select the right skill for each request. All four deployment models — **hosted** (provider cloud), **BYOC** including BYO-VPC and PrivateLink (customer cloud accounts), **BYOC-K8s** (customer-managed Kubernetes / `byoc-onprem`), and **air-gapped** (`onPremDeployment` installer) — are supported across all artifact types (the air-gapped installer packages a Helm chart, so non-Helm stacks must first be bundled into a chart).

| Request shape | Skill |
|---------------|-------|
| Design new SaaS app from scratch; choose tech stack; convert local `build:` compose to cloud-ready | **omnistrate-sa** |
| Onboard Docker Compose, Helm chart, Terraform/OpenTofu module, Kustomize, or mixed stack to Omnistrate | **omnistrate-fde** |
| Onboard a Kubernetes operator (CRDs + controller, e.g. CloudNativePG, Strimzi, KubeAI) | **omnistrate-operator** |
| Debug a FAILED or stuck Omnistrate instance (any artifact type, any deployment model) | **omnistrate-sre** |

## Available Skills

### Omnistrate Solutions Architect
**Location**: `skills/omnistrate-sa/`

Guide users through designing application architectures from scratch for SaaS deployment on Omnistrate. Includes deployment-model discovery (hosted/BYOC/BYOC-K8s/air-gapped) before technology selection, and hands off a production-ready artifact (vanilla compose spec, or a Helm/Terraform ServicePlanSpec skeleton) to the FDE or operator skill.

**When to use**:
- Designing new SaaS applications from scratch and choosing technology stacks
- Selecting databases, frameworks, caches, message queues for specific domains
- Understanding domain-specific requirements (AI/ML, analytics, APIs, data platforms)
- Evaluating compliance needs (SOC2, HIPAA, GDPR, data residency)
- Determining customer SLA requirements and availability architecture
- Making architectural decisions informed by Omnistrate's tenancy and deployment models
- Iteratively developing and validating Docker Compose specifications
- **User has a compose file with `build:` contexts** (needs conversion to `image:` references)
- **Compose file only works locally** (needs registry setup for cloud deployment)
- Converting local compose specs (with build contexts) to cloud-ready specs (with image registries)
- Preparing compose specs or ServicePlanSpec skeletons for FDE transformation

**Do NOT use when**:
- User already has a complete compose spec with ALL services using `image:` references (no `build:` contexts) AND images are in accessible registries → Use **FDE skill** instead
- User needs to debug failed deployments → Use **SRE skill** instead

**Key capabilities**:
- Deployment-model discovery and mapping (hosted / BYOC / BYOC-K8s / air-gapped) before architecture decisions
- Technology stack selection (frameworks, databases, caches, queues, storage)
- Domain-specific architecture patterns (API, ML, analytics, data platforms)
- Tenancy model design (shared, siloed, hybrid) informed by Omnistrate capabilities
- Compliance and security architecture (SOC2, HIPAA, GDPR, PCI)
- SLA-driven availability design (99.9% to 99.999% uptime)
- Iterative Docker Compose spec development and validation
- Container image registry setup (convert build contexts to image references)
- Private registry auth needs: identify and collect requirements for FDE (FDE configures `x-omnistrate-image-registry-attributes` and the Omnistrate secrets)
- Output-format decision: compose vs Helm vs Terraform skeleton vs operator handoff
- Omnistrate-aware design decisions (autoscaling, backups, multi-zone readiness)

### Onboarding Services to Omnistrate (Universal Router)
**Location**: `skills/omnistrate-fde/`

The primary onboarding skill for all artifact types and all deployment models. Runs an intake interview to select the right method and deployment model, then drives the phased build-deploy-debug workflow. **CRITICAL**: ALWAYS starts with ZERO parameterization (hardcoded values) to ensure successful initial deployment, then adds API parameters incrementally ONLY when user explicitly requests customization. The deployment model is chosen from intake — never silently defaulted.

**When to use**:
- Onboarding any application to Omnistrate (Docker Compose, Helm, Terraform, Kustomize, or mixed)
- Creating SaaS offerings with multi-tenant infrastructure
- Transforming artifacts into Omnistrate service definitions for any deployment target
- Setting up customer-facing service catalogs

**Supported artifact types**: Docker Compose, Helm charts, Terraform/OpenTofu modules, Kustomize overlays, mixed stacks.

**Supported deployment models**: Hosted, BYOC (incl. BYO-VPC, PrivateLink), BYOC-K8s (`byoc-onprem`), air-gapped (`onPremDeployment`).

**Key capabilities**:
- Intake interview: artifact type → method selection; deployment-model discovery
- Compose spec transformation with `x-omnistrate-*` extensions (`COMPOSE_ONBOARDING_REFERENCE.md`)
- Helm `helmChartConfiguration`, values templating, multi-service `dependsOn` (`HELM_ONBOARDING_REFERENCE.md`)
- Terraform/OpenTofu and Kustomize ServicePlanSpec (`TERRAFORM_KUSTOMIZE_REFERENCE.md`)
- Deployment model `deployment:` blocks and customer account onboarding (`DEPLOYMENT_MODELS_REFERENCE.md`)
- Zero-parameterization initial builds; incremental API parameter addition
- Compute and storage resource setup
- Iterative debugging until instances are RUNNING (delegates to SRE skill)
- Multi-service architecture with synthetic root patterns and `dependsOn`
- Air-gapped installer artifact (`onPremDeployment`)

**Hands off to**:
- **omnistrate-operator** when the artifact is a Kubernetes operator (CRDs + controller)
- **omnistrate-sa** when no artifact exists yet and architecture design is needed
- **omnistrate-sre** when instances fail during deploy-debug cycles

### Kubernetes Operator Onboarding
**Location**: `skills/omnistrate-operator/`

Deep-dive onboarding for Kubernetes operator-based services (CRDs + controller). Owns `systemWorkflows` and lifecycle verb mapping; does NOT handle Docker Compose services.

**When to use**:
- Onboarding an operator-managed service (CloudNativePG, Strimzi, KubeAI, ECK, RabbitMQ operator, etc.)
- Writing or reviewing a ServicePlanSpec with `systemWorkflows`
- Adding lifecycle verbs (stop/start, backup/restore, failover) to an operator integration

**Do NOT use when**:
- Service is Docker Compose → Use **FDE skill** instead
- Instance is failing → Use **SRE skill** instead

**Key capabilities**:
- `systemWorkflows` and `customWorkflows` authoring
- Lifecycle verb mapping (create/modify/stop/delete/backup/restore)
- `operatorCRDConfiguration` and `helmChartConfiguration` for the operator deployment
- `successCondition` and `outputParameters` design
- Canonical examples and schema-verified spec fragments

### Debugging Omnistrate Deployments
**Location**: `skills/omnistrate-sre/`

Systematically debug failed Omnistrate instance deployments using a progressive workflow across all resource types and all deployment models. Identifies root causes efficiently while avoiding token limits.

**When to use**:
- Instance deployments showing FAILED or DEPLOYING (stuck) status
- Resources with unhealthy pod statuses or deployment errors
- Startup/readiness probe failures (HTTP 503, timeouts)
- Helm releases with unclear or failed deployment states
- Terraform/OpenTofu apply errors (IAM, quota, SKU/region, naming conflicts)
- Operator custom-resource (CR) reconciliation stalls
- Kustomize substitution or missing StorageClass failures
- BYOC agent or connectivity issues (account not READY, dataplane agent down, egress blocked)
- Air-gapped installer or action-hook failures

**Key capabilities**:
- Progressive debugging: status → workflow events → `instance debug` (rendered artifacts, apply logs) → live cluster access
- Per-resource-type branches: Compose / Helm / Terraform / Operator / Kustomize
- Per-deployment-model branches: hosted / BYOC / BYOC-K8s / air-gapped
- Pod-level investigation with kubectl via Omnistrate remote tunneling (no cloud-provider CLI)
- Rendered-artifact inspection via `instance debug`: chart values, `.tf` files, CR status (kustomize: workflow events + tunnel, no rendered-artifact view)
- Common failure-pattern recognition (infrastructure, container lifecycle, probe, per-model)

