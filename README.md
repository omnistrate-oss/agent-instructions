# Agent Instructions for Omnistrate

This repository contains agent skills for onboarding, operating, and debugging services on the Omnistrate platform. The skills drive the [`omnistrate-ctl`](https://docs.omnistrate.com/getting-started/installing-ctl/) command line tool by default, so any coding assistant that can run shell commands can use them.

## Prerequisite

Install and authenticate the Omnistrate CLI before using any skill:

1. Install `omnistrate-ctl` — see the [installation guide](https://ctl.omnistrate.cloud/install/) and the [CTL command reference](https://ctl.omnistrate.cloud/omnistrate-ctl/).
2. Log in: `omnistrate-ctl login` (the CLI is also aliased as `omctl`).

That is all the skills require. An Omnistrate MCP server is an optional add-on (see [Optional: MCP server](#optional-mcp-server)); use it only if you explicitly want an agent to work through MCP instead of the CLI.

## Supported Agents

Any assistant that can run `omnistrate-ctl` can use these skills, including:

- Claude Code
- Claude.ai and Claude for Desktop
- Cursor
- VS Code with Copilot
- Cline
- Windsurf
- Gemini Code Assist
- Gemini CLI

The same agents can optionally connect the Omnistrate MCP server if they prefer MCP tools over direct CLI calls.

## Repository Structure

### Agent Configuration Files

- **[CLAUDE.md](./CLAUDE.md)** - Claude Code skill configuration
- **[AGENTS.md](./AGENTS.md)** - Generic agent instructions for any CLI-capable agent

### Skills

This repository organizes agent capabilities into specialized skills:

#### [**skills/omnistrate-sa/**](./skills/omnistrate-sa/) - Solutions Architect

Guide users through designing application architectures from scratch for SaaS deployment on Omnistrate, including deployment-model discovery (hosted/BYOC/BYOC-K8s/air-gapped).

- **SKILL.md** - Architecture design workflow, deployment-model discovery, and technology selection
- **SOLUTIONS_ARCHITECT_REFERENCE.md** - Domain patterns, compliance checklists, SLA guidelines

**Capabilities**: Technology stack selection (frameworks, databases, caches, queues), domain-specific architecture patterns (AI/ML, analytics, APIs, data platforms), tenancy model design (shared, siloed, hybrid), deployment model planning (hosted, BYOC, BYOC-K8s, air-gapped), compliance and security architecture (SOC2, HIPAA, GDPR, PCI), SLA-driven availability design (99.9% to 99.999% uptime), iterative Docker Compose spec development.

**Use when**: Designing new SaaS applications from scratch, choosing technology stacks, architecting for specific domains/compliance/SLA requirements.

**Output**: Production-ready vanilla Docker Compose spec (without `x-omnistrate-*` extensions), or a ServicePlanSpec skeleton recommendation when the stack uses Helm, Terraform, or a Kubernetes operator — ready for FDE or operator-skill transformation.

#### [**skills/omnistrate-fde/**](./skills/omnistrate-fde/) - Service Onboarding (Universal Router)

The primary onboarding skill. Runs an intake interview, selects the right artifact method and deployment model, and drives the phased build-deploy-debug workflow. **Starts with zero parameterization** (hardcoded values) and iterates until instances are RUNNING.

- **SKILL.md** - Universal onboarding router, Decision Matrix, and phased workflow
- **COMPOSE_ONBOARDING_REFERENCE.md** - Docker Compose path: `x-omnistrate-*` transformation, API parameters, compute/storage, lifecycle
- **HELM_ONBOARDING_REFERENCE.md** - Helm `helmChartConfiguration`, values templating, multi-service `dependsOn`
- **TERRAFORM_KUSTOMIZE_REFERENCE.md** - Terraform/OpenTofu and Kustomize ServicePlanSpec, combined patterns
- **DEPLOYMENT_MODELS_REFERENCE.md** - Hosted / BYOC / BYOC-K8s / air-gapped `deployment:` blocks, customer account onboarding, ISV-phrasing FAQ
- **ONPREM_INSTALLER_REFERENCE.md** - Generic air-gapped/on-prem installer setup: multiple Helm releases, image registry copy resources, action hooks, runtime skips, and operator runbooks
- **BILLING_METERING_REFERENCE.md** - FinOps: Stripe end-to-end billing vs custom metering export, `pricing` dimensions, `billingProviders`, usage-export schema, custom dimensions and exporters, cloud marketplaces, cost insights
- **DISTRIBUTION_REFERENCE.md** - Release states, prod visibility, Customer Portal, subscriptions, go-live checklist, and the `DEPLOYMENT_OVERVIEW.md` + SVG artifact pair

**Supported artifact types**: Docker Compose, Helm charts, Terraform/OpenTofu modules, Kustomize overlays, and mixed stacks.

**Supported deployment models**: Hosted (provider cloud), BYOC including BYO-VPC and PrivateLink (customer cloud accounts), BYOC-K8s (customer-managed Kubernetes / `byoc-onprem`), and air-gapped (`onPremDeployment` installer, including complex multi-Helm / multi-registry graphs).

**Use when**: Onboarding any application to Omnistrate regardless of artifact type or deployment target.

#### [**skills/omnistrate-operator/**](./skills/omnistrate-operator/) - Kubernetes Operator Onboarding

Deep-dive onboarding for Kubernetes operator-based services (CRDs + controller). Owns `systemWorkflows` and lifecycle verb mapping.

- **SKILL.md** - Operator integration workflow, `systemWorkflows` authoring, canonical examples

**Use when**: Onboarding an operator-managed service (CloudNativePG, Strimzi, KubeAI, ECK, RabbitMQ operator, etc.) or writing/extending a ServicePlanSpec with `systemWorkflows`.

#### [**skills/omnistrate-sre/**](./skills/omnistrate-sre/) - Deployment Debugging

Systematically debug failed Omnistrate deployments across all resource types and all deployment models using a progressive workflow.

- **SKILL.md** - Progressive debugging workflow per resource type and deployment model
- **OMNISTRATE_SRE_REFERENCE.md** - Detailed debugging procedures, failure-pattern catalog, and templates

**Capabilities**: Instance status analysis, workflow event analysis, rendered-artifact debug (`instance debug`), pod-level investigation with kubectl via Omnistrate remote tunneling, and failure-pattern recognition across Compose / Helm / Terraform / Kustomize / Operator resources and hosted / BYOC / BYOC-K8s / air-gapped deployment models.

**Use when**: Instance deployments showing FAILED or DEPLOYING status, probe failures, Helm/Terraform/operator errors, BYOC agent or connectivity issues.

## Skill Decision Tree

Use this table to pick the right skill for a request:

| What the user has / wants | Deployment target | Skill to invoke |
|---------------------------|-------------------|-----------------|
| Nothing yet — design from scratch | any | **omnistrate-sa** |
| Compose file with `build:` contexts (local only) | any | **omnistrate-sa** (convert to image refs first) |
| Docker Compose (`image:` refs, no build contexts) | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-fde** |
| Helm chart | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-fde** |
| Terraform / OpenTofu module | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-fde** |
| Kustomize overlays | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-fde** |
| Mixed stack (e.g., Terraform infra + Helm app) | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-fde** |
| Kubernetes operator (CRDs + controller) | hosted / BYOC / BYOC-K8s | **omnistrate-operator** |
| Instance showing FAILED / DEPLOYING / probe errors | hosted / BYOC / BYOC-K8s / air-gapped | **omnistrate-sre** |

**Deployment model quick-map** (all models available for all artifact types via the FDE skill; the air-gapped installer packages Helm chart(s), so non-Helm stacks must first be bundled into chart(s)):

| Where instances run | Model name | Spec block |
|---------------------|------------|------------|
| Your (provider) cloud account | Hosted | `hostedDeployment` |
| Customer's cloud account (AWS/GCP/Azure/OCI) | BYOC / BYO-VPC / PrivateLink | `byoaDeployment` |
| Customer's own Kubernetes cluster | BYOC-K8s (`byoc-onprem`) | `byoaDeployment` |
| Fully disconnected / no internet | Air-gapped | `onPremDeployment` |

## Installing the Skills

Each skill is a self-contained directory under `skills/<skill-name>/` (SKILL.md + reference files + assets) in the open [Agent Skills](https://agentskills.io) format. Install the ones you need — `omnistrate-fde`, `omnistrate-operator`, `omnistrate-sre`, `omnistrate-sa`.

### Cross-agent (one command)

The [`skills` CLI](https://github.com/vercel-labs/skills) auto-detects your installed agents and places the skills in the right directories:

```bash
# All skills, all detected agents (add -g for personal/global scope)
npx skills add omnistrate-oss/agent-instructions

# A single skill for a specific agent
npx skills add omnistrate-oss/agent-instructions -s omnistrate-fde --agent claude-code
```

### Claude Code

Skills load from `~/.claude/skills/` (personal, all projects) or `.claude/skills/` (per project):

```bash
git clone https://github.com/omnistrate-oss/agent-instructions /tmp/agent-instructions
mkdir -p ~/.claude/skills
for s in omnistrate-fde omnistrate-operator omnistrate-sre omnistrate-sa; do
  cp -r "/tmp/agent-instructions/skills/$s" ~/.claude/skills/
done
```

### OpenAI Codex

Codex CLI supports the same SKILL.md format from `~/.agents/skills/` (personal) or `.agents/skills/` (per project):

```bash
git clone https://github.com/omnistrate-oss/agent-instructions /tmp/agent-instructions
mkdir -p ~/.agents/skills
for s in omnistrate-fde omnistrate-operator omnistrate-sre omnistrate-sa; do
  cp -r "/tmp/agent-instructions/skills/$s" ~/.agents/skills/
done
```

### GitHub Copilot

Copilot (coding agent, CLI, and VS Code agent mode) supports agent skills; install with the GitHub CLI (v2.90.0+):

```bash
gh skill install omnistrate-oss/agent-instructions omnistrate-fde
gh skill install omnistrate-oss/agent-instructions omnistrate-operator
gh skill install omnistrate-oss/agent-instructions omnistrate-sre
gh skill install omnistrate-oss/agent-instructions omnistrate-sa
# add --scope user for personal scope; project installs land in .github/skills/
```

## How to Use

### For Claude Code Users

Once installed (see [Installing the Skills](#installing-the-skills)), Claude Code discovers the skills automatically. Simply start working with Omnistrate and Claude will invoke the appropriate skill based on your intent; [CLAUDE.md](./CLAUDE.md) describes the routing between skills.

### For Other Agent Users

1. Read [AGENTS.md](./AGENTS.md) to understand available skills
2. Browse `skills/*/SKILL.md` files for workflow guidance
3. Consult `skills/*/*_REFERENCE.md` files for detailed syntax and examples
4. Ensure `omnistrate-ctl` is installed and logged in (see [Prerequisite](#prerequisite)); optionally connect the MCP server if you prefer working through MCP

### Quick Start

**Designing a new SaaS application:**
1. Use the **omnistrate-sa** skill
2. Start with requirements (domain, scale, compliance, SLA) and deployment-model discovery (hosted vs BYOC vs BYOC-K8s vs air-gapped)
3. Select appropriate technologies and architecture patterns
4. Iteratively develop Docker Compose spec (or recommend a Helm/Terraform skeleton if appropriate)
5. Handoff artifact to the FDE skill for Omnistrate-native transformation

**Onboarding a service (Docker Compose, Helm, Terraform, Kustomize, or mixed):**
1. Use the **omnistrate-fde** skill
2. Provide your artifact (compose file, Helm chart, Terraform module, etc.)
3. FDE runs intake to determine the deployment model (hosted / BYOC / BYOC-K8s / air-gapped)
4. Transform to Omnistrate-native with ZERO parameterization initially
5. Build, deploy, and iterate until RUNNING
6. Add API parameters and lifecycle incrementally as needed

**Onboarding a Kubernetes operator (CRDs + controller):**
1. Use the **omnistrate-operator** skill
2. Provide the operator name and CRD/CR examples
3. Skill authors the `systemWorkflows` ServicePlanSpec and lifecycle verbs

**Debugging a deployment:**
1. Use the **omnistrate-sre** skill
2. Start with deployment status analysis
3. Follow the progressive workflow (status → events → instance debug → live cluster access)
4. Skill branches by resource type (Compose / Helm / Terraform / Operator / Kustomize) and deployment model (hosted / BYOC / BYOC-K8s / air-gapped)

## Optional: MCP server

The skills default to the `omnistrate-ctl` CLI and need nothing beyond it. If you
prefer to have an agent work through the [Model Context Protocol](https://modelcontextprotocol.io)
instead of running CLI commands, you can connect the Omnistrate MCP server, which
exposes tools equivalent to the CLI subcommands. Set this up only if you
explicitly want MCP; it is never required.

Per-agent MCP configuration for read-only access lives in the
`skills/omnistrate-mcp-readonly/` skill. When connected, the server provides
tools that map to the same operations the CLI performs:

- `mcp__ctl__account_*` - Cloud account management (CLI: `omnistrate-ctl account ...`)
- `mcp__ctl__docs_*` - Documentation search (CLI default: the [docs site](https://docs.omnistrate.com))
- `mcp__ctl__build_compose` - Service builds (CLI: `omnistrate-ctl build ...`)
- `mcp__ctl__service_plan_*` - Plan management (CLI: `omnistrate-ctl service-plan ...`)
- `mcp__ctl__instance_*` - Instance operations (CLI: `omnistrate-ctl instance ...`)
- `mcp__ctl__workflow_*` - Workflow analysis (CLI: `omnistrate-ctl workflow ...`)
- `mcp__ctl__deployment-cell_*` - Kubernetes access (CLI: `omnistrate-ctl deployment-cell ...`)

## Contributing

To add new skills:
1. Follow [Claude's skill best practices](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices)
2. Create `skills/<skill-name>/` directory
3. Add `SKILL.md` with workflow and patterns
4. Add method-specific reference documentation
5. Update [CLAUDE.md](./CLAUDE.md) and [AGENTS.md](./AGENTS.md)

## Support

- **Omnistrate Documentation**: https://docs.omnistrate.com
- **Skill Best Practices**: https://docs.claude.com/en/docs/agents-and-tools/agent-skills/best-practices
- **Issues**: Report issues in this repository
