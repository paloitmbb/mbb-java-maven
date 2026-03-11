---
description: "Implement single-artifact semantic versioning (v1.0.0.{sha}) with three-environment sequential deployment (SIT auto → UAT 1 approval → PROD 2 approvals) and immutable Git tag after production deploy, without changing workflow triggers or the workflow_run chain."
agent: "agent"
tools: ["codebase", "editFiles", "search", "problems"]
---

# Pipeline Versioning & Three-Environment Deployment Strategy

You are a **senior DevSecOps engineer** with deep expertise in GitHub Actions workflow design, immutable artifact delivery, semantic versioning, and multi-environment Kubernetes deployments. You follow build-once principles and maintain strict `workflow_run` chain integrity.

---

## Step 0 — Read and Analyse Before Touching Any File

Before making any change, read these files in full and extract the values listed below. Do not skip this step — incorrect extraction will cascade errors across all four phases.

**Files to read:**

- `pom.xml` → extract `<artifactId>` and `<version>`
- `.github/workflows/ci.yml` → locate the `Normalize JAR filename` step and the `Upload app JAR` step; note exact step names and their position in `build-and-package`
- `.github/workflows/container.yml` → locate every occurrence of `env.COMMIT_SHA`; note the `build-image` job's current `outputs:` block (or absence of it); locate `Export deploy metadata` step
- `.github/workflows/deploy.yml` → note current job names, their `environment:` values, the `Read deploy metadata` step content, and the kubectl command patterns
- `.github/workflows/pr-validation.yml` → read only; no changes needed — confirm `name: PR Validation` is unchanged after all edits

**Extract and confirm:**

```
artifactId  = <value from pom.xml>       # e.g. hello-java
version     = <value from pom.xml>       # e.g. 1.0-SNAPSHOT → will change to 1.0.0
image_tag   = v{version}.{sha}           # e.g. v1.0.0.abc1234  (constructed, not extracted)
named_jar   = {artifactId}-{version}.{sha}.jar  # e.g. hello-java-1.0.0.abc1234.jar
```

Report these extracted values before proceeding to Phase 1.

---

## Strategy Overview

### Single Build → Single Image → Three Environments

```
main branch (commit sha abc1234)
      │
      ▼
  CI workflow  (name: CI — DO NOT RENAME)
  ├─ Build, test, package → target/app.jar
  ├─ Named JAR: hello-java-1.0.0.abc1234.jar  (audit trail copy)
  ├─ Artifact: app-jar  (contains target/app.jar — unchanged)
  └─ Artifact: version-metadata  (new — contains image-tag, app-version, commit-sha-short)
         │
         ▼
  Container workflow  (name: Container — DO NOT RENAME)
  ├─ Download app-jar  +  version-metadata from CI
  ├─ Build image: app:v1.0.0.abc1234
  ├─ Trivy scan (CRITICAL/HIGH gate)
  ├─ Push to ACR: registry/repo:v1.0.0.abc1234
  └─ Artifact: deploy-metadata  (image-tag, full-image-ref, image-digest)
         │
         ▼
  Deploy workflow  (name: Deploy — DO NOT RENAME)
  ├─ deploy-sit       (auto-deploy, 0 approvals)
  ├─ deploy-uat       (needs deploy-sit, 1 required reviewer)
  └─ deploy-production (needs deploy-uat, 2 required reviewers)
         └─► Git tag: v1.0.0.abc1234  ← ONLY after PROD deploy succeeds
```

---

## Versioning Format

**No environment suffix — one tag used across SIT, UAT, and PROD.**

| Artifact          | Format                              | Concrete Example                 |
|-------------------|-------------------------------------|----------------------------------|
| `pom.xml` version | `1.0.0`                             | `1.0.0`                          |
| JAR (audit copy)  | `{artifactId}-{version}.{sha}.jar`  | `hello-java-1.0.0.abc1234.jar`  |
| Docker image tag  | `v{version}.{sha}`                  | `v1.0.0.abc1234`                |
| Git tag           | `v{version}.{sha}`                  | `v1.0.0.abc1234`                |
| Git tag timing    | After `deploy-production` success   | Never in SIT or UAT              |

**Short SHA** = `${GITHUB_SHA::7}` — first 7 characters of the triggering commit hash.

---

## Phase 1: pom.xml

**File**: `pom.xml`
**Change**: one line — remove `-SNAPSHOT` suffix from `<version>`.

```xml
<!-- BEFORE -->
<version>1.0-SNAPSHOT</version>

<!-- AFTER -->
<version>1.0.0</version>
```

Do not change any other line in pom.xml. CI will extract the version dynamically via `mvn help:evaluate` — never hard-code `1.0.0` elsewhere.

---

## Phase 2: ci.yml

**File**: `.github/workflows/ci.yml`
**Job**: `build-and-package`
**Insert after**: the existing `Normalize JAR filename` step (which creates `target/app.jar`)
**Insert before**: the existing `Upload app JAR` step

Add these three steps in order:

### Step A — Resolve version metadata

```yaml
      - name: Resolve version metadata
        id: version
        run: |
          VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
          ARTIFACT_ID=$(mvn help:evaluate -Dexpression=project.artifactId -q -DforceStdout)
          SHA="${GITHUB_SHA::7}"
          IMAGE_TAG="v${VERSION}.${SHA}"
          NAMED_JAR="${ARTIFACT_ID}-${VERSION}.${SHA}.jar"
          echo "version=${VERSION}"      >> "$GITHUB_OUTPUT"
          echo "sha=${SHA}"              >> "$GITHUB_OUTPUT"
          echo "image_tag=${IMAGE_TAG}"  >> "$GITHUB_OUTPUT"
          echo "named_jar=${NAMED_JAR}"  >> "$GITHUB_OUTPUT"
          mkdir -p /tmp/version-metadata
          echo "${VERSION}"   > /tmp/version-metadata/app-version
          echo "${SHA}"       > /tmp/version-metadata/commit-sha-short
          echo "${IMAGE_TAG}" > /tmp/version-metadata/image-tag
```

### Step B — Create named JAR (audit trail copy)

```yaml
      - name: Create named JAR
        run: |
          cp target/app.jar "target/${{ steps.version.outputs.named_jar }}"
```

### Step C — Upload version-metadata artifact

```yaml
      - name: Upload version-metadata artifact
        uses: actions/upload-artifact@v4
        with:
          name: version-metadata
          path: /tmp/version-metadata/
          retention-days: 3
          if-no-files-found: error
```

**Do NOT remove or modify:**
- The existing `Normalize JAR filename` step
- The existing `Upload app JAR` step that uploads `target/app.jar` as `app-jar`

Container.yml downloads the `app-jar` artifact and expects exactly `target/app.jar` — do not rename it.

---

## Phase 3: container.yml

**File**: `.github/workflows/container.yml`

### 3a — Add `outputs:` block to `build-image` job

The current `build-image` job declaration has no `outputs:` block. Add it directly after the `permissions:` block:

```yaml
    outputs:
      image_tag: ${{ steps.version.outputs.image_tag }}
```

The resulting job header should look like:

```yaml
  build-image:
    name: Build Image
    runs-on: ubuntu-latest
    timeout-minutes: 15
    if: >
      github.event.workflow_run.conclusion == 'success' ||
      github.event_name == 'workflow_dispatch'
    permissions:
      contents: read
      actions: read
    outputs:
      image_tag: ${{ steps.version.outputs.image_tag }}
```

### 3b — Download version-metadata in `build-image` steps

Insert these two steps immediately after the existing `Download app-jar artifact from CI` step:

```yaml
      - name: Download version-metadata artifact from CI
        uses: actions/download-artifact@v4
        with:
          name: version-metadata
          path: /tmp/version-metadata/
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Read version metadata
        id: version
        run: |
          echo "image_tag=$(cat /tmp/version-metadata/image-tag)" >> "$GITHUB_OUTPUT"
```

### 3c — Update `Build Docker image (no push)` step — replace `tags:` value

```yaml
          # BEFORE
          tags: app:${{ env.COMMIT_SHA }}

          # AFTER
          tags: app:${{ steps.version.outputs.image_tag }}
```

Also update `build-args:` — replace `APP_VERSION=${{ env.COMMIT_SHA }}` with:

```yaml
          build-args: |
            APP_VERSION=${{ steps.version.outputs.image_tag }}
            BUILD_DATE=${{ steps.meta.outputs.build_date }}
```

### 3d — Update `scan-image` job — replace `image-ref:` in Trivy step

```yaml
          # BEFORE
          image-ref: app:${{ env.COMMIT_SHA }}

          # AFTER
          image-ref: app:${{ needs.build-image.outputs.image_tag }}
```

### 3e — Update `attest-and-push` job — replace `Tag, push, and capture digest` step body

```yaml
      - name: Tag, push, and capture digest
        id: push
        run: |
          IMAGE_TAG="${{ needs.build-image.outputs.image_tag }}"
          IMAGE="${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}:${IMAGE_TAG}"
          docker tag "app:${IMAGE_TAG}" "${IMAGE}"
          docker push "${IMAGE}"
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | cut -d@ -f2)
          echo "image=${IMAGE}"   >> "$GITHUB_OUTPUT"
          echo "digest=${DIGEST}" >> "$GITHUB_OUTPUT"
```

### 3f — Replace `Export deploy metadata` step body

```yaml
      - name: Export deploy metadata
        run: |
          echo "${{ needs.build-image.outputs.image_tag }}" > /tmp/image-tag
          echo "${{ steps.push.outputs.image }}"            > /tmp/full-image-ref
          echo "${{ steps.push.outputs.digest }}"           > /tmp/image-digest
```

### 3g — Update `Upload deploy-metadata artifact` paths

```yaml
      - name: Upload deploy-metadata artifact
        uses: actions/upload-artifact@v4
        with:
          name: deploy-metadata
          path: |
            /tmp/image-tag
            /tmp/full-image-ref
            /tmp/image-digest
          retention-days: 7
```

**Note**: The old artifact included `/tmp/commit-sha`. The new artifact replaces it with `/tmp/full-image-ref`. Update `deploy.yml`'s read step accordingly (done in Phase 4).

---

## Phase 4: deploy.yml

**File**: `.github/workflows/deploy.yml`

Replace the **entire `jobs:` section** (currently `deploy-staging` + `deploy-production`) with the three-job sequential chain below. Keep all content above `jobs:` unchanged (the workflow header, `on:`, `concurrency:`, `permissions:` blocks).

```yaml
jobs:

  # ---------------------------------------------------------------------------
  # Job 1: deploy-sit
  # Auto-deploys on every Container workflow success. No approval required.
  # Rolls back automatically if any step fails.
  # ---------------------------------------------------------------------------
  deploy-sit:
    name: Deploy to SIT
    runs-on: ubuntu-latest
    timeout-minutes: 15
    if: >
      github.event.workflow_run.conclusion == 'success' ||
      github.event_name == 'workflow_dispatch'
    environment: sit      # Configure: 0 required reviewers (auto-deploy)
    permissions:
      contents: read
      id-token: write     # Required for Azure OIDC
      actions: read       # Required for cross-workflow artifact download

    steps:
      - name: Download deploy-metadata artifact
        uses: actions/download-artifact@v4
        with:
          name: deploy-metadata
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Read deploy metadata
        id: meta
        run: |
          echo "image_tag=$(cat image-tag)"      >> "$GITHUB_OUTPUT"
          echo "image=$(cat full-image-ref)"     >> "$GITHUB_OUTPUT"
          echo "digest=$(cat image-digest)"      >> "$GITHUB_OUTPUT"

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Set AKS context (SIT)
        uses: azure/aks-set-context@v4
        with:
          cluster-name: ${{ vars.AKS_CLUSTER_NAME_SIT }}
          resource-group: ${{ vars.AKS_RESOURCE_GROUP_SIT }}

      - name: Deploy image to SIT
        run: |
          kubectl set image deployment/${{ vars.APP_NAME }} \
            ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} \
            -n sit
          echo "Deployed ${{ steps.meta.outputs.image_tag }} to SIT"

      - name: Wait for rollout (SIT)
        run: |
          kubectl rollout status deployment/${{ vars.APP_NAME }} \
            -n sit \
            --timeout=5m

      - name: Health check (SIT)
        run: |
          for i in $(seq 1 5); do
            if curl --silent --fail "${{ vars.SIT_HEALTH_URL }}"; then
              echo "Health check passed"
              exit 0
            fi
            echo "Attempt ${i}/5 failed — retrying in 15s"
            sleep 15
          done
          echo "Health check failed after 5 attempts"
          exit 1

      - name: Rollback on failure (SIT)
        if: failure()
        run: |
          kubectl rollout undo deployment/${{ vars.APP_NAME }} -n sit
          kubectl rollout status deployment/${{ vars.APP_NAME }} -n sit

  # ---------------------------------------------------------------------------
  # Job 2: deploy-uat
  # Requires deploy-sit to succeed first, then waits for 1 required reviewer.
  # Same deploy/health-check/rollback pattern as SIT.
  # ---------------------------------------------------------------------------
  deploy-uat:
    name: Deploy to UAT
    runs-on: ubuntu-latest
    needs: [deploy-sit]
    timeout-minutes: 15
    environment: uat      # Configure: 1 required reviewer in repo Settings → Environments
    permissions:
      contents: read
      id-token: write
      actions: read

    steps:
      - name: Download deploy-metadata artifact
        uses: actions/download-artifact@v4
        with:
          name: deploy-metadata
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Read deploy metadata
        id: meta
        run: |
          echo "image_tag=$(cat image-tag)"      >> "$GITHUB_OUTPUT"
          echo "image=$(cat full-image-ref)"     >> "$GITHUB_OUTPUT"
          echo "digest=$(cat image-digest)"      >> "$GITHUB_OUTPUT"

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Set AKS context (UAT)
        uses: azure/aks-set-context@v4
        with:
          cluster-name: ${{ vars.AKS_CLUSTER_NAME_UAT }}
          resource-group: ${{ vars.AKS_RESOURCE_GROUP_UAT }}

      - name: Deploy image to UAT
        run: |
          kubectl set image deployment/${{ vars.APP_NAME }} \
            ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} \
            -n uat
          echo "Deployed ${{ steps.meta.outputs.image_tag }} to UAT"

      - name: Wait for rollout (UAT)
        run: |
          kubectl rollout status deployment/${{ vars.APP_NAME }} \
            -n uat \
            --timeout=5m

      - name: Health check (UAT)
        run: |
          for i in $(seq 1 5); do
            if curl --silent --fail "${{ vars.UAT_HEALTH_URL }}"; then
              echo "Health check passed"
              exit 0
            fi
            echo "Attempt ${i}/5 failed — retrying in 15s"
            sleep 15
          done
          echo "Health check failed after 5 attempts"
          exit 1

      - name: Rollback on failure (UAT)
        if: failure()
        run: |
          kubectl rollout undo deployment/${{ vars.APP_NAME }} -n uat
          kubectl rollout status deployment/${{ vars.APP_NAME }} -n uat

  # ---------------------------------------------------------------------------
  # Job 3: deploy-production
  # Requires deploy-uat to succeed first, then waits for 2 required reviewers.
  # On success, creates an immutable Git tag that permanently marks the release.
  # CRITICAL: cancel-in-progress is false (set at workflow level) — never change.
  # ---------------------------------------------------------------------------
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [deploy-uat]
    timeout-minutes: 20
    environment: production   # Configure: 2 required reviewers in repo Settings → Environments
    permissions:
      contents: write         # Required for git tag push after successful deploy
      id-token: write
      actions: read

    steps:
      - name: Checkout (for Git tag push)
        uses: actions/checkout@v4
        with:
          fetch-depth: 1
          persist-credentials: true   # Must be true to allow git push for tag
          ref: ${{ github.event.workflow_run.head_sha || github.sha }}

      - name: Download deploy-metadata artifact
        uses: actions/download-artifact@v4
        with:
          name: deploy-metadata
          run-id: ${{ github.event.workflow_run.id }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Read deploy metadata
        id: meta
        run: |
          echo "image_tag=$(cat image-tag)"      >> "$GITHUB_OUTPUT"
          echo "image=$(cat full-image-ref)"     >> "$GITHUB_OUTPUT"
          echo "digest=$(cat image-digest)"      >> "$GITHUB_OUTPUT"

      - name: Azure login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Set AKS context (Production)
        uses: azure/aks-set-context@v4
        with:
          cluster-name: ${{ vars.AKS_CLUSTER_NAME_PROD }}
          resource-group: ${{ vars.AKS_RESOURCE_GROUP_PROD }}

      - name: Deploy image to Production
        run: |
          kubectl set image deployment/${{ vars.APP_NAME }} \
            ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} \
            -n production
          echo "Deployed ${{ steps.meta.outputs.image_tag }} to Production"

      - name: Wait for rollout (Production)
        run: |
          kubectl rollout status deployment/${{ vars.APP_NAME }} \
            -n production \
            --timeout=10m

      - name: Health check (Production)
        run: |
          for i in $(seq 1 10); do
            if curl --silent --fail "${{ vars.PRODUCTION_HEALTH_URL }}"; then
              echo "Health check passed"
              exit 0
            fi
            echo "Attempt ${i}/10 failed — retrying in 20s"
            sleep 20
          done
          echo "Health check failed after 10 attempts"
          exit 1

      - name: Rollback on failure (Production)
        if: failure()
        run: |
          kubectl rollout undo deployment/${{ vars.APP_NAME }} -n production
          kubectl rollout status deployment/${{ vars.APP_NAME }} -n production

      # Creates an immutable Git tag anchored to the exact commit that was
      # built, scanned, attested, and successfully deployed to production.
      # Uses workflow_run head_sha (not github.sha) to avoid SHA drift.
      - name: Create immutable Git tag
        if: success()
        run: |
          TAG="${{ steps.meta.outputs.image_tag }}"
          COMMIT="${{ github.event.workflow_run.head_sha || github.sha }}"
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git tag -a "${TAG}" "${COMMIT}" -m "Production deploy: ${TAG}"
          git push origin "${TAG}"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## Variables Required in GitHub Repository Settings → Secrets and Variables

### Secrets (must already exist — do not change)

| Secret                   | Purpose                       |
|--------------------------|-------------------------------|
| `AZURE_CLIENT_ID`        | OIDC federated credential     |
| `AZURE_TENANT_ID`        | OIDC tenant                   |
| `AZURE_SUBSCRIPTION_ID`  | Azure subscription            |

### Variables → add new SIT/UAT entries

These variables need to be added for the new environments:

| Variable                  | Example Value                                    |
|---------------------------|--------------------------------------------------|
| `AKS_CLUSTER_NAME_SIT`    | `aks-sit-eastasia`                               |
| `AKS_RESOURCE_GROUP_SIT`  | `rg-sit`                                         |
| `AKS_CLUSTER_NAME_UAT`    | `aks-uat-eastasia`                               |
| `AKS_RESOURCE_GROUP_UAT`  | `rg-uat`                                         |
| `SIT_HEALTH_URL`          | `https://sit.example.com/actuator/health`        |
| `UAT_HEALTH_URL`          | `https://uat.example.com/actuator/health`        |

These variables already exist and **must not be renamed**:

| Variable                  | Used in                   |
|---------------------------|---------------------------|
| `AKS_CLUSTER_NAME_PROD`   | `deploy-production`       |
| `AKS_RESOURCE_GROUP_PROD` | `deploy-production`       |
| `PRODUCTION_HEALTH_URL`   | `deploy-production`       |
| `APP_NAME`                | All deploy jobs           |
| `ACR_LOGIN_SERVER`        | container.yml             |
| `ACR_REPOSITORY`          | container.yml             |

---

## GitHub Environments — Configure in Settings → Environments

| Environment  | Required Reviewers | Deployment Branch | Notes                                   |
|--------------|--------------------|-------------------|-----------------------------------------|
| `sit`        | 0                  | `main`, `develop` | Auto-deploys immediately                |
| `uat`        | 1                  | `main`, `develop` | Pending approval gate after SIT passes  |
| `production` | 2                  | `main` only       | Git tag created on successful deploy    |

---

## Validation Checklist

After all four phases are complete, verify every item before closing:

**Phase 1 — pom.xml**
- [ ] `<version>` is `1.0.0` (no `-SNAPSHOT`, no env suffix)

**Phase 2 — ci.yml**
- [ ] `Resolve version metadata` step exists in `build-and-package`, runs after `Normalize JAR filename`
- [ ] `steps.version.outputs.image_tag` produces `v{version}.{sha}` format (e.g. `v1.0.0.abc1234`)
- [ ] `version-metadata` artifact uploaded with `retention-days: 3` and `if-no-files-found: error`
- [ ] `Upload app JAR` step still uploads `target/app.jar` as artifact `app-jar` (unchanged)
- [ ] Workflow `name: CI` header is unchanged

**Phase 3 — container.yml**
- [ ] `build-image` job has `outputs: image_tag: ${{ steps.version.outputs.image_tag }}`
- [ ] `version-metadata` artifact downloaded in `build-image` using `run-id: ${{ github.event.workflow_run.id }}`
- [ ] Docker image tagged `v{version}.{sha}` — no raw SHA, no `:latest`
- [ ] `scan-image` Trivy `image-ref` uses `needs.build-image.outputs.image_tag`
- [ ] `attest-and-push` push step uses `needs.build-image.outputs.image_tag`
- [ ] `deploy-metadata` artifact contains files: `image-tag`, `full-image-ref`, `image-digest`
- [ ] Workflow `name: Container` header is unchanged

**Phase 4 — deploy.yml**
- [ ] Exactly three jobs: `deploy-sit`, `deploy-uat`, `deploy-production`
- [ ] Job chain: `deploy-uat` has `needs: [deploy-sit]`; `deploy-production` has `needs: [deploy-uat]`
- [ ] `deploy-sit` has no `needs:`, triggers automatically (`environment: sit`, 0 reviewers)
- [ ] `deploy-uat` uses `environment: uat` (1 reviewer in Settings)
- [ ] `deploy-production` uses `environment: production` (2 reviewers in Settings)
- [ ] All three jobs download `deploy-metadata` with `run-id: ${{ github.event.workflow_run.id }}`
- [ ] All three jobs read `image-tag`, `full-image-ref`, `image-digest` (not `commit-sha`)
- [ ] `Create immutable Git tag` step exists **only** in `deploy-production`
- [ ] Git tag step has `if: success()` (never `if: always()`)
- [ ] Git tag step uses `github.event.workflow_run.head_sha` (not `github.sha`)
- [ ] `deploy-production` checkout has `persist-credentials: true`
- [ ] `deploy-production` has `contents: write` permission
- [ ] All three rollback steps use `if: failure()` (never `if: always()`)
- [ ] `concurrency.cancel-in-progress: false` at workflow level is preserved
- [ ] Workflow `name: Deploy` header is unchanged

**pr-validation.yml**
- [ ] File is untouched — confirm `name: PR Validation` header is unchanged

---

## Constraints — Never Violate

| Rule | Reason |
|------|--------|
| Never rename `name: CI`, `name: Container`, `name: Deploy` | `workflow_run` triggers match on exact name strings |
| Never re-derive SHA in container.yml or deploy.yml | SHA drift occurs across `workflow_run` hops; always read from artifact |
| Never build or recompile Java in container.yml | Build-once principle; JAR comes from ci.yml `app-jar` artifact |
| Never push `:latest` or any mutable tag | Immutability required for audit trail and rollback safety |
| Never add environment suffix to image tag | Same `v1.0.0.abc1234` tag is used for SIT, UAT, and PROD |
| Never create Git tags in `deploy-sit` or `deploy-uat` | Tags mark production releases only |
| Never set `cancel-in-progress: true` in deploy.yml | Interrupting `kubectl rollout` corrupts pod state |
| Always use `if: failure()` on rollback steps | `if: always()` would roll back successful deploys |
| Never change `on:` trigger blocks | Workflow triggering is fixed per design |


---

## Mission

Implement semantic versioning (`v{VERSION}.{sha}`) with a single build artifact and a three-environment sequential deployment pipeline across the existing CI/CD workflows. You must **not** change workflow triggers, workflow `name:` fields, or the `workflow_run` chain structure. Only add version metadata generation, update image tagging, and restructure the deploy jobs.

---

## Context — Read Before Modifying Anything

Read these files to understand the current state before making any changes:

1. **`pom.xml`** — extract `<version>` and `<artifactId>` (used to derive artifact filename)
2. **`.github/workflows/ci.yml`** — current `build-and-package` job; understand `app-jar` artifact upload
3. **`.github/workflows/container.yml`** — current image tag construction using `COMMIT_SHA`; understand `deploy-metadata` artifact structure and job outputs chain
4. **`.github/workflows/deploy.yml`** — current staging + production jobs; understand kubectl deploy pattern, rollback guard, and artifact download
5. **`.github/plans/versioning-plan.md`** — background context and original problem statement

---

## Strategy Overview

### Single Build → Single Image → Three Environments

```
main branch (commit sha abc1234)
      │
      ▼
  CI workflow
  ├─ Build, test, package
  ├─ JAR: hello-java-1.0.0.abc1234.jar   (renamed from app.jar)
  ├─ Artifact: app-jar  (app.jar, always)
  └─ Artifact: version-metadata
         │
         ▼
  Container workflow
  ├─ Build image: app:v1.0.0.abc1234
  ├─ Trivy scan
  ├─ Push to ACR: registry/repo:v1.0.0.abc1234
  └─ Artifact: deploy-metadata (image-tag, image-digest)
         │
         ▼
  Deploy workflow
  ├─ deploy-sit       (auto, no approval)
  ├─ deploy-uat       (1 required reviewer, needs deploy-sit success)
  └─ deploy-production (2 required reviewers, needs deploy-uat success)
         └─ Git tag: v1.0.0.abc1234  ← created only after PROD success
```

---

## Versioning Format

**Single format for all environments — no environment suffix in the version string.**

| Artifact            | Format                              | Example                          |
|---------------------|-------------------------------------|----------------------------------|
| `pom.xml` version   | `1.0.0` (no `-SNAPSHOT`)            | `1.0.0`                          |
| JAR filename        | `{artifactId}-{version}.{sha}.jar`  | `hello-java-1.0.0.abc1234.jar`  |
| Docker image tag    | `v{version}.{sha}`                  | `v1.0.0.abc1234`                |
| Git tag             | `v{version}.{sha}`                  | `v1.0.0.abc1234`                |
| Git tag timing      | After PROD `deploy-production` only | —                                |

**Short SHA** = first 7 characters of the triggering commit SHA (`${GITHUB_SHA::7}`).

**Key principle**: The same image tag `v1.0.0.abc1234` is deployed to SIT, UAT, and PROD. The version string alone identifies what is deployed everywhere — the environment is determined by which job runs, not by the tag.

---

## Required Changes — Phase by Phase

### Phase 1: pom.xml

**File**: `pom.xml`

Update `<version>` to remove `-SNAPSHOT` and use `1.0.0` as a clean semantic version:

```xml
<!-- BEFORE -->
<version>1.0-SNAPSHOT</version>

<!-- AFTER -->
<version>1.0.0</version>
```

**Constraint**: `pom.xml` holds the version number only. No environment suffix. CI extracts it dynamically — never hard-code `1.0.0` anywhere in workflow YAML.

---

### Phase 2: ci.yml — Add Version Metadata Artifact

**File**: `.github/workflows/ci.yml`

**Where to insert**: Inside the `build-and-package` job, immediately after the existing `Normalize JAR filename` step.

#### Step A — Resolve version metadata

```yaml
- name: Resolve version metadata
  id: version
  run: |
    VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
    ARTIFACT_ID=$(mvn help:evaluate -Dexpression=project.artifactId -q -DforceStdout)
    SHA="${GITHUB_SHA::7}"
    IMAGE_TAG="v${VERSION}.${SHA}"
    NAMED_JAR="${ARTIFACT_ID}-${VERSION}.${SHA}.jar"
    echo "version=${VERSION}"         >> "$GITHUB_OUTPUT"
    echo "sha=${SHA}"                 >> "$GITHUB_OUTPUT"
    echo "image_tag=${IMAGE_TAG}"     >> "$GITHUB_OUTPUT"
    echo "named_jar=${NAMED_JAR}"     >> "$GITHUB_OUTPUT"
    # Write metadata files for downstream workflows
    mkdir -p /tmp/version-metadata
    echo "${VERSION}"    > /tmp/version-metadata/app-version
    echo "${SHA}"        > /tmp/version-metadata/commit-sha-short
    echo "${IMAGE_TAG}"  > /tmp/version-metadata/image-tag
```

#### Step B — Create named JAR alongside app.jar

```yaml
- name: Create named JAR
  run: |
    cp target/app.jar "target/${{ steps.version.outputs.named_jar }}"
```

#### Step C — Upload version-metadata artifact

```yaml
- name: Upload version-metadata artifact
  uses: actions/upload-artifact@v4
  with:
    name: version-metadata
    path: /tmp/version-metadata/
    retention-days: 3
    if-no-files-found: error
```

**Constraint**: Do **not** remove the existing `Normalize JAR filename` step or the `Upload app JAR` step that uploads `target/app.jar` as artifact `app-jar`. Container.yml depends on `app-jar` containing `target/app.jar` exactly as-is. The named JAR (`hello-java-1.0.0.abc1234.jar`) is supplementary for audit trail visibility.

---

### Phase 3: container.yml — Use Semver Image Tags

**File**: `.github/workflows/container.yml`

#### 3a. Add job outputs to `build-image`

Immediately after the job's `runs-on:` / `timeout-minutes:` declarations, add:

```yaml
build-image:
  name: Build Image
  runs-on: ubuntu-latest
  timeout-minutes: 15
  if: >
    github.event.workflow_run.conclusion == 'success' ||
    github.event_name == 'workflow_dispatch'
  permissions:
    contents: read
    actions: read
  outputs:
    image_tag: ${{ steps.version.outputs.image_tag }}
```

#### 3b. Download version-metadata and read it

In `build-image` steps, immediately after `Download app-jar artifact from CI`:

```yaml
- name: Download version-metadata artifact from CI
  uses: actions/download-artifact@v4
  with:
    name: version-metadata
    path: /tmp/version-metadata/
    run-id: ${{ github.event.workflow_run.id }}
    github-token: ${{ secrets.GITHUB_TOKEN }}

- name: Read version metadata
  id: version
  run: |
    echo "image_tag=$(cat /tmp/version-metadata/image-tag)" >> "$GITHUB_OUTPUT"
```

#### 3c. Update `Build Docker image (no push)` — replace `tags:`

```yaml
# BEFORE
tags: app:${{ env.COMMIT_SHA }}

# AFTER
tags: app:${{ steps.version.outputs.image_tag }}
```

#### 3d. Update `scan-image` job — use image tag from build-image outputs

Replace the `image-ref:` value in the Trivy step:

```yaml
# BEFORE
image-ref: app:${{ env.COMMIT_SHA }}

# AFTER
image-ref: app:${{ needs.build-image.outputs.image_tag }}
```

Also update the `Load Docker image` Docker reference in `scan-image` if it references `COMMIT_SHA` directly in any `docker` commands. Use `needs.build-image.outputs.image_tag` instead.

#### 3e. Update `attest-and-push` job — tag and push with semver tag

In the `Tag, push, and capture digest` step, replace SHA-based tag logic:

```yaml
- name: Tag, push, and capture digest
  id: push
  run: |
    IMAGE_TAG="${{ needs.build-image.outputs.image_tag }}"
    IMAGE="${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}:${IMAGE_TAG}"
    docker tag "app:${IMAGE_TAG}" "${IMAGE}"
    docker push "${IMAGE}"
    DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | cut -d@ -f2)
    echo "image=${IMAGE}"   >> "$GITHUB_OUTPUT"
    echo "digest=${DIGEST}" >> "$GITHUB_OUTPUT"
```

#### 3f. Update `Export deploy metadata` step — write all fields

```yaml
- name: Export deploy metadata
  run: |
    echo "${{ needs.build-image.outputs.image_tag }}" > /tmp/image-tag
    echo "${{ steps.push.outputs.image }}"            > /tmp/full-image-ref
    echo "${{ steps.push.outputs.digest }}"           > /tmp/image-digest
```

Update the `Upload deploy-metadata artifact` paths to include `full-image-ref`:

```yaml
- name: Upload deploy-metadata artifact
  uses: actions/upload-artifact@v4
  with:
    name: deploy-metadata
    path: |
      /tmp/image-tag
      /tmp/full-image-ref
      /tmp/image-digest
    retention-days: 7
```

**Constraint**: Never re-derive the SHA or version in container.yml. Always read from the `version-metadata` artifact produced by ci.yml. This prevents SHA drift across `workflow_run` hops.

---

### Phase 4: deploy.yml — Three-Environment Sequential Deployment

**File**: `.github/workflows/deploy.yml`

Replace the current two-job structure (`deploy-staging`, `deploy-production`) with a three-job sequential chain.

#### Updated `Read deploy metadata` step (apply to all three jobs)

```yaml
- name: Read deploy metadata
  id: meta
  run: |
    echo "image_tag=$(cat image-tag)"        >> "$GITHUB_OUTPUT"
    echo "image=$(cat full-image-ref)"       >> "$GITHUB_OUTPUT"
    echo "digest=$(cat image-digest)"        >> "$GITHUB_OUTPUT"
```

---

#### Job 1: `deploy-sit` — Auto-deploy, no approval

```yaml
deploy-sit:
  name: Deploy to SIT
  runs-on: ubuntu-latest
  timeout-minutes: 15
  if: >
    github.event.workflow_run.conclusion == 'success' ||
    github.event_name == 'workflow_dispatch'
  environment: sit              # Configure: 0 required reviewers (auto-deploy)
  permissions:
    contents: read
    id-token: write
    actions: read
```

Deploy steps pattern (same kubectl pattern as current staging job):
- Download `deploy-metadata` artifact with `run-id: ${{ github.event.workflow_run.id }}`
- Read metadata
- Azure OIDC login
- AKS context: use `vars.AKS_CLUSTER_NAME_SIT` / `vars.AKS_RESOURCE_GROUP_SIT`
- `kubectl set image deployment/${{ vars.APP_NAME }} ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} -n sit`
- `kubectl rollout status deployment/${{ vars.APP_NAME }} -n sit --timeout=5m`
- Health check: `vars.SIT_HEALTH_URL`
- Rollback: `if: failure()` → `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n sit`

---

#### Job 2: `deploy-uat` — 1 required approval

```yaml
deploy-uat:
  name: Deploy to UAT
  runs-on: ubuntu-latest
  needs: [deploy-sit]
  timeout-minutes: 15
  environment: uat              # Configure: 1 required reviewer in repo Settings
  permissions:
    contents: read
    id-token: write
    actions: read
```

Deploy steps pattern:
- Download `deploy-metadata` artifact (same `run-id` from `github.event.workflow_run.id`)
- Read metadata
- Azure OIDC login
- AKS context: use `vars.AKS_CLUSTER_NAME_UAT` / `vars.AKS_RESOURCE_GROUP_UAT`
- `kubectl set image deployment/${{ vars.APP_NAME }} ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} -n uat`
- `kubectl rollout status deployment/${{ vars.APP_NAME }} -n uat --timeout=5m`
- Health check: `vars.UAT_HEALTH_URL`
- Rollback: `if: failure()` → `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n uat`

---

#### Job 3: `deploy-production` — 2 required approvals + Git tag

```yaml
deploy-production:
  name: Deploy to Production
  runs-on: ubuntu-latest
  needs: [deploy-uat]
  timeout-minutes: 20
  environment: production       # Configure: 2 required reviewers in repo Settings
  permissions:
    contents: write    # Required for git tag push
    id-token: write
    actions: read
```

Deploy steps pattern:
- Download `deploy-metadata` artifact (same `run-id`)
- Read metadata
- Azure OIDC login
- AKS context: use `vars.AKS_CLUSTER_NAME_PROD` / `vars.AKS_RESOURCE_GROUP_PROD`
- `kubectl set image deployment/${{ vars.APP_NAME }} ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} -n production`
- `kubectl rollout status deployment/${{ vars.APP_NAME }} -n production --timeout=10m`
- Health check: `vars.PRODUCTION_HEALTH_URL` (more retries than SIT/UAT)
- Rollback: `if: failure()` → `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n production`

**Git tag step — add as the final step, after health check passes**:

```yaml
- name: Create immutable Git tag
  if: success()
  run: |
    TAG="$(cat image-tag)"    # e.g. v1.0.0.abc1234
    git config user.name  "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git tag -a "${TAG}" \
      -m "Production deploy: ${TAG}" \
      "${{ github.event.workflow_run.head_sha || github.sha }}"
    git push origin "${TAG}"
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Constraint**: Git tag is created **exclusively** in `deploy-production`, only when `if: success()`. Never create git tags in `deploy-sit` or `deploy-uat`.

---

## Variables Required — Update in GitHub Repository Settings

After workflow changes, ensure these GitHub Variables are configured:

| Variable                     | Used in Job         | Example Value                       |
|------------------------------|---------------------|-------------------------------------|
| `AKS_CLUSTER_NAME_SIT`       | `deploy-sit`        | `aks-sit-eastasia`                  |
| `AKS_RESOURCE_GROUP_SIT`     | `deploy-sit`        | `rg-sit`                            |
| `AKS_CLUSTER_NAME_UAT`       | `deploy-uat`        | `aks-uat-eastasia`                  |
| `AKS_RESOURCE_GROUP_UAT`     | `deploy-uat`        | `rg-uat`                            |
| `AKS_CLUSTER_NAME_PROD`      | `deploy-production` | `aks-prod-eastasia`                 |
| `AKS_RESOURCE_GROUP_PROD`    | `deploy-production` | `rg-prod`                           |
| `SIT_HEALTH_URL`             | `deploy-sit`        | `https://sit.example.com/actuator/health` |
| `UAT_HEALTH_URL`             | `deploy-uat`        | `https://uat.example.com/actuator/health` |
| `PRODUCTION_HEALTH_URL`      | `deploy-production` | `https://app.example.com/actuator/health` |
| `APP_NAME`                   | All deploy jobs     | `hello-java`                        |
| `ACR_LOGIN_SERVER`           | container.yml       | `myregistry.azurecr.io`            |
| `ACR_REPOSITORY`             | container.yml       | `hello-java`                        |

## Environments — Configure in GitHub Settings → Environments

| Environment  | Required Reviewers | Notes                                         |
|--------------|--------------------|-----------------------------------------------|
| `sit`        | 0 (auto-deploy)    | Triggers immediately on Container success     |
| `uat`        | 1                  | Gate between SIT and PROD                     |
| `production` | 2                  | Final gate; Git tag created on success        |

---

## Validation Checklist

Before completing implementation, verify all of the following:

**pom.xml**
- [ ] `<version>` is `1.0.0` (no `-SNAPSHOT`)

**ci.yml**
- [ ] `Resolve version metadata` step exists in `build-and-package` job
- [ ] Output `image_tag` follows format `v{version}.{sha}` (e.g. `v1.0.0.abc1234`)
- [ ] `version-metadata` artifact uploaded with `retention-days: 3` and `if-no-files-found: error`
- [ ] Existing `app-jar` artifact still uploads `target/app.jar` unchanged
- [ ] Workflow `name: CI` is unchanged

**container.yml**
- [ ] `version-metadata` artifact downloaded in `build-image` with `run-id: ${{ github.event.workflow_run.id }}`
- [ ] Image tagged with `v{version}.{sha}` (no environment suffix)
- [ ] `build-image` job exposes `image_tag` as a job output
- [ ] `scan-image` uses `needs.build-image.outputs.image_tag` for `image-ref`
- [ ] `attest-and-push` uses `needs.build-image.outputs.image_tag` for docker tag and push
- [ ] `deploy-metadata` artifact contains `image-tag`, `full-image-ref`, and `image-digest`
- [ ] Workflow `name: Container` is unchanged

**deploy.yml**
- [ ] Exactly three jobs: `deploy-sit`, `deploy-uat`, `deploy-production`
- [ ] Job chain: `deploy-uat` needs `deploy-sit`; `deploy-production` needs `deploy-uat`
- [ ] `deploy-sit` has no approval gate, runs automatically
- [ ] `deploy-uat` uses `environment: uat` (1 reviewer configured in Settings)
- [ ] `deploy-production` uses `environment: production` (2 reviewers configured in Settings)
- [ ] All three jobs download `deploy-metadata` with `run-id: ${{ github.event.workflow_run.id }}`
- [ ] Git tag created only in `deploy-production`, only when `if: success()`
- [ ] `deploy-production` has `contents: write` permission
- [ ] All rollback steps use `if: failure()` (never `if: always()`)
- [ ] `concurrency.cancel-in-progress: false` preserved in deploy.yml
- [ ] Workflow `name: Deploy` is unchanged

**Security**
- [ ] No credentials or secrets hard-coded in any workflow file
- [ ] OIDC authentication (`azure/login@v2`) unchanged in all deploy jobs
- [ ] `git push origin "${TAG}"` uses `GITHUB_TOKEN` (not a PAT)
- [ ] Image tag is always read from artifact — never re-derived from `github.sha`

---

## Constraints — Do Not Violate

1. **Never rename** `name: CI`, `name: Container`, or `name: Deploy` — the `workflow_run` chain depends on exact names.
2. **Never re-derive SHA** in container.yml or deploy.yml — always read from the `version-metadata` artifact.
3. **Never rebuild or recompile** in container.yml — the JAR always comes from the `app-jar` artifact produced by ci.yml.
4. **Never push `:latest`** — only immutable `v{version}.{sha}` tags.
5. **Never add environment suffix** to the version string — a single tag is used for SIT, UAT, and PROD.
6. **Never create git tags** in `deploy-sit` or `deploy-uat` — only `deploy-production` on success.
7. **Never set `cancel-in-progress: true`** in deploy.yml — interrupting a `kubectl rollout` corrupts pod state.
8. **Keep `if: failure()`** on all rollback steps — never `if: always()`.
9. **Keep existing workflow triggers unchanged** — no changes to `on:` blocks in any workflow file.
