## Costs

All cost tools require: `--start-date`, `--end-date`, `--environment`, and `--frequency`. Use `DAILY` or `MONTHLY` for `--frequency` (uppercase accepted by the API).

### List costs by provider

- MCP tool: `mcp__omnistrate__omnistrate-ctl_cost_by-provider_list`
- Command:
  `omnistrate-ctl cost by-provider list --environment prod --start-date 2026-02-04T00:00:00Z --end-date 2026-02-11T23:59:59Z --frequency DAILY --output json`

Output (trimmed):
```json
[
  {
    "cloudProviderCosts": {
      "infra-RLOcAyh4ge": {
        "cloudProviderName": "gcp",
        "totalCost": 94.5881360933333
      },
      "infra-qcOqbk99LS": {
        "cloudProviderName": "aws",
        "totalCost": 5.914300000000001
      }
    }
  }
]
```

### Provider show/compare

- MCP tools: `mcp__omnistrate__omnistrate-ctl_cost_by-provider_show`,
  `mcp__omnistrate__omnistrate-ctl_cost_by-provider_compare`
- Commands:
  - `omnistrate-ctl cost by-provider show infra-RLOcAyh4ge --environment prod --start-date ... --end-date ... --frequency DAILY --output json`
  - `omnistrate-ctl cost by-provider compare infra-qcOqbk99LS infra-RLOcAyh4ge --environment prod --start-date ... --end-date ... --frequency DAILY --output json`

### Region list/show/compare/in-provider

- MCP tools: `mcp__omnistrate__omnistrate-ctl_cost_by-region_list`,
  `mcp__omnistrate__omnistrate-ctl_cost_by-region_show`,
  `mcp__omnistrate__omnistrate-ctl_cost_by-region_compare`,
  `mcp__omnistrate__omnistrate-ctl_cost_by-region_in-provider`
- Example show output (trimmed):
```json
[
  {
    "regionCosts": {
      "region-ZAFH4vpi6G": {
        "regionName": "us-central1",
        "totalCost": 94.5881360933333
      }
    }
  }
]
```

### Cell/instance/user costs (frequently empty)

Observed outputs for the same time range:

- `cost by-cell list/show/compare/in-provider/in-region`:
```json
[
  {}
]
```

- `cost by-instance list/show/compare/top/in-cell`:
```
No instance cost data found
```

- `cost by-instance-type list/show/top/in-cell/in-region`:
```
No instance type cost data found
```

- `cost by-user list/show/compare/top/top-instances`:
```json
[
  {}
]
```

### Common errors (record and retry)

Missing required flags:
```
Error: required flag(s) "end-date", "environment", "start-date" not set
```

Invalid frequency (use `DAILY` or `MONTHLY`):
```
Detail: Invalid request: invalid frequency. Supported values are DAILY and MONTHLY
```
