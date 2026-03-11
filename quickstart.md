**Quick Start: CI → Container → Deploy Workflows**

- **Repo**: paloitmbb/mbb-java-maven

**Overview**
- This repo contains a 3-stage pipeline:
  - `CI` ([.github/workflows/ci.yml](.github/workflows/ci.yml)) — build, test, package, produce `image-tag` metadata and `app-jar` artifact
  - `Container` ([.github/workflows/container.yml](.github/workflows/container.yml)) — downloads JAR, builds Docker image, scans, pushes to ACR, writes `deploy-metadata`
  - `Deploy` ([.github/workflows/deploy.yml](.github/workflows/deploy.yml)) → calls reusable `deploy-environment.yml` to deploy to AKS (SIT → UAT → Production)

**Important workflow files**
- [ci.yml](.github/workflows/ci.yml)
- [container.yml](.github/workflows/container.yml)
- [deploy-environment.yml](.github/workflows/deploy-environment.yml)
- [deploy.yml](.github/workflows/deploy.yml)
- [pr-validation.yml](.github/workflows/pr-validation.yml)

**Required Repository Variables (Actions → Variables)**
- **CONTAINER_REGISTRY**: e.g. `myregistry.azurecr.io` — ACR login server (registry hostname)
- **APP_NAME**: e.g. `hello-java` — image name/repository inside registry
- **AKS_CLUSTER_NAME_SIT**: AKS cluster name for SIT
- **AKS_RESOURCE_GROUP_SIT**: resource group for SIT cluster
- **AKS_CLUSTER_NAME_UAT**: AKS cluster name for UAT
- **AKS_RESOURCE_GROUP_UAT**: resource group for UAT cluster
- **AKS_CLUSTER_NAME_PROD**: AKS cluster name for Production
- **AKS_RESOURCE_GROUP_PROD**: resource group for Production cluster

Notes:
- `FULL_IMAGE_NAME` is computed at runtime as `${{ vars.CONTAINER_REGISTRY }}/${{ vars.APP_NAME }}` — do not create as a repo variable.
- `CI` writes `image-tag` into the build artifact (`target/version-metadata/image-tag`) which `Container` reads; keep CI untouched.

**Required Secrets (Actions → Secrets)**
- **AZURE_CLIENT_ID** — service principal / OIDC client id
- **AZURE_TENANT_ID** — Azure tenant id
- **AZURE_SUBSCRIPTION_ID** — Azure subscription id

Optional (if you use extra tools):
- GitHub `GITLEAKS_LICENSE` if your policy requires it (not mandatory for these workflows)

**Azure RBAC / Network Requirements**
- The OIDC identity (federated identity / service principal) must have RBAC to authenticate and access the AKS resource for `az aks get-credentials`. At minimum grant the identity:
  - `Azure Kubernetes Service Cluster User Role` for read-only kubeconfig access, or
  - `Contributor` / cluster admin for admin kubeconfig as needed.
- The AKS API must be reachable from GitHub Actions runners. For private clusters you must use self-hosted runners or a network path that can reach the control plane.

**How to add repository variables & secrets (examples)**
- GitHub UI: Settings → Secrets and variables → Actions → Variables / Secrets → New repository variable/secret

- GitHub CLI examples (replace values):

```bash
# Set repo variables (replace owner/repo as needed)
gh variable set CONTAINER_REGISTRY --body "myregistry.azurecr.io" --repo paloitmbb/mbb-java-maven
gh variable set APP_NAME --body "hello-java" --repo paloitmbb/mbb-java-maven
gh variable set AKS_CLUSTER_NAME_SIT --body "aks-sit" --repo paloitmbb/mbb-java-maven
gh variable set AKS_RESOURCE_GROUP_SIT --body "rg-sit" --repo paloitmbb/mbb-java-maven
# repeat for UAT/PROD clusters

# Set secrets (values read from env or file)
echo "$AZURE_CLIENT_ID" | gh secret set AZURE_CLIENT_ID --repo paloitmbb/mbb-java-maven
echo "$AZURE_TENANT_ID" | gh secret set AZURE_TENANT_ID --repo paloitmbb/mbb-java-maven
echo "$AZURE_SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID --repo paloitmbb/mbb-java-maven
```

**Quick run / expected flow**
1. Push to `main` (or open PR → `CI` runs). `CI` produces `target/version-metadata/image-tag` and uploads `app-jar` artifact.
2. After `CI` success, `Container` triggers (workflow_run) — downloads artifact, builds image `${{ vars.CONTAINER_REGISTRY }}/${{ vars.APP_NAME }}:${IMAGE_TAG}`, scans and pushes to ACR. It uploads `deploy-metadata` (contains `image-tag`).
3. After `Container` success, `Deploy` triggers (workflow_run) and calls `deploy-environment.yml` for SIT → UAT → Production. `deploy-environment.yml`:
   - downloads `deploy-metadata` using the Container run id,
   - logs into Azure via OIDC (`AZURE_*` secrets),
   - pulls the image, verifies attestation, sets AKS context via `azure/aks-set-context@v4`, updates `k8s/deployment.yaml` image entry, and applies the manifest.

**Manual dispatch (advanced)**
- To manually dispatch `Deploy` from a specific `Container` run id, use `Deploy` → Run workflow (workflow_dispatch) and provide `container_run_id` (the run id shown on the Container workflow run page).

**Troubleshooting tips**
- If `azure/aks-set-context@v4` fails: confirm `AZURE_*` secrets are set and the identity has permission to the target resource group/cluster.
- If `docker push` fails: confirm `CONTAINER_REGISTRY` is correct and the service principal has push permissions to the ACR.
- If `Container` cannot find the JAR artifact: verify `CI` uploaded `app-jar` with `target/version-metadata/` present.

**Useful file references**
- Workflows: [.github/workflows/ci.yml](.github/workflows/ci.yml), [.github/workflows/container.yml](.github/workflows/container.yml), [.github/workflows/deploy-environment.yml](.github/workflows/deploy-environment.yml), [.github/workflows/deploy.yml](.github/workflows/deploy.yml)
- K8s manifest: [k8s/deployment.yaml](k8s/deployment.yaml)

---
If you want, I can: add a small pre-check step to `deploy-environment.yml` that verifies `az aks show` before attempting `aks-set-context`, or create a `docs/quickstart.md` instead — which do you prefer?
