---
title: CI/CD Workflow Specification - CI
version: 1.0
date_created: 2026-03-05
last_updated: 2026-03-10
owner: DevOps Team
tags: [process, cicd, github-actions, automation, build, test, security, sbom, sast, java, maven]
---

# Introduction

This specification defines the Continuous Integration (CI) process for the Java Maven application. It ensures that every code change pushed to the main development branches is automatically built, tested, and scanned for security vulnerabilities before producing a deployable artifact.

## 1. Purpose & Scope

The purpose of this specification is to provide a clear and unambiguous definition of the CI workflow. It covers the build lifecycle, testing requirements, security scanning gates, and artifact production. This document is intended for DevOps engineers, developers, and security auditors.

## 2. Definitions

- **CI**: Continuous Integration.
- **SBOM**: Software Bill of Materials.
- **SAST**: Static Application Security Testing (CodeQL).
- **OWASP**: Open Web Application Security Project.
- **CVSS**: Common Vulnerability Scoring System.
- **Artifact**: A deployable version of the application (e.g., a JAR file).
- **SARIF**: Static Analysis Results Interchange Format.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Single Maven lifecycle: `clean verify -P integration-test` builds, tests, and packages.
- **REQ-002**: Integration tests run as soft gate (non-blocking).
- **REQ-003**: Line coverage ≥ 80% enforced as hard gate via JaCoCo.
- **REQ-004**: Test results published to GitHub Checks.
- **REQ-005**: JAR normalized to `app.jar` before artifact upload.
- **REQ-006**: OWASP Dependency-Check fails on CVSS ≥ 7.
- **REQ-007**: OWASP SARIF uploaded to GitHub Security tab.
- **REQ-008**: SPDX SBOM generated and archived per commit SHA.
- **REQ-009**: Dependency graph submitted to GitHub.
- **REQ-010**: CodeQL uses full git history (`fetch-depth: 0`).
- **REQ-011**: Weekly scheduled run for CodeQL drift detection.
- **SEC-001**: No credentials persist after checkout (`persist-credentials: false`).
- **SEC-002**: CVSS ≥ 7 dependency CVEs block build.
- **CON-001**: Workflow Name must remain `CI` for downstream `workflow_run` triggers.
- **CON-002**: Concurrency: `ci-${{ github.ref }}` — one active run per branch.
- **GUD-001**: Separate body/footers from subject in commit messages.

## 4. Interfaces & Data Contracts

### Workflow Trigger
```yaml
on:
  push:
    branches: [main, develop]
  workflow_dispatch:
  schedule:
    - cron: '0 21 * * 0'
```

### Artifact Contract
The workflow produces an artifact named `app-jar` containing:
- `app.jar`: The executable Spring Boot application.
- `version-metadata/`: Directory containing version information.

## 5. Acceptance Criteria

- **AC-001**: Given a push to `main`, When the CI workflow runs, Then it must produce a valid `app-jar` artifact if all gates pass.
- **AC-002**: Given a code change with < 80% coverage, When the CI workflow runs, Then the build must fail.
- **AC-003**: Given a dependency with CVSS 8.0, When the security scan runs, Then the `security-gate` job must fail.

## 6. Test Automation Strategy

- **Test Levels**: Unit, Integration (soft gate).
- **Frameworks**: JUnit 4 (specified in `pom.xml`).
- **CI/CD Integration**: Automated via GitHub Actions `ci.yml`.
- **Coverage Requirements**: Line coverage ≥ 80% (JaCoCo).

## 7. Rationale & Context

The build-once principle is central to this architecture. The CI workflow builds the JAR once, which is then used by the Container workflow to build the image, ensuring that the exact same code that was tested is what gets deployed.

## 8. Dependencies & External Integrations

### External Systems
- **EXT-001**: GitHub Actions - Execution platform.
- **EXT-002**: GitHub Security Tab - SARIF result consumption.

### Infrastructure Dependencies
- **INF-001**: Ubuntu Latest - GitHub-hosted runner.

### Technology Platform Dependencies
- **PLT-001**: Java 11 (Source/Target) - Application runtime.
- **PLT-002**: Maven 3.8.x - Build system.

## 9. Examples & Edge Cases

### POM Configuration for JaCoCo
```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>${jacoco.version}</version>
    <executions>
        <execution>
            <id>check</id>
            <goals><goal>check</goal></goals>
            <configuration>
                <rules>
                    <rule>
                        <element>BUNDLE</element>
                        <limits>
                            <limit>
                                <counter>LINE</counter>
                                <value>COVEREDRATIO</value>
                                <minimum>0.80</minimum>
                            </limit>
                        </limits>
                    </rule>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

## 10. Validation Criteria

- **VAL-001**: Successful run on `main` branch producing `app-jar`.
- **VAL-002**: Failure of `security-gate` job when vulnerable dependencies are added.
- **VAL-003**: Presence of SBOM in workflow artifacts.

## 11. Related Specifications / Further Reading

- [spec-process-cicd-container.md](spec-process-cicd-container.md)
- [spec-process-cicd-deploy.md](spec-process-cicd-deploy.md)
- [.github/instructions/java.instructions.md](../.github/instructions/java.instructions.md)


```yaml
# GitHub Events
triggers:
  push:
    branches: [main, develop]
  workflow_dispatch: {}
  schedule:
    - cron: '0 21 * * 0'   # Weekly Sunday 21:00 UTC

# Source code: src/main/java/**/*.java
# Build config: pom.xml
```

### Outputs

```yaml
# Critical Artifact (consumed by container.yml)
app-jar:
  path: target/app.jar
  retention: 3 days
  on-missing: error   # Hard failure if JAR not found

# Supporting Artifacts
test-reports:
  path: target/surefire-reports/
  retention: 7 days
coverage-report:
  path: target/site/jacoco/
  retention: 7 days
dependency-check-report:
  path: target/dependency-check-report.*
  retention: 30 days
sbom-{sha}:
  format: SPDX JSON
  retention: per anchore/sbom-action default

# GitHub Security Tab
owasp-dependency-check: SARIF category
codeql: SARIF category  (/language:java)

# GitHub Dependency Graph
dependency-submission: submitted via maven-dependency-submission-action
```

### Secrets & Variables

| Type | Name | Purpose | Scope |
|---|---|---|---|
| Built-in | `GITHUB_TOKEN` | Checks API, SARIF upload, artifact download | All jobs |

---

## Execution Constraints

### Runtime Constraints

- **Max single-job timeout**: 30 min (`codeql`)
- **Concurrency group**: `ci-${{ github.ref }}`
- **Cancel policy**: `cancel-in-progress: false` — running CI must complete
- **Workflow-level permissions**: `contents: read` (overridden per job as needed)

### Environmental Constraints

- **Runner**: `ubuntu-latest`
- **Java**: JDK 21 (Temurin) — devcontainer and CI runtime
- **Compilation target**: Java 11 (enforced in `pom.xml`)
- **Build tool**: Maven (with cache)

### Permissions (Minimum Required)

| Job | Required Permissions |
|---|---|
| `build-and-package` | `contents: read`, `checks: write` |
| `security-gate` | `contents: read`, `security-events: write` |
| `sbom` | `contents: write` (dependency graph submission) |
| `codeql` | `contents: read`, `security-events: write`, `actions: read` |

---

## Error Handling Strategy

| Error Type | Response | Recovery Action |
|---|---|---|
| Test failure | `build-and-package` fails; reports still uploaded | Fix failing tests |
| Coverage < 80% | `jacoco:check` exits non-zero; build fails | Increase test coverage |
| Integration test failure | `continue-on-error: true` — soft gate, logged only | Review integration failures separately |
| CVSS ≥ 7 CVE detected | `security-gate` fails; SARIF uploaded regardless | Upgrade or exclude vulnerable dependency |
| OWASP report upload failure | `if: always()` ensures SARIF always uploaded | Check Security tab for partial results |
| JAR normalization failure | `if-no-files-found: error` on artifact upload | Investigate Maven packaging step |
| CodeQL failure | Build continues (advisory); SARIF uploaded | Review Security tab |
| SBOM generation failure | `sbom` job fails; does not block `security-gate` or `codeql` | Investigate SBOM action |

---

## Quality Gates

| Gate | Criteria | Bypass Conditions |
|---|---|---|
| Unit Tests | All pass | None |
| Integration Tests | Soft gate — logged but non-blocking | `continue-on-error: true` |
| Line Coverage | ≥ 80% (JaCoCo hard gate) | None |
| OWASP CVEs | CVSS < 7 for all dependencies | None |
| CodeQL SAST | Advisory (uploaded to Security tab) | None — but non-blocking |
| JAR Availability | `app.jar` must exist in `target/` | None — build fails if absent |

---

## Monitoring & Observability

### Key Metrics

- **Success Rate**: Target ≥ 98% of pushes to `main`/`develop`
- **Execution Time**: Target ≤ 45 min total wall-clock
- **OWASP Report Age**: Weekly scheduled run revalidates dependency landscape

### Alerting

| Condition | Severity | Notification Target |
|---|---|---|
| CVSS ≥ 7 CVE found | High | Build failure + SARIF in Security tab |
| Coverage drops below 80% | High | Build failure notification |
| Weekly scheduled scan failure | Medium | Repository owner notification |

---

## Integration Points

### External Systems

| System | Integration Type | Data Exchange | SLA Requirements |
|---|---|---|---|
| GitHub Checks API | Write | Test result XML → commit status | Synchronous |
| GitHub Security Tab | Write (SARIF) | OWASP + CodeQL alerts | On run completion |
| GitHub Dependency Graph | Write | Maven BOM snapshot | Post-build |
| OWASP NVD Feed | Read | CVE database fetch | Network access required |

### Dependent Workflows

| Workflow | Relationship | Trigger Mechanism |
|---|---|---|
| `Container` (`container.yml`) | Downstream consumer | `workflow_run: workflows: ['CI']` |

---

## Compliance & Governance

### Audit Requirements

- **OWASP Reports**: Retained 30 days as artifact
- **SBOM**: Archived per commit SHA for supply chain traceability
- **Dependency Graph**: Submitted to GitHub for Dependabot alerting
- **Approval Gates**: None on CI (gated by PR Validation before merge)

### Security Controls

- **Credential Isolation**: `persist-credentials: false` everywhere
- **Least Privilege**: `contents: write` scoped only to `sbom` job
- **Attestation Foundation**: `app-jar` artifact feeds into SLSA provenance in `container.yml`

---

## Edge Cases & Exceptions

| Scenario | Expected Behavior | Validation Method |
|---|---|---|
| Push with no Java changes | All jobs still run (no path filters) | Verify on docs-only push |
| OWASP NVD feed unreachable | `security-gate` may fail or produce incomplete report | Retry; check NVD status |
| JAR has unexpected name pattern | `ls target/*.jar | grep -v original` must match exactly one file | Verify build produces single JAR |
| Weekly schedule on inactive repo | Runs normally — detects new CVEs even without code changes | Check Actions schedule tab |
| `workflow_dispatch` on branch | Runs full pipeline; `security-gate` and `sbom` run in parallel | Manual trigger test |

---

## Validation Criteria

- **VLD-001**: Workflow `name:` must be exactly `CI` (not `CI Pipeline`, `Main CI`, etc.)
- **VLD-002**: `app-jar` artifact must use `if-no-files-found: error`
- **VLD-003**: `security-gate` and `sbom` and `codeql` must all have `needs: [build-and-package]`
- **VLD-004**: OWASP SARIF uploaded with `if: always()`
- **VLD-005**: `cancel-in-progress: false` — CI runs must not be interrupted
- **VLD-006**: CodeQL checkout uses `fetch-depth: 0`
- **VLD-007**: Integration test step has `continue-on-error: true`
- **VLD-008**: JAR normalized to `app.jar` before upload

---

## Change Management

### Update Process

1. **Specification Update**: Modify this document first
2. **Name Change Impact**: If `name: CI` must change, update `container.yml` `workflows: ['CI']` simultaneously
3. **Review & Approval**: PR review by DevOps Team
4. **Implementation**: Apply changes; verify artifact names unchanged
5. **Testing**: Push to `develop`, confirm all 4 jobs pass and `app-jar` artifact created

### Version History

| Version | Date | Changes | Author |
|---|---|---|---|
| 1.0 | 2026-03-05 | Initial specification | DevOps Team |

---

## Related Specifications

- [spec-process-cicd-pr-validation.md](spec-process-cicd-pr-validation.md) — Pre-merge validation
- [spec-process-cicd-container.md](spec-process-cicd-container.md) — Downstream: Docker build & scan
- [spec-process-cicd-deploy.md](spec-process-cicd-deploy.md) — Final: AKS deployment
