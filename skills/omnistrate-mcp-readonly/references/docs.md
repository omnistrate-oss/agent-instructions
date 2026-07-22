## Docs and Schemas

### Compose spec tag list

- MCP tool: `mcp__omnistrate__omnistrate-ctl_docs_compose-spec`
- Command: `omnistrate-ctl docs compose-spec --output json`

Output (trimmed):
```json
[
  { "available_tag": "Basic Structure" },
  { "available_tag": "x-omnistrate-compute" }
]
```

### Compose spec tag detail

- MCP tool: `mcp__omnistrate__omnistrate-ctl_docs_compose-spec`
- Command: `omnistrate-ctl docs compose-spec "x-omnistrate-compute" --output json`

Output (trimmed):
```json
[
  {
    "tag": "x-omnistrate-compute",
    "url": "https://docs.omnistrate.com/spec-guides/compose-spec/#x-omnistrate-compute"
  }
]
```

### System parameters schema

- MCP tool: `mcp__omnistrate__omnistrate-ctl_docs_system-parameters`
- Command: `omnistrate-ctl docs system-parameters --output json`

Output (trimmed):
```json
{
  "$id": "https://github.com/omnistrate/commons/model/cluster/schema/system-parameters",
  "$defs": {
    "SystemParameters": {
      "properties": {
        "compute": {},
        "deployment": {}
      }
    }
  }
}
```

### Docs search

- MCP tool: `mcp__omnistrate__omnistrate-ctl_docs_search`
- Command: `omnistrate-ctl docs search "deployment cell" --limit 5 --output json`

Output (trimmed):
```json
[
  {
    "title": "Deployment Cell Amenities",
    "url": "https://docs.omnistrate.com/operate-guides/deployment-cell-amenities/"
  }
]
```
