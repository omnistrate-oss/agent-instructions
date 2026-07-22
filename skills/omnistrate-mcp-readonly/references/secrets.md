## Secrets (Read-Only Names)

Only list secret names during onboarding. Do not fetch secret values unless you have explicit permission.

### List secrets

- MCP tool: `mcp__omnistrate__omnistrate-ctl_secret_list`
- Command: `omnistrate-ctl secret list dev --output json`

Output:
```json
{
  "secrets": [
    {
      "environment_type": "dev",
      "name": "CLAUDE_KEY"
    }
  ]
}
```

### Get a secret (name only)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_secret_get`
- Command: `omnistrate-ctl secret get dev CLAUDE_KEY --output json`

Output:
```json
{
  "environment_type": "dev",
  "name": "CLAUDE_KEY"
}
```
