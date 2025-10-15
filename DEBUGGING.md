# Omnistrate Instance Debugging Guide for Agents

## Overview
This guide provides a systematic approach for debugging failed Omnistrate deployments to avoid token limits and gather targeted information efficiently.

## Step-by-Step Debugging Process

### Step 1: Initial Instance Analysis
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_instance_describe`
**Purpose**: Get overall instance status and identify failed resources
**Parameters**: `--deployment-status --output json` for concise deployment status

```bash
omctl instance describe <instance-id> --deployment-status --output json
```

**Key Benefits of `--deployment-status` Flag**:
- Returns succinct deployment status for each resource
- Focuses on deployment errors and pod statuses
- Significantly reduces token usage compared to full describe
- Assumes resources without deployment errors or pod issues are healthy

**Key Data Points to Extract**:
- `status`: Overall instance status
- Resource-specific deployment status and errors
- Pod status indicators for problematic resources only
- Focus analysis on resources with deployment errors or unhealthy pod statuses

### Step 2: Workflow Analysis
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_workflow_list`
**Purpose**: Identify deployment workflows and their status

```bash
omctl workflow list --service-id <service-id> --environment-id <environment-id> --instance-id <instance-id> --output json
```

**Key Data Points to Extract**:
- Workflow IDs for failed deployments
- Start/end times to understand duration
- Workflow type (PROVISIONING, etc.)

### Step 3: Workflow Events Analysis (Improved Two-Phase Method)
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_workflow_events`
**Purpose**: Efficiently identify problematic resources and then deep-dive only where needed
**Strategy**: Start with summary view, then use detail flag for failed steps only

**Phase 1: Summary Overview (Primary Analysis)**:
```bash
# Get high-level summary of all resources and their workflow step status
omctl workflow events <workflow-id> --service-id <service-id> --environment-id <environment-id> --output json
```

**Key Benefits of Summary View**:
- Shows all resources with their workflow steps and status in one call
- Minimal token usage - safe for large workflows
- Identifies failed/in-progress steps immediately
- Provides event counts and time ranges for each step

**What to Look For in Summary**:
- Resources with steps showing `"status": "failed"`
- Resources with steps showing `"status": "in-progress"` for excessive duration
- Steps that should have completed but are stuck (compare start/end times)
- Event count patterns (high event counts often indicate failures with retries)

**Phase 2: Targeted Detail Analysis (Only When Needed)**:
```bash
# For specific failed resources/steps identified in Phase 1
omctl workflow events <workflow-id> --service-id <service-id> --environment-id <environment-id> \
  --resource-key <resource-name> --step-types <step-type> --detail --output json
```

**Available Parameters for Detail Analysis**:
- `--resource-key`: Filter to specific resource (e.g., "core-server", "database")
- `--step-types`: Filter to specific step types (e.g., "deployment", "bootstrap", "compute")
- `--detail`: Include full event details (use sparingly to avoid token limits)
- `--since/--until`: Time-bound the detailed analysis

**Implementation Strategy**:
1. **Always start with Phase 1** (summary) to identify all problematic resources
2. **Only use Phase 2** (detail) for specific failed steps identified in summary
3. **Target specific step types** when using detail flag to minimize token usage
4. **Time-bound detail queries** if step ran for extended periods

**Key Data Points to Extract from Summary**:
- Resource workflow step status (success/failed/in-progress)
- Step duration analysis (start time to end time)
- Event count indicators of retry/failure patterns
- Step type progression (Bootstrap → Compute → Deployment → Network → Storage → Monitoring)

**Key Data Points to Extract from Detail (when needed)**:
- Specific error messages in WorkflowStepDebug events
- Pod scheduling failure details
- VM allocation errors and constraints
- Container readiness/probe failure details

**Pod Event Timeline Analysis**:
When extracting pod events from workflow events or instance describe, create ASCII timeline visualizations to better understand deployment progression:

1. **Parse Event Data Structure**:
    - Extract timestamps from `eventTime` or `creationTimestamp`
    - Group events by pod name and event type
    - Identify key lifecycle phases: scheduling → image pulling → container startup → health checks

2. **Create ASCII Timeline Visualization**:
```
Pod Deployment Timeline
=======================

HH:MM:SS ┬─── [status symbol] [event description]
         │    [affected pods/details]
         │
HH:MM:SS ├─── [status symbol] [event description]
         │    [affected pods/details]
         │
HH:MM:SS └─── [status symbol] [final state]
              [summary information]
```

3. **Status Symbols for Events**:
    - `✗` Failed events (FailedScheduling, probe failures)
    - `✅` Success events (Scheduled, Started, Ready)
    - `⚡` Autoscaler events (scale-up triggers)
    - `💾` Storage events (volume attachments)
    - `📥` Image events (pulling containers)
    - `🚀` Runtime events (containers starting)
    - `⚠️` Warning events (restarts, health issues)

4. **Critical Event Categories**:
    - **Scheduling**: FailedScheduling, NotTriggerScaleUp/TriggeredScaleUp, Scheduled
    - **Storage**: SuccessfulAttachVolume, volume mount events
    - **Images**: Pulling, Pulled (with timing)
    - **Runtime**: Created, Started, health probe results
    - **Issues**: BackOff, Unhealthy, container restarts

5. **Timeline Organization Rules**:
    - Chronological order by actual timestamp
    - Group simultaneous events under same timestamp
    - Indent related pods/details consistently
    - Show duration for long operations (image pulls)
    - End with summary of final pod states

### Step 4: Resource-Specific Event Analysis
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_operations_events`
**Purpose**: Get targeted events for specific failed resources
**Strategy**: Make separate calls for each failed resource identified in Step 1

```bash
omctl operations events --instance-id <instance-id> --start-date <start-time> --end-date <end-time> --output json
```

**Filtering Strategy**:
- Use time windows from workflow analysis
- Filter by event types relevant to failures
- Make separate calls for different time ranges if needed

### Step 5: Deep Pod-Level Debugging (For Application-Level Failures)
**Use Case**: When there is no conclusive strong evidence of why deployment is failing from previous steps, especially:
- Resources are DEPLOYING but failing health/startup probes (HTTP 503, container readiness failures)
- Containers are Running but applications aren't starting properly
- Need to investigate actual application logs to understand root cause
  **Tool**: `mcp__omnistrate-platform__omnistrate-ctl_deployment-cell_update-kubeconfig` + kubectl commands
  **Purpose**: Access pod logs to understand application-level failures after containers have started

**Prerequisites**:
- Resource is in DEPLOYING status (not infrastructure failures)
- Pods are Running but failing startup/readiness probes
- Previous debugging steps haven't provided conclusive evidence of the failure cause
- Need application logs to understand root cause

**Implementation Strategy**:
```bash
# Step 5a: Setup kubeconfig access to the deployment cell
omctl deployment-cell update-kubeconfig <deployment-cell-id> --kubeconfig /tmp/kubeconfig

# Step 5b: Get detailed pod information for the failing resource
kubectl get pods -n <instance-id> --kubeconfig /tmp/kubeconfig

# Step 5c: Get logs from the failing pod(s) - focus on main service container
kubectl logs <pod-name> -c service -n <instance-id> --kubeconfig /tmp/kubeconfig --tail=50

# Step 5d: Check pod describe for additional context
kubectl describe pod <pod-name> -n <instance-id> --kubeconfig /tmp/kubeconfig
```

**Key Information to Extract**:
- Application startup logs and error messages
- Database connection failures
- Configuration issues
- Resource constraint errors
- Service dependency failures
- Authentication/authorization errors

**When to Use This Approach**:
1. **Insufficient Evidence from Previous Steps**: When workflow events and pod events don't provide clear root cause
2. **Probe Failures**: Resources showing startup/readiness probe failures (HTTP 503, timeouts)
3. **Container Running**: Pods are in "Running" status but not Ready
4. **Application-Level Issues**: Infrastructure is healthy but applications won't start
5. **Dependency Issues**: Need to verify service-to-service communication
6. **General Debugging**: When you need to investigate the actual application behavior and logs

**Fallback Strategy**:
If kubectl is not available or kubeconfig setup fails:
- Use pod events from `instance_describe` with `--resource-key` filtering
- Extract error messages from `resourceVersionSummaries.PodEvents`
- Analyze probe failure patterns from pod status information

### Step 6: Helm-Specific Debugging for Inconclusive Details
**Use Case**: When dealing with Helm-based resources and previous steps don't provide conclusive evidence about deployment status, especially:
- Instance shows DEPLOYING but Helm release status is unclear
- Need to verify actual Helm deployment status and get application credentials
- Want to confirm Helm revision and deployment details
- Need to check for Helm-specific configuration issues

**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_deployment-cell_update-kubeconfig` with cluster-admin role + helm commands
**Purpose**: Get definitive Helm release status and application access details

**Prerequisites**:
- Resource uses Helm deployment type
- Previous debugging steps show conflicting or insufficient information
- Need to verify actual Helm release state vs. workflow reports
- Deployment cell access is available

**Implementation Strategy**:
```bash
# Step 6a: Setup kubeconfig with cluster-admin access to get full Helm permissions
omctl deployment-cell update-kubeconfig <deployment-cell-id> --kubeconfig /tmp/kubeconfig --role cluster-admin

# Step 6b: Check Helm release status and details
helm list -n <instance-id> --kubeconfig /tmp/kubeconfig
helm status <release-name> -n <instance-id> --kubeconfig /tmp/kubeconfig

# Step 6c: Get pod status overview for the release
kubectl get pods -n <instance-id> --kubeconfig /tmp/kubeconfig

# Step 6d: Check for problematic pods if needed
kubectl get pods -n <instance-id> --kubeconfig /tmp/kubeconfig | grep -E "(CrashLoopBackOff|Pending|Error|ImagePullBackOff|Init|Terminating)"

# Step 6e: Get logs from specific failing pods if identified
kubectl logs <pod-name> -n <instance-id> --kubeconfig /tmp/kubeconfig --tail=50
kubectl describe pod <pod-name> -n <instance-id> --kubeconfig /tmp/kubeconfig
```

**Key Information to Extract from Helm Status**:
- **Release Status**: deployed, failed, pending-install, pending-upgrade
- **Revision Number**: Current revision and deployment history
- **Chart Details**: Chart name, version, app version
- **Last Deployed Time**: When the current revision was deployed
- **Release Notes**: Application-specific setup instructions and credentials
- **Namespace**: Confirm deployment namespace matches instance ID

**Key Information to Extract from Pod Analysis**:
- **Total Pod Count**: Overall scale of the deployment
- **Running vs Failed Ratio**: Health percentage of the application
- **Specific Failure Patterns**: CrashLoopBackOff, ImagePull issues, etc.
- **Resource-Specific Issues**: Which components are problematic
- **Application Logs**: Root cause analysis from container logs

**When to Use This Approach**:
1. **Conflicting Status Reports**: Workflow shows success but instance still DEPLOYING
2. **Helm Release Verification**: Need to confirm actual Helm deployment state
3. **Application Access Required**: Need to extract credentials or access URLs
4. **Complex Multi-Service Deployments**: Large deployments with many pods
5. **Post-Deployment Validation**: Verify deployment completed successfully
6. **Troubleshoot Background Jobs**: Identify non-critical job failures that might be blocking completion

**Expected Outcomes**:
- **Definitive Helm Status**: Clear deployed/failed state with revision details
- **Application Readiness**: Confirmation of service availability
- **Access Information**: Credentials, URLs, or connection details from Helm notes
- **Issue Identification**: Specific pods or services causing deployment delays
- **Root Cause Clarity**: Application-level vs infrastructure-level problems

**Integration with Overall Debugging Flow**:
Use this step when:
- Steps 1-5 show resource is "DEPLOYING" but no clear failure cause
- Helm-based resources report conflicting status information
- Need to distinguish between infrastructure success and application readiness
- Application endpoint is available but platform still shows DEPLOYING

### Step 7: Debug Information Gathering (Legacy)
**Tool**: `mcp__omnistrate-platform__omnistrate-ctl_instance_debug`
**Problem**: Often returns very large responses
**Alternative Approach**: Use the structured information from Steps 1-5 instead

## Common Failure Patterns and Analysis

### Container Restart Failures
**Indicators**:
- Pod events showing "Back-off restarting failed container"
- `ProcessLiveness: "UNHEALTHY"`
- `ConnectivityStatus: "UNHEALTHY"`

**Root Cause Analysis**:
1. Check pod events in `resourceVersionSummaries`
2. Look for resource dependency issues
3. Examine health check failures

### Startup/Readiness Probe Failures (New Pattern)
**Indicators**:
- Pod status: "Running" but not Ready
- Pod events: "Startup probe failed: HTTP probe failed with statuscode: 503"
- `ProcessLiveness: "UNHEALTHY"` but other health indicators healthy
- Multiple services showing identical probe failure patterns

**Root Cause Analysis Process**:
1. **Setup Kubeconfig Access**: Use deployment-cell update-kubeconfig
2. **Examine Pod Logs**: kubectl logs focusing on service container startup
3. **Check Dependencies**: Look for database/service connectivity issues
4. **Verify Configuration**: Check environment variables and config maps
5. **Analyze Patterns**: If multiple services fail identically, suspect common dependency

**Common Causes**:
- Database connection failures (PostgreSQL, MySQL timeouts)
- Message queue unavailability (RabbitMQ, Kafka connection issues)
- Authentication service problems (Keycloak, OAuth failures)
- Configuration missing or incorrect (environment variables, secrets)
- Resource constraints (memory limits causing OOM during startup)
- Network policies blocking service-to-service communication
- **Application syntax/runtime errors** (Python syntax errors, import failures, etc.)

**Example Log Analysis for Application Syntax Errors**:
When pod logs reveal application startup failures, look for patterns like:
```
# Python syntax error example (instance-eafmrkxbd):
File "/app/v1/routers/user_router.py", line 92
  logger.info(f"Getting permissions for user_name: {user_info["username"]}")
                                                             ^^^^^^^^
SyntaxError: f-string: unmatched '['

# Java compilation error example:
Exception in thread "main" java.lang.Error: Unresolved compilation problem

# Node.js import error example:
Error [ERR_MODULE_NOT_FOUND]: Cannot find module '/app/src/missing-module.js'
```

These application-level errors will cause the container to start but fail to serve traffic, resulting in probe failures.

### Service Dependencies
**Analysis Pattern**:
- If multiple services show FAILED status but only some show UNHEALTHY health
- Look for cascading failures from core services (databases, message queues)
- Check connectivity between services

## Implementation Strategy for Agents

### 1. Resource Prioritization
When multiple resources are failed:
1. **Core Infrastructure First**: Databases, message queues, storage
2. **Application Services Second**: Web servers, APIs
3. **Support Services Last**: Monitoring, logging

### 2. Information Gathering Sequence (Updated for Efficiency)
```
instance_describe(--deployment-status) // Get concise deployment status, focus on resources with issues
-> identify_failed_resources_from_deployment_status()
-> workflow_list()
-> workflow_events_summary(workflow_id) // PHASE 1: Get all resources status overview
-> analyze_failed_steps_from_summary()
-> for each failed_step_identified:
     workflow_events_detail(workflow_id, resource_key, step_types, detail=true) // PHASE 2: Targeted details
-> if no conclusive strong evidence found OR resource is DEPLOYING with probe failures:
     deployment_cell_update_kubeconfig(deployment_cell_id)
     kubectl_logs_analysis(pod_name, container=service)
-> if helm_resource && (conflicting_status_reports OR need_application_access):
     deployment_cell_update_kubeconfig(deployment_cell_id, role=cluster-admin)
     helm_status_analysis(release_name, namespace)
     pod_overview_analysis_for_helm()
-> if still need broader context:
     operations_events(time_window_for_resource)
-> parse_resource_specific_failures()
-> compile_failure_analysis()
```

**Key Enhancement**: The workflow events tool now provides a two-phase approach:
1. **Summary View**: Overview of all resources and workflow steps without token limits
2. **Detail View**: Targeted deep-dive with `--detail` flag only for failed steps

### 3. Response Management
- Always use `--output json` for structured parsing
- If a tool returns "exceeds maximum allowed tokens":
    - Try more specific filters
    - Break down the request into smaller time windows
    - Focus on specific resources or event types
    - Use alternative tools with more targeted queries

### 4. Failure Analysis Template
```
## Instance: <instance-id>
## Overall Status: <status>
## Failed Resources:
- Resource: <name> | Status: <status> | Health: <health>
- Key Events: <events>
- Probable Cause: <analysis>

## Root Cause Analysis:
<detailed analysis based on events and resource interdependencies>

## Recommended Actions:
<actionable steps for resolution>
```

## Example Usage Pattern

### Instance-a9x2m4pvqr Failure Analysis Using New Resource-Targeted Approach:

1. **Step 1 - Instance Describe with Deployment Status**: Used `--deployment-status` flag to get concise status
2. **Step 2 - Identified Failed Resources**: neo4j (deployment errors), rabbitmq (pod status issues)
3. **Step 3 - Resource-Targeted Workflow Events**:
   ```bash
   omctl workflow events submit-create-instance-a9x2m4pvqr-1734567890123456 \
     --service-id s-k8Lp5Q2mX9 --environment-id se-YhVnRuWzLm \
     --resource-key neo4j --output json
   ```
4. **Root Cause Analysis**:
    - VM allocation failures: "Allocation failed. VM(s) with the following constraints cannot be allocated"
    - Constraints too restrictive: Availability Zone + Networking + VM Size
    - Pod scheduling failures: PersistentVolumeClaim not found, node taints
    - Network step timed out waiting for service endpoints
    - Container never became ready due to infrastructure issues

5. **Key Timeline from Workflow Events**:
    - 14:23:15 - Bootstrap, Compute, Deployment, Network, Storage steps started
    - 14:23:32 - First pod scheduling failure (PVC not found)
    - 14:23:42 - Cluster autoscaler triggered scale-up
    - 14:28:51 - Node affinity issues after scale-up
    - 15:23:17 - Network step failed (timeout waiting for service endpoints)
    - Multiple VM allocation retries throughout deployment

This targeted approach revealed the actual infrastructure constraint issues rather than just container restart symptoms.

## Parsing Workflow Events for Resource-Specific Analysis

When workflow events succeed in returning data, extract resource-specific information by:

### 1. Resource Event Filtering
Look for events containing resource names identified in Step 1:
```json
// Search for events mentioning failed resources like "neo4j", "rabbitmq"
events.filter(event => event.resourceName === "neo4j" || event.message.includes("neo4j"))
```

### 2. Event Type Prioritization
Focus on critical event types:
- Container/Pod restart events
- Health check failures
- Deployment failures
- Resource provisioning errors

### 3. Timeline Analysis
- Map events to deployment sequence using ASCII timeline visualization (see Pod Event Timeline Analysis in Step 3)
- Identify when each resource started failing
- Find root cause by chronological analysis
- Create visual timeline charts showing scheduling, image pulling, and container startup phases

### 4. Dependency Chain Analysis
- Track which resource failed first
- Identify cascading failures
- Map resource interdependencies from event sequence

## Best Practices

1. **Start Broad, Then Focus**: Use describe first, then drill down into specific failures
2. **Time-bound Queries**: Use start/end dates to limit response sizes
3. **Resource-specific Analysis**: Make separate calls for each failed resource
4. **Dependency Mapping**: Understand service interdependencies for root cause analysis
5. **Event Correlation**: Match pod events with health status changes
6. **Timeline Visualization**: Create ASCII timeline charts for pod events to clearly show deployment progression, failures, and timing relationships
7. **Progressive Debugging**: If one tool fails with token limits, use alternative approaches

## Tool Alternatives for Large Responses

| Primary Tool | Alternative Approach | When to Use |
|-------------|---------------------|-------------|
| `workflow_events` | `operations_events` with filters | When workflow events exceed token limit |
| `instance_debug` | `instance_describe` + targeted queries | When debug output is too large |
| Large time ranges | Multiple smaller time windows | When date ranges return too much data |

This systematic approach ensures comprehensive failure analysis while avoiding token limits and gathering actionable debugging information.%       