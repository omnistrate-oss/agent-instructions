## Subscriptions

### List subscriptions (use filters to avoid huge output)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_subscription_list`
- Command: `omnistrate-ctl subscription list -f "service_id:s-ThS3SMI6ec" --output json`

Output (trimmed):
```json
[
  {
    "subscription_id": "sub-QKlqdMzFnt",
    "service_id": "s-ThS3SMI6ec",
    "service_name": "Aerospike",
    "plan_id": "pt-DMgwsqxkag",
    "plan_name": "Aerospike In-Memory Cluster (GCP)",
    "environment": "Dev",
    "status": "ACTIVE"
  }
]
```

### Describe a subscription

- MCP tool: `mcp__omnistrate__omnistrate-ctl_subscription_describe`
- Command: `omnistrate-ctl subscription describe sub-QKlqdMzFnt --output json`

Output:
```json
{
  "subscription_id": "sub-QKlqdMzFnt",
  "service_id": "s-ThS3SMI6ec",
  "plan_id": "pt-DMgwsqxkag",
  "environment": "Dev",
  "status": "ACTIVE"
}
```

### List subscriptions for a service environment

- MCP tool: `mcp__omnistrate__omnistrate-ctl_subscription_list-for-service`
- Command: `omnistrate-ctl subscription list-for-service --environment-id se-yhh3HZqM5H --service-id s-ThS3SMI6ec --output json`

Output (trimmed):
```json
[
  {
    "ids": ["sub-QKlqdMzFnt", "sub-1kTKQPOZTC"],
    "subscriptions": [
      {
        "id": "sub-QKlqdMzFnt",
        "rootUserEmail": "drumilj+demo@omnistrate.com",
        "status": "ACTIVE"
      }
    ]
  }
]
```

### List subscription requests (none found)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_subscription_list-requests`
- Command: `omnistrate-ctl subscription list-requests --environment-id se-yhh3HZqM5H --service-id s-ThS3SMI6ec --output json`

Output:
```json
[
  { "ids": [] }
]
```
