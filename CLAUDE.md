## Available Skills

### Onboarding Services to Omnistrate
**Location**: `skills/omnistrate-fde/`

Guide users through onboarding applications onto the Omnistrate platform. Currently supports Docker Compose-based services with full deployment lifecycle management. **CRITICAL**: (1) ALWAYS uses `hostedDeployment` (deploys in provider's account) unless user explicitly wants to offer BYOC to their customers, (2) ALWAYS starts with ZERO parameterization (hardcoded values) to ensure successful initial deployment, then adds API parameters incrementally ONLY when user explicitly requests customization.

**When to use**:
- Onboarding applications to Omnistrate platform
- Creating SaaS offerings with multi-tenant infrastructure
- Transforming Docker Compose files into Omnistrate service definitions
- Setting up customer-facing service catalogs

**Supported methods**:
- Docker Compose (fully supported)
- Helm, Terraform, Kustomize, Kubernetes Operators (planned - direct users to https://docs.omnistrate.com/getting-started/overview/)

**Key capabilities**:
- Compose spec transformation with validation
- Zero-parameterization initial builds (hardcoded defaults)
- Incremental API parameter addition (ONLY when user requests)
- Compute and storage resource setup
- Iterative debugging until instances are RUNNING
- Multi-service architecture with synthetic root patterns

### Debugging Omnistrate Deployments
**Location**: `skills/omnistrate-sre/`

Systematically debug failed Omnistrate instance deployments using a progressive workflow that identifies root causes efficiently while avoiding token limits.

**When to use**:
- Instance deployments showing FAILED or DEPLOYING status
- Resources with unhealthy pod statuses or deployment errors
- Startup/readiness probe failures (HTTP 503, timeouts)
- Helm releases with unclear deployment states
- Need to identify root cause of deployment failures

**Key capabilities**:
- Progressive debugging workflow (status → workflows → events → logs)
- Pod-level investigation with kubectl
- Helm-specific verification
- Common failure pattern recognition
- Infrastructure and application-level analysis

### Omnistrate Solutions Architect
**Location**: `skills/omnistrate-sa/`

Guide users through designing application architectures from scratch for SaaS deployment on Omnistrate. Focuses on technology selection, domain-specific patterns, compliance/SLA requirements, and iterative Docker Compose development. Handles transition from local development (with build contexts) to cloud deployment (with image registries). Output is a production-ready vanilla compose spec (without `x-omnistrate-*` extensions) that can be handed off to the FDE skill for Omnistrate-native transformation.

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
- Preparing compose specs for FDE skill transformation

**Do NOT use when**:
- User already has a complete compose spec with ALL services using `image:` references (no `build:` contexts) AND images are in accessible registries → Use **FDE skill** instead
- User needs to debug failed deployments → Use **SRE skill** instead

**Key capabilities**:
- Technology stack selection (frameworks, databases, caches, queues, storage)
- Domain-specific architecture patterns (API, ML, analytics, data platforms)
- Tenancy model design (shared, siloed, hybrid) informed by Omnistrate capabilities
- Deployment model planning (SaaS, BYOC, BYOC Copilot, On-Premise)
- Compliance and security architecture (SOC2, HIPAA, GDPR, PCI)
- SLA-driven availability design (99.9% to 99.999% uptime)
- Iterative Docker Compose spec development and validation
- Container image registry setup (convert build contexts to image references)
- Private registry authentication configuration (x-omnistrate-image-registry-attributes)
- Omnistrate-aware design decisions (autoscaling, backups, multi-zone readiness)

