# Agent Instructions for Omnistrate

This repository contains comprehensive instructions and configurations for using AI agents to interact with Omnistrate. It enables seamless integration between popular AI coding assistants and the Omnistrate platform through the Model Context Protocol (MCP).

## Supported Agents

This repository provides instructions and MCP server configurations for the following AI agents:

- Claude Code
- Claude.ai and Claude for Desktop
- Cursor
- VS Code with Copilot
- Cline
- Windsurf
- Gemini Code Assist
- Gemini CLI
- Any MCP-capable agent

## What is MCP?

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io) is an open standard that allows AI agents to securely interact with external tools and services. This repository leverages MCP to enable agents to communicate with Omnistrate's APIs and services.

## Repository Structure

### Agent Configuration Files

- **[CLAUDE.md](./CLAUDE.md)** - Claude Code skill configuration
- **[AGENTS.md](./AGENTS.md)** - Generic agent instructions for all MCP-capable agents

### Skills

This repository organizes agent capabilities into specialized skills:

#### [**skills/omnistrate-fde/**](./skills/omnistrate-fde/) - Service Onboarding

Guide users through onboarding applications onto the Omnistrate platform.

- **SKILL.md** - Core onboarding workflow and decision guides
- **COMPOSE_ONBOARDING_REFERENCE.md** - Complete Docker Compose transformation reference

**Currently supported**: Docker Compose-based services with full deployment lifecycle management including compose spec transformation, API parameter configuration, compute/storage setup, and iterative debugging until instances are RUNNING.

**Planned support**: Helm charts, Terraform modules, Kustomize configurations, and Kubernetes operators (see [Omnistrate docs](https://docs.omnistrate.com/getting-started/overview/)).

#### [**skills/omnistrate-sre/**](./skills/omnistrate-sre/) - Deployment Debugging

Systematically debug failed Omnistrate deployments using a progressive workflow that identifies root causes efficiently.

- **SKILL.md** - Progressive debugging workflow
- **OMNISTRATE_SRE_REFERENCE.md** - Detailed debugging procedures and templates

**Capabilities**: Instance status analysis, workflow event analysis, pod-level investigation with kubectl, Helm-specific verification, and common failure pattern recognition.

## How to Use

### For Claude Code Users

Claude Code automatically discovers and uses skills defined in [CLAUDE.md](./CLAUDE.md). Simply start working with Omnistrate and Claude will invoke the appropriate skill based on your intent.

### For Other Agent Users

1. Read [AGENTS.md](./AGENTS.md) to understand available skills
2. Browse `skills/*/SKILL.md` files for workflow guidance
3. Consult `skills/*/*_REFERENCE.md` files for detailed syntax and examples
4. Configure your agent with the Omnistrate MCP server

### Quick Start

**Onboarding a service:**
1. Use the **omnistrate-fde** skill
2. Start with your Docker Compose file
3. Follow the transformation workflow
4. Build, deploy, and iterate until RUNNING

**Debugging a deployment:**
1. Use the **omnistrate-sre** skill
2. Start with deployment status analysis
3. Follow the progressive debugging workflow
4. Identify root cause and resolve issues

## MCP Tools Required

Both skills require the Omnistrate MCP server providing:
- `mcp__ctl__account_*` - Cloud account management
- `mcp__ctl__docs_*` - Documentation search
- `mcp__ctl__build_compose` - Service builds
- `mcp__ctl__service_plan_*` - Plan management
- `mcp__ctl__instance_*` - Instance operations
- `mcp__ctl__workflow_*` - Workflow analysis
- `mcp__ctl__deployment-cell_*` - Kubernetes access

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
