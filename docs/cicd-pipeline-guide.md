# CI/CD Pipeline — Plain English Guide

> A quick-read explanation of what every workflow does, why it exists,
> and what you need to set up before running it.
> Written to be read on a phone.

---

## The Big Picture

There are **5 GitHub Actions workflows** that run in a chain:

```
Pull Request  →  CI (push to main/develop)
                 ↓
              Container (build & scan Docker image)
                 ↓
              Deploy (staging → production)
```

Plus two supporting files:
- **Dockerfile** — the recipe for building the container image
- **Dependabot** — automatically opens PRs when dependencies have updates or CVEs

---

## Plan 1 — PR Validation

**File:** `.github/workflows/pr-validation.yml`
**Runs when:** Someone opens or updates a pull request targeting `main` or `develop`
**Goal:** Fast feedback before code merges. No JAR is built, no container is touched.

### What it does

**1. setup-cache** *(runs first)*
Pre-downloads all Maven dependencies into a shared cache so the 3 jobs below don't each waste time downloading the internet. Think of it as filling a shared toolbox before the work starts.

**2. build-and-test** *(needs the cache)*
- Compiles the code
- Runs all unit tests
- Measures code coverage with JaCoCo
- **Fails the PR** if coverage drops below 80%
- Publishes a test summary directly on the PR page
- Uploads the test XML reports as a downloadable artifact (kept 5 days)

**3. code-quality** *(needs the cache, runs in parallel with build-and-test)*
- Runs Checkstyle — checks code formatting rules
- Runs SpotBugs — finds likely bugs before they reach production
- Uploads the quality reports as an artifact (kept 7 days)

**4. codeql** *(needs the cache, runs in parallel)*
- GitHub's own static security analysis (SAST)
- Scans for security vulnerabilities in the Java code
- Results appear in the repository's Security tab
- Skipped automatically for PRs coming from forks (they can't access secrets)

**5. secrets-scan** *(runs immediately, no cache needed)*
- Uses Gitleaks to scan the entire git history for accidentally committed API keys, passwords, or tokens
- Needs `GITLEAKS_LICENSE` secret for private repos

**6. dependency-review** *(runs immediately, no cache needed)*
- Checks every new dependency being added by the PR
- Fails if any new dependency has a HIGH or CRITICAL CVE
- Fails if any new dependency uses a forbidden license (GPL-2.0, AGPL-3.0)
- Posts a comment on the PR explaining what it found

### What you need first
- `GITLEAKS_LICENSE` secret set in repo settings (private repos only)
- pom.xml must have: JaCoCo plugin with 80% gate, Surefire plugin, Checkstyle plugin, SpotBugs plugin

---

## Plan 2 — CI (Continuous Integration)

**File:** `.github/workflows/ci.yml`
**Runs when:** Code is pushed to `main` or `develop`, or manually triggered, or weekly on **Sunday 21:00 UTC** (Monday 05:00 UTC+8)
**Goal:** Build the production JAR, enforce all quality gates, run security scans. The JAR produced here is the one that ends up in production — it is never rebuilt.

### What it does

**1. build-and-package** *(runs first)*
- Full build: compile → unit tests → integration tests → package
- Enforces 80% code coverage
- Normalises the JAR filename to `app.jar`
- Uploads three artifacts:
  - `test-reports` — surefire XML files (7 days)
  - `coverage-report` — JaCoCo HTML (7 days)
  - **`app-jar`** — the production JAR (3 days) → consumed by the container workflow

**2. security-gate** *(runs after build, in parallel with sbom and codeql)*
- OWASP Dependency-Check scans all Maven dependencies for known CVEs
- **Fails the build** if any CVE has a CVSS score of 7 or above (High/Critical)
- Uploads findings to the Security tab as SARIF
- Saves full reports (HTML, JSON, SARIF) for 30 days — useful for compliance audits

**3. sbom** *(runs in parallel)*
- Submits the full dependency graph to GitHub, which powers Dependabot alerts
- Generates an SPDX-format Software Bill of Materials (SBOM) — a legal/compliance document listing every library in the app

**4. codeql** *(runs in parallel)*
- Same SAST scanning as PR validation, but for every push
- Also runs on the weekly Monday schedule (required by some compliance frameworks)

### Key rule
`name: CI` — this exact name is referenced by the container workflow. Changing it breaks the pipeline.

---

## Plan 3 — Container

**File:** `.github/workflows/container.yml`
**Runs when:** The CI workflow completes successfully on `main` or `develop`
**Goal:** Build the Docker image from the pre-built JAR (never recompile), scan it for CVEs, then push it to Azure Container Registry (ACR) with a tamper-proof provenance attestation.

### What it does

**1. build-image**
- Downloads the `app-jar` artifact from the CI run that just finished
- Builds the Docker image using BuildKit with layer caching
- Does NOT install Java or run Maven — the JAR is already built
- Saves the image as a tarball and uploads it (kept 1 day) for the scan job

**2. scan-image** *(needs build-image)*
- Downloads the image tarball and loads it into Docker
- Runs Trivy to scan every layer for CVEs
- **Fails the build** if any CRITICAL or HIGH CVE is found (exit-code 1)
- Uploads Trivy findings to the Security tab
- Saves the full Trivy report for 30 days

**3. attest-and-push** *(needs scan-image, only runs on main/develop)*
- Logs into Azure using OIDC (no stored passwords)
- Tags the image with the exact commit SHA — no `:latest` tag ever
- Pushes to ACR
- Generates SLSA provenance attestation — a cryptographic proof of what source code produced this image
- Uploads `deploy-metadata` artifact (commit SHA, image tag, image digest) for the deploy workflow

### Key rules
- `name: Container` — referenced by the deploy workflow
- Image tags are always `sha-xxxxxxx` format — immutable, traceable to a specific commit
- `id-token: write` permission only on this last job (OIDC requirement)

### What you need first
- Azure App Registration with OIDC federated credentials
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` secrets
- `ACR_LOGIN_SERVER` and `ACR_REPOSITORY` variables
- `AcrPush` RBAC role assigned on the ACR

---

## Plan 4 — Deploy

**File:** `.github/workflows/deploy.yml`
**Runs when:** The Container workflow completes successfully
**Goal:** Roll out the new image to Kubernetes — staging first, then production with a human approval gate.

### What it does

**1. deploy-staging** *(runs for both main and develop)*
- Downloads the `deploy-metadata` artifact (reads image tag from artifact, never re-derives it)
- Logs into Azure via OIDC
- Connects to the staging AKS cluster
- Runs `kubectl set image` to update the deployment
- Waits up to 5 minutes for the rollout to finish
- Hits the `/actuator/health` endpoint to confirm the app is healthy
- **If anything fails:** automatically runs `kubectl rollout undo` to restore the previous version

**2. deploy-production** *(runs only from `main`, needs staging to pass first)*
- Uses the `production` GitHub Environment — this requires **at least 2 human approvers** before the job starts
- Same steps as staging but against the production AKS cluster
- Rollout timeout is 10 minutes (versus 5 for staging)
- **If anything fails:** automatically rolls back

### Key rules
- `cancel-in-progress: false` — a running deploy is **never** cancelled, even if another push comes in
- Rollback uses `if: failure()` — it only runs when something actually breaks
- Production is main-branch only — you can never deploy a feature branch to prod

### What you need first
- GitHub Environments `staging` and `production` created in repo settings
- `production` environment configured with ≥2 required reviewers
- AKS clusters and namespaces (`staging`, `production`) already exist
- Variables: `APP_NAME`, `AKS_CLUSTER_NAME_STAGING`, `AKS_RESOURCE_GROUP_STAGING`, `AKS_CLUSTER_NAME_PROD`, `AKS_RESOURCE_GROUP_PROD`, `STAGING_HEALTH_URL`, `PRODUCTION_HEALTH_URL`
- Azure RBAC: `Azure Kubernetes Service Cluster User Role` + `Azure Kubernetes Service RBAC Writer` on each cluster

---

## Plan 5 — Dockerfile

**File:** `Dockerfile` at repository root

This is a single-stage, minimal runtime image. It does **not** build the code — the JAR is copied in by the container workflow.

### Key design decisions

| Decision | Reason |
|---|---|
| `eclipse-temurin:21-jre-alpine` base | JRE only (no JDK), Alpine is tiny |
| Non-root user `appuser` (UID 1001) | Security hardening — no root in containers |
| `COPY target/app.jar` | Pre-built JAR from CI, never compile in Docker |
| `HEALTHCHECK` uses `wget` | Alpine JRE doesn't ship `curl` |
| `exec java $JAVA_OPTS -jar app.jar` | `exec` makes Java PID 1 — clean signal handling |
| `-XX:+UseContainerSupport` | JVM reads cgroup memory limits, not host RAM |
| No `:latest` tag | Image tags are always the commit SHA |

---

## Plan 6 — Dependabot

**File:** `.github/dependabot.yml`

Dependabot automatically opens pull requests when your dependencies are outdated or have security advisories.

### What it watches

| Ecosystem | Schedule | Day | Time |
|---|---|---|---|
| Maven (Java deps in pom.xml) | Weekly | Monday | 06:00 UTC |
| GitHub Actions (action versions) | Weekly | Monday | 06:30 UTC |

Spring Boot dependencies are grouped together so you get one consolidated PR instead of 20 separate ones.

---

## Plan 7 — Prerequisites Checklist

**File:** `docs/cicd-prerequisites.md`

A one-time setup doc. Everything on this list must be done **before** the workflows work end-to-end.

### GitHub Settings

- [ ] Enable GitHub Advanced Security (GHAS) on the repository
- [ ] Enable secret scanning with push protection
- [ ] Create environment `staging` (no approval required)
- [ ] Create environment `production` with **≥2 required reviewers**, main branch only

### Secrets to add in repo settings

| Secret | Used by |
|---|---|
| `AZURE_CLIENT_ID` | container.yml, deploy.yml |
| `AZURE_TENANT_ID` | container.yml, deploy.yml |
| `AZURE_SUBSCRIPTION_ID` | container.yml, deploy.yml |
| `GITLEAKS_LICENSE` | pr-validation.yml (private repos) |

### Variables to add in repo settings

| Variable | Example value |
|---|---|
| `ACR_LOGIN_SERVER` | `myregistry.azurecr.io` |
| `ACR_REPOSITORY` | `myapp` |
| `APP_NAME` | `myapp` |
| `AKS_CLUSTER_NAME_STAGING` | `aks-staging` |
| `AKS_RESOURCE_GROUP_STAGING` | `rg-staging` |
| `AKS_CLUSTER_NAME_PROD` | `aks-prod` |
| `AKS_RESOURCE_GROUP_PROD` | `rg-prod` |
| `STAGING_HEALTH_URL` | `https://staging.myapp.example.com` |
| `PRODUCTION_HEALTH_URL` | `https://myapp.example.com` |

### Azure setup

1. Create an App Registration in Azure AD
2. Add 3 federated credentials (for OIDC — no stored passwords):
   - Subject: `repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/main`
   - Subject: `repo:YOUR_ORG/YOUR_REPO:ref:refs/heads/develop`
   - Subject: `repo:YOUR_ORG/YOUR_REPO:environment:production`
3. Assign roles to the App Registration:
   - `AcrPush` on the ACR resource
   - `Azure Kubernetes Service Cluster User Role` on each AKS cluster
   - `Azure Kubernetes Service RBAC Writer` on each AKS cluster

### Critical: Workflow name reference

The `workflow_run` trigger chain only works if the `name:` values match **exactly**:

| File | Must be named |
|---|---|
| `ci.yml` | `CI` |
| `container.yml` | `Container` |

A single character difference silently breaks the entire chain — the downstream workflow just never triggers.

---

## How everything connects

```
[Developer pushes code]
        |
        v
[PR Validation] — runs on every pull request
  - Cache warm-up
  - Unit tests + coverage
  - Code style + bugs
  - Secret scan
  - Dependency CVE review
  - CodeQL SAST
        |
   PR merged
        |
        v
[CI] — runs on push to main/develop
  - Full build + integration tests
  - OWASP dependency scan (CVSS ≥7 = fail)
  - SBOM generation
  - CodeQL SAST
  - Produces: app-jar artifact
        |
   on success
        |
        v
[Container] — triggered automatically
  - Build Docker image (no Maven)
  - Trivy CVE scan (CRITICAL/HIGH = fail)
  - Push to ACR with SHA tag
  - SLSA provenance attestation
  - Produces: deploy-metadata artifact
        |
   on success
        |
        v
[Deploy]
  - Staging deployment (automatic)
  - Health check
  - Auto-rollback on failure
        |
  human approval (≥2 reviewers)
        |
        v
  - Production deployment
  - Health check
  - Auto-rollback on failure
```

---

## Related Specifications

Detailed AI-optimized specifications for each workflow are in the `spec/` directory:

| Workflow | Specification File |
|---|---|
| PR Validation | [spec/spec-process-cicd-pr-validation.md](../spec/spec-process-cicd-pr-validation.md) |
| CI | [spec/spec-process-cicd-ci.md](../spec/spec-process-cicd-ci.md) |
| Container | [spec/spec-process-cicd-container.md](../spec/spec-process-cicd-container.md) |
| Deploy | [spec/spec-process-cicd-deploy.md](../spec/spec-process-cicd-deploy.md) |

Each spec covers: execution flow diagram, jobs & dependencies, requirements matrix, input/output contracts, error handling, quality gates, edge cases, and validation criteria.

---

*Last updated: 2026-03-05*
