
---

### File 4: `.github/plans/plan4-deploy.md`

```markdown
# Plan 4: Deploy Workflow

## Plan Metadata
- **Plan Number**: 4
- **Filename**: plan4-deploy.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md
  - .github/instructions/github-actions-ci-cd-best-practices.instructions.md

## Objective

Create `.github/workflows/deploy.yml` — deployment workflow with 2 sequential jobs: deploy-staging (both develop and main) → deploy-production (main only, gated by environment protection with ≥2 required reviewers). Uses kubectl for deployments with automated rollback on failure.

## Scope

**In Scope**:
- `.github/workflows/deploy.yml`
- 2 sequential jobs: `deploy-staging`, `deploy-production`
- Metadata reading from `deploy-metadata` artifact
- kubectl-based deployment with health checks and rollback

**Out of Scope**:
- Kubernetes manifest creation (assumed pre-existing)
- AKS cluster provisioning
- Environment protection rule configuration (documented in plan7)

## pom.xml Prerequisites

None — this workflow does not run Maven.

## Secrets & Variables Required

| Type | Name | Purpose |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Azure OIDC |
| Secret | `AZURE_TENANT_ID` | Azure OIDC |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure OIDC |
| Variable | `APP_NAME` | Deployment/container name in kubectl |
| Variable | `AKS_CLUSTER_NAME_STAGING` | Staging AKS cluster |
| Variable | `AKS_RESOURCE_GROUP_STAGING` | Staging resource group |
| Variable | `AKS_CLUSTER_NAME_PROD` | Production AKS cluster |
| Variable | `AKS_RESOURCE_GROUP_PROD` | Production resource group |
| Variable | `STAGING_HEALTH_URL` | Staging health check base URL |
| Variable | `PRODUCTION_HEALTH_URL` | Production health check base URL |

## Upstream/Downstream Workflows

| Direction | Workflow | Trigger |
|---|---|---|
| Upstream | `container.yml` (`Container`) | `workflow_run: workflows: ['Container']`, `types: [completed]` |

## Critical Design Notes

- **Never cancel in-progress deploys**: `cancel-in-progress: false`
- **Read metadata from artifact**, not from re-derived SHA (avoids drift across `workflow_run` hops)
- **Production only from main**: Branch check required
- **Rollback uses `if: failure()`**, NEVER `if: always()` on destructive kubectl commands

## Task Breakdown

### Task 001: Create deploy.yml — workflow header and triggers
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 5 minutes
- **Description**: Create the deploy workflow with workflow_run trigger and safe concurrency settings.
- **Actions**:
  1. Create file `.github/workflows/deploy.yml`
  2. Set `name: Deploy`
  3. Trigger: `workflow_run: workflows: ['Container']`, `types: [completed]`; also `workflow_dispatch`
  4. Concurrency: `group: deploy-${{ github.event.workflow_run.head_branch || github.ref }}`, `cancel-in-progress: false` — **never cancel in-progress deploys**
  5. Workflow-level `permissions: contents: read`
- **Outputs**: File header of `deploy.yml`
- **Validation**: `cancel-in-progress: false`; upstream workflow name exactly `Container`
- **Rollback**: `rm .github/workflows/deploy.yml`

---

### Task 002: Add deploy-staging job
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 15 minutes
- **Description**: Add the `deploy-staging` job with artifact download, Azure OIDC login, AKS context, kubectl set image, rollout status, health check, and rollback on failure.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 15`
  2. Condition: `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'`
  3. Environment: `staging`
  4. Job permissions: `contents: read`, `id-token: write`
  5. Step 1: `actions/checkout@v4` — `persist-credentials: false`
  6. Step 2: `actions/download-artifact@v4` — name `deploy-metadata`, `run-id: ${{ github.event.workflow_run.id }}`, `github-token: ${{ secrets.GITHUB_TOKEN }}`
  7. Step 3 (id: `meta`): Read deploy metadata:
     ```bash
     echo "sha=$(cat commit-sha)" >> "$GITHUB_OUTPUT"
     echo "image=$(cat image-tag)" >> "$GITHUB_OUTPUT"
     echo "digest=$(cat image-digest)" >> "$GITHUB_OUTPUT"
     ```
  8. Step 4: `azure/login@v2` — OIDC (with TODO comments on secrets)
  9. Step 5: `azure/aks-set-context@v4` — `cluster-name: ${{ vars.AKS_CLUSTER_NAME_STAGING }}`, `resource-group: ${{ vars.AKS_RESOURCE_GROUP_STAGING }}` (with TODO comments)
  10. Step 6: Deploy: `kubectl set image deployment/${{ vars.APP_NAME }} ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} -n staging` (with TODO on APP_NAME)
  11. Step 7: `kubectl rollout status deployment/${{ vars.APP_NAME }} -n staging --timeout=5m`
  12. Step 8: Health check: `curl --fail --retry 5 --retry-delay 10 ${{ vars.STAGING_HEALTH_URL }}/actuator/health` (with TODO)
  13. Step 9 (`if: failure()`): Rollback: `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n staging`
- **Outputs**: `deploy-staging` job definition
- **Validation**:
  - `id-token: write` present
  - `environment: staging`
  - Rollback step uses `if: failure()` (NOT `if: always()`)
  - Image tag read from artifact, not re-derived
- **Rollback**: Remove the `deploy-staging` job block

---

### Task 003: Add deploy-production job
- **ID**: `task-003`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 15 minutes
- **Description**: Add the `deploy-production` job with main-only condition, environment protection (`production` with ≥2 reviewers), and same deploy/rollback pattern as staging.
- **Actions**:
  1. Job config: `needs: deploy-staging`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`
  2. Condition — main only:
     ```yaml
     if: |
       github.event.workflow_run.head_branch == 'main' ||
       (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main')
     ```
  3. Environment: `production` — **must have ≥2 required reviewers in repo settings**
  4. Job permissions: `contents: read`, `id-token: write`
  5. Step 1: `actions/checkout@v4` — `persist-credentials: false`
  6. Step 2: Download `deploy-metadata` artifact (same pattern as staging, via `run-id`)
  7. Step 3 (id: `meta`): Read metadata files
  8. Step 4: `azure/login@v2` — OIDC (production federated credential)
  9. Step 5: `azure/aks-set-context@v4` — `cluster-name: ${{ vars.AKS_CLUSTER_NAME_PROD }}`, `resource-group: ${{ vars.AKS_RESOURCE_GROUP_PROD }}`
  10. Step 6: Deploy: `kubectl set image deployment/${{ vars.APP_NAME }} ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} -n production`
  11. Step 7: `kubectl rollout status deployment/${{ vars.APP_NAME }} -n production --timeout=10m`
  12. Step 8: Health check: `curl --fail --retry 10 --retry-delay 15 ${{ vars.PRODUCTION_HEALTH_URL }}/actuator/health`
  13. Step 9 (`if: failure()`): Rollback: `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n production`
- **Outputs**: `deploy-production` job definition
- **Validation**:
  - `needs: deploy-staging`
  - Main-only condition present
  - `environment: production`
  - Rollback `if: failure()`, NOT `if: always()`
  - No hardcoded APP_NAME, cluster names, or URLs
- **Rollback**: Remove the `deploy-production` job block

---

### Task 004: Final validation
- **ID**: `task-004`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the complete deploy workflow.
- **Actions**:
  1. YAML lint
  2. Verify 2 jobs: `deploy-staging` → `deploy-production`
  3. Verify `cancel-in-progress: false`
  4. Verify `id-token: write` on both deploy jobs
  5. Verify NO `attestations: write` or `security-events: write`
  6. Verify rollback steps use `if: failure()` (not `if: always()`)
  7. Verify image tag read from `deploy-metadata` artifact
  8. Verify production is main-only
  9. Verify `environment:` set on both jobs
  10. Verify all `vars.*` and `secrets.*` have `# TODO` comments
- **Validation**: All 10 checks pass
- **Rollback**: N/A

## Dependency Graph

```mermaid
graph TD
    task-001[Task 001: Workflow header]
    task-002[Task 002: deploy-staging job]
    task-003[Task 003: deploy-production job]
    task-004[Task 004: Final validation]
    task-001 --> task-002
    task-002 --> task-003
    task-003 --> task-004
