
---

### File 6: `.github/plans/plan6-dependabot.md`

```markdown
# Plan 6: Dependabot Configuration

## Plan Metadata
- **Plan Number**: 6
- **Filename**: plan6-dependabot.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md

## Objective

Create `.github/dependabot.yml` covering both `maven` and `github-actions` ecosystems with weekly schedules. Groups Spring Boot dependencies together.

## Scope

**In Scope**:
- `.github/dependabot.yml`
- Maven ecosystem with Spring Boot grouping
- GitHub Actions ecosystem

**Out of Scope**:
- Docker base image updates (could be added later)

## pom.xml Prerequisites

| Requirement | Purpose |
|---|---|
| Valid `pom.xml` at repository root | Dependabot needs it to detect Maven dependencies |

## Task Breakdown

### Task 001: Create dependabot.yml
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 5 minutes
- **Description**: Create the Dependabot config with two ecosystem entries.
- **Actions**:
  1. Create file `.github/dependabot.yml`
  2. `version: 2`
  3. Maven ecosystem:
     - `package-ecosystem: maven`
     - `directory: "/"`
     - `schedule: interval: weekly, day: monday, time: "06:00"`
     - `labels: [dependencies, java]`
     - `open-pull-requests-limit: 10`
     - `groups: spring-boot: patterns: ["org.springframework.boot:*"]`
  4. GitHub Actions ecosystem:
     - `package-ecosystem: github-actions`
     - `directory: "/"`
     - `schedule: interval: weekly, day: monday, time: "06:30"`
     - `labels: [dependencies, github-actions]`
- **Outputs**: File `.github/dependabot.yml`
- **Validation**: YAML lint; both ecosystems present
- **Rollback**: `rm .github/dependabot.yml`

---

### Task 002: Validate
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 2 minutes
- **Description**: Validate YAML syntax and content.
- **Actions**:
  1. YAML lint
  2. Verify `version: 2`
  3. Verify both `maven` and `github-actions` ecosystems
  4. Verify Spring Boot grouping pattern
- **Validation**: All checks pass
- **Rollback**: N/A

## Files to Create/Modify

| File Path | Type | Purpose | Related Tasks |
|-----------|------|---------|---------------|
| `.github/dependabot.yml` | Create | Automated dependency update PRs | task-001, task-002 |

## Verification Commands

```bash
yamllint .github/dependabot.yml
grep "maven" .github/dependabot.yml && echo "PASS" || echo "FAIL"
grep "github-actions" .github/dependabot.yml && echo "PASS" || echo "FAIL"
