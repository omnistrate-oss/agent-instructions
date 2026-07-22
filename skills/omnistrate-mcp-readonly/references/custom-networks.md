## Custom Networks

### List custom networks

- MCP tool: `mcp__omnistrate__omnistrate-ctl_custom-network_list`
- Command: `omnistrate-ctl custom-network list --output json`

Observed output (error):
```
Error: failed_request
Detail: An internal error occurred
```

### Describe a custom network (requires ID)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_custom-network_describe`
- Command: `omnistrate-ctl custom-network describe --custom-network-id <id> --output json`

Observed output when ID is missing:
```
Error: required flag(s) "custom-network-id" not set
```

If this persists, retry with a filter (e.g., `--filter "cloud_provider:aws"`). If the error remains, record the failure and proceed with other onboarding checks.
