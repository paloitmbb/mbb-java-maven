---
title: CI/CD Workflow Specification - Container
version: 1.0
date_created: 2026-03-05
last_updated: 2026-03-10
owner: DevOps Team
tags: [process, cicd, github-actions, automation, docker, container, trivy, slsa, acr, azure, security]
---

# Introduction

This specification defines the Containerization workflow, which packages the application JAR into a secure Docker image, performs vulnerability scans, and pushes it to Azure Container Registry (ACR).

## 1. Purpose & Scope

The purpose of this specification is to provide a clear and unambiguous definition of the Container workflow. It covers the Docker build process, vulnerability scanning gates, SLSA level 2 provenance attestation, and metadata management for deployment.

## 2. Definitions

- **ACR**: Azure Container Registry.
- **OIDC**: OpenID Connect.
- **SLSA**: Supply-chain Levels for Software Artifacts.
- **Trivy**: A vulnerability scanner for containers.
- **Provenance**: Information about how an artifact was built.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: JAR artifact fetched from upstream CI run — no Maven rebuild.
- **REQ-002**: Docker image built and saved as tarball artifact for scanning.
- **REQ-003**: Docker layer cache shared across runs via GHA cache.
- **REQ-004**: Trivy exits non-zero on any CRITICAL or HIGH CVE.
- **REQ-005**: Unfixed CVEs ignored in Trivy scan for noise reduction.
- **REQ-006**: Trivy SARIF uploaded to Security tab even on failure.
- **REQ-007**: Azure login uses OIDC (`azure/login@v2`).
- **REQ-008**: Image tagged with immutable commit SHA only.
- **REQ-009**: SLSA Level 2 provenance attestation generated and pushed.
- **REQ-010**: `deploy-metadata` artifact contains `commit-sha`, `image-tag`, `image-digest`.
- **REQ-011**: `attest-and-push` restricted to `main` and `develop` branches.
- **REQ-012**: COMMIT_SHA resolved from `workflow_run.head_sha`.
- **SEC-001**: No credentials stored; Azure login via OIDC only.
- **SEC-002**: No CRITICAL or HIGH CVEs allowed in final image.
- **SEC-003**: Image tag is commit SHA — no mutable `:latest`.
- **CON-001**: Workflow Name must remain `Container` for downstream triggers.
- **CON-002**: Concurrency: `container-${{ github.event.workflow_run.head_branch }}`.

## 4. Interfaces & Data Contracts

### Workflow Trigger
```yaml
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]
  workflow_dispatch:
```

### Artifact Contract
The workflow produces an artifact named `deploy-metadata` containing:
- `commit-sha`: The SHA of the commit being deployed.
- `image-tag`: The unique immutable tag for the image.
- `image-digest`: The SHA256 digest of the final image.

## 5. Acceptance Criteria

- **AC-001**: Given a successful CI run, When the Container workflow finishes, Then a new image must exist in ACR with a SHA-based tag.
- **AC-002**: Given a Dockerfile with a HIGH CVE, When the Trivy scan runs, Then the `scan-image` job must fail.
- **AC-003**: Given a push to a non-protected branch, When the workflow runs, Then the `attest-and-push` job must be skipped.

## 6. Test Automation Strategy

- **Scanning**: Trivy (hard gate).
- **Verification**: Attestation verification (SLSA).
- **CI/CD Integration**: Automated via GitHub Actions `container.yml`.

## 7. Rationale & Context

By separating the build into stages and avoiding Maven rebuilds, we ensure that the image contains the exact artifact produced and tested in CI. The metadata artifact ensures that downstream deployments don't need to re-query ACR for the tag.

## 8. Dependencies & External Integrations

### External Systems
- **EXT-001**: Azure Container Registry (ACR) - Image storage.
- **EXT-002**: GitHub Security Tab - Trivy scan results.

### Infrastructure Dependencies
- **INF-001**: Ubuntu Latest - GitHub-hosted runner.

### Technology Platform Dependencies
- **PLT-001**: Docker - Containerization engine.
- **PLT-002**: Azure CLI - ACR authentication and push.

## 9. Examples & Edge Cases

### SLSA Attestation Step
```yaml
- name: Generate SLSA attestation
  uses: actions/attest-build-provenance@v2
  with:
    subject-name: ${{ vars.CONTAINER_REGISTRY }}/${{ vars.APP_NAME }}
    subject-digest: ${{ steps.push.outputs.digest }}
    push-to-registry: true
```

## 10. Validation Criteria

- **VAL-001**: Tagged image present in ACR following a successful `main` CI run.
- **VAL-002**: Trivy scan failure correctly stopping the pipeline.
- **VAL-003**: Verification that `deploy-metadata` artifact contains correct image-tag.

## 11. Related Specifications / Further Reading

- [spec-process-cicd-ci.md](spec-process-cicd-ci.md)
- [spec-process-cicd-deploy.md](spec-process-cicd-deploy.md)
- [.github/instructions/containerization-docker-best-practices.instructions.md](../.github/instructions/containerization-docker-best-practices.instructions.md)

# Upstream Trigger
trigger: workflow_run
workflows: ['CI']       # CRITICAL: must match ci.yml name exactly
types: [completed]
branches: [main, develop]

# Workflow-level Environment
COMMIT_SHA: ${{ github.event.workflow_run.head_sha || github.sha }}

# Consumed Artifact (from CI run)
app-jar:
  path: target/app.jar
  run-id: github.event.workflow_run.id    # Cross-workflow download
  github-token: GITHUB_TOKEN
```

### Outputs

```yaml
# Pushed to ACR
image:
  registry: vars.ACR_LOGIN_SERVER
  repository: vars.ACR_REPOSITORY
  tag: COMMIT_SHA                          # Immutable SHA tag
  attestation: SLSA Level 2 provenance

# Artifact consumed by deploy.yml
deploy-metadata:
  files:
    - commit-sha    # Raw COMMIT_SHA string
    - image-tag     # Full image reference e.g. registry.azurecr.io/app:sha-abc123
    - image-digest  # sha256:... digest
  retention: 7 days

# GitHub Security Tab
trivy-container: SARIF category

# In-workflow artifact (ephemeral)
container-image:
  path: /tmp/image.tar
  retention: 1 day
```

### Secrets & Variables

| Type | Name | Purpose | Scope |
|---|---|---|---|
| Secret | `AZURE_CLIENT_ID` | OIDC federated identity | `attest-and-push` job |
| Secret | `AZURE_TENANT_ID` | OIDC tenant | `attest-and-push` job |
| Secret | `AZURE_SUBSCRIPTION_ID` | Azure subscription scope | `attest-and-push` job |
| Variable | `ACR_LOGIN_SERVER` | ACR hostname (e.g. `myregistry.azurecr.io`) | `attest-and-push` job |
| Variable | `ACR_REPOSITORY` | Image name within ACR | `attest-and-push` job |
| Built-in | `GITHUB_TOKEN` | Cross-workflow artifact download | `build-image` job |

---

## Execution Constraints

### Runtime Constraints

- **Max single-job timeout**: 15 min (all jobs)
- **Concurrency group**: `container-${{ github.event.workflow_run.head_branch || github.ref }}`
- **Cancel policy**: `cancel-in-progress: true` (image builds can be cancelled; pushes protected by branch gate)
- **Top-level condition**: `github.event.workflow_run.conclusion == 'success' || github.event_name == 'workflow_dispatch'`

### Environmental Constraints

- **Runner**: `ubuntu-latest` (Docker available)
- **Azure OIDC**: Federated credential must be configured in Azure AD app registration
- **ACR Access**: Push permission to ACR repository
- **Network**: Docker Hub (base image pull), ACR push, SLSA attestation API

### Permissions (Minimum Required)

| Job | Required Permissions |
|---|---|
| `build-image` | `contents: read`, `actions: read` |
| `scan-image` | `contents: read`, `security-events: write` |
| `attest-and-push` | `contents: read`, `id-token: write`, `attestations: write` |

---

## Error Handling Strategy

| Error Type | Response | Recovery Action |
|---|---|---|
| CI workflow failed | Entire Container workflow skipped (top-level condition) | Fix CI, re-push |
| JAR artifact not found | `build-image` fails (artifact download exits non-zero) | Verify CI `app-jar` artifact exists |
| Docker build failure | `build-image` fails; no tarball uploaded | Fix Dockerfile |
| Trivy CRITICAL/HIGH CVE | `scan-image` fails; SARIF uploaded regardless | Upgrade base image or fix vulnerability |
| Azure OIDC auth failure | `attest-and-push` fails at login step | Verify federated credentials configured |
| ACR push failure | `attest-and-push` fails; no image published | Check ACR permissions and connectivity |
| SLSA attestation failure | `attest-and-push` fails; image already pushed | Re-run job; verify `attestations: write` |
| Wrong COMMIT_SHA (github.sha fallback) | Image tagged with default branch SHA in `workflow_run` context | Always set `workflow_run.head_sha` as primary |

---

## Quality Gates

| Gate | Criteria | Bypass Conditions |
|---|---|---|
| Upstream CI Success | CI workflow must conclude `success` | `workflow_dispatch` manual override |
| Trivy Scan | No CRITICAL or HIGH CVEs (fixed) | `ignore-unfixed: true` exempts unfixable |
| Branch Gate (push) | `attest-and-push` restricted to `main`/`develop` | `workflow_dispatch` override |
| SLSA Attestation | Provenance must be generated and pushed | None |

---

## Monitoring & Observability

### Key Metrics

- **Success Rate**: Target ≥ 98% after CI success
- **Execution Time**: Target ≤ 35 min total (build + scan + push)
- **Trivy SARIF Freshness**: Uploaded on every run regardless of pass/fail

### Alerting

| Condition | Severity | Notification Target |
|---|---|---|
| CRITICAL/HIGH CVE in image | High | Build failure + SARIF in Security tab |
| ACR push failure | High | Build failure notification |
| OIDC auth failure | Critical | Ops team (identity misconfiguration) |

---

## Integration Points

### External Systems

| System | Integration Type | Data Exchange | SLA Requirements |
|---|---|---|---|
| Azure Container Registry | Write | Docker image push | < 5 min push time |
| Azure Active Directory (OIDC) | Authentication | Short-lived JWT token | Pre-push |
| GitHub Security Tab | Write (SARIF) | Trivy vulnerability report | On run completion |
| SLSA Attestation API | Write | Provenance bundle | Post-push |

### Dependent Workflows

| Workflow | Relationship | Trigger Mechanism |
|---|---|---|
| `CI` (`ci.yml`) | Upstream trigger | `workflow_run: workflows: ['CI']` → this workflow |
| `Deploy` (`deploy.yml`) | Downstream consumer | `workflow_run: workflows: ['Container']` → deploy |

---

## Compliance & Governance

### Audit Requirements

- **Trivy Reports**: Retained 30 days as artifact
- **SLSA Attestation**: Persisted in ACR registry alongside image
- **Deploy Metadata**: Retained 7 days; links SHA → full image reference → digest
- **Approval Gates**: None (automated scan gate only)

### Security Controls

- **No Stored Credentials**: Azure access exclusively via OIDC federated identity
- **Immutable Tags**: SHA-only tags prevent image substitution attacks
- **Supply Chain Integrity**: SLSA Level 2 provenance attestation
- **Vulnerability Gate**: Trivy hard-fails on CRITICAL/HIGH (fixed) CVEs

---

## Edge Cases & Exceptions

| Scenario | Expected Behavior | Validation Method |
|---|---|---|
| `workflow_dispatch` on `feature` branch | `build-image` + `scan-image` run; `attest-and-push` skipped | Check branch gate condition |
| CI run artifact expired (> 3 days) | `build-image` fails — artifact not found | Verify CI artifact retention policy |
| Same commit pushed twice | Second Container run replaces first (concurrency cancel) | Check concurrency group behavior |
| New base image layer with CVE | `scan-image` fails; engineer must update Dockerfile | Weekly CI schedule catches drift |
| OIDC token expired mid-push | `attest-and-push` fails mid-run; image may be partially pushed | Re-run job; verify idempotency |

---

## Validation Criteria

- **VLD-001**: Workflow `name:` must be exactly `Container` (never rename)
- **VLD-002**: `workflows: ['CI']` in `on.workflow_run` must match `ci.yml` `name:` exactly
- **VLD-003**: `COMMIT_SHA` env must use `workflow_run.head_sha` (not `github.sha`)
- **VLD-004**: `build-image` uses `run-id: ${{ github.event.workflow_run.id }}` for artifact download
- **VLD-005**: Trivy has `exit-code: '1'` and `severity: CRITICAL,HIGH`
- **VLD-006**: SARIF upload has `if: always()`
- **VLD-007**: `attest-and-push` has branch condition for `main`/`develop` only
- **VLD-008**: `deploy-metadata` artifact contains all three files: `commit-sha`, `image-tag`, `image-digest`
- **VLD-009**: `cancel-in-progress: true` — stale image builds are cancelled
- **VLD-010**: Top-level `if:` checks `workflow_run.conclusion == 'success'`

---

## Change Management

### Update Process

1. **Specification Update**: Modify this document first
2. **Name Change Impact**: If `name: Container` must change, update `deploy.yml` `workflows: ['Container']` simultaneously
3. **Review & Approval**: PR review by DevOps Team
4. **Implementation**: Apply changes to `container.yml`
5. **Testing**: Push to `develop`, confirm image appears in ACR with correct SHA tag

### Version History

| Version | Date | Changes | Author |
|---|---|---|---|
| 1.0 | 2026-03-05 | Initial specification | DevOps Team |

---

## Related Specifications

- [spec-process-cicd-pr-validation.md](spec-process-cicd-pr-validation.md) — Pre-merge validation
- [spec-process-cicd-ci.md](spec-process-cicd-ci.md) — Upstream: build & test
- [spec-process-cicd-deploy.md](spec-process-cicd-deploy.md) — Downstream: AKS deployment
