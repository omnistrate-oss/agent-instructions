# AI Instructions for Omnistrate

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

## Repository Contents

### [**COMPOSE-ONBOARDING.md**](./COMPOSE-ONBOARDING.md) - Omnistrate Onboarding Instructions

Step-by-step instructions for transforming a Docker Compose file into an Omnistrate-enabled service definition. This guide covers the complete transformation process including service plan configuration, API parameter definition, compute and storage resource configuration, and deployment testing. It provides detailed patterns for single-service and multi-service applications, environment variable interpolation with system parameters, and production readiness validation.

### [**DEBUGGING.md**](./DEBUGGING.md) - Omnistrate Debugging Instructions

Systematic approach for debugging failed Omnistrate deployments with a focus on efficiency and avoiding token limits. This guide provides a structured seven-step debugging process including instance analysis, workflow analysis, pod-level debugging with kubectl, and Helm-specific debugging. It includes common failure patterns, analysis templates, and best practices for identifying root causes of deployment failures.

### **LICENSE** - Repository License

Standard open-source license for this repository.

## How to use the Agent Instructions

1. Choose your preferred AI agent (Claude, GitHub Copilot, or another MCP-capable agent)
2. Configure the MCP server connection to Omnistrate
3. Start with **ONBOARDING.md** to transform your Docker Compose file into an Omnistrate service
4. Use **DEBUGGING.md** if you encounter deployment issues
5. Iterate and refine your service configuration

## Support

For issues, questions, or contributions, please refer to the Omnistrate documentation or open an issue in this repository.
