## Services and Plans

### List services

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service_list`
- Command: `omnistrate-ctl service list --output json`

Output (trimmed):
```json
[
  {
    "id": "s-ThS3SMI6ec",
    "name": "Aerospike",
    "environments": "Dev"
  }
]
```

### Describe a service (get environment IDs)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service_describe`
- Command: `omnistrate-ctl service describe --id s-ThS3SMI6ec --output json`

Output (trimmed):
```json
{
  "id": "s-ThS3SMI6ec",
  "name": "Aerospike",
  "serviceEnvironments": [
    {
      "id": "se-yhh3HZqM5H",
      "name": "Dev",
      "servicePlans": [
        {
          "name": "Aerospike In-Memory Cluster (GCP)",
          "productTierID": "pt-DMgwsqxkag",
          "latestMajorVersion": "20.0"
        }
      ]
    }
  ]
}
```

### List plans for a service

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service-plan_list`
- Command: `omnistrate-ctl service-plan list -f "service_id:s-ThS3SMI6ec" --output json`

Output (trimmed):
```json
[
  {
    "plan_id": "pt-DMgwsqxkag",
    "plan_name": "Aerospike In-Memory Cluster (GCP)",
    "environment": "Dev"
  }
]
```

### Describe a plan

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service-plan_describe`
- Command: `omnistrate-ctl service-plan describe --service-id s-ThS3SMI6ec --plan-id pt-DMgwsqxkag --output json`

Output (trimmed, secrets redacted):
```json
{
  "plan_id": "pt-DMgwsqxkag",
  "enabled_features": [
    { "feature": "LOGS", "scope": "CUSTOMER" }
  ],
  "resources": [
    {
      "resource_id": "r-0tlaUMPI50",
      "resource_name": "aerospike-cluster",
      "resource_type": "HelmChart",
      "helm_chart_configuration": {
        "chartName": "acms-aerospike-stack",
        "chartRepoUrl": "oci://ghcr.io/omnistrate/demos-aerospike",
        "password": "<redacted>"
      }
    }
  ]
}
```

### List plan versions

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service-plan_list-versions`
- Command: `omnistrate-ctl service-plan list-versions --service-id s-ThS3SMI6ec --plan-id pt-DMgwsqxkag --limit 3 --output json`

Output (trimmed):
```json
[
  { "version": "20.0", "release_description": "aeropeek lb", "version_set_status": "Active" }
]
```

### Describe a plan version

- MCP tool: `mcp__omnistrate__omnistrate-ctl_service-plan_describe-version`
- Command: `omnistrate-ctl service-plan describe-version --service-id s-ThS3SMI6ec --plan-id pt-DMgwsqxkag --version 20.0 --output json`

Output (trimmed, secrets redacted):
```json
{
  "version": "20.0",
  "resources": [
    {
      "resource_id": "r-0tlaUMPI50",
      "resource_name": "aerospike-cluster",
      "helm_chart_configuration": {
        "chartName": "acms-aerospike-stack",
        "password": "<redacted>",
        "featureKey": "<redacted>"
      }
    }
  ]
}
```
