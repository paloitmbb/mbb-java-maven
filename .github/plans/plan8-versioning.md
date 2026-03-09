# Plan 8: Pipeline Semantic Versioning & Three-Environment Deployment

> **Status**: Approved — Ready for execution
> **Created**: 2026-03-09
> **Based on**: `.github/plans/versioning.prompt.md`

---

## Objective

Implement semantic versioning (`v{version}.{sha}`) with a single build artifact and a three-environment sequential deployment pipeline (SIT auto → UAT 1-approval → PROD 2-approvals + immutable Git tag) across the existing CI/CD workflows — without changing workflow triggers, `name:` fields, or the `workflow_run` chain.

---

## Extracted Values (Step 0)

```
artifactId  = hello-java
version     = 1.0-SNAPSHOT  →  1.0.0
image_tag   = v{version}.{sha}              e.g. v1.0.0.abc1234
named_jar   = hello-java-1.0.0.abc1234.jar (ephemeral, target/ only — not uploaded)
```

---

## Scope

**In Scope**:
- `pom.xml` — remove `-SNAPSHOT`, set version to `1.0.0`
- `.github/workflows/ci.yml` — add 3 version metadata steps in `build-and-package`
- `.github/workflows/container.yml` — 7 sub-changes to switch raw-SHA tags to semver tags
- `.github/workflows/deploy.yml` — replace 2-job chain with 3-job SIT→UAT→PROD chain

**Out of Scope**:
- `pr-validation.yml` — untouched
- Kubernetes namespace/RBAC configuration (operator responsibility)
- GitHub Environment approval configuration (documented as manual post-steps)

---

## Constraints (Never Violate)

| Rule | Reason |
|------|--------|
| `name: CI`, `name: Container`, `name: Deploy` must not change | `workflow_run` triggers match on exact name strings |
| No Maven/JDK in `container.yml` | Build-once principle |
| Never re-derive SHA in downstream workflows | SHA drift across `workflow_run` hops |
| `cancel-in-progress: false` in `deploy.yml` preserved | Interrupting `kubectl rollout` corrupts pod state |
| `if: success()` on Git tag step | `if: always()` would tag failed deploys |
| Git tag only in `deploy-production` | Tags mark production releases only |
| `github.event.workflow_run.head_sha` in tag step | `github.sha` drifts in `workflow_run` context |

---

## Task Breakdown

### Task 001: Bump pom.xml version to 1.0.0

- **ID**: `task-001`
- **Dependencies**: None
- **Estimated Time**: 5 minutes

**Change**: One line only — remove `-SNAPSHOT` suffix.

```xml
<!-- BEFORE -->
<version>1.0-SNAPSHOT</version>

<!-- AFTER -->
<version>1.0.0</version>
```

**Validation**:
```bash
mvn help:evaluate -Dexpression=project.version -q -DforceStdout
# Expected output: 1.0.0
```

**Rollback**:
```bash
git checkout pom.xml
```

---

### Task 002: Add Version Metadata Generation to ci.yml

- **ID**: `task-002`
- **Dependencies**: `task-001`
- **Estimated Time**: 20 minutes

**Where to insert**: Inside `build-and-package` job, after `Normalize JAR filename` step (id: `jar`), before `Upload app JAR` step.

**Step A — Resolve version metadata** (id: `version`):
```yaml
      - name: Resolve version metadata
        id: version
        run: |
          VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
          SHA="${GITHUB_SHA::7}"
          IMAGE_TAG="v${VERSION}.${SHA}"
          echo "version=${VERSION}"     >> "$GITHUB_OUTPUT"
          echo "sha=${SHA}"             >> "$GITHUB_OUTPUT"
          echo "image_tag=${IMAGE_TAG}" >> "$GITHUB_OUTPUT"
          mkdir -p /tmp/version-metadata
          printf '%s' "${VERSION}"    > /tmp/version-metadata/version
          printf '%s' "${SHA}"        > /tmp/version-metadata/sha
          printf '%s' "${IMAGE_TAG}"  > /tmp/version-metadata/image-tag
```

**Step B — Create named JAR**:
```yaml
      - name: Create named JAR
        run: |
          ARTIFACT_ID=$(mvn help:evaluate -Dexpression=project.artifactId -q -DforceStdout)
          NAMED_JAR="${ARTIFACT_ID}-${{ steps.version.outputs.version }}.${{ steps.version.outputs.sha }}.jar"
          cp target/app.jar "target/${NAMED_JAR}"
          echo "Named JAR created: target/${NAMED_JAR}"
```

**Step C — Upload version-metadata artifact**:
```yaml
      - name: Upload version-metadata artifact
        uses: actions/upload-artifact@v4
        with:
          name: version-metadata
          path: /tmp/version-metadata/
          retention-days: 3
          if-no-files-found: error
```

**Constraints**:
- Do NOT remove `Normalize JAR filename` step
- Do NOT remove `Upload app JAR` step (uploads `target/app.jar` as `app-jar`)
- Named JAR is supplementary — `container.yml` depends only on `app-jar`

**Validation**:
```bash
gh run download <run-id> --name version-metadata
cat image-tag
# Expected: v1.0.0.XXXXXXX
```

**Rollback**:
```bash
git checkout .github/workflows/ci.yml
```

---

### Task 003: Update container.yml for Semver Image Tags

- **ID**: `task-003`
- **Dependencies**: `task-002`
- **Estimated Time**: 30 minutes

**7 sub-changes across `build-image`, `scan-image`, and `attest-and-push` jobs:**

#### 3a — Add `outputs:` block to `build-image` job
```yaml
    outputs:
      image_tag: ${{ steps.version.outputs.image_tag }}
```
Position: directly after `permissions:` block in `build-image` job declaration.

#### 3b — Download + read version-metadata in `build-image`
Insert two steps after `Download app-jar artifact from CI`:
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
          IMAGE_TAG=$(cat /tmp/version-metadata/image-tag)
          echo "image_tag=${IMAGE_TAG}" >> "$GITHUB_OUTPUT"
```

#### 3c — Update `Build Docker image (no push)` step
```yaml
# tags:
app:${{ env.COMMIT_SHA }}  →  app:${{ steps.version.outputs.image_tag }}

# build-args APP_VERSION:
APP_VERSION=${{ env.COMMIT_SHA }}  →  APP_VERSION=${{ steps.version.outputs.image_tag }}
```

#### 3d — Update `scan-image` job Trivy step
```yaml
# image-ref:
app:${{ env.COMMIT_SHA }}  →  app:${{ needs.build-image.outputs.image_tag }}
```

#### 3e — Update `Tag, push, and capture digest` step in `attest-and-push`
```yaml
        run: |
          IMAGE_TAG="${{ needs.build-image.outputs.image_tag }}"
          IMAGE="${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}:${IMAGE_TAG}"
          docker tag "app:${IMAGE_TAG}" "${IMAGE}"
          docker push "${IMAGE}"
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | cut -d@ -f2)
          echo "image=${IMAGE}"         >> "$GITHUB_OUTPUT"
          echo "digest=${DIGEST}"       >> "$GITHUB_OUTPUT"
          echo "image_tag=${IMAGE_TAG}" >> "$GITHUB_OUTPUT"
```

#### 3f — Replace `Export deploy metadata` step body
```yaml
        run: |
          echo "${{ needs.build-image.outputs.image_tag }}" > /tmp/image-tag
          echo "${{ steps.push.outputs.image }}"            > /tmp/full-image-ref
          echo "${{ steps.push.outputs.digest }}"           > /tmp/image-digest
```

#### 3g — Update `Upload deploy-metadata artifact` paths
```yaml
          path: |
            /tmp/image-tag
            /tmp/full-image-ref
            /tmp/image-digest
```
(Replace `/tmp/commit-sha` with `/tmp/full-image-ref`)

**Validation**:
```bash
gh run download <run-id> --name deploy-metadata
cat image-tag        # Expected: v1.0.0.XXXXXXX
cat full-image-ref   # Expected: {ACR_LOGIN_SERVER}/{ACR_REPOSITORY}:v1.0.0.XXXXXXX
```

**Rollback**:
```bash
git checkout .github/workflows/container.yml
```

---

### Task 004: Replace deploy.yml Jobs with SIT→UAT→PROD Chain

- **ID**: `task-004`
- **Dependencies**: `task-003`
- **Estimated Time**: 25 minutes

Replace the entire `jobs:` section (currently `deploy-staging` + `deploy-production`) with 3 sequential jobs. All content above `jobs:` is **unchanged**.

**Read deploy metadata step** (pattern for all 3 jobs — reads updated artifact format):
```yaml
      - name: Read deploy metadata
        id: meta
        run: |
          echo "image_tag=$(cat image-tag)"      >> "$GITHUB_OUTPUT"
          echo "image=$(cat full-image-ref)"     >> "$GITHUB_OUTPUT"
          echo "digest=$(cat image-digest)"      >> "$GITHUB_OUTPUT"
```

#### Job 1: `deploy-sit` — Auto-deploy, no approval
```yaml
  deploy-sit:
    name: Deploy to SIT
    runs-on: ubuntu-latest
    timeout-minutes: 15
    if: >
      github.event.workflow_run.conclusion == 'success' ||
      github.event_name == 'workflow_dispatch'
    environment: sit
    permissions:
      contents: read
      id-token: write
      actions: read
```
- AKS vars: `AKS_CLUSTER_NAME_SIT` / `AKS_RESOURCE_GROUP_SIT`
- kubectl namespace: `-n sit`
- Rollout timeout: `--timeout=5m`
- Health check: `SIT_HEALTH_URL` (retry 5 × 10s)
- Rollback: `if: failure()` → `kubectl rollout undo -n sit`

#### Job 2: `deploy-uat` — 1 required approval
```yaml
  deploy-uat:
    name: Deploy to UAT
    runs-on: ubuntu-latest
    needs: [deploy-sit]
    timeout-minutes: 15
    if: >
      github.event.workflow_run.conclusion == 'success' ||
      github.event_name == 'workflow_dispatch'
    environment: uat
    permissions:
      contents: read
      id-token: write
      actions: read
```
- AKS vars: `AKS_CLUSTER_NAME_UAT` / `AKS_RESOURCE_GROUP_UAT`
- kubectl namespace: `-n uat`
- Rollout timeout: `--timeout=5m`
- Health check: `UAT_HEALTH_URL` (retry 5 × 10s)
- Rollback: `if: failure()` → `kubectl rollout undo -n uat`

#### Job 3: `deploy-production` — 2 required approvals + Git tag
```yaml
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [deploy-uat]
    timeout-minutes: 20
    if: |
      github.event.workflow_run.head_branch == 'main' ||
      (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main')
    environment: production
    permissions:
      contents: write   # Required for git tag push
      id-token: write
      actions: read
```
- Checkout: `persist-credentials: true` (required for `git push tag`)
- AKS vars: `AKS_CLUSTER_NAME_PROD` / `AKS_RESOURCE_GROUP_PROD`
- kubectl namespace: `-n production`
- Rollout timeout: `--timeout=10m`
- Health check: `PRODUCTION_HEALTH_URL` (retry 10 × 15s)
- Rollback: `if: failure()` → `kubectl rollout undo -n production`
- **Final step** — `Create immutable Git tag` (`if: success()`):
  ```bash
  IMAGE_TAG="${{ steps.meta.outputs.image_tag }}"
  git config user.name  "github-actions[bot]"
  git config user.email "github-actions[bot]@users.noreply.github.com"
  git tag "${IMAGE_TAG}" "${{ github.event.workflow_run.head_sha }}"
  git push origin "${IMAGE_TAG}"
  ```

**Validation**:
```bash
grep -n 'deploy-sit\|deploy-uat\|deploy-production' .github/workflows/deploy.yml
# Expected: 3 job names

grep -n 'Create immutable Git tag' .github/workflows/deploy.yml
# Expected: present, in deploy-production only

grep -n "if: success()" .github/workflows/deploy.yml
# Expected: git tag step only

grep -n 'cancel-in-progress' .github/workflows/deploy.yml
# Expected: cancel-in-progress: false
```

**Rollback**:
```bash
git checkout .github/workflows/deploy.yml
```

---

## Post-Implementation Manual Steps

### GitHub Repository Settings → Environments

Configure these environments (Settings → Environments):

| Environment  | Required Reviewers | Allowed Branches  | Notes                                      |
|--------------|--------------------|-------------------|---------------------------------------------|
| `sit`        | 0                  | `main`, `develop` | Auto-deploys — no approval gate             |
| `uat`        | 1                  | `main`, `develop` | Requires 1 approval after SIT passes        |
| `production` | 2                  | `main` only       | Requires 2 approvals; Git tag created here  |

### GitHub Repository Settings → Variables

**Add new variables**:

| Variable               | Example Value                             |
|------------------------|-------------------------------------------|
| `AKS_CLUSTER_NAME_SIT` | `aks-sit-eastasia`                        |
| `AKS_RESOURCE_GROUP_SIT` | `rg-sit`                                |
| `AKS_CLUSTER_NAME_UAT` | `aks-uat-eastasia`                        |
| `AKS_RESOURCE_GROUP_UAT` | `rg-uat`                                |
| `SIT_HEALTH_URL`       | `https://sit.example.com/actuator/health` |
| `UAT_HEALTH_URL`       | `https://uat.example.com/actuator/health` |

**Existing variables (must not be renamed)**:

| Variable                  | Used in              |
|---------------------------|----------------------|
| `AKS_CLUSTER_NAME_PROD`   | `deploy-production`  |
| `AKS_RESOURCE_GROUP_PROD` | `deploy-production`  |
| `PRODUCTION_HEALTH_URL`   | `deploy-production`  |
| `APP_NAME`                | All deploy jobs      |
| `ACR_LOGIN_SERVER`        | `container.yml`      |
| `ACR_REPOSITORY`          | `container.yml`      |

**Variables that can be removed after validation**:
- `AKS_CLUSTER_NAME_STAGING` (replaced by `AKS_CLUSTER_NAME_SIT`)
- `AKS_RESOURCE_GROUP_STAGING` (replaced by `AKS_RESOURCE_GROUP_SIT`)

### Known Limitation

When `deploy.yml` is triggered via `workflow_dispatch` (not `workflow_run`), the `deploy-metadata` artifact download uses `run-id: ${{ github.event.workflow_run.id }}` which will be empty. This is a pre-existing architectural constraint — manual dispatch of the deploy workflow requires a matching upstream Container workflow run-id. This limitation is documented here; no workaround is in scope for this plan.

---

## Files to Create/Modify

| File Path | Type | Purpose | Task |
|-----------|------|---------|------|
| `pom.xml` | Modify (1 line) | Clean semver version | task-001 |
| `.github/workflows/ci.yml` | Modify (insert 3 steps) | Version metadata artifact | task-002 |
| `.github/workflows/container.yml` | Modify (7 sub-changes) | Semver image tags + new deploy-metadata | task-003 |
| `.github/workflows/deploy.yml` | Modify (replace `jobs:`) | 3-env chain + Git tag | task-004 |

---

## Validation Checklist

**Phase 1 — pom.xml**
- [ ] `<version>` is `1.0.0` (no `-SNAPSHOT`, no env suffix)

**Phase 2 — ci.yml**
- [ ] `Resolve version metadata` step exists after `Normalize JAR filename`
- [ ] `steps.version.outputs.image_tag` produces `v{version}.{sha}` format
- [ ] `version-metadata` artifact uploaded with `retention-days: 3` and `if-no-files-found: error`
- [ ] `Upload app JAR` step still uploads `target/app.jar` as `app-jar` (unchanged)
- [ ] Workflow `name: CI` header is unchanged

**Phase 3 — container.yml**
- [ ] `build-image` job has `outputs: image_tag: ${{ steps.version.outputs.image_tag }}`
- [ ] `version-metadata` artifact downloaded with `run-id: ${{ github.event.workflow_run.id }}`
- [ ] Docker image tagged `v{version}.{sha}` — no raw SHA, no `:latest`
- [ ] `scan-image` Trivy `image-ref` uses `needs.build-image.outputs.image_tag`
- [ ] `attest-and-push` push step uses `needs.build-image.outputs.image_tag`
- [ ] `deploy-metadata` artifact contains: `image-tag`, `full-image-ref`, `image-digest` (no `commit-sha`)
- [ ] Workflow `name: Container` header is unchanged

**Phase 4 — deploy.yml**
- [ ] Exactly 3 jobs: `deploy-sit`, `deploy-uat`, `deploy-production`
- [ ] Job chain: `deploy-uat` has `needs: [deploy-sit]`; `deploy-production` has `needs: [deploy-uat]`
- [ ] `deploy-sit` has no `needs:` (auto-deploys, `environment: sit`)
- [ ] `deploy-uat` uses `environment: uat`
- [ ] `deploy-production` uses `environment: production` (main-branch gate preserved)
- [ ] All 3 jobs download `deploy-metadata` with `run-id: ${{ github.event.workflow_run.id }}`
- [ ] All 3 jobs read `image-tag`, `full-image-ref`, `image-digest` (not `commit-sha`)
- [ ] `Create immutable Git tag` step exists **only** in `deploy-production`
- [ ] Git tag step has `if: success()`
- [ ] Git tag step uses `github.event.workflow_run.head_sha`
- [ ] `deploy-production` checkout has `persist-credentials: true`
- [ ] `deploy-production` has `contents: write` permission
- [ ] All 3 rollback steps use `if: failure()`
- [ ] `concurrency.cancel-in-progress: false` at workflow level is preserved
- [ ] Workflow `name: Deploy` header is unchanged

**pr-validation.yml**
- [ ] File is untouched — `name: PR Validation` header is unchanged

---

## Commit Message

```
ci(versioning): :sparkles: add semver v{version}.{sha} + 3-env deploy chain

- bump pom.xml version to 1.0.0 (removes -SNAPSHOT)
- add version metadata generation in ci.yml (3 steps after Normalize JAR)
- switch container.yml image tags to v{version}.{sha} format
- replace deploy-staging+deploy-production with sit+uat+production chain
- add immutable git tag creation on production deploy success

References: .github/plans/versioning.prompt.md
```

---

## Machine-Readable Implementation Plan

```json
{
  "plan_metadata": {
    "plan_number": 8,
    "filename": "plan8-versioning.md",
    "created_by": "ai-plan-agent",
    "model": "claude-sonnet-4.6",
    "created_at": "2026-03-09T00:00:00Z",
    "based_on_input": "versioning.prompt.md — semantic versioning v{version}.{sha} with 3-environment sequential deployment",
    "instructions_considered": [
      ".github/copilot-instructions.md",
      ".github/instructions/github-actions-ci-cd-best-practices.instructions.md",
      ".github/instructions/git.instructions.md"
    ],
    "total_estimated_time_minutes": 80,
    "task_count": 4
  },
  "tasks": [
    {
      "id": "task-001",
      "title": "Bump pom.xml version to 1.0.0",
      "description": "Remove -SNAPSHOT suffix. Change <version>1.0-SNAPSHOT</version> to <version>1.0.0</version>. No other lines changed.",
      "dependencies": [],
      "outputs": [
        {
          "type": "file",
          "path": "pom.xml",
          "purpose": "Clean semver version for dynamic extraction in CI"
        }
      ],
      "validation": {
        "commands": ["mvn help:evaluate -Dexpression=project.version -q -DforceStdout"],
        "expected_result": "1.0.0"
      },
      "rollback": {
        "commands": ["git checkout pom.xml"]
      },
      "estimated_time_minutes": 5,
      "assignee": "ai-agent",
      "tags": ["maven", "versioning"]
    },
    {
      "id": "task-002",
      "title": "Add version metadata generation to ci.yml",
      "description": "Insert 3 steps after Normalize JAR filename in build-and-package job: (A) Resolve version metadata — runs mvn help:evaluate, builds image_tag=v{VERSION}.{SHA}, writes /tmp/version-metadata/{version,sha,image-tag}; (B) Create named JAR — copies app.jar to hello-java-{VERSION}.{SHA}.jar in target/; (C) Upload version-metadata artifact with retention-days: 3.",
      "dependencies": ["task-001"],
      "outputs": [
        {
          "type": "file",
          "path": ".github/workflows/ci.yml",
          "purpose": "3 new steps in build-and-package"
        },
        {
          "type": "artifact",
          "path": "version-metadata/",
          "purpose": "Contains version, sha, image-tag files consumed by container.yml"
        }
      ],
      "validation": {
        "commands": ["gh run download <run-id> --name version-metadata", "cat image-tag"],
        "expected_result": "v1.0.0.XXXXXXX"
      },
      "rollback": {
        "commands": ["git checkout .github/workflows/ci.yml"]
      },
      "estimated_time_minutes": 20,
      "assignee": "ai-agent",
      "tags": ["ci", "versioning", "github-actions"]
    },
    {
      "id": "task-003",
      "title": "Update container.yml for semver image tags",
      "description": "7 sub-changes: (3a) add outputs block to build-image job; (3b) download+read version-metadata artifact in build-image; (3c) update Build Docker image tags and build-args to use steps.version.outputs.image_tag; (3d) update scan-image Trivy image-ref to use needs.build-image.outputs.image_tag; (3e) update Tag/push/digest step to use semver tag; (3f) update Export deploy metadata to write image-tag, full-image-ref, image-digest; (3g) update Upload deploy-metadata paths replacing /tmp/commit-sha with /tmp/full-image-ref.",
      "dependencies": ["task-002"],
      "outputs": [
        {
          "type": "file",
          "path": ".github/workflows/container.yml",
          "purpose": "7 sub-changes across build-image, scan-image, attest-and-push jobs"
        },
        {
          "type": "artifact",
          "path": "deploy-metadata/",
          "purpose": "Contains image-tag, full-image-ref, image-digest (no commit-sha)"
        }
      ],
      "validation": {
        "commands": [
          "gh run download <run-id> --name deploy-metadata",
          "cat image-tag",
          "cat full-image-ref"
        ],
        "expected_result": "image-tag=v1.0.0.XXXXXXX; full-image-ref={ACR}/{repo}:v1.0.0.XXXXXXX"
      },
      "rollback": {
        "commands": ["git checkout .github/workflows/container.yml"]
      },
      "estimated_time_minutes": 30,
      "assignee": "ai-agent",
      "tags": ["container", "docker", "github-actions", "versioning"]
    },
    {
      "id": "task-004",
      "title": "Replace deploy.yml jobs with SIT+UAT+PROD chain",
      "description": "Replace entire jobs: section (keeping all content above jobs: unchanged). New jobs: deploy-sit (auto, environment: sit, AKS_CLUSTER_NAME_SIT, -n sit); deploy-uat (needs: deploy-sit, environment: uat 1-approval, AKS_CLUSTER_NAME_UAT, -n uat); deploy-production (needs: deploy-uat, environment: production 2-approvals, main-only, -n production, contents: write, persist-credentials: true, Create immutable Git tag if: success()). All 3 jobs read image-tag, full-image-ref, image-digest from deploy-metadata artifact.",
      "dependencies": ["task-003"],
      "outputs": [
        {
          "type": "file",
          "path": ".github/workflows/deploy.yml",
          "purpose": "3-environment sequential deployment chain with git tag on prod success"
        }
      ],
      "validation": {
        "commands": [
          "grep -n 'deploy-sit\\|deploy-uat\\|deploy-production' .github/workflows/deploy.yml",
          "grep -n 'Create immutable Git tag' .github/workflows/deploy.yml",
          "grep -n 'if: success()' .github/workflows/deploy.yml",
          "grep -n 'cancel-in-progress' .github/workflows/deploy.yml"
        ],
        "expected_result": "3 job names; git tag in deploy-production only; if: success(); cancel-in-progress: false"
      },
      "rollback": {
        "commands": ["git checkout .github/workflows/deploy.yml"]
      },
      "estimated_time_minutes": 25,
      "assignee": "ai-agent",
      "tags": ["deploy", "kubernetes", "github-actions", "versioning", "git-tag"]
    }
  ],
  "success_criteria": [
    "pom.xml <version> is 1.0.0 (no -SNAPSHOT)",
    "ci.yml version-metadata artifact contains image-tag file with v1.0.0.XXXXXXX format",
    "container.yml deploy-metadata artifact contains image-tag, full-image-ref, image-digest (no commit-sha)",
    "deploy.yml has exactly 3 jobs: deploy-sit, deploy-uat, deploy-production",
    "deploy-uat has needs: [deploy-sit]; deploy-production has needs: [deploy-uat]",
    "Create immutable Git tag step exists only in deploy-production with if: success()",
    "workflow name: fields (CI, Container, Deploy) are unchanged",
    "cancel-in-progress: false on deploy.yml is preserved"
  ],
  "rollback_strategy": {
    "backup_commands": ["git tag pre-plan8", "git stash"],
    "recovery_commands": ["git reset --hard pre-plan8"]
  }
}
```
