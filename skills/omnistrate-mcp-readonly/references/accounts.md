## Accounts

### List accounts

- MCP tool: `mcp__omnistrate__omnistrate-ctl_account_list`
- Command: `omnistrate-ctl account list --output json`

Output (trimmed):
```json
[
  {
    "id": "ac-95b1fB9j1U",
    "name": "Config for 383746634676",
    "status": "READY",
    "cloud_provider": "GCP",
    "target_account_id": "omnistrate-test-dp(ProjectID: 383746634676)"
  }
]
```

Key fields to capture: `id`, `status`, `cloud_provider`, `target_account_id`.

### Describe an account

- MCP tool: `mcp__omnistrate__omnistrate-ctl_account_describe`
- Command: `omnistrate-ctl account describe ac-mvXOrKxkg6 --output json`

Output (trimmed, long URLs omitted):
```json
{
  "id": "ac-mvXOrKxkg6",
  "name": "AWS Demo Account",
  "awsAccountID": "541226919566",
  "awsBootstrapRoleARN": "arn:aws:iam::541226919566:role/omnistrate-bootstrap-role",
  "cloudProviderId": "infra-qcOqbk99LS",
  "status": "READY",
  "statusMessage": "account verified"
}
```

Key fields to capture: `cloudProviderId` (used in cost tools), `awsAccountID`, `status`.
