# Hello Java Maven

A simple Java Maven application paired with a **production-grade CI/CD pipeline** on GitHub Actions — covering code quality, security scanning, container building, and automated deployment to Azure Kubernetes Service (AKS).

The application itself is deliberately minimal (a `HelloWorld` class) so the focus stays on the pipeline architecture: how a commit travels from a developer's branch all the way to a live Kubernetes workload with zero stored credentials and automatic rollback.

---

## Features

- **Java 11** application built with Maven, tested with JUnit 4
- **Code quality gates** — Checkstyle (Google style), SpotBugs, JaCoCo (≥80% line coverage)
- **Security scanning** — CodeQL SAST, OWASP Dependency-Check, Trivy container scan, Gitleaks secret scan
- **Build-once principle** — JAR compiled once in CI, the same artifact flows through every subsequent stage
- **Minimal Docker image** — `eclipse-temurin:21-jre-alpine`, non-root user, read-only JAR
- **SLSA provenance attestation** — cryptographic proof linking image to source commit
- **SBOM generation** — full SPDX software bill of materials for compliance
- **Staged deployment** — automatic staging deploy, manual approval gate for production
- **Auto-rollback** — `kubectl rollout undo` fires automatically on any deployment failure
- **Passwordless Azure auth** — OIDC workload identity federation, no stored service principal secrets

---

## Prerequisites

| Requirement | Details |
|---|---|
| Java 11+ | `maven.compiler.source/target = 11` |
| Maven 3.8+ | Used for build, test, and quality gates |
| Docker | For local image builds |
| Azure subscription | ACR + AKS clusters for the full pipeline |
| GitHub Advanced Security | For CodeQL and secret scanning |

See [docs/cicd-prerequisites.md](docs/cicd-prerequisites.md) for the complete one-time Azure and GitHub setup guide.

---

## Getting Started

### Clone and build locally

```bash
git clone https://github.com/your-org/mbb-java-maven.git
cd mbb-java-maven
mvn clean verify
```

This runs compilation, all unit tests, JaCoCo coverage, Checkstyle, and SpotBugs in one command.

### Run the application

```bash
mvn package -DskipTests
java -jar target/hello-java-*.jar
```

### Run tests only

```bash
mvn test
```

### View coverage report

After `mvn verify`, open `target/site/jacoco/index.html` in a browser.

---

## Project Structure

```
.
├── Dockerfile                        # Single-stage runtime image (no build step)
├── pom.xml                           # Maven build configuration
├── src/
│   ├── main/java/com/example/
│   │   └── HelloWorld.java           # Application entry point
│   └── test/java/com/example/
│       └── HelloWorldTest.java       # JUnit 4 unit tests
├── docs/
│   ├── cicd-pipeline-guide.md        # Plain-English pipeline walkthrough
│   └── cicd-prerequisites.md         # One-time Azure + GitHub setup
└── .github/
    ├── workflows/
    │   ├── pr-validation.yml         # PR quality gates
    │   ├── ci.yml                    # Build, test, OWASP, SBOM
    │   ├── container.yml             # Docker build, Trivy scan, ACR push
    │   └── deploy.yml                # AKS staging → production
    ├── dependabot.yml                # Automated dependency updates
    └── copilot-instructions.md       # GitHub Copilot configuration
```

---

## CI/CD Pipeline

The pipeline is a four-workflow chain. Each stage triggers the next on success.

```
Pull Request
    │
    ▼
PR Validation  ──  tests, coverage, Checkstyle, SpotBugs,
                   CodeQL, Gitleaks, dependency CVE review
    │
  merge
    │
    ▼
CI  ──────────  full build, OWASP scan, SBOM, CodeQL
                produces: app-jar artifact
    │
  success
    │
    ▼
Container  ────  Docker build (no Maven), Trivy scan,
                 ACR push (sha-xxxxxx tag), SLSA attestation
                 produces: deploy-metadata artifact
    │
  success
    │
    ▼
Deploy  ────────  staging (automatic) → production (≥2 approvers)
                  health check + auto-rollback on failure
```

### Workflow overview

| Workflow | Trigger | Key jobs |
|---|---|---|
| `pr-validation.yml` | Pull request to `main`/`develop` | cache, build-and-test, code-quality, codeql, secrets-scan, dependency-review |
| `ci.yml` | Push to `main`/`develop` | build-and-package, security-gate (OWASP), sbom, codeql |
| `container.yml` | `CI` workflow completes | build-image, scan-image (Trivy), attest-and-push |
| `deploy.yml` | `Container` workflow completes | deploy-staging, deploy-production |

> [!IMPORTANT]
> The `workflow_run` chain depends on exact workflow names. `ci.yml` must have `name: CI` and `container.yml` must have `name: Container`. Renaming either silently breaks the pipeline.

For a detailed walkthrough of every job and step, see [docs/cicd-pipeline-guide.md](docs/cicd-pipeline-guide.md).

---

## Quality Gates

Every gate below is a hard build failure — a workflow does not proceed if any gate fails.

| Gate | Threshold | Checked in |
|---|---|---|
| JaCoCo line coverage | ≥ 80% | PR Validation, CI |
| Checkstyle | Zero violations (Google style) | PR Validation |
| SpotBugs | Zero violations | PR Validation |
| OWASP Dependency-Check | No CVE with CVSS ≥ 7 | CI |
| Gitleaks secret scan | No secrets in git history | PR Validation |
| Dependency review | No HIGH/CRITICAL CVEs on new deps | PR Validation |
| Trivy container scan | No CRITICAL or HIGH CVEs | Container |

---

## Docker Image

The image uses a build-once approach: Maven produces the JAR in CI; Docker only copies it in.

```dockerfile
FROM eclipse-temurin:21-jre-alpine
# Non-root user (UID 1001)
RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D -h /app appuser
WORKDIR /app
COPY target/app.jar /app/app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-jar", "app.jar"]
```

Images are always tagged with the triggering commit SHA (`sha-xxxxxxx`). The `:latest` tag is never used.

---

## Azure Setup Summary

The pipeline uses **OIDC workload identity federation** — no service principal passwords are stored in GitHub Secrets.

```
Azure App Registration
    ├── Federated credential → repo:ORG/REPO:ref:refs/heads/main
    ├── Federated credential → repo:ORG/REPO:ref:refs/heads/develop
    └── Federated credential → repo:ORG/REPO:environment:production

RBAC assignments
    ├── AcrPush          → Azure Container Registry
    ├── AKS Cluster User → AKS staging cluster
    ├── AKS RBAC Writer  → AKS staging cluster
    ├── AKS Cluster User → AKS production cluster
    └── AKS RBAC Writer  → AKS production cluster
```

### Required secrets

| Secret | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | App Registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `GITLEAKS_LICENSE` | Gitleaks (private repos only) |

### Required variables

| Variable | Example |
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

> [!NOTE]
> The full step-by-step setup guide, including Kubernetes namespace configuration and environment protection rules, is in [docs/cicd-prerequisites.md](docs/cicd-prerequisites.md).

---

## Development Workflow

```bash
# Full validation (mirrors CI)
mvn clean verify

# Fast feedback during development
mvn test

# Build JAR without tests
mvn package -DskipTests

# Pre-download dependencies (useful in devcontainer)
mvn dependency:resolve
```

### Branch strategy

| Branch | Deploys to |
|---|---|
| `develop` | Staging (automatic) |
| `main` | Staging (automatic) → Production (≥2 approvers) |
| Feature branches | No deployment — PR validation only |

---

## Technology Stack

| Component | Version |
|---|---|
| Java | 11 (source/target) |
| Maven Compiler Plugin | 3.8.1 |
| Maven Surefire Plugin | 2.22.2 |
| JUnit | 4.13.2 |
| JaCoCo | 0.8.11 |
| Checkstyle | 10.13.0 (Google checks) |
| SpotBugs Maven Plugin | 4.8.3.0 |
| Base image | `eclipse-temurin:21-jre-alpine` |

---

## Resources

- [CI/CD Pipeline Guide](docs/cicd-pipeline-guide.md) — plain-English explanation of every workflow
- [CI/CD Prerequisites](docs/cicd-prerequisites.md) — one-time Azure and GitHub setup
- [eclipse-temurin Docker images](https://hub.docker.com/_/eclipse-temurin)
- [GitHub Actions workflow_run trigger](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_run)
- [Azure Workload Identity Federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- [SLSA provenance for containers](https://slsa.dev/spec/v1.0/provenance)
