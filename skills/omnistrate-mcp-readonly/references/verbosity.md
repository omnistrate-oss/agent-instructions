## Verbose Output Handling

Use this whenever a command returns large JSON blobs (plan details, instance describe, helm values, workflow events).

### Keep only key fields

- IDs, names, status, environment, provider, region.
- Counts (e.g., `total_entities`, `failed_entities`, `resource_count`).
- One representative object from large arrays.

### Redact sensitive fields

Always replace values with `<redacted>` for:

- `password`, `token`, `featureKey`, `provider_password`
- `cluster_endpoint` values with embedded credentials (e.g., `user:pass@host`)
- Workflow event messages that include rendered helm values or secrets

### Trim strategy

- Prefer `--output json` and record only the excerpt you need.
- For long lists, add filters (`--filter` or `--limit`) before re-running.
- If a tool returns a repeated error message, keep one short example and summarize the rest.
