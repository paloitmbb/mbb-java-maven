
---

### File 3: `.github/plans/plan3-container.md`

```markdown
# Plan 3: Container Workflow

## Plan Metadata
- **Plan Number**: 3
- **Filename**: plan3-container.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md
  - .github/instructions/github-actions-ci-cd-best-practices.instructions.md

## Objective

Create `.github/workflows/container.yml` — builds a thin runtime image from the pre-built JAR (build-once principle), scans with Trivy, generates SLSA provenance attestation, and pushes to ACR with immutable SHA-only tags. 3 chained jobs: build-image → scan-image → attest-and-push.

## Scope

**In Scope**:
- `.github/workflows/container.yml`
- 3 chained jobs
- `deploy-metadata` artifact production (commit-sha, image-tag, image-digest)

**Out of Scope**:
- Dockerfile creation (plan5) — this workflow references it but doesn't create it
- Deployment (plan4)

## pom.xml Prerequisites

None — this workflow does NOT run Maven. It downloads the pre-built `app-jar` artifact from CI.

## Secrets & Variables Required

| Type | Name | Purpose |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Azure OIDC client ID |
| Secret | `AZURE_TENANT_ID` | Azure AD tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| Variable | `ACR_LOGIN_SERVER` | ACR login server (e.g., `myregistry.azurecr.io`) |
| Variable | `ACR_REPOSITORY` | ACR repository name (e.g., `myapp`) |

## Upstream/Downstream Workflows

| Direction | Workflow | Trigger |
|---|---|---|
| Upstream | `ci.yml` (`CI`) | `workflow_run: workflows: ['CI']`, `types: [completed]`, `branches: [main, develop]` |
| Downstream | `deploy.yml` (`Deploy`) | `workflow_run: workflows: ['Container']` — **name must be exactly `Container`** |

## Critical Design Notes

- **`github.ref` in `workflow_run`**: Resolves to default branch, NOT triggering branch. Use `github.event.workflow_run.head_branch` for concurrency and branch conditionals.
- **Commit SHA**: Use `github.event.workflow_run.head_sha || github.sha` via workflow-level `env.COMMIT_SHA`.
- **No Maven/JDK**: The `build-image` job only runs Docker — no `setup-java`, no `mvn`.
- **Immutable tags**: SHA-only, never `:latest`.

## Task Breakdown

### Task 001: Create container.yml — workflow header, triggers, env
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 5 minutes
- **Description**: Create the container workflow with workflow_run trigger, concurrency, and COMMIT_SHA env.
- **Actions**:
  1. Create file `.github/workflows/container.yml`
  2. Set `name: Container` — **critical**: referenced by `deploy.yml`'s `workflow_run`
  3. Trigger: `workflow_run: workflows: ['CI']`, `types: [completed]`, `branches: [main, develop]`; also `workflow_dispatch`
  4. Concurrency: `group: container-${{ github.event.workflow_run.head_branch || github.ref }}`, `cancel-in-progress: true`
  5. Workflow-level `permissions: contents: read`
  6. Top-level condition: `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'`
  7. Workflow-level env: `COMMIT_SHA: ${{ github.event.workflow_run.head_sha || github.sha }}`
- **Outputs**: File header of `container.yml`
- **Validation**: `name: Container` exact; `workflow_run: workflows: ['CI']` references correct upstream name
- **Rollback**: `rm .github/workflows/container.yml`

---

### Task 002: Add build-image job
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 15 minutes
- **Description**: Add the `build-image` job that downloads the pre-built JAR from CI, builds a Docker image (no Maven/JDK), saves to tarball, and uploads as artifact.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 15`
  2. Job permissions: `contents: read`, `actions: read`
  3. **No `setup-java` step** — this is critical.
  4. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  5. Step 2: `actions/download-artifact@v4` — `name: app-jar`, `path: target/`, `run-id: ${{ github.event.workflow_run.id }}`, `github-token: ${{ secrets.GITHUB_TOKEN }}`
  6. Step 3: `docker/setup-buildx-action@v3`
  7. Step 4: `docker/build-push-action@v6`:
     - `push: false`
     - `tags: app:${{ env.COMMIT_SHA }}`
     - `cache-from: type=gha`, `cache-to: type=gha,mode=max`
     - `outputs: type=docker,dest=/tmp/image.tar`
     - `build-args: APP_VERSION=${{ env.COMMIT_SHA }}`, `BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')`
  8. Step 5: `actions/upload-artifact@v4` — name `container-image`, path `/tmp/image.tar`, `retention-days: 1`
- **Outputs**: `build-image` job; `container-image` artifact
- **Validation**:
  - No `setup-java` or `mvn` step anywhere in this job
  - Uses `docker/build-push-action@v6` (not v5)
  - `push: false` (scan before push)
  - Docker layer cache via `type=gha`
- **Rollback**: Remove the `build-image` job block

---

### Task 003: Add scan-image job
- **ID**: `task-003`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `scan-image` job that loads the image, runs Trivy with exit-code 1 on HIGH/CRITICAL, uploads SARIF, and uploads report artifact.
- **Actions**:
  1. Job config: `needs: build-image`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`
  2. Job permissions: `contents: read`, `security-events: write`
  3. Step 1: `actions/download-artifact@v4` — name `container-image`
  4. Step 2: Run `docker load --input /tmp/image.tar`
  5. Step 3: `aquasecurity/trivy-action@0.29.0`:
     - `image-ref: app:${{ env.COMMIT_SHA }}`
     - `format: sarif`, `output: trivy-results.sarif`
     - `severity: CRITICAL,HIGH`, `exit-code: '1'`, `ignore-unfixed: true`
  6. Step 4: `github/codeql-action/upload-sarif@v3` — `sarif_file: trivy-results.sarif`, `category: trivy-container`, `if: always()`
  7. Step 5: `actions/upload-artifact@v4` — name `trivy-report`, path `trivy-results.sarif`, `retention-days: 30`, `if: always()`
- **Outputs**: `scan-image` job; Trivy SARIF in Security tab
- **Validation**: `exit-code: '1'` (hard gate); `if: always()` on SARIF upload and artifact
- **Rollback**: Remove the `scan-image` job block

---

### Task 004: Add attest-and-push job
- **ID**: `task-004`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 20 minutes
- **Description**: Add the `attest-and-push` job that loads the image, logs into Azure via OIDC, pushes to ACR with SHA-only tag, generates SLSA provenance, and uploads deploy-metadata artifact.
- **Actions**:
  1. Job config: `needs: scan-image`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`
  2. Condition:
     ```yaml
     if: |
       github.event_name == 'workflow_dispatch' ||
       github.event.workflow_run.head_branch == 'main' ||
       github.event.workflow_run.head_branch == 'develop'
     ```
  3. Job permissions: `contents: read`, `id-token: write`, `attestations: write`
  4. Step 1: `actions/download-artifact@v4` — name `container-image`
  5. Step 2: Run `docker load --input /tmp/image.tar`
  6. Step 3: `azure/login@v2` — OIDC with `client-id`, `tenant-id`, `subscription-id` from secrets (all with `# TODO` comments)
  7. Step 4: `azure/docker-login@v2` — `login-server: ${{ vars.ACR_LOGIN_SERVER }}` with `# TODO: set ACR_LOGIN_SERVER variable`
  8. Step 5 (id: `push`): Tag and push with immutable SHA tag:
     ```bash
     SHA="${{ env.COMMIT_SHA }}"
     IMAGE="${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}:${SHA}"
     docker tag "app:${SHA}" "${IMAGE}"
     docker push "${IMAGE}"
     DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | cut -d@ -f2)
     echo "image=${IMAGE}" >> "$GITHUB_OUTPUT"
     echo "digest=${DIGEST}" >> "$GITHUB_OUTPUT"
     ```
  9. Step 6: `actions/attest-build-provenance@v2`:
     - `subject-name: ${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}`
     - `subject-digest: ${{ steps.push.outputs.digest }}`
     - `push-to-registry: true`
  10. Step 7: Export deploy metadata:
      ```bash
      echo "${{ env.COMMIT_SHA }}" > /tmp/commit-sha
      echo "${{ steps.push.outputs.image }}" > /tmp/image-tag
      echo "${{ steps.push.outputs.digest }}" > /tmp/image-digest
      ```
  11. Step 8: `actions/upload-artifact@v4` — name `deploy-metadata`, paths `/tmp/commit-sha`, `/tmp/image-tag`, `/tmp/image-digest`, `retention-days: 7`
- **Outputs**: `attest-and-push` job; pushed image in ACR; SLSA provenance; `deploy-metadata` artifact
- **Validation**:
  - `id-token: write` and `attestations: write` ONLY on this job
  - Immutable SHA tag, no `:latest`
  - `deploy-metadata` includes all 3 files: commit-sha, image-tag, image-digest
  - Branch condition restricts to main/develop/workflow_dispatch
- **Rollback**: Remove the `attest-and-push` job block

---

### Task 005: Final validation
- **ID**: `task-005`
- **Dependencies**: [`task-004`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the complete container workflow.
- **Actions**:
  1. YAML lint
  2. Verify `name: Container` exactly
  3. Verify 3 chained jobs: `build-image` → `scan-image` → `attest-and-push`
  4. Verify `build-image` has NO `setup-java` or `mvn` steps
  5. Verify `security-events: write` only on `scan-image`
  6. Verify `id-token: write` only on `attest-and-push`
  7. Verify `attestations: write` only on `attest-and-push`
  8. Verify no `:latest` tag anywhere
  9. Verify `exit-code: '1'` on Trivy
  10. Verify `deploy-metadata` artifact uploaded with 3 files
  11. Verify `COMMIT_SHA` env uses `workflow_run.head_sha`
- **Validation**: All 11 checks pass
- **Rollback**: N/A

## Dependency Graph

```mermaid
graph TD
    task-001[Task 001: Workflow header]
    task-002[Task 002: build-image job]
    task-003[Task 003: scan-image job]
    task-004[Task 004: attest-and-push job]
    task-005[Task 005: Final validation]
    task-001 --> task-002
    task-002 --> task-003
    task-003 --> task-004
    task-004 --> task-005