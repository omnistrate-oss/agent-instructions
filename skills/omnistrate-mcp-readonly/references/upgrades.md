## Upgrades (Read-Only)

### List upgrade paths

- MCP tool: `mcp__omnistrate__omnistrate-ctl_upgrade_list`
- Command: `omnistrate-ctl upgrade list --service-id s-ThS3SMI6ec --product-tier-id pt-DMgwsqxkag --page-size 5 --output json`

Output (trimmed):
```json
[
  {
    "upgradePaths": [
      {
        "upgradePathId": "upgrade-EZB53Q1b3A",
        "status": "FAILED",
        "sourceVersion": "7.0",
        "targetVersion": "8.0"
      }
    ]
  }
]
```

### Describe an upgrade path

- MCP tool: `mcp__omnistrate__omnistrate-ctl_upgrade_describe`
- Command: `omnistrate-ctl upgrade describe upgrade-EZB53Q1b3A --service-id s-ThS3SMI6ec --product-tier-id pt-DMgwsqxkag --output json`

Output (trimmed):
```json
[
  {
    "upgradePathId": "upgrade-EZB53Q1b3A",
    "status": "FAILED",
    "failedCount": 1
  }
]
```

### Upgrade status detail

- MCP tool: `mcp__omnistrate__omnistrate-ctl_upgrade_status_detail`
- Command: `omnistrate-ctl upgrade status detail upgrade-EZB53Q1b3A --output json`

Output:
```
(empty output returned)
```
