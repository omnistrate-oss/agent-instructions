# On-Prem Installer Reference

Use this reference for generic air-gapped / on-prem installer setup when a
ServicePlanSpec must package Helm releases, container images, customer-facing
configuration, and lifecycle scripts into a downloadable installer.

Core rule: an on-prem installer uses `deployment.onPremDeployment`. It is not
BYOC-K8s (`byoc-onprem`), and there is no live control-plane link after the
customer runs the installer.

---

## Functional Building Blocks

Build complex installers from these reusable functions:

| Function | Spec shape | Purpose |
|---|---|---|
| Installer metadata | `deployment.onPremDeployment` | Defines artifact hosting account and Kubernetes requirements. |
| Shared hook library | `deployment.onPremInstallerTools.helperUserScript` | Provides reusable shell functions to all action hooks. |
| Image sync | internal service with `containerImagesRegistryCopyConfiguration` | Copies images from source registries to the customer's registry. |
| Prerequisite Helm release | internal service with `helmChartConfiguration` | Installs cluster dependencies such as ingress, certs, storage, agents, or CRDs. |
| Application Helm release | customer-facing service with `helmChartConfiguration` | Installs the product chart and owns the user-visible parameters. |
| Parameter forwarding | `parameterDependencyMap` | Required when a value from one service must be passed to another service. |
| Conditional inclusion | `disable` or hook-level skip | Skips optional resources based on parameters or target-cluster state. |

Keep implementation details `internal: true` so the customer sees the product
resource, not registry mirrors or bootstrap charts.

---

## Deployment Block

Use `onPremDeployment` and optional Kubernetes requirements:

```yaml
name: My Application Installer
deployment:
  requirements:
    k8sVersion: ">=1.30.0"
  onPremDeployment:
    AwsAccountId: "<artifact-hosting-aws-account-id>"
    AWSBootstrapRoleAccountArn: "arn:aws:iam::<artifact-hosting-aws-account-id>:role/omnistrate-bootstrap-role"
  onPremInstallerTools:
    helperUserScript: |
      {{ $file:./scripts/installer_helpers.sh }}
```

Use `helperUserScript` for small generic functions used by several hooks:
logging, command checks, Kubernetes/Helm probes, skip wrappers, registry helpers,
or value-merge utilities. Keep product-specific logic in hook files referenced
with `$file`.

---

## Action Hooks

On-prem installer hooks live under `services[].actionHooks`, use
`scope: CLUSTER`, and run on the customer's cluster during installer execution.
There are four supported hook types: `VALIDATE`, `PRE_INSTALL`,
`POST_INSTALL`, and `BACKUP`.

| Hook type | When it runs | Common use |
|---|---|---|
| `VALIDATE` | Before install/upgrade, and for installer validation phases | Check `kubectl`/`helm`, cluster version, required CRDs, storage classes, existing releases, DNS/TLS prerequisites. May call `skip_resource_deployment` for an acceptable preexisting resource. |
| `PRE_INSTALL` | After validation, before Helm install/upgrade | Create namespaces, secrets, configmaps, pull secrets, certificates, or merge values from an existing install. |
| `POST_INSTALL` | After Helm install/upgrade succeeds | Wait for custom readiness, create marker resources, print access details, verify expected endpoints, or finalize generated config. |
| `BACKUP` | Before upgrades | Snapshot application state, export manifests/config, or run product-specific backup commands. |

Generic hook shape:

```yaml
actionHooks:
  - scope: CLUSTER
    type: VALIDATE
    commandTemplate: |
      {{ $file:./scripts/validate.sh }}
  - scope: CLUSTER
    type: PRE_INSTALL
    commandTemplate: |
      {{ $file:./scripts/pre_install.sh }}
  - scope: CLUSTER
    type: POST_INSTALL
    commandTemplate: |
      {{ $file:./scripts/post_install.sh }}
  - scope: CLUSTER
    type: BACKUP
    commandTemplate: |
      {{ $file:./scripts/backup.sh }}
```

Use `disable` when a parameter decides whether a resource should run. Use
`skip_resource_deployment` in a `VALIDATE` hook when the installer must inspect
the target cluster before deciding:

```bash
existing="$(helm list -A --all --short | grep -E '^my-prerequisite$' || true)"
if [ -n "${existing}" ]; then
  skip_resource_deployment "my-prerequisite already exists"
fi
```

Skip only if the existing resource is healthy and compatible. Exit non-zero when
the existing resource needs operator action.

---

## Image Sync Services

Use one internal image sync service per source registry or repository layout.
For air-gapped sites, prefer `INSTALLER_EMBED`: images are pulled during build
and packaged into the installer artifact.

```yaml
x-api-skip-image-sync: &api-skip-image-sync
  name: Skip Image Sync
  key: skipImageSync
  type: Boolean
  required: false
  export: true
  defaultValue: "false"
  modifiable: false

x-api-private-registry-url: &api-private-registry-url
  name: Private Image Registry URL
  key: privateRegistryUrl
  type: String
  required: true
  export: true
  modifiable: true

x-api-pull-mode: &api-pull-mode
  name: Pull Mode
  key: pullMode
  type: String
  required: true
  export: true
  modifiable: true
  defaultValue: "INSTALLER_EMBED"
  options:
    - INSTALLER_EMBED
    - RUNTIME_PULL

services:
  - name: AppImages
    internal: true
    apiParameters:
      - <<: *api-skip-image-sync
      - <<: *api-private-registry-url
      - <<: *api-pull-mode
    disable: "{{ $var.skipImageSync }}"
    containerImagesRegistryCopyConfiguration:
      pullMode: "{{ $var.pullMode }}"
      pullSource:
        registryURL: "docker.io"
        repositoryName: "my-org"
        credentials:
          username: "{{ $secret.SOURCE_REGISTRY_USERNAME }}"
          password: "{{ $secret.SOURCE_REGISTRY_PASSWORD }}"
      pushTarget:
        registryURL: "{{ $var.privateRegistryUrl }}"
        repositoryName: "my-org"
      images:
        - imageName: "app"
          imageTag: "1.0.0"
```

Rules:

- Use multiple image sync services when source registry, source repository, or
  source credentials differ.
- Keep image sync services `internal: true`.
- Do not put target registry credentials in `pushTarget`; the installer obtains
  target upload credentials during execution.
- Use `INSTALLER_EMBED` for disconnected installs. Use `RUNTIME_PULL` only when
  the installer environment can reach the source registry.

---

## Helm Release Services

Model each Helm release as its own service. Prerequisites usually stay internal;
the application chart is usually the customer-facing service.

```yaml
  - name: IngressController
    internal: true
    dependsOn:
      - IngressImages
    apiParameters:
      - <<: *api-skip-image-sync
        parameterDependencyMap:
          IngressImages: skipImageSync
      - <<: *api-private-registry-url
        parameterDependencyMap:
          IngressImages: privateRegistryUrl
      - <<: *api-pull-mode
        parameterDependencyMap:
          IngressImages: pullMode
    disable: "{{ $var.prerequisiteAlreadyInstalled }}"
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: |
          {{ $file:./scripts/ingress_validate.sh }}
      - scope: CLUSTER
        type: POST_INSTALL
        commandTemplate: |
          {{ $file:./scripts/ingress_post_install.sh }}
    helmChartConfiguration:
      chartName: ingress-nginx
      chartVersion: 4.15.1
      chartRepoName: ingress-nginx
      chartRepoURL: https://kubernetes.github.io/ingress-nginx
      releaseName: ingress-nginx
      namespace: ingress-nginx
      runtimeConfiguration:
        wait: true
        waitForJobs: true
      layeredChartValues:
        - scope:
            "{{ $var.skipImageSync }}": "true"
          values:
            global:
              image:
                registry: registry.k8s.io
        - scope:
            "{{ $var.skipImageSync }}": "false"
          values:
            global:
              image:
                registry: "{{ $var.privateRegistryUrl }}"
```

Use `dependsOn` for real ordering only:

- Helm service depends on the image sync service whose images it consumes.
- Later Helm releases depend on prerequisite Helm releases they require.
- Independent prerequisites should not depend on each other.

`dependsOn` does not pass parameter values by itself. If a parameter value from
one service must populate another service, define the parameter on each service
that needs it and add `parameterDependencyMap` on the upstream/customer-facing
parameter. Every service named in a `parameterDependencyMap` must declare the
target parameter key in its own `apiParameters`.

---

## Customer-Facing Application Service

Put shared customer inputs on the main service and forward them to internal
services:

```yaml
  - name: MyApplication
    dependsOn:
      - AppImages
      - IngressController
      - CertificateManager
    apiParameters:
      - name: Private Image Registry URL
        key: privateRegistryUrl
        type: String
        required: true
        export: true
        modifiable: true
        parameterDependencyMap:
          AppImages: privateRegistryUrl
          IngressController: privateRegistryUrl
          CertificateManager: privateRegistryUrl
      - name: Pull Mode
        key: pullMode
        type: String
        required: true
        export: true
        defaultValue: "INSTALLER_EMBED"
        options:
          - INSTALLER_EMBED
          - RUNTIME_PULL
        parameterDependencyMap:
          AppImages: pullMode
          IngressController: pullMode
          CertificateManager: pullMode
      - name: Release Name
        key: releaseName
        type: String
        required: false
        export: true
        modifiable: false
        defaultValue: "my-application"
      - name: Namespace
        key: namespace
        type: String
        required: false
        export: true
        modifiable: false
        defaultValue: "my-application"
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: |
          {{ $file:./scripts/validate.sh }}
      - scope: CLUSTER
        type: PRE_INSTALL
        commandTemplate: |
          {{ $file:./scripts/pre_install.sh }}
      - scope: CLUSTER
        type: POST_INSTALL
        commandTemplate: |
          {{ $file:./scripts/post_install.sh }}
      - scope: CLUSTER
        type: BACKUP
        commandTemplate: |
          {{ $file:./scripts/backup.sh }}
    helmChartConfiguration:
      chartName: my-application
      chartVersion: 1.0.0
      chartRepoName: my-org
      chartRepoURL: oci://registry-1.docker.io/my-org
      releaseName: "{{ $var.releaseName }}"
      namespace: "{{ $var.namespace }}"
      autoDiscoverImagesTag: "my-org.com/images"
      authProvider:
        username: "{{ $secret.SOURCE_REGISTRY_USERNAME }}"
        password: "{{ $secret.SOURCE_REGISTRY_PASSWORD }}"
```

Use `autoDiscoverImagesTag` when the chart can publish image metadata in
`Chart.yaml`; otherwise list images manually in the relevant image sync service.

---

## Build and Delivery Flow

1. Author the ServicePlanSpec with `onPremDeployment`.
2. Build and release the installer product:

```bash
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file installer-spec.yaml \
  --product-name "My Application Air-Gapped Installer" \
  --release \
  --release-description "v1.0.0 initial release"
```

3. Create an installer instance for the customer-facing resource.
4. Wait for installer readiness; API flows expose this as `INSTALLER_READY`.
5. Download the artifact:

```bash
omnistrate-ctl instance get-installer <instance-id> \
  --output-path ./installer.tar.gz
```

6. Give the customer an operator runbook: required `kubectl`, `helm`,
   kubeconfig, target registry credentials, expected prompts, install command,
   upgrade/backup steps, and diagnostics commands.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Treating air-gapped as BYOC-K8s | Use `onPremDeployment`, not `byoaDeployment` / `byoc-onprem`. |
| Exposing prerequisites or image sync as product resources | Set implementation resources `internal: true`. |
| Using `RUNTIME_PULL` for a disconnected site | Use `INSTALLER_EMBED`. |
| Combining images from different sources into one image sync service | Split image sync services by source registry/repository/credentials. |
| Expecting `dependsOn` to pass parameter values | Define the parameter on each service that needs it and wire it with `parameterDependencyMap`. |
| Skipping existing prerequisites unconditionally | Probe with `helm`/`kubectl`; skip only compatible healthy resources. |
| Omitting action hooks for lifecycle-sensitive products | Use `VALIDATE`, `PRE_INSTALL`, `POST_INSTALL`, and `BACKUP` as needed. |
| Debugging as if a control-plane tunnel exists | Use installer output, hook logs, local `kubectl`, and customer-provided diagnostics. |
