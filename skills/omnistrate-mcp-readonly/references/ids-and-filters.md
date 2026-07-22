## IDs and Filters

Use list commands to collect IDs, then pass those IDs into describe/show tools.

### Common ID sources

- Service environment ID: `service describe` -> `serviceEnvironments[].id`
- Product tier ID: `service describe` or `service-plan list` -> `productTierID` / `plan_id`
- Deployment cell ID: `deployment-cell list` -> `id`
- Provider ID: `account describe` -> `cloudProviderId`
- Region ID: `deployment-cell list` -> `region_id`
- User ID: `instance describe` -> `createdByUserId`

### Filters to cut noise

Examples:

- `omnistrate-ctl service-plan list -f "service_id:s-ThS3SMI6ec" --output json`
- `omnistrate-ctl instance list -f "service:Aerospike,environment:Dev" --output json`
- `omnistrate-ctl subscription list -f "service_id:s-ThS3SMI6ec" --output json`

### Limits

Use `--limit` on workflow or version lists to avoid huge outputs.
