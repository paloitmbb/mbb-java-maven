
---

### File 7: `.github/plans/plan7-cicd-prerequisites.md`

```markdown
# Plan 7: CI/CD Prerequisites Documentation

## Plan Metadata
- **Plan Number**: 7
- **Filename**: plan7-cicd-prerequisites.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md
  - .github/instructions/update-docs-on-code-change.instructions.md

## Objective

Create `docs/cicd-prerequisites.md` documenting all one-time setup requirements: GHAS enablement, GitHub environments, secrets/variables, Azure Workload Identity Federation, Kubernetes namespaces, and workflow name reference table.

## Scope

**In Scope**:
- `docs/cicd-prerequisites.md` with 6 sections
- All secrets, variables, RBAC assignments, and environment configurations
- Workflow name reference table (critical for `workflow_run` chain)

**Out of Scope**:
- Actual Azure/AKS provisioning
- GitHub settings configuration (document only)

## Task Breakdown

### Task 001: Create cicd-prerequisites.md — GHAS section
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 10 minutes
- **Description**: Create the file with Section 1: GitHub Advanced Security enablement, including a table mapping GHAS features to pipeline jobs.
- **Actions**:
  1. Create file `docs/cicd-prerequisites.md`
  2. Title: `# CI/CD Pipeline Prerequisites`
  3. Section 1: `## 1. GitHub Advanced Security (GHAS) — Enable in Repository Settings`
  4. GHAS coverage table:

     | GHAS Feature | Where it runs |
     |---|---|
     | CodeQL code scanning | `pr-validation.yml` (`codeql` on PRs) + `ci.yml` (`codeql` on push + weekly) |
     | Secret scanning (with push protection) | GitHub-native; `secrets-scan` (Gitleaks) in `pr-validation.yml` complementary |
     | Dependency graph + Dependabot alerts | `ci.yml` `sbom` job via `maven-dependency-submission-action`; `.github/dependabot.yml` |
- **Outputs**: `docs/cicd-prerequisites.md` Section 1
- **Validation**: All 3 GHAS pillars documented with pipeline locations
- **Rollback**: `rm docs/cicd-prerequisites.md`

---

### Task 002: Add GitHub Environments section
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 5 minutes
- **Description**: Section 2: Required GitHub repository environments.
- **Actions**:
  1. Section 2: `## 2. GitHub Repository Environments`
  2. `staging`: no required reviewers, deployment branches `develop` and `main`
  3. `production`: require ≥2 reviewers, restrict deployment branch to `main`
- **Outputs**: Section 2 in doc
- **Validation**: Both environments documented with correct restrictions
- **Rollback**: Remove section

---

### Task 003: Add Secrets and Variables section
- **ID**: `task-003`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 10 minutes
- **Description**: Section 3: All required secrets and variables with their purpose and which workflow uses them.
- **Actions**:
  1. Section 3: `## 3. Required Secrets and Variables`
  2. Secrets table:
     - `AZURE_CLIENT_ID` — Azure OIDC (container.yml, deploy.yml)
     - `AZURE_TENANT_ID` — Azure OIDC (container.yml, deploy.yml)
     - `AZURE_SUBSCRIPTION_ID` — Azure OIDC (container.yml, deploy.yml)
     - `GITLEAKS_LICENSE` — pr-validation.yml (private/org repos only)
  3. Variables table:
     - `ACR_LOGIN_SERVER` — container.yml
     - `ACR_REPOSITORY` — container.yml
     - `APP_NAME` — deploy.yml
     - `AKS_CLUSTER_NAME_STAGING` — deploy.yml
     - `AKS_RESOURCE_GROUP_STAGING` — deploy.yml
     - `AKS_CLUSTER_NAME_PROD` — deploy.yml
     - `AKS_RESOURCE_GROUP_PROD` — deploy.yml
     - `STAGING_HEALTH_URL` — deploy.yml
     - `PRODUCTION_HEALTH_URL` — deploy.yml
- **Outputs**: Section 3 in doc
- **Validation**: All 4 secrets and 9 variables documented
- **Rollback**: Remove section

---

### Task 004: Add Azure Workload Identity Federation section
- **ID**: `task-004`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 10 minutes
- **Description**: Section 4: Azure AD setup for OIDC.
- **Actions**:
  1. Section 4: `## 4. Azure Workload Identity Federation`
  2. Create Azure AD App Registration
  3. Add 3 federated credentials with subjects:
     - `repo:<org>/<repo>:ref:refs/heads/main`
     - `repo:<org>/<repo>:ref:refs/heads/develop`
     - `repo:<org>/<repo>:environment:production`
  4. RBAC assignments:
     - `AcrPush` on ACR resource scope
     - `Azure Kubernetes Service Cluster User Role` on each AKS cluster
     - `Azure Kubernetes Service RBAC Writer` on each AKS cluster
- **Outputs**: Section 4 in doc
- **Validation**: All federated credentials and RBAC assignments documented
- **Rollback**: Remove section

---

### Task 005: Add Kubernetes Namespaces section
- **ID**: `task-005`
- **Dependencies**: [`task-004`]
- **Estimated Time**: 5 minutes
- **Description**: Section 5: Required namespaces and Deployment resources.
- **Actions**:
  1. Section 5: `## 5. Kubernetes Namespaces`
  2. Namespaces `staging` and `production` in respective AKS clusters
  3. Deployment resource named `$APP_NAME` must exist in each namespace
- **Outputs**: Section 5 in doc
- **Validation**: Both namespaces and Deployment resource requirement documented
- **Rollback**: Remove section

---

### Task 006: Add Workflow Name Reference Table
- **ID**: `task-006`
- **Dependencies**: [`task-005`]
- **Estimated Time**: 5 minutes
- **Description**: Section 6: Exact `name:` values used in `workflow_run` triggers — mismatch silently breaks the chain.
- **Actions**:
  1. Section 6: `## 6. Workflow Name Reference Table`
  2. Table:

     | Workflow file | `name:` (referenced by downstream) |
     |---|---|
     | `ci.yml` | `CI` |
     | `container.yml` | `Container` |
  3. Warning: a name mismatch silently breaks the `workflow_run` chain
- **Outputs**: Section 6 in doc
- **Validation**: Both workflow names documented with warning
- **Rollback**: Remove section

---

### Task 007: Final validation
- **ID**: `task-007`
- **Dependencies**: [`task-006`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the complete prerequisites document.
- **Actions**:
  1. Verify all 6 sections present
  2. Verify GHAS coverage table
  3. Verify workflow name reference table
  4. Verify all 4 secrets and 9 variables listed
  5. Verify Azure RBAC assignments documented
  6. Verify Markdown renders correctly
- **Validation**: All checks pass
- **Rollback**: N/A

## Dependency Graph

```mermaid
graph TD
    task-001[Task 001: GHAS section]
    task-002[Task 002: Environments]
    task-003[Task 003: Secrets/Variables]
    task-004[Task 004: Azure OIDC]
    task-005[Task 005: K8s Namespaces]
    task-006[Task 006: Workflow names]
    task-007[Task 007: Validation]
    task-001 --> task-002
    task-002 --> task-003
    task-003 --> task-004
    task-004 --> task-005
    task-005 --> task-006
    task-006 --> task-007