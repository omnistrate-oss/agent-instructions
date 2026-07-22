---
name: omnistrate-mcp-readonly
description: Read-only Omnistrate MCP/omnistrate-ctl inspection workflows for onboarding. Use when you need to list or describe accounts, services, plans, instances, subscriptions, deployment cells, workflows, costs, docs, or secrets while explicitly avoiding create/update/delete actions and redacting sensitive fields.
---

# Omnistrate MCP Read-Only Inspection

## Workflow

1. List resources to collect IDs and environment IDs.
2. Describe or drill down using those IDs.
3. Trim verbose output to key fields and redact secrets.
4. Use the category reference that matches the user's request.

## Output Hygiene

- Use `--output json` by default and summarize only the top-level keys, IDs, and statuses.
- Redact any sensitive fields: `password`, `token`, `featureKey`, `cluster_endpoint` with creds, and rendered secrets in workflow events or helm values.
- If an output is huge, record a short excerpt plus counts (e.g., `total_entities`, `resource_count`).

## References (pick only what you need)

- Accounts: `references/accounts.md`
- IDs and filters: `references/ids-and-filters.md`
- Services and plans: `references/services-and-plans.md`
- Instances and debug data: `references/instances.md`
- Subscriptions: `references/subscriptions.md`
- Deployment cells: `references/deployment-cells.md`
- Workflows: `references/workflows.md`
- Upgrades: `references/upgrades.md`
- Costs: `references/costs.md`
- Docs search/specs/system parameters: `references/docs.md`
- Secrets (names only): `references/secrets.md`
- Custom networks (error handling): `references/custom-networks.md`
- Verbose output handling: `references/verbosity.md`
