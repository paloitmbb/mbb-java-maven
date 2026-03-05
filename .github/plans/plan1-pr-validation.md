# Plan 1: PR Validation Workflow

## Plan Metadata
- **Plan Number**: 1
- **Filename**: plan1-pr-validation.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md
  - .github/instructions/github-actions-ci-cd-best-practices.instructions.md

## Objective

Create `.github/workflows/pr-validation.yml` — a fast-feedback workflow for pull requests with 6 jobs: one `setup-cache` job pre-warms the Maven dependency cache, then `build-and-test`, `code-quality`, and `codeql` run in parallel using that cache; `secrets-scan` and `dependency-review` run fully independently with no Maven dependency. No artifacts published, no containers built.

## Scope

**In Scope**:
- `.github/workflows/pr-validation.yml` (workflow file)
- 6 jobs: 1 cache warm-up (`setup-cache`) + 3 Maven-dependent (`build-and-test`, `code-quality`, `codeql`) + 2 fully independent (`secrets-scan`, `dependency-review`)

**Out of Scope**:
- CI build/package pipeline (plan2)
- Container/deployment workflows (plan3, plan4)
- Dockerfile, dependabot, prerequisites docs (plan5-7)

## pom.xml Prerequisites

The following Maven plugins and configurations MUST exist in `pom.xml` before this workflow can run:

| Plugin/Config | Purpose | Required For |
|---|---|---|
| `spring-boot-starter-test` dependency | JUnit 5 test framework | `build-and-test` job |
| `maven-surefire-plugin` | Runs unit tests, produces `target/surefire-reports/*.xml` | `build-and-test` job |
| `jacoco-maven-plugin` | Code coverage reporting and enforcement | `build-and-test` job (jacoco:report, jacoco:check) |
| JaCoCo `check` rule: ≥80% line coverage | Coverage gate | `build-and-test` job step 6 |
| `maven-checkstyle-plugin` | Style checking | `code-quality` job |
| `spotbugs-maven-plugin` | Bug detection | `code-quality` job |
| `<java.version>21</java.version>` or `<maven.compiler.source>21</maven.compiler.source>` | Java version | All jobs using `setup-java` |

## Secrets & Variables Required

| Type | Name | Purpose |
|---|---|---|
| Secret | `GITLEAKS_LICENSE` | Gitleaks license key (required for org/private repos; omit for public) |

## Task Breakdown

### Task 001: Create workflow directory
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 2 minutes
- **Description**: Create `.github/workflows/` directory if it doesn't exist.
- **Actions**:
  1. `mkdir -p .github/workflows`
- **Outputs**: Directory `.github/workflows/`
- **Validation**: `test -d .github/workflows && echo "OK"`
- **Rollback**: `rmdir .github/workflows` (only if it was newly created)

---

### Task 002: Create pr-validation.yml — workflow header and triggers
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 5 minutes
- **Description**: Create the workflow file with `name: PR Validation`, trigger on `pull_request` targeting `main` and `develop`, concurrency group `pr-${{ github.event.pull_request.number }}` with `cancel-in-progress: true`, and workflow-level `permissions: contents: read`.
- **Actions**:
  1. Create file `.github/workflows/pr-validation.yml`
  2. Set `name: PR Validation`
  3. Set trigger: `on: pull_request: branches: [main, develop]`
  4. Set `concurrency: group: pr-${{ github.event.pull_request.number }}` with `cancel-in-progress: true`
  5. Set workflow-level `permissions: contents: read`
- **Outputs**: File `.github/workflows/pr-validation.yml` (header section)
- **Validation**: YAML lint passes on the file header
- **Rollback**: `rm .github/workflows/pr-validation.yml`

---

### Task 003: Add setup-cache job
- **ID**: `task-003`
- **Dependencies**: [`task-002`]
- **Estimated Time**: 5 minutes
- **Description**: Add the `setup-cache` job that checks out the repo and runs `mvn dependency:go-offline` to pre-download all Maven dependencies into `~/.m2`. `actions/setup-java` saves this to the Actions cache. The 3 downstream Maven jobs (`build-and-test`, `code-quality`, `codeql`) restore from this cache instead of each downloading dependencies independently — eliminating 2 redundant dependency resolution cycles on cold cache.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 10`
  2. Job permissions: `contents: read`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — `java-version: '21'`, `distribution: temurin`, `cache: maven` (saves cache at job end)
  5. Step 3: Run `mvn --batch-mode --no-transfer-progress dependency:go-offline` — resolves and downloads all compile/test/plugin dependencies to `~/.m2`
- **Outputs**: Warm Maven Actions cache keyed on `pom.xml` hash
- **Validation**:
  - `cache: maven` on `setup-java` step (triggers cache save)
  - `dependency:go-offline` step present
  - No compile, test, or package steps
- **Rollback**: Remove the `setup-cache` job block

---

### Task 004: Add build-and-test job
- **ID**: `task-004`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 15 minutes
- **Description**: Add the `build-and-test` job with 8 steps: checkout (fetch-depth: 1, persist-credentials: false), setup-java (Java 21, temurin, cache: maven — restores warm cache from `setup-cache`), compile, test, jacoco:report (if: always()), jacoco:check (≥80% line coverage), publish-unit-test-result-action (if: always()), upload surefire reports artifact (retention-days: 5, if: always()).
- **Actions**:
  1. Job config: `needs: setup-cache`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`
  2. Job permissions: `contents: read`, `checks: write`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — `java-version: '21'`, `distribution: temurin`, `cache: maven` (restores cache saved by `setup-cache`)
  5. Step 3: Run `mvn --batch-mode --no-transfer-progress clean compile`
  6. Step 4: Run `mvn --batch-mode test`
  7. Step 5: Run `mvn jacoco:report` with `if: always()`
  8. Step 6: Run `mvn jacoco:check` (enforces ≥80% line coverage)
  9. Step 7: `EnricoMi/publish-unit-test-result-action@v2` with `if: always()`
  10. Step 8: `actions/upload-artifact@v4` — name `pr-test-reports`, path `target/surefire-reports/`, `retention-days: 5`, `if: always()`
- **Outputs**: `build-and-test` job definition in workflow YAML
- **Validation**:
  - YAML lint passes
  - `actions/setup-java@v4` uses `cache: maven` (no separate `actions/cache` step)
  - `persist-credentials: false` on checkout
  - `if: always()` on steps 5, 7, 8
- **Rollback**: Remove the `build-and-test` job block from the YAML

---

### Task 005: Add code-quality job
- **ID**: `task-005`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `code-quality` job with 5 steps: checkout, setup-java, checkstyle:check, spotbugs:check, upload quality reports artifact.
- **Actions**:
  1. Job config: `needs: setup-cache`, `runs-on: ubuntu-latest`, `timeout-minutes: 10`
  2. Job permissions: `contents: read`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  4. Step 2: `actions/setup-java@v4` — Java 21, temurin, `cache: maven` (restores cache saved by `setup-cache`)
  5. Step 3: Run `mvn --batch-mode compile checkstyle:check` (fail on any violation)
  6. Step 4: Run `mvn --batch-mode compile spotbugs:check` (fail on HIGH/CRITICAL — explicit `compile` ensures bytecode exists for SpotBugs analysis)
  7. Step 5: `actions/upload-artifact@v4` — name `quality-reports`, paths `target/checkstyle-result.xml` and `target/spotbugsXml.xml`, `retention-days: 7`
- **Outputs**: `code-quality` job definition
- **Validation**: YAML lint, no `security-events: write` permission, `persist-credentials: false`
- **Rollback**: Remove the `code-quality` job block

---

### Task 006: Add secrets-scan job
- **ID**: `task-006`
- **Dependencies**: [`task-002`] — **no `needs: setup-cache`** — Gitleaks does not use Maven; starts immediately in parallel with `setup-cache`
- **Estimated Time**: 5 minutes
- **Description**: Add the `secrets-scan` job with 2 steps: full checkout (fetch-depth: 0 for Gitleaks) and gitleaks-action.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 5`
  2. Job permissions: `contents: read`
  3. Step 1: `actions/checkout@v4` — `fetch-depth: 0`, `persist-credentials: false`
  4. Step 2: `gitleaks/gitleaks-action@v2` — `args: detect --verbose --redact`, env `GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}` with `# TODO: set GITLEAKS_LICENSE secret`
- **Outputs**: `secrets-scan` job definition
- **Validation**: `fetch-depth: 0` (required for Gitleaks full scan), `persist-credentials: false`
- **Rollback**: Remove the `secrets-scan` job block

---

### Task 007: Add codeql job
- **ID**: `task-007`
- **Dependencies**: [`task-003`]
- **Estimated Time**: 10 minutes
- **Description**: Add the `codeql` job with fork-detection condition, CodeQL init, manual compile (mvn compile -DskipTests), and CodeQL analyze.
- **Actions**:
  1. Job config: `needs: setup-cache`, `runs-on: ubuntu-latest`, `timeout-minutes: 30`
  2. Job permissions: `contents: read`, `security-events: write`, `actions: read`
  3. Condition: `if: github.event.pull_request.head.repo.full_name == github.repository` (skip on forks)
  4. Step 1: `actions/checkout@v4` — `fetch-depth: 0` (CodeQL needs full history), `persist-credentials: false`
  5. Step 2: `github/codeql-action/init@v3` — `languages: java-kotlin`, `queries: security-and-quality`
  6. Step 3: `actions/setup-java@v4` — Java 21, temurin, `cache: maven` (restores cache saved by `setup-cache`)
  7. Step 4: Run `mvn --batch-mode compile -DskipTests` (manual autobuild)
  8. Step 5: `github/codeql-action/analyze@v3` — `category: /language:java`
- **Outputs**: `codeql` job definition
- **Validation**:
  - `security-events: write` ONLY on this job (and not on build-and-test, code-quality, etc.)
  - `fetch-depth: 0` used (required by CodeQL)
  - Fork guard condition present
- **Rollback**: Remove the `codeql` job block

---

### Task 008: Add dependency-review job
- **ID**: `task-008`
- **Dependencies**: [`task-002`] — **no `needs: setup-cache`** — pure GitHub API call, no Maven needed; starts immediately in parallel with `setup-cache`
- **Estimated Time**: 5 minutes
- **Description**: Add the `dependency-review` job using `actions/dependency-review-action@v4` with fail-on-severity high, license deny list, and PR comment on failure.
- **Actions**:
  1. Job config: `runs-on: ubuntu-latest`, `timeout-minutes: 10`
  2. Job permissions: `contents: read`, `pull-requests: write`
  3. Step 1: `actions/checkout@v4` — `persist-credentials: false`
  4. Step 2: `actions/dependency-review-action@v4` — `fail-on-severity: high`, `deny-licenses: GPL-2.0, AGPL-3.0`, `comment-summary-in-pr: on-failure`
- **Outputs**: `dependency-review` job definition
- **Validation**: `pull-requests: write` permission (required for PR comments), `persist-credentials: false`
- **Rollback**: Remove the `dependency-review` job block

---

### Task 009: Final validation
- **ID**: `task-009`
- **Dependencies**: [`task-004`, `task-005`, `task-006`, `task-007`, `task-008`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the complete workflow file for YAML syntax, permission correctness, and compliance with constraints.
- **Actions**:
  1. Run YAML linter on `.github/workflows/pr-validation.yml`
  2. Verify workflow `name:` is exactly `PR Validation`
  3. Verify exactly 6 jobs exist: `setup-cache`, `build-and-test`, `code-quality`, `secrets-scan`, `codeql`, `dependency-review`
  4. Verify `build-and-test`, `code-quality`, `codeql` each have `needs: setup-cache`
  5. Verify `secrets-scan` and `dependency-review` have NO `needs:` (start immediately)
  6. Verify `persist-credentials: false` on every checkout step
  7. Verify `security-events: write` appears ONLY on the `codeql` job
  8. Verify `fetch-depth: 0` appears ONLY on `codeql` and `secrets-scan` jobs
  9. Verify no `id-token: write` or `attestations: write` permissions
  10. Verify `setup-cache` has no compile/test/package steps — only `dependency:go-offline`
- **Validation**: All 10 checks pass
- **Rollback**: N/A (validation only)

## Dependency Graph

```mermaid
graph TD
    task-001[Task 001: Create workflow dir]
    task-002[Task 002: Workflow header/triggers]
    task-003[Task 003: setup-cache job]
    task-004[Task 004: build-and-test job]
    task-005[Task 005: code-quality job]
    task-006[Task 006: secrets-scan job]
    task-007[Task 007: codeql job]
    task-008[Task 008: dependency-review job]
    task-009[Task 009: Final validation]
    task-001 --> task-002
    task-002 --> task-003
    task-003 --> task-004
    task-003 --> task-005
    task-003 --> task-007
    task-002 --> task-006
    task-002 --> task-008
    task-004 --> task-009
    task-005 --> task-009
    task-006 --> task-009
    task-007 --> task-009
    task-008 --> task-009