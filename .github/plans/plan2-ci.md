
---

### File 2: `.github/plans/plan2-ci.md`

```markdown
# Plan 2: CI Workflow

## Plan Metadata
- **Plan Number**: 2
- **Filename**: plan2-ci.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md
  - .github/instructions/github-actions-ci-cd-best-practices.instructions.md

## Objective

Create `.github/workflows/ci.yml` — the full build, test, package, and security gate workflow for pushes to `main`/`develop`. Produces the immutable JAR artifact consumed by the container workflow. Contains 4 jobs: build-and-package, security-gate, sbom, codeql (all three parallel after build-and-package).

## Scope

**In Scope**:
- `.github/workflows/ci.yml`
- 4 jobs: `build-and-package`, `security-gate`, `sbom`, `codeql`
- `app-jar` artifact production (the single point where the JAR is built, inside `build-and-package`)

**Out of Scope**:
- PR validation (plan1), container/deploy (plan3-4), Dockerfile (plan5), dependabot (plan6), docs (plan7)

## pom.xml Prerequisites

All prerequisites from plan1-pr-validation, plus:

| Plugin/Config | Purpose | Required For |
|---|---|---|
| `maven-failsafe-plugin` | Integration tests | `build` job step 5 |
| Integration test profile `-P integration-test` | Separates integration from unit tests | `build` job step 5 |
| `-DskipUnitTests=true` system property support | Skip unit tests during integration phase | `build` job step 5 |
| `org.owasp:dependency-check-maven` plugin | OWASP dependency scanning | `security-gate` job |
| `spring-boot-maven-plugin` | Packages executable JAR | `package` job |

## Secrets & Variables Required

None specific to this workflow beyond standard `GITHUB_TOKEN`.

## Upstream/Downstream Workflows

| Direction | Workflow | Trigger |
|---|---|---|
| Downstream | `container.yml` (`Container`) | `workflow_run: workflows: ['CI']` — **name must be exactly `CI`** |

## Task Breakdown

### Task 001: Create ci.yml — workflow header, triggers, and schedule
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 5 minutes
- **Description**: Create the CI workflow file with proper triggers, concurrency, and permissions.
- **Actions**:
  1. Create file `.github/workflows/ci.yml`
  2. Set `name: CI` — **critical**: this exact name is referenced by `container.yml`'s `workflow_run` trigger
  3. Triggers: `push` to `main`/`develop`, `workflow_dispatch`, `schedule: cron: '0 2 * * 1'` (weekly Monday 2AM for CodeQL)
  4. Concurrency: `group: ci-${{ github.ref }}`, `cancel-in-progress: false` — **never cancel in-progress CI on protected branches** (avoids lost artifacts/security scans when rapid pushes occur)
  5. Workflow-level `permissions: contents: read`
- **Outputs**: File `.github/workflows/ci.yml` header
- **Validation**: `name: CI` is exact; schedule cron syntax valid; `cancel-in-progress: false`
- **Rollback**: `rm .github/workflows/ci.yml`

---

### Task 002: Add build-and-package job (merged — eliminates double compilation)
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 20 minutes
- **Description**: Add the `build-and-package` job that compiles, tests, enforces coverage, packages the JAR, and uploads all artifacts — all in a **single job** to avoid redundant Maven compilation across separate runners.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 25`
  2. Job permissions: `contents: read`, `checks: write`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  5. Step 3: Run `mvn --batch-mode --no-transfer-progress clean verify -P integration-test` (compile + unit tests + integration tests + package in one lifecycle)
  6. Step 4: Run `mvn --batch-mode verify -P integration-test -DskipUnitTests=true` with `continue-on-error: true` (integration tests — soft gate)
  7. Step 5: Run `mvn jacoco:report` with `if: always()`
  8. Step 6: Run `mvn jacoco:check` (≥80% line coverage)
  9. Step 7: `EnricoMi/publish-unit-test-result-action@v2` with `if: always()`
  10. Step 8: `actions/upload-artifact@v4` — name `test-reports`, path `target/surefire-reports/`, `retention-days: 7`, `if: always()`
  11. Step 9: `actions/upload-artifact@v4` — name `coverage-report`, path `target/site/jacoco/`, `retention-days: 7`
  12. Step 10 (id: `jar`): Normalize JAR filename:
      ```bash
      JAR=$(ls target/*.jar | grep -v original | head -1)
      cp "$JAR" target/app.jar
      echo "path=target/app.jar" >> "$GITHUB_OUTPUT"
      ```
  13. Step 11: `actions/upload-artifact@v4` — name `app-jar`, path `target/app.jar`, `retention-days: 3`
- **Outputs**: `build-and-package` job definition; `app-jar` artifact; test/coverage reports
- **Validation**:
  - Artifact name is exactly `app-jar` (referenced by `container.yml`)
  - `continue-on-error: true` on integration test step
  - `if: always()` on report steps
  - Single Maven lifecycle — no redundant compilation
- **Rollback**: Remove the `build-and-package` job block

---

### Task 003: Add security-gate job
- **ID**: `task-003`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `security-gate` job running OWASP Dependency-Check with failBuildOnCVSS=7, SARIF upload, and report artifact.
- **Actions**:
  1. Job config: `needs: build-and-package`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`
  2. Job permissions: `contents: read`, `security-events: write`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  5. Step 3: Run OWASP DC: `mvn --batch-mode org.owasp:dependency-check-maven:check -DfailBuildOnCVSS=7 -Dformats=HTML,JSON,SARIF`
  6. Step 4: `github/codeql-action/upload-sarif@v3` — `sarif_file: target/dependency-check-report.sarif`, `category: owasp-dependency-check`, `if: always()`
  7. Step 5: `actions/upload-artifact@v4` — name `dependency-check-report`, path `target/dependency-check-report.*`, `retention-days: 30`, `if: always()`
- **Outputs**: `security-gate` job definition
- **Validation**: `security-events: write` present; `if: always()` on SARIF upload and artifact upload
- **Rollback**: Remove the `security-gate` job block

---

### Task 004: Add sbom job
- **ID**: `task-004`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `sbom` job with Maven dependency submission (powers Dependabot) and SPDX SBOM generation.
- **Actions**:
  1. Job config: `needs: build-and-package`, `runs-on: ubuntu-latest`, `timeout-minutes: 10`
  2. Job permissions: `contents: write` — required by `maven-dependency-submission-action` (NOT `security-events: write`)
  3. Step 1: `actions/checkout@v4` — `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  5. Step 3: `advanced-security/maven-dependency-submission-action@v4` — submits dependency graph to GitHub
  6. Step 4: `anchore/sbom-action@v0` — `format: spdx-json`, artifact name `sbom-${{ github.sha }}`
- **Outputs**: `sbom` job definition
- **Validation**: Permission is `contents: write` (NOT `security-events: write`)
- **Rollback**: Remove the `sbom` job block

---

### Task 005: Add codeql job
- **ID**: `task-005`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `codeql` job for push-triggered and weekly scheduled CodeQL SAST scanning. Same structure as pr-validation codeql but without fork guard (not needed on push).
- **Actions**:
  1. Job config: `needs: build-and-package`, `runs-on: ubuntu-latest`, `timeout-minutes: 30`
  2. Job permissions: `contents: read`, `security-events: write`, `actions: read`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 0`, `persist-credentials: false`
  4. Step 2: `github/codeql-action/init@v3` — `languages: java-kotlin`, `queries: security-and-quality`
  5. Step 3: `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  6. Step 4: Run `mvn --batch-mode compile -DskipTests` (manual autobuild)
  7. Step 5: `github/codeql-action/analyze@v3` — `category: /language:java`
- **Outputs**: `codeql` job definition
- **Validation**: `fetch-depth: 0`; `security-events: write` present; no fork guard (push-only)
- **Rollback**: Remove the `codeql` job block

---

### Task 006: Final validation
- **ID**: `task-006`
- **Dependencies**: [`task-002`, `task-003`, `task-004`, `task-005`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the complete CI workflow file.
- **Actions**:
  1. YAML lint
  2. Verify `name: CI` exactly
  3. Verify 4 jobs: `build-and-package`, `security-gate`, `sbom`, `codeql`
  4. Verify `security-gate`, `sbom`, `codeql` all need `build-and-package`
  5. Verify `schedule: cron: '0 2 * * 1'` is present
  6. Verify `persist-credentials: false` on all checkouts
  7. Verify `security-events: write` only on `security-gate` and `codeql`
  8. Verify `sbom` has `contents: write`, NOT `security-events: write`
  9. Verify artifact name is `app-jar` in `build-and-package` job
  10. Verify no `id-token: write` or `attestations: write`
  11. Verify `cancel-in-progress: false` (never cancel CI on protected branches)
- **Validation**: All 11 checks pass
- **Rollback**: N/A

## Dependency Graph

```mermaid
graph TD
    task-001[Task 001: Workflow header]
    task-002[Task 002: build-and-package job]
    task-003[Task 003: security-gate job]
    task-004[Task 004: sbom job]
    task-005[Task 005: codeql job]
    task-006[Task 006: Final validation]
    task-001 --> task-002
    task-002 --> task-003
    task-002 --> task-004
    task-002 --> task-005
    task-003 --> task-006
    task-004 --> task-006
    task-005 --> task-006