## Deployment Cells

### List deployment cells

- MCP tool: `mcp__omnistrate__omnistrate-ctl_deployment-cell_list`
- Command: `omnistrate-ctl deployment-cell list --output json`

Output (trimmed):
```json
[
  {
    "id": "hc-9c5ok6tmv",
    "status": "RUNNING",
    "cloud_provider": "gcp",
    "region": "us-central1",
    "current_number_of_deployments": 4,
    "health_status": {
      "overall_status": "HEALTHY",
      "failed_entities": 1
    }
  }
]
```

### Deployment cell status

- MCP tool: `mcp__omnistrate__omnistrate-ctl_deployment-cell_status`
- Command: `omnistrate-ctl deployment-cell status --id hc-9c5ok6tmv --output json`

Output (trimmed):
```json
[
  {
    "id": "hc-9c5ok6tmv",
    "status": "RUNNING",
    "health_status": {
      "overall_status": "HEALTHY",
      "failed_entities_by_type": { "GCS_FILESTORE": 1 }
    }
  }
]
```

### Describe config template (org + cell)

- MCP tool: `mcp__omnistrate__omnistrd599c9dc2af290fce6db007be1553188db4c35c1`
- Commands:
  - `omnistrate-ctl deployment-cell describe-config-template --cloud aws --output json`
  - `omnistrate-ctl deployment-cell describe-config-template --id hc-9c5ok6tmv --output json`

Output (org template, trimmed):
```json
{
  "managed_amenities": [
    { "name": "AWS Load Balancer Controller", "type": "Helm" },
    { "name": "Kubernetes Dashboard", "type": "Helm" }
  ]
}
```

Output (cell template, trimmed):
```json
{
  "managed_amenities": [
    { "name": "Observability Prometheus", "type": "Helm" }
  ]
}
```

### Deployment cell workflows

- MCP tools: `mcp__omnistrate__omnistrate-ctl_deployment-cell_workflow_list`,
  `mcp__omnistrate__omnistrate-ctl_deployment-cell_workflow_events`,
  `mcp__omnistrate__omnistred8bc8381e5569e73dcab63cd8bb40f5993bd44b`
- Commands:
  - `omnistrate-ctl deployment-cell workflow list hc-9c5ok6tmv --limit 3 --output json`
  - `omnistrate-ctl deployment-cell workflow events hc-9c5ok6tmv redeploy-hc-9c5ok6tmv-1770322072085870809 --output json`
  - `omnistrate-ctl deployment-cell workflow describe hc-9c5ok6tmv redeploy-hc-9c5ok6tmv-1770322072085870809 --output json`

Output (list, trimmed):
```json
[
  {
    "id": "redeploy-hc-9c5ok6tmv-1770322072085870809",
    "status": "SUCCESS",
    "workflowType": "DEPLOYMENT_CELL_REDEPLOY"
  }
]
```

Output (events, trimmed):
```json
[
  {
    "eventsPerWorkflowStep": [
      { "stepName": "Infrastructure", "events": [{ "eventType": "WorkflowStepCompleted" }] }
    ]
  }
]
```
