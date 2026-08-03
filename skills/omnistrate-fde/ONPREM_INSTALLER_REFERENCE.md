# On-Prem Installer Reference

Use this reference when an air-gapped / on-prem installer needs more than a
single Helm release: prerequisite charts, several image sources, private target
registries, runtime skips, or customer-cluster validation. The source patterns
come from the Omnistrate air-gapped Helm guide and the
`omni-test-github-action/test/e2e-test/onprem-installer` e2e spec.

Core rule: an on-prem installer is a ServicePlanSpec with `deployment.onPremDeployment`.
It packages Helm resources and image registry copy resources into a downloadable
installer. It is not BYOC-K8s (`byoc-onprem`), and it has no live control-plane
connection after the customer runs it.

---

## When to Use This Reference

- Customer requires a fully disconnected / air-gapped installer.
- The installer must install multiple Helm releases in a specific order.
- Images come from multiple source registries or repositories.
- A target private registry must receive embedded images before Helm install.
- Existing customer-cluster components may need to be detected and skipped.
- The user says "on-prem installer", "air-gapped", "offline installer",
  "package all images", "private registry", or "install prerequisites first".

Do not use this for BYOC-K8s. If the customer cluster can open outbound
connectivity to the control plane, read `DEPLOYMENT_MODELS_REFERENCE.md`
§BYOC-K8s instead.

---

## Setup Workflow

1. Confirm deployment model is air-gapped: no live control-plane connection, no
   required internet at install time.
2. Confirm the workload is Helm-packaged. If the source is compose, terraform,
   kustomize, or mixed, first bundle the runtime pieces into one or more Helm
   charts; the installer deploys Helm releases.
3. Start minimal: one Helm service, hardcoded release/namespace, no optional
   skips, and either no image sync or one hardcoded image sync service.
4. Build and release the installer spec with `omnistrate-ctl build
   --spec-type ServicePlanSpec --file installer-spec.yaml --release`.
5. Create an installer instance for the customer-facing Helm resource and wait
   for installer readiness. In the API/e2e flow the terminal status is
   `INSTALLER_READY`.
6. Download the installer with `omnistrate-ctl instance get-installer
   <instance-id> --output-path <path>`.
7. Test locally against a disposable Kubernetes cluster before shipping:
   extract the artifact, prepare the target private registry and image pull
   secrets, then run `./installer.sh install` against the current kubeconfig.
8. Add complexity one layer at a time: additional registry copy service,
   additional Helm service, dependency edge, runtime skip hook, then parameters.

Build command:

```bash
omnistrate-ctl build \
  --spec-type ServicePlanSpec \
  --file installer-spec.yaml \
  --product-name "My Application Air-Gapped Installer" \
  --release \
  --release-description "v1.0.0 initial release"
```

Download command:

```bash
omnistrate-ctl instance get-installer <instance-id> \
  --output-path ./installer.tar.gz
```

---

## Service Graph Pattern

Model the installer as a graph:

- One `services[]` entry for each Helm release.
- One internal `services[]` entry for each source registry or repository copy
  path.
- `dependsOn` edges from Helm services to the registry copy services they
  consume.
- `dependsOn` edges from later Helm services to prerequisite Helm services.
- `parameterDependencyMap` from the customer-facing service to internal
  services so customers enter shared values once.
- `internal: true` for implementation details such as image sync,
  ingress-nginx, cert-manager, CSI drivers, or bootstrap charts.

Example graph:

```text
DockerHubImages -----> MainApp
RegistryK8sImages --> IngressNginx --> MainApp
QuayJetstackImages --> CertManager --> MainApp
```

For parallel prerequisites, do not create artificial dependencies. If chart A
and chart B are independent, let them both depend on their image sync service
and make chart C depend on A and B.

---

## Deployment Block

Use the on-prem deployment block under `deployment`:

```yaml
name: My Application
deployment:
  requirements:
    k8sVersion: ">=1.30.0"
  onPremDeployment:
    AwsAccountId: "<artifact-hosting-aws-account-id>"
    AWSBootstrapRoleAccountArn: "arn:aws:iam::<artifact-hosting-aws-account-id>:role/omnistrate-bootstrap-role"
  onPremInstallerTools:
    helperUserScript: |
      #!/bin/bash
      log_error() {
        echo "Error: $1" > /tmp/error.log
      }
```

`onPremInstallerTools.helperUserScript` is available to action hooks. Put shared
bash helpers there or reference a file:

```yaml
  onPremInstallerTools:
    helperUserScript: |
      {{ $file:./custom_scripts/helper.sh }}
```

---

## Image Registry Copy Services

Use `containerImagesRegistryCopyConfiguration` for image transfer. For a true
air-gapped install, prefer `INSTALLER_EMBED`: images are pulled at build time,
stored in the installer artifact, and pushed to the customer's target registry
at install time.

```yaml
services:
  - name: DockerHubImages
    internal: true
    disable: "{{ $var.skipPrivateRegistry }}"
    apiParameters:
      - name: Skip Private Image Registry
        key: skipPrivateRegistry
        type: Boolean
        required: false
        export: true
        defaultValue: "false"
        modifiable: false
      - name: Private Image Registry URL
        key: privateRegistryUrl
        type: String
        required: true
        export: true
        modifiable: true
      - name: Pull Mode
        key: pullMode
        type: String
        required: true
        export: true
        modifiable: true
        defaultValue: "INSTALLER_EMBED"
        options:
          - INSTALLER_EMBED
          - RUNTIME_PULL
    containerImagesRegistryCopyConfiguration:
      pullMode: "{{ $var.pullMode }}"
      pullSource:
        registryURL: "docker.io"
        repositoryName: "my-org"
        credentials:
          username: "{{ $secret.DOCKERHUB_USERNAME }}"
          password: "{{ $secret.DOCKERHUB_PASSWORD }}"
      pushTarget:
        registryURL: "{{ $var.privateRegistryUrl }}"
        repositoryName: "my-org"
      images:
        - imageName: "app-server"
          imageTag: "1.0.0"
```

Rules:

- Create separate copy services when source registry URL, repository layout,
  credentials, target repository, or skip behavior differs.
- Do not put target registry credentials in `pushTarget`. The installer
  collects or receives target-registry upload credentials at install time.
- Use `disable` only for parameter-known skips. Use runtime skip hooks when the
  installer must inspect the target cluster.
- Keep registry copy services `internal: true`.

---

## Helm Services

Each Helm release gets its own service. A service can depend on image sync
resources and other Helm resources:

```yaml
  - name: MainApp
    dependsOn:
      - DockerHubImages
      - IngressNginx
      - CertManager
    apiParameters:
      - name: Private Image Registry URL
        key: privateRegistryUrl
        type: String
        required: true
        export: true
        modifiable: true
        parameterDependencyMap:
          DockerHubImages: privateRegistryUrl
          IngressNginx: privateRegistryUrl
          CertManager: privateRegistryUrl
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
          DockerHubImages: pullMode
          IngressNginx: pullMode
          CertManager: pullMode
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: "echo 'validating main app prerequisites'"
      - scope: CLUSTER
        type: PRE_INSTALL
        commandTemplate: "echo 'preparing main app'"
      - scope: CLUSTER
        type: POST_INSTALL
        commandTemplate: "echo 'main app installed'"
      - scope: CLUSTER
        type: BACKUP
        commandTemplate: "echo 'backup before upgrade'"
    helmChartConfiguration:
      chartName: main-app
      chartVersion: 1.0.0
      chartRepoName: my-org
      chartRepoURL: oci://registry-1.docker.io/my-org
      releaseName: main-app
      namespace: main-app
      autoDiscoverImagesTag: "my-org.com/images"
      runtimeConfiguration:
        wait: true
        waitForJobs: true
      layeredChartValues:
        - scope:
            "{{ $var.skipPrivateRegistry }}": "true"
          values:
            global:
              imageRegistry: docker.io
        - scope:
            "{{ $var.skipPrivateRegistry }}": "false"
          values:
            global:
              imageRegistry: "{{ $var.privateRegistryUrl }}"
```

Every service named in a `parameterDependencyMap` must declare the target
parameter key in its own `apiParameters`.

For private OCI chart repositories, include `authProvider` under
`helmChartConfiguration` unless the chart is in private ECR and the account is
configured for IAM-based ECR Helm pulls:

```yaml
      authProvider:
        username: "{{ $secret.REGISTRY_USERNAME }}"
        password: "{{ $secret.REGISTRY_PASSWORD }}"
```

---

## Image Discovery

Prefer `autoDiscoverImagesTag` when the chart can declare its images in
`Chart.yaml`. It keeps installer image sync aligned with chart updates.

Spec:

```yaml
helmChartConfiguration:
  autoDiscoverImagesTag: "my-org.com/images"
```

Chart metadata:

```yaml
annotations:
  my-org.com/images: |
    - name: app-server
      image: docker.io/my-org/app-server:{{.Chart.AppVersion}}
    - name: worker
      image: docker.io/my-org/worker:{{.Chart.AppVersion}}
```

If the chart cannot publish image annotations, list `images` manually in each
registry copy service.

---

## Runtime Skip for Existing Prerequisites

Use `disable` for user-selected skips. Use a `VALIDATE` hook with
`skip_resource_deployment` when the installer must inspect the cluster and skip
only if the existing component is acceptable.

```yaml
  - name: CertManager
    internal: true
    dependsOn:
      - QuayJetstackImages
    actionHooks:
      - scope: CLUSTER
        type: VALIDATE
        commandTemplate: |
          match="$(helm list -A --all --short | grep -E '^cert-manager$' || true)"
          if [ -n "${match}" ]; then
            skip_resource_deployment "cert-manager already exists"
          fi
    helmChartConfiguration:
      chartName: cert-manager
      chartVersion: v1.21.0
      chartRepoName: jetstack
      chartRepoURL: https://charts.jetstack.io
      releaseName: cert-manager
      namespace: cert-manager
```

Guidance:

- Skip only healthy, acceptable existing installations.
- If the existing installation is present but incompatible or unhealthy, exit
  non-zero and tell the operator what to fix.
- The helper function name is `skip_resource_deployment`; do not invent
  alternate names.
- Use validation hooks for checks that need `kubectl` or `helm` against the
  customer's cluster.

---

## Local Installer Test Checklist

Use the e2e test shape when validating a complex installer locally:

1. Build and release the spec.
2. Create an installer instance and wait for `INSTALLER_READY`.
3. Download with `instance get-installer`.
4. Extract the artifact.
5. Verify embedded image content exists under `imageregistries/` when using
   `INSTALLER_EMBED`.
6. Start or identify a target private registry reachable from the test cluster.
7. Create target registry pull secrets in namespaces the Helm charts use.
8. Preinstall any resource meant to exercise runtime skip.
9. Run `./installer.sh install`.
10. Verify output order: image uploads first, prerequisite Helm releases next,
    dependent Helm releases last.
11. Verify skipped resources report the skip reason and dependent resources
    still install.
12. Run `kubectl get pods`, `kubectl describe pods`, `kubectl get events`, and
    `kubectl logs` for every namespace involved.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Treating air-gapped as BYOC-K8s | Use `onPremDeployment`, not `byoaDeployment` / `byoc-onprem`. |
| Assuming only one Helm chart is supported | Model each Helm release as its own service and connect them with `dependsOn`. |
| Assuming only one image sync is supported | Use one internal registry copy service per source registry or repository copy path. |
| Exposing image sync in the portal | Set `internal: true` on registry copy resources. |
| Duplicating shared registry params on every service | Put the customer-facing parameter on the main service and use `parameterDependencyMap`. |
| Using `RUNTIME_PULL` for a no-internet site | Use `INSTALLER_EMBED` so images are packaged at build time. |
| Forgetting chart image metadata | Add `autoDiscoverImagesTag` and matching `Chart.yaml` annotations, or list `images` manually. |
| Skipping existing prerequisites unconditionally | Inspect with `helm`/`kubectl`; skip only when the existing install is acceptable. |
| Putting target registry credentials in `pushTarget` | Provide target upload credentials to the installer at install time. |
| Debugging as if control-plane tunnel exists | Work from installer output, hook logs, and local `kubectl`; air-gapped has no live tunnel. |
