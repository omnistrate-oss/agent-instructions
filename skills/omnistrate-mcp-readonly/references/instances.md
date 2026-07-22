## Instances

### List instances

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_list`
- Command: `omnistrate-ctl instance list --output json`

Output (trimmed):
```json
[
  {
    "instance_id": "instance-wzmso8e26",
    "service": "Aerospike",
    "environment": "Dev",
    "plan": "Aerospike In-Memory Cluster (GCP)",
    "version": "20.0",
    "resource": "aerospike-cluster",
    "cloud_provider": "gcp",
    "region": "us-central1",
    "status": "RUNNING"
  }
]
```

### Describe an instance

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_describe`
- Command: `omnistrate-ctl instance describe instance-wzmso8e26 --output json`

Output (trimmed, endpoints redacted):
```json
{
  "deploymentCellID": "hc-9c5ok6tmv",
  "environmentId": "se-yhh3HZqM5H",
  "serviceId": "s-ThS3SMI6ec",
  "productTierId": "pt-DMgwsqxkag",
  "status": "RUNNING",
  "consumptionResourceInstanceResult": {
    "resourceID": "r-0tlaUMPI50",
    "detailedNetworkTopology": {
      "r-0tlaUMPI50": {
        "resourceKey": "aerospike-cluster",
        "additionalEndpoints": { "primary": { "endpoint": "<redacted>" } }
      }
    }
  }
}
```

### List instance endpoints

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_list-endpoints`
- Command: `omnistrate-ctl instance list-endpoints instance-wzmso8e26 --output json`

Output (trimmed, credentials redacted):
```json
{
  "Omnistrate Observability": {
    "cluster_endpoint": "<redacted>"
  },
  "aerospike-cluster": {
    "additional_endpoints": {
      "primary": { "endpoint": "r-0tlaumpi50.instance-wzmso8e26..." }
    }
  }
}
```

### List snapshots (none found)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_list-snapshots`
- Command: `omnistrate-ctl instance list-snapshots instance-wzmso8e26 --output json`

Output:
```json
{}
```

If this is empty, skip `instance describe-snapshot` until you have a real snapshot ID.

### Helm logs and values (verbose)

- MCP tools: `mcp__omnistrate__omnistrate-ctl_instance_debug_helm-logs`, `mcp__omnistrate__omnistrate-ctl_instance_debug_helm-values`
- Commands:
  - `omnistrate-ctl instance debug helm-logs instance-wzmso8e26 --resource-key aerospike-cluster --output json`
  - `omnistrate-ctl instance debug helm-values instance-wzmso8e26 --resource-key aerospike-cluster --output json`

Output excerpt (logs):
```json
{
  "resources": [
    {
      "resourceKey": "aerospike-cluster",
      "installLog": "preparing upgrade... Deployment is not ready: ... 0 out of 1 expected pods are ready"
    }
  ]
}
```

Output excerpt (values, secrets redacted):
```json
{
  "resources": [
    {
      "resourceKey": "aerospike-cluster",
      "chartValues": {
        "aerospikeCluster": {
          "image": "aerospike/aerospike-server-enterprise:8.0.0.1",
          "size": 3
        },
        "bootstrap": {
          "secrets": {
            "admin": { "password": "<redacted>" },
            "featureKey": "<redacted>"
          }
        }
      }
    }
  ]
}
```

### Terraform output/files (empty for this instance)

- MCP tools: `mcp__omnistrate__omnistrate-ctl_instance_debug_terraform-output`, `mcp__omnistrate__omnistrate-ctl_instance_debug_terraform-files`
- Commands:
  - `omnistrate-ctl instance debug terraform-output instance-wzmso8e26 --resource-key aerospike-cluster --output json`
  - `omnistrate-ctl instance debug terraform-files instance-wzmso8e26 --resource-key aerospike-cluster --output json`

Output:
```json
{ "instanceId": "instance-wzmso8e26", "resources": [] }
```

### Evaluate expressions

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_evaluate`
- Command: `omnistrate-ctl instance evaluate instance-wzmso8e26 aerospike-cluster --expression "$sys.id" --output json`

Output:
```json
{ "result": "instance-wzmso8e26" }
```

### Deployment parameters

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_deployment-parameters`
- Command: `omnistrate-ctl instance deployment-parameters --service "Aerospike" --plan "Aerospike In-Memory Cluster (GCP)" --version 20.0 --resource "aerospike-cluster" --output json`

Output (trimmed):
```json
{
  "parameters": [
    { "key": "adminPassword", "type": "String", "required": true },
    { "key": "clusterSize", "type": "Float64", "defaultValue": "3" }
  ]
}
```

### Download installer (writes a file)

- MCP tool: `mcp__omnistrate__omnistrate-ctl_instance_get-installer`
- Command: `omnistrate-ctl instance get-installer instance-l4nmjr5k1 --output-path /tmp/installer-instance-l4nmjr5k1.tar.gz --output json`

Output:
```
Successfully downloaded installer to /tmp/installer-instance-l4nmjr5k1.tar.gz
```
