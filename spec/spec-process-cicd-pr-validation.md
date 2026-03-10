---
title: CI/CD Workflow Specification - PR Validation
version: 1.0
date_created: 2026-03-05
last_updated: 2026-03-10
owner: DevOps Team
tags: [process, cicd, github-actions, automation, pull-request, validation, java, maven, security]
---

# Introduction

This specification defines the manual validation process for all Pull Requests (PRs) targeting the main development branches. It ensures code quality, security, and coverage standards are met before merging.

## 1. Purpose & Scope

The purpose of this specification is to provide a clear and unambiguous definition of the PR Validation workflow. It covers Maven builds, fast-feedback unit testing, parallel security gates, and static analysis for Java 11 pull requests.

## 2. Definitions

- **PR**: Pull Request.
- **JaCoCo**: Java Code Coverage.
- **SAST**: Static Application Security Testing.
- **Checkstyle**: Development tool to help programmers write Java code that adheres to a coding standard.
- **SpotBugs**: A program which uses static analysis to look for bugs in Java code.

## 3. Requirements, Constraints & Guidelines

- **REQ-001**: Maven dependency cache pre-warmed before parallel test/quality jobs.
- **REQ-002**: Unit tests compile and pass on every PR.
- **REQ-003**: Line coverage ≥ 80% enforced as hard gate via JaCoCo.
- **REQ-004**: Test results published to GitHub Checks UI.
- **REQ-005**: Checkstyle: zero violations.
- **REQ-006**: SpotBugs: zero violations.
- **REQ-007**: CodeQL SAST runs on non-fork PRs only.
- **REQ-008**: Full git history available for secrets scanning (`fetch-depth: 0`).
- **REQ-009**: Dependency review comments on PR on failure.
- **REQ-010**: GPL-2.0 and AGPL-3.0 licenses blocked.
- **SEC-001**: No credentials stored in repo (`persist-credentials: false`).
- **SEC-002**: Secrets scan on full commit history.
- **SEC-003**: CodeQL results visible in Security tab.
- **SEC-004**: High-severity CVEs in new dependencies block merge.
- **CON-001**: Concurrency: One run per PR number with `cancel-in-progress: true`.
- **GUD-001**: Expected value must be first in assertions: `assertEquals(expected, actual)`.

## 4. Interfaces & Data Contracts

### Workflow Trigger
```yaml
on:
  pull_request:
    branches: [main, develop]
    types: [opened, synchronize, reopened]
```

### Published Reports
- **Surefire Reports**: XML files from `target/surefire-reports/`.
- **JaCoCo Report**: HTML coverage report uploaded as artifact.
- **Quality Reports**: Checkstyle and SpotBugs XML results.

## 5. Acceptance Criteria

- **AC-001**: Given a PR with passing tests and 85% coverage, When the validation runs, Then all checks must turn green.
- **AC-002**: Given a PR with a Checkstyle violation, When the validation runs, Then the `code-quality` job must fail.
- **AC-003**: Given a PR that adds a GPLv2 dependency, When the validation runs, Then the `dependency-review` job must fail.

## 6. Test Automation Strategy

- **Test Levels**: Unit testing only.
- **Frameworks**: JUnit 4.13.2 (specified in `pom.xml`).
- **CI/CD Integration**: Automated via GitHub Actions `pr-validation.yml`.

## 7. Rationale & Context

PR validation is the first line of defense. By running checks in parallel after a cache setup job, we maximize developer feedback speed while ensuring strict enforcement of project standards.

## 8. Dependencies & External Integrations

### External Systems
- **EXT-001**: GitHub PR Checks - Status reporting.
- **EXT-002**: GitHub Security Tab - Vulnerability visualization.

### Infrastructure Dependencies
- **INF-001**: Ubuntu Latest - GitHub-hosted runner.

### Technology Platform Dependencies
- **PLT-001**: Java 11 (Source/Target).
- **PLT-002**: Maven 3.8.x.

## 9. Examples & Edge Cases

### Gitleaks Configuration Step
```yaml
- name: Secrets Scan
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    GITLEAKS_LICENSE: ${{ secrets.GITLEAKS_LICENSE }}
```

## 10. Validation Criteria

- **VAL-001**: Mandatory green status for all jobs before PR merge.
- **VAL-002**: Correct failure of JaCoCo check when coverage drops.
- **VAL-003**: CodeQL successfully scanning internal PRs.

## 11. Related Specifications / Further Reading

- [spec-process-cicd-ci.md](spec-process-cicd-ci.md)
- [.github/instructions/testing.instructions.md](../.github/instructions/testing.instructions.md)
- [.github/instructions/git.instructions.md](../.github/instructions/git.instructions.md)


---

## Input/Output Contracts

### Inputs

```yaml
# GitHub Events
trigger: pull_request
branches: [main, develop]

# Pull Request Context
gh.event.pull_request.number: int     # Used in concurrency group
gh.event.pull_request.head.repo.full_name: string  # Fork detection for CodeQL
```

### Outputs

```yaml
# Artifacts (uploaded per PR run)
pr-test-reports: directory     # Surefire XML reports — retention: 5 days
pr-coverage-report: directory  # JaCoCo HTML report — retention: 5 days
quality-reports: files         # checkstyle-result.xml + spotbugsXml.xml — retention: 7 days

# GitHub Checks
test-results-check: GitHub Checks entry with pass/fail counts
codeql-alerts: GitHub Security tab (advisory)
```

### Secrets & Variables

| Type | Name | Purpose | Scope |
|---|---|---|---|
| Secret | `GITLEAKS_LICENSE` | Authenticate Gitleaks for private repo scans | `secrets-scan` job |
| Built-in | `GITHUB_TOKEN` | Publish test results to Checks API | `build-and-test` job |

---

## Execution Constraints

### Runtime Constraints

- **Max single-job timeout**: 30 min (`codeql`)
- **Concurrency**: Scoped to `pr-${{ github.event.pull_request.number }}` — one active run per PR
- **Cancel policy**: `cancel-in-progress: true` — older runs cancelled on new push

### Environmental Constraints

- **Runner**: `ubuntu-latest` for all jobs
- **Java**: JDK 21 (Temurin distribution) for compilation and analysis
- **Compilation target**: Java 11 (`maven.compiler.source/target`)
- **Fork restriction**: `codeql` skipped on fork PRs (no `security-events: write` access)

### Permissions (Minimum Required)

| Job | Required Permissions |
|---|---|
| `setup-cache` | `contents: read` |
| `build-and-test` | `contents: read`, `checks: write` |
| `code-quality` | `contents: read` |
| `codeql` | `contents: read`, `security-events: write`, `actions: read` |
| `secrets-scan` | `contents: read` |
| `dependency-review` | `contents: read`, `pull-requests: write` |

---

## Error Handling Strategy

| Error Type | Response | Recovery Action |
|---|---|---|
| Test failure | Build fails; Surefire XML still uploaded (`if: always()`) | Fix failing tests before merge |
| Coverage below 80% | `jacoco:check` exits non-zero; fails `build-and-test` | Increase test coverage |
| Checkstyle violation | `checkstyle:check` exits non-zero; fails `code-quality` | Fix formatting/style violations |
| SpotBugs violation | `spotbugs:check` exits non-zero; fails `code-quality` | Fix bug patterns |
| CodeQL alert | Advisory only; does not block merge | Review in Security tab |
| Secret detected | `gitleaks-action` exits non-zero; fails `secrets-scan` | Rotate secret, clean history |
| GPL/AGPL license | Dependency review fails + PR comment added | Replace with compatible dependency |
| High CVE in new dep | Dependency review fails | Upgrade or replace dependency |

---

## Quality Gates

| Gate | Criteria | Bypass Conditions |
|---|---|---|
| Unit Tests | All tests pass | None |
| Line Coverage | ≥ 80% line coverage (JaCoCo) | None — hard build gate |
| Checkstyle | Zero violations | None |
| SpotBugs | Zero violations | None |
| Secrets Detection | No secrets in commit history | None |
| Dependency Licenses | No GPL-2.0 or AGPL-3.0 | None |
| Dependency CVEs | No high/critical CVEs in new deps | None |
| CodeQL SAST | Advisory (non-blocking) | Forks (skipped entirely) |

---

## Monitoring & Observability

### Key Metrics

- **Success Rate**: Target ≥ 95% of PRs pass on first run
- **Execution Time**: Target ≤ 20 min wall-clock
- **Cache Hit Rate**: Monitor via Actions cache UI

### Alerting

| Condition | Severity | Notification Target |
|---|---|---|
| Secret detected in PR | Critical | PR author + repo admins (Gitleaks) |
| GPL/AGPL license introduced | High | PR comment (auto-posted) |
| High CVE in new dependency | High | PR comment (auto-posted) |

---

## Integration Points

### External Systems

| System | Integration Type | Data Exchange | SLA Requirements |
|---|---|---|---|
| GitHub Checks API | Write | Test result XML → Checks UI | Synchronous during run |
| GitHub Security Tab | Write (SARIF) | CodeQL alerts | Within run completion |
| Gitleaks License Server | Auth | License key validation | Pre-run |

### Dependent Workflows

| Workflow | Relationship | Trigger Mechanism |
|---|---|---|
| None | Standalone — no downstream consumers | N/A |

---

## Compliance & Governance

### Audit Requirements

- **Execution Logs**: GitHub Actions log retention (per org policy)
- **Approval Gates**: None (automated gate only)
- **Artifact Retention**: Test reports 5 days; quality reports 7 days

### Security Controls

- **Access Control**: `persist-credentials: false` on all checkouts
- **Fork Safety**: CodeQL skipped on forks; no secret exposure
- **License Compliance**: GPL-2.0 and AGPL-3.0 automatically blocked

---

## Edge Cases & Exceptions

| Scenario | Expected Behavior | Validation Method |
|---|---|---|
| Fork PR submitted | `codeql` job skipped; all other gates run | Check job skip condition in run history |
| PR with no Java changes | All jobs still run (no path filters) | Observe run on docs-only PRs |
| Maven cache miss | `setup-cache` succeeds but is slower; subsequent jobs unaffected | Job runtime metrics |
| Gitleaks without license in private repo | `secrets-scan` fails | Verify `GITLEAKS_LICENSE` secret set |
| New dependency with no license | Dependency review fails (treated as unknown) | PR comment indicating unknown license |

---

## Validation Criteria

- **VLD-001**: `setup-cache` must complete before `build-and-test` and `code-quality` start
- **VLD-002**: `build-and-test` must fail when line coverage < 80%
- **VLD-003**: `code-quality` must fail on any Checkstyle or SpotBugs violation
- **VLD-004**: `secrets-scan` must use `fetch-depth: 0` (full history)
- **VLD-005**: `codeql` must not run on fork PRs
- **VLD-006**: Artifacts must be uploaded even when tests fail (`if: always()`)
- **VLD-007**: `dependency-review` must post to PR on failure
- **VLD-008**: `cancel-in-progress: true` — only one run active per PR number

---

## Change Management

### Update Process

1. **Specification Update**: Modify this document first
2. **Review & Approval**: PR review by DevOps Team
3. **Implementation**: Apply changes to `pr-validation.yml`
4. **Testing**: Open a test PR, verify all 6 jobs behave as specified
5. **Deployment**: Merge to `main`; effective immediately on next PR

### Version History

| Version | Date | Changes | Author |
|---|---|---|---|
| 1.0 | 2026-03-05 | Initial specification | DevOps Team |

---

## Related Specifications

- [spec-process-cicd-ci.md](spec-process-cicd-ci.md) — Downstream CI workflow (runs after merge)
- [spec-process-cicd-container.md](spec-process-cicd-container.md) — Container build workflow
- [spec-process-cicd-deploy.md](spec-process-cicd-deploy.md) — Deployment workflow
