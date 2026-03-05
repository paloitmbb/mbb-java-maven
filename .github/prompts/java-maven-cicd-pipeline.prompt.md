---
description: "Generate 4 production-grade GitHub Actions workflow files for a Java Maven microservice — PR Validation (compile/quality/test/SAST/secrets scan/CodeQL/dependency-review), CI (full build/test/package/OWASP security gate/CodeQL/SBOM), Container delivery (thin image from pre-built JAR + Trivy scan + SLSA provenance attestation + ACR publish via OIDC), and Deploy (kubectl-based staging + approval gate + production) — plus thin-copy Dockerfile, Dependabot config, and prerequisites documentation."
agent: "agent"
tools: ["codebase", "editFiles", "search", "problems", "changes"]
---

# Java Maven Microservice — Production-Grade CI/CD Pipeline

You are a **senior DevSecOps architect** specializing in zero-trust Java/Maven pipelines, build-once immutable artifact delivery, GitHub Advanced Security (GHAS — CodeQL, Secret Scanning, Dependabot), Azure OIDC workload-identity authentication, container supply-chain security (SLSA provenance attestation), and kubectl-based deployment to AKS.

---

## Context

Before generating any file, read these project files and extract configuration values:

1. **`pom.xml`** — extract `<artifactId>` (use as default `APP_NAME`), `<java.version>` or `<maven.compiler.source>` (default `21` if absent), Spring Boot parent version.
2. **`.github/workflows/`** — check for existing workflow files; do **not** duplicate or overwrite them.
3. **`Dockerfile`** — if present, replace with thin copy-JAR image (build-once principle).
4. **`src/main/resources/application.properties`** or **`application.yml`** — detect `server.port` (default `8080`).

---

## Task

Generate **4 GitHub Actions workflow files** plus 3 supporting files that form a complete, production-grade CI/CD pipeline for this Java Maven microservice. The pipeline enforces the **build-once principle**: the JAR is compiled and packaged exactly once in CI, then propagated as an immutable artifact through container build and deployment stages. Downstream workflows chain via `workflow_run` triggers.

---

## Core Design Principles

1. **Build once** — The JAR is built in CI and never rebuilt. The Dockerfile copies the pre-built JAR into a thin runtime image. No Maven, no JDK in the production image.
2. **Scan before push** — Container images are Trivy-scanned and must pass before being pushed to any registry.
3. **Provenance attestation** — Every pushed image receives a SLSA provenance attestation via `actions/attest-build-provenance`, anchoring the image digest to the exact commit and workflow run that produced it.
4. **Immutable tags only** — Images are tagged exclusively with the commit SHA. No mutable `:latest` tag.
5. **Separate permissions per workflow** — Each workflow and job declares minimal permissions independently.
6. **Fail gates on severity** — Security scans fail the pipeline on HIGH/CRITICAL findings.
7. **Environment protection rules** — Production deploys require manual approval via GitHub environment protection.

---

## Workflow Architecture

```
pr-validation.yml (PR only — fast feedback, no publishing)
  ↳ jobs: build-and-test | code-quality | secrets-scan | codeql | dependency-review

ci.yml (push to main/develop — build + test + package + full security gate)
  ↳ jobs: build → package | security-gate (OWASP DC) | codeql | sbom
  └──► container.yml (thin image from JAR → Trivy scan → SLSA attestation → ACR push)
          ↳ jobs: build-image → scan-image → attest-and-push
                └──► deploy.yml (staging → approval gate → production)
                        ↳ jobs: deploy-staging → deploy-production
```

### Single upstream — no fan-in needed

Because all security checks run as jobs **within** `pr-validation.yml` (for PRs) and `ci.yml` (for pushes), `container.yml` has only **one** upstream workflow (`CI`). This eliminates the `workflow_run` fan-in race entirely — no gate script is required. `container.yml` fires once when CI completes.

### `github.ref` in `workflow_run` context

When triggered via `workflow_run`, `github.ref` resolves to the **default branch**, not the triggering branch. Always use `github.event.workflow_run.head_branch` for concurrency groups and branch conditionals inside `workflow_run`-triggered workflows.

### Commit SHA propagation across `workflow_run` hops

`github.event.workflow_run.head_sha` reliably refers to the upstream workflow run's commit SHA. However, after multiple `workflow_run` hops the SHA may drift to the default branch HEAD. To guarantee correctness, the `attest-and-push` job in `container.yml` must upload a `deploy-metadata` artifact containing the resolved commit SHA, full image tag, and image digest. Downstream deploy workflows must download and read this artifact instead of re-deriving the SHA.

### Build-once artifact flow

```
ci.yml [package job]            → uploads `app-jar` artifact (target/app.jar)
container.yml [build-image job] → downloads `app-jar`, COPY into thin runtime image (no Maven in Docker)
container.yml [attest-and-push] → uploads `deploy-metadata` (commit-sha, image-tag, image-digest)
deploy.yml [deploy-* jobs]      → downloads `deploy-metadata`, reads image tag + digest
```

---

## FILE 1 · `.github/workflows/pr-validation.yml` — name: `PR Validation`

Fast feedback workflow for pull requests. No artifacts published, no containers built. All jobs run in parallel for speed.

| Property | Value |
|---|---|
| **Trigger** | `pull_request` targeting `main`, `develop` |
| **Concurrency** | `group: pr-${{ github.event.pull_request.number }}`, `cancel-in-progress: true` |
| **Workflow permissions** | `contents: read` |

### Job: `build-and-test`

- `runs-on: ubuntu-latest`, `timeout-minutes: 20`
- Permissions: `contents: read`, `checks: write`
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. `actions/setup-java@v4` — `java-version: '21'`, `distribution: temurin`, `cache: maven`
  3. Run: `mvn --batch-mode --no-transfer-progress clean compile`
  4. Run: `mvn --batch-mode test` — unit tests
  5. Run: `mvn jacoco:report` — `if: always()`
  6. Run: `mvn jacoco:check` — enforce ≥80 % line coverage
  7. `EnricoMi/publish-unit-test-result-action@v2` — publish JUnit XML to Checks UI, `if: always()`
  8. `actions/upload-artifact@v4` — name `pr-test-reports`, path `target/surefire-reports/`, `retention-days: 5`, `if: always()`

### Job: `code-quality`

- `runs-on: ubuntu-latest`, `timeout-minutes: 10`
- Permissions: `contents: read`
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  3. Run: `mvn --batch-mode compile checkstyle:check` — fail on any violation
  4. Run: `mvn --batch-mode spotbugs:check` — fail on HIGH or CRITICAL
  5. `actions/upload-artifact@v4` — name `quality-reports`, paths: `target/checkstyle-result.xml`, `target/spotbugsXml.xml`, `retention-days: 7`

### Job: `secrets-scan`

- `runs-on: ubuntu-latest`, `timeout-minutes: 5`
- Permissions: `contents: read`
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 0`, `persist-credentials: false`
  2. `gitleaks/gitleaks-action@v2` — `args: detect --verbose --redact`
     - env: `GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}` # TODO: set GITLEAKS_LICENSE secret (required for org/private repos; omit for public repos)

### Job: `codeql`

- `runs-on: ubuntu-latest`, `timeout-minutes: 30`
- Permissions: `contents: read`, `security-events: write`, `actions: read`
- Condition: `if: github.event.pull_request.head.repo.full_name == github.repository` (skip on forks — SARIF upload requires `security-events: write` which forks lack)
- Steps:
  1. `actions/checkout@v4` — **`fetch-depth: 0`** (CodeQL needs full history), `persist-credentials: false`
  2. `github/codeql-action/init@v3` — `languages: java-kotlin`, `queries: security-and-quality`
  3. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  4. Run: `mvn --batch-mode compile -DskipTests` — manual autobuild
  5. `github/codeql-action/analyze@v3` — `category: /language:java`

### Job: `dependency-review`

- `runs-on: ubuntu-latest`, `timeout-minutes: 10`
- Permissions: `contents: read`, `pull-requests: write`
- Steps:
  1. `actions/checkout@v4` — `persist-credentials: false`
  2. `actions/dependency-review-action@v4` — `fail-on-severity: high`, `deny-licenses: GPL-2.0, AGPL-3.0`, `comment-summary-in-pr: on-failure`

---

## FILE 2 · `.github/workflows/ci.yml` — name: `CI`

Full build, test, package, and security gate for pushes. Produces the immutable JAR artifact consumed by the container workflow. Integration tests run here (not in PR validation). Also runs CodeQL SAST on push.

| Property | Value |
|---|---|
| **Trigger** | `push` to `main`, `develop`; `workflow_dispatch` |
| **Concurrency** | `group: ci-${{ github.ref }}`, `cancel-in-progress: true` |
| **Workflow permissions** | `contents: read` |

### Job: `build`

- `runs-on: ubuntu-latest`, `timeout-minutes: 20`
- Permissions: `contents: read`, `checks: write`
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  3. Run: `mvn --batch-mode --no-transfer-progress clean compile`
  4. Run: `mvn --batch-mode test` — unit tests
  5. Run: `mvn --batch-mode verify -P integration-test -DskipUnitTests=true` — `continue-on-error: true` (missing profile must not abort before JaCoCo runs)
  6. Run: `mvn jacoco:report` — `if: always()`
  7. Run: `mvn jacoco:check` — enforce ≥80 % line coverage
  8. `EnricoMi/publish-unit-test-result-action@v2` — publish JUnit XML to Checks UI, `if: always()`
  9. `actions/upload-artifact@v4` — name `test-reports`, path `target/surefire-reports/`, `retention-days: 7`, `if: always()`
  10. `actions/upload-artifact@v4` — name `coverage-report`, path `target/site/jacoco/`, `retention-days: 7`

### Job: `package`

- `needs: build`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`
- Permissions: `contents: read`
- **This is the single point where the JAR is built.** All downstream stages consume this artifact.
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  3. Run: `mvn --batch-mode package -DskipTests`
  4. Run (step id `jar`): normalize JAR filename for downstream consumption:
     ```bash
     JAR=$(ls target/*.jar | grep -v original | head -1)
     cp "$JAR" target/app.jar
     echo "path=target/app.jar" >> "$GITHUB_OUTPUT"
     ```
  5. `actions/upload-artifact@v4` — name `app-jar`, path `target/app.jar`, `retention-days: 3`

### Job: `security-gate`

- `needs: build`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`
- Permissions: `contents: read`, `security-events: write`
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  3. Run OWASP Dependency-Check via Maven plugin:
     ```bash
     mvn --batch-mode org.owasp:dependency-check-maven:check \
       -DfailBuildOnCVSS=7 \
       -Dformats=HTML,JSON,SARIF
     ```
  4. `github/codeql-action/upload-sarif@v3` — `sarif_file: target/dependency-check-report.sarif`, `category: owasp-dependency-check`, **`if: always()`**
  5. `actions/upload-artifact@v4` — name `dependency-check-report`, path `target/dependency-check-report.*`, `retention-days: 30`, **`if: always()`**

### Job: `sbom`

- `needs: build`, `runs-on: ubuntu-latest`, `timeout-minutes: 10`
- Permissions: `contents: write` — required by `maven-dependency-submission-action` to POST the dependency snapshot to the GitHub API. `anchore/sbom-action` uploads an artifact only — it does **not** need `security-events: write`.
- Steps:
  1. `actions/checkout@v4` — `persist-credentials: false`
  2. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  3. `advanced-security/maven-dependency-submission-action@v4` — submit dependency graph to GitHub API, powering **Dependabot** vulnerability alerts and version update PRs
  4. `anchore/sbom-action@v0` — `format: spdx-json`, artifact name `sbom-${{ github.sha }}`

### Job: `codeql`

- `needs: build`, `runs-on: ubuntu-latest`, `timeout-minutes: 30`
- Permissions: `contents: read`, `security-events: write`, `actions: read`
- Purpose: runs **GitHub Advanced Security CodeQL SAST** on every push to `main`/`develop` and on the weekly schedule. Results surface in the Security tab as GHAS code scanning alerts.
- Steps:
  1. `actions/checkout@v4` — **`fetch-depth: 0`** (CodeQL needs full history), `persist-credentials: false`
  2. `github/codeql-action/init@v3` — `languages: java-kotlin`, `queries: security-and-quality`
  3. `actions/setup-java@v4` — Java 21, temurin, `cache: maven`
  4. Run: `mvn --batch-mode compile -DskipTests` — manual autobuild for CodeQL
  5. `github/codeql-action/analyze@v3` — `category: /language:java`

---

## FILE 3 · `.github/workflows/container.yml` — name: `Container`

Builds a **thin runtime image** from the pre-built JAR artifact (build-once principle — no Maven, no JDK in the image). Scans with Trivy as a hard gate, generates a SLSA provenance attestation anchoring the image digest to the producing commit and workflow run, then pushes to ACR. Image is tagged **exclusively** with the commit SHA — no mutable `:latest` tag.

| Property | Value |
|---|---|
| **Trigger** | `workflow_run: workflows: ['CI']`, `types: [completed]`, `branches: [main, develop]`; `workflow_dispatch` |
| **Concurrency** | `group: container-${{ github.event.workflow_run.head_branch || github.ref }}`, `cancel-in-progress: true` |
| **Workflow permissions** | `contents: read` |
| **Top-level condition** | `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'` |

Define a workflow-level `env` block to resolve the commit SHA once:

```yaml
env:
  COMMIT_SHA: ${{ github.event.workflow_run.head_sha || github.sha }}
```

### Job: `build-image`

- `runs-on: ubuntu-latest`, `timeout-minutes: 15`
- Permissions: `contents: read`, `actions: read`
- **No Maven, no JDK** — this job only runs Docker build. The JAR is downloaded from the CI workflow.
- Steps:
  1. `actions/checkout@v4` — `fetch-depth: 1`, `persist-credentials: false`
  2. Download pre-built JAR from CI workflow:
     ```yaml
     - uses: actions/download-artifact@v4
       with:
         name: app-jar
         path: target/
         run-id: ${{ github.event.workflow_run.id }}
         github-token: ${{ secrets.GITHUB_TOKEN }}
     ```
  3. `docker/setup-buildx-action@v3`
  4. `docker/build-push-action@v6`:
     - `push: false`
     - `tags: app:${{ env.COMMIT_SHA }}`
     - `cache-from: type=gha`, `cache-to: type=gha,mode=max`
     - `outputs: type=docker,dest=/tmp/image.tar`
     - `build-args:` `APP_VERSION=${{ env.COMMIT_SHA }}`, `BUILD_DATE=<date -u +'%Y-%m-%dT%H:%M:%SZ'>`
  5. `actions/upload-artifact@v4` — name `container-image`, path `/tmp/image.tar`, `retention-days: 1`

### Job: `scan-image`

- `needs: build-image`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`
- Permissions: `contents: read`, `security-events: write`
- Steps:
  1. `actions/download-artifact@v4` — name `container-image`
  2. Run: `docker load --input /tmp/image.tar`
  3. `aquasecurity/trivy-action@0.29.0`:
     - `image-ref: app:${{ env.COMMIT_SHA }}`
     - `format: sarif`, `output: trivy-results.sarif`
     - `severity: CRITICAL,HIGH`, `exit-code: '1'`, `ignore-unfixed: true`
  4. `github/codeql-action/upload-sarif@v3` — `sarif_file: trivy-results.sarif`, `category: trivy-container`, **`if: always()`**
  5. `actions/upload-artifact@v4` — name `trivy-report`, path `trivy-results.sarif`, `retention-days: 30`, **`if: always()`**

### Job: `attest-and-push`

- `needs: scan-image`, `runs-on: ubuntu-latest`, `timeout-minutes: 15`
- Condition: branch must be `main` or `develop`, or event is `workflow_dispatch`
  ```yaml
  if: |
    github.event_name == 'workflow_dispatch' ||
    github.event.workflow_run.head_branch == 'main' ||
    github.event.workflow_run.head_branch == 'develop'
  ```
- Permissions: `contents: read`, `id-token: write`, `attestations: write`
- Steps:
  1. `actions/download-artifact@v4` — name `container-image`
  2. Run: `docker load --input /tmp/image.tar`
  3. `azure/login@v2` — OIDC: `client-id: ${{ secrets.AZURE_CLIENT_ID }}`, `tenant-id: ${{ secrets.AZURE_TENANT_ID }}`, `subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}`
  4. `azure/docker-login@v2` — `login-server: ${{ vars.ACR_LOGIN_SERVER }}` # TODO: set ACR_LOGIN_SERVER variable
  5. Tag and push (step id `push`) — **immutable SHA tag only, no `:latest`**:
     ```bash
     SHA="${{ env.COMMIT_SHA }}"
     IMAGE="${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}:${SHA}"  # TODO: set ACR_REPOSITORY variable
     docker tag "app:${SHA}" "${IMAGE}"
     docker push "${IMAGE}"
     DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "${IMAGE}" | cut -d@ -f2)
     echo "image=${IMAGE}" >> "$GITHUB_OUTPUT"
     echo "digest=${DIGEST}" >> "$GITHUB_OUTPUT"
     ```
  6. `actions/attest-build-provenance@v2` — SLSA provenance attestation anchoring image digest to the exact commit and workflow run:
     - `subject-name: ${{ vars.ACR_LOGIN_SERVER }}/${{ vars.ACR_REPOSITORY }}`
     - `subject-digest: ${{ steps.push.outputs.digest }}`
     - `push-to-registry: true`
  7. Export deploy metadata — upload a `deploy-metadata` artifact containing the commit SHA, image tag, and digest so downstream deploy workflow can read it reliably (avoids SHA drift across `workflow_run` hops):
     ```bash
     echo "${{ env.COMMIT_SHA }}" > /tmp/commit-sha
     echo "${{ steps.push.outputs.image }}" > /tmp/image-tag
     echo "${{ steps.push.outputs.digest }}" > /tmp/image-digest
     ```
     `actions/upload-artifact@v4` — name `deploy-metadata`, path `/tmp/commit-sha`, `/tmp/image-tag`, `/tmp/image-digest`, `retention-days: 7`

---

## FILE 4 · `.github/workflows/deploy.yml` — name: `Deploy`

Single deployment workflow with two sequential jobs: staging then production. Both `develop` and `main` branches deploy to staging. Only `main` promotes to production (gated by GitHub environment protection with required reviewers). Deployments use raw `kubectl` commands.

| Property | Value |
|---|---|
| **Trigger** | `workflow_run: workflows: ['Container']`, `types: [completed]`; `workflow_dispatch` |
| **Concurrency** | `group: deploy-${{ github.event.workflow_run.head_branch || github.ref }}`, `cancel-in-progress: false` (never cancel in-progress deploys) |
| **Workflow permissions** | `contents: read` |

### Job: `deploy-staging`

- `runs-on: ubuntu-latest`, `timeout-minutes: 15`
- Condition: `if: github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'`
- Environment: `staging`
- Permissions: `contents: read`, `id-token: write`
- Steps:
  1. `actions/checkout@v4` — `persist-credentials: false`
  2. Download deploy metadata (step id `meta`):
     ```yaml
     - uses: actions/download-artifact@v4
       with:
         name: deploy-metadata
         run-id: ${{ github.event.workflow_run.id }}
         github-token: ${{ secrets.GITHUB_TOKEN }}
     - name: Read deploy metadata
       id: meta
       run: |
         echo "sha=$(cat commit-sha)" >> "$GITHUB_OUTPUT"
         echo "image=$(cat image-tag)" >> "$GITHUB_OUTPUT"
         echo "digest=$(cat image-digest)" >> "$GITHUB_OUTPUT"
     ```
  3. `azure/login@v2` — OIDC (same secrets as container push)
  4. `azure/aks-set-context@v4` — `cluster-name: ${{ vars.AKS_CLUSTER_NAME_STAGING }}`, `resource-group: ${{ vars.AKS_RESOURCE_GROUP_STAGING }}` # TODO: set both vars
  5. Deploy with kubectl: # TODO: set APP_NAME variable
     ```bash
     kubectl set image deployment/${{ vars.APP_NAME }} \
       ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} \
       -n staging
     ```
  6. Run: `kubectl rollout status deployment/${{ vars.APP_NAME }} -n staging --timeout=5m`
  7. Health check: `curl --fail --retry 5 --retry-delay 10 ${{ vars.STAGING_HEALTH_URL }}/actuator/health` # TODO: set STAGING_HEALTH_URL variable
  8. Rollback (`if: failure()`): `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n staging`

### Job: `deploy-production`

- `needs: deploy-staging`, `runs-on: ubuntu-latest`, `timeout-minutes: 20`
- Condition: only promote to production from `main`:
  ```yaml
  if: |
    github.event.workflow_run.head_branch == 'main' ||
    (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main')
  ```
- Environment: `production` — **must have ≥2 required reviewers configured in GitHub repository settings**
- Permissions: `contents: read`, `id-token: write`
- Steps:
  1. `actions/checkout@v4` — `persist-credentials: false`
  2. Download deploy metadata (step id `meta`) — same pattern as staging: download `deploy-metadata` artifact via `run-id: ${{ github.event.workflow_run.id }}`, read `commit-sha`, `image-tag`, and `image-digest` files into step outputs
  3. `azure/login@v2` — OIDC (production federated credential)
  4. `azure/aks-set-context@v4` — `cluster-name: ${{ vars.AKS_CLUSTER_NAME_PROD }}`, `resource-group: ${{ vars.AKS_RESOURCE_GROUP_PROD }}` # TODO: set both vars
  5. Deploy with kubectl:
     ```bash
     kubectl set image deployment/${{ vars.APP_NAME }} \
       ${{ vars.APP_NAME }}=${{ steps.meta.outputs.image }} \
       -n production
     ```
  6. Run: `kubectl rollout status deployment/${{ vars.APP_NAME }} -n production --timeout=10m`
  7. Health check: `curl --fail --retry 10 --retry-delay 15 ${{ vars.PRODUCTION_HEALTH_URL }}/actuator/health` # TODO: set PRODUCTION_HEALTH_URL variable
  8. Rollback (`if: failure()`): `kubectl rollout undo deployment/${{ vars.APP_NAME }} -n production`

---

## FILE 5 · `Dockerfile`

Generate a **thin, single-stage runtime `Dockerfile`** (build-once principle — no multi-stage Maven build). The pre-built JAR from CI is placed in the Docker build context by the `build-image` job in `container.yml`.

**Single stage — `runtime`** (base: `eclipse-temurin:21-jre-alpine`):
- `ARG APP_VERSION=unknown`
- `ARG BUILD_DATE=unknown`
- OCI labels via `LABEL`: `org.opencontainers.image.title`, `.version=${APP_VERSION}`, `.revision=${APP_VERSION}`, `.created=${BUILD_DATE}`, `.source`
- Create non-root group + user `appuser` (UID 1001, GID 1001): `RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D -h /app appuser`
- `WORKDIR /app`
- `COPY target/app.jar /app/app.jar` — copies the pre-built JAR from the build context (downloaded by `container.yml`)
- `USER appuser`
- `EXPOSE 8080`
- `ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"`
- `HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD wget -qO- http://localhost:8080/actuator/health || exit 1` — use `wget` (available in Alpine by default; `curl` is not installed in Alpine JRE images)
- `ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]` — `exec` replaces the shell so Java becomes PID 1 and receives signals (SIGTERM) correctly

> **Why no multi-stage build?** The JAR is built exactly once in `ci.yml` (`package` job) and propagated as an artifact. Rebuilding inside Docker would violate the build-once principle and could produce a different binary.

---

## FILE 6 · `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: maven
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "06:00"
    labels: [dependencies, java]
    open-pull-requests-limit: 10
    groups:
      spring-boot:
        patterns: ["org.springframework.boot:*"]

  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "06:30"
    labels: [dependencies, github-actions]
```

---

## FILE 7 · `docs/cicd-prerequisites.md`

Document all required one-time setup steps:

### 1. GitHub Advanced Security (GHAS) — Enable in Repository Settings

All three GHAS pillars must be enabled. Go to Settings → Code Security and enable:

| GHAS Feature | Where it runs in this pipeline |
|---|---|
| **CodeQL code scanning** | `pr-validation.yml` (`codeql` job on PRs) + `ci.yml` (`codeql` job on push + weekly schedule) |
| **Secret scanning** (with push protection) | GitHub-native; `secrets-scan` (Gitleaks) in `pr-validation.yml` is a complementary in-workflow gate |
| **Dependency graph + Dependabot alerts** | `ci.yml` `sbom` job submits graph via `maven-dependency-submission-action`; `.github/dependabot.yml` drives update PRs |

### 2. GitHub Repository Environments

- Create environment **`staging`**: no required reviewers, deployment branches `develop` and `main`
- Create environment **`production`**: require ≥2 reviewers, restrict deployment branch to `main`

### 3. Required Secrets and Variables

- Required **Secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `GITLEAKS_LICENSE` (private/org repos only; omit for public repos)
- Required **Variables**: `ACR_LOGIN_SERVER`, `ACR_REPOSITORY`, `APP_NAME`, `AKS_CLUSTER_NAME_STAGING`, `AKS_RESOURCE_GROUP_STAGING`, `AKS_CLUSTER_NAME_PROD`, `AKS_RESOURCE_GROUP_PROD`, `STAGING_HEALTH_URL`, `PRODUCTION_HEALTH_URL`

### 4. Azure Workload Identity Federation

- Create Azure AD App Registration
- Add 3 federated credentials: subjects `repo:<org>/<repo>:ref:refs/heads/main`, `...develop`, `...environment:production`
- Assign **`AcrPush`** on ACR resource scope
- Assign **`Azure Kubernetes Service Cluster User Role`** + **`Azure Kubernetes Service RBAC Writer`** on each AKS cluster

### 5. Kubernetes Namespaces

- Ensure namespaces `staging` and `production` exist in the respective AKS clusters
- Ensure a `Deployment` resource named `$APP_NAME` exists in each namespace (or is created by an initial manual deploy/manifest)

### 6. Workflow Name Reference Table

List the exact `name:` values used in `workflow_run` triggers — a mismatch silently breaks the chain:

| Workflow file | `name:` (referenced in downstream `workflow_run`) |
|---|---|
| `ci.yml` | `CI` |
| `container.yml` | `Container` |

---

## Constraints

### DO

- Use `actions/setup-java@v4` with `cache: maven` in every job that runs `mvn` — do **not** add a separate `actions/cache` step
- Pin every `uses:` to a concrete major version tag (e.g., `@v4`, `@v3`, `@v6`, `@0.29.0`) — never `@main` or `@latest`
- Declare `permissions:` at **both** workflow level (`contents: read`) and each job level
- Set `persist-credentials: false` on every `actions/checkout@v4` step
- Add `timeout-minutes` to every job
- Add `# TODO: set <description>` inline comments on every `vars.*` and `secrets.*` reference
- Use `if: always()` on SARIF upload steps and security artifact upload steps so evidence is preserved even on scan failure
- Use `if: failure()` on all rollback steps — never `if: always()` on destructive kubectl commands
- Set `cancel-in-progress: false` on `deploy.yml` (never cancel in-progress deploys)
- Use Docker layer cache exclusively via `cache-from: type=gha` and `cache-to: type=gha,mode=max`
- Use `wget` (not `curl`) for Dockerfile `HEALTHCHECK` — Alpine JRE does not include `curl`
- Use `exec` in Dockerfile `ENTRYPOINT` so Java is PID 1 and receives container signals correctly
- Use `docker/build-push-action@v6` (not v5)
- Tag images **only** with commit SHA — never push a mutable `:latest` tag
- Include `image-digest` in the `deploy-metadata` artifact alongside `commit-sha` and `image-tag`
- Run CodeQL in **both** `pr-validation.yml` (PRs) and `ci.yml` (push + weekly schedule) for complete GHAS coverage
- Submit the Maven dependency graph via `advanced-security/maven-dependency-submission-action` in `ci.yml` to power Dependabot alerts
- Enable GHAS secret scanning with push protection in repository settings (documented in prerequisites)

### DO NOT

- Do NOT rebuild the JAR inside Docker — the Dockerfile must only COPY the pre-built JAR from the build context (build-once principle)
- Do NOT include Maven or JDK in the production container image — use JRE-only base
- Do NOT use long-lived Azure credentials or `AZURE_CLIENT_SECRET` — OIDC / Workload Identity Federation only
- Do NOT grant `security-events: write` except on the `codeql` job (in both `pr-validation.yml` and `ci.yml`), `security-gate` job, and `scan-image` job — the jobs that upload SARIF
- Do NOT grant `id-token: write` except on jobs that call `azure/login` or `actions/attest-build-provenance` (`attest-and-push`, `deploy-staging`, `deploy-production`)
- Do NOT grant `attestations: write` except on the `attest-and-push` job
- Do NOT use `fetch-depth: 0` except in the `codeql` and `secrets-scan` jobs
- Do NOT hardcode `APP_NAME`, registry URLs, cluster names, or resource groups — always reference `vars.*`
- Do NOT skip SARIF uploads on scan failure — always use `if: always()` on `upload-sarif` and security artifact steps
- Do NOT use `persist-credentials: true` on any checkout step
- Do NOT re-derive the commit SHA in deploy workflows — always read it from the `deploy-metadata` artifact
- Do NOT push mutable image tags (`:latest`, `:stable`, etc.) — SHA-only immutable tags prevent tag mutation attacks

---

## Maven Cache Pattern

Use `actions/setup-java@v4` with `cache: maven` in every job that invokes `mvn`. This caches `~/.m2/repository` keyed on `**/pom.xml` hash automatically. Do **not** add a redundant `actions/cache@v4` step alongside it.

---

## Done When

- [ ] Exactly 4 workflow files exist under `.github/workflows/`: `pr-validation.yml`, `ci.yml`, `container.yml`, `deploy.yml`
- [ ] Each workflow `name:` exactly matches the value referenced in downstream `workflow_run` triggers (`CI`, `Container`)
- [ ] `pr-validation.yml` contains 5 parallel jobs: `build-and-test`, `code-quality`, `secrets-scan`, `codeql`, `dependency-review`
- [ ] `ci.yml` triggers include `schedule: cron: '0 2 * * 1'` for weekly CodeQL runs
- [ ] `ci.yml` contains 5 jobs: `build` → `package` (produces `app-jar` artifact), `security-gate`, `sbom`, `codeql`
- [ ] `codeql` job appears in **both** `pr-validation.yml` and `ci.yml` for full GHAS code scanning coverage
- [ ] `sbom` job submits dependency graph via `advanced-security/maven-dependency-submission-action` (powers Dependabot)
- [ ] `container.yml` contains 3 chained jobs: `build-image` (downloads JAR, no Maven) → `scan-image` → `attest-and-push`
- [ ] `container.yml` `build-image` job downloads the pre-built JAR artifact — no `mvn` or `setup-java` step in this job
- [ ] `container.yml` `attest-and-push` job generates SLSA provenance via `actions/attest-build-provenance@v2` and uploads `deploy-metadata` with commit SHA, image tag, and image digest
- [ ] `deploy.yml` contains 2 sequential jobs: `deploy-staging` → `deploy-production` (main only, `environment: production`)
- [ ] All deployments use `kubectl set image` + `kubectl rollout status`; rollbacks use `kubectl rollout undo`
- [ ] Images are tagged exclusively with commit SHA — no `:latest` tag anywhere
- [ ] `security-events: write` appears only on `codeql` jobs (both workflows), `security-gate` job, and `scan-image` job
- [ ] `sbom` job uses `contents: write`, not `security-events: write`
- [ ] `id-token: write` appears only on `attest-and-push`, `deploy-staging`, and `deploy-production` jobs
- [ ] `attestations: write` appears only on `attest-and-push` job
- [ ] `container.yml` `scan-image` job uses `exit-code: '1'` and `if: always()` on its SARIF upload
- [ ] `container.yml` `attest-and-push` job only runs for `main`, `develop`, or `workflow_dispatch`
- [ ] Deploy jobs read the image tag from the `deploy-metadata` artifact, not from re-derived SHA
- [ ] `Dockerfile` is a single-stage thin runtime image (no Maven/JDK), non-root user UID 1001, `HEALTHCHECK` using `wget`, and `exec` in `ENTRYPOINT`
- [ ] `.github/dependabot.yml` covers both `maven` and `github-actions` ecosystems
- [ ] `docs/cicd-prerequisites.md` contains the GHAS coverage table, workflow name reference table, all secrets/variables, Kubernetes namespace requirements, and Azure RBAC assignments
- [ ] `problems` tool reports zero YAML syntax errors across all workflow files
