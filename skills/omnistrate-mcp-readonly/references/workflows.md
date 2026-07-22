## Service Workflows

### List workflows for a service/environment

- MCP tool: `mcp__omnistrate__omnistrate-ctl_workflow_list`
- Command: `omnistrate-ctl workflow list --environment-id se-yhh3HZqM5H --service-id s-ThS3SMI6ec --instance-id instance-wzmso8e26 --limit 3 --output json`

Output (trimmed):
```json
[
  {
    "id": "submit-create-instance-wzmso8e26-1770732374478567",
    "status": "SUCCESS",
    "workflowType": "PROVISIONING",
    "cloudProvider": "gcp"
  }
]
```

### Workflow summary

- MCP tool: `mcp__omnistrate__omnistrate-ctl_workflow_summary`
- Command: `omnistrate-ctl workflow summary --environment-id se-yhh3HZqM5H --service-id s-ThS3SMI6ec --output json`

Output:
```json
[
  {
    "ActiveWorkflowCount": 0,
    "CompletedWorkflowCount": 57,
    "FailedWorkflowCount": 19
  }
]
```

### Workflow events (verbose)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_workflow_events`
- Command: `omnistrate-ctl workflow events submit-create-instance-wzmso8e26-1770732374478567 --service-id s-ThS3SMI6ec --environment-id se-yhh3HZqM5H --detail --max-events 2 --output json`

Output (trimmed, secrets redacted):
```json
{
  "resources": [
    {
      "resourceKey": "aerospike-cluster",
      "steps": [
        {
          "stepName": "Deployment",
          "status": "success",
          "detailedStep": { "events": [{ "eventType": "WorkflowStepCompleted" }] }
        }
      ]
    }
  ]
}
```

### Workflow describe

- MCP tool: `mcp__omnistrate__omnistrate-ctl_workflow_describe`
- Command: `omnistrate-ctl workflow describe submit-create-instance-wzmso8e26-1770732374478567 --service-id s-ThS3SMI6ec --environment-id se-yhh3HZqM5H --output json`

Output (trimmed):
```json
[
  {
    "WorkflowType": "PROVISIONING",
    "status": "SUCCESS",
    "servicePlanName": "Aerospike In-Memory Cluster (GCP)"
  }
]
```
