````instructions
# GitHub Copilot Instructions

## Priority Guidelines

When generating code for this repository, always follow these principles in order:

1. **Version Compatibility**: Strictly use only Java 11 language features — no records, sealed classes, pattern matching for `instanceof`, text blocks, or any Java 14+ features
2. **Context Files Priority**: Always consult `.github/instructions/` files first for domain-specific guidance (Java, testing, security, CI/CD, Docker, Kubernetes)
3. **Codebase Patterns First**: Match the naming, structure, and style of existing files before consulting external best practices
4. **Architectural Consistency**: Maintain the strict `controller → service → repository → domain` layered boundary — controllers never import repositories directly
5. **Quality Gates**: All code must maintain JaCoCo line coverage ≥ 80%, pass Checkstyle and SpotBugs with zero violations
6. **CI/CD Stability**: Never rename workflow files or their `name:` fields — downstream `workflow_run` triggers depend on exact names
7. **Documentation Sync**: When changing behavior, commands, or APIs, immediately update relevant documentation per `.github/instructions/update-docs-on-code-change.instructions.md`

---

## Technology Stack & Exact Versions

### Language & Build System

| Component | Version | Source | Constraints |
|---|---|---|---|
| Java (source/target) | **11** | `pom.xml` `maven.compiler.source/target` | No Java 12+ features (var OK, but no records, sealed, switch expressions, text blocks, pattern matching) |
| Maven Compiler Plugin | **3.8.1** | `pom.xml` | Standard compilation only |
| Maven Surefire Plugin | **2.22.2** | `pom.xml` | JUnit 4 compatible, XML reports required |
| Project Encoding | **UTF-8** | `pom.xml` `project.build.sourceEncoding` | Always use UTF-8 |

### Testing Framework

| Component | Version | Source | Constraints |
|---|---|---|---|
| JUnit | **4.13.2** | `pom.xml` | **NOT JUnit 5** — always import `org.junit.Test`, `org.junit.Assert.*` |
| JaCoCo | (configured) | Plugin in `pom.xml` | Line coverage ≥ 80% enforced as build gate |

### Package Structure

| Property | Value |
|---|---|
| Group ID | `com.example` |
| Artifact ID | `hello-java` |
| Packaging | `jar` → renamed to `app.jar` in CI pipeline |
| Base Package | `com.example` (all Java code under this) |

### Development Environment

| Component | Version | Source |
|---|---|
| DevContainer Base Image | `mcr.microsoft.com/devcontainers/java:1-21-bookworm` | `.devcontainer/devcontainer.json` |
| DevContainer User | `vscode` | `.devcontainer/devcontainer.json` |
| IDE Formatter | Red Hat Java formatter | `.devcontainer/devcontainer.json` |
| Format on Save | **Enabled** | `.devcontainer/devcontainer.json` |

**Note**: DevContainer uses Java 21 runtime for development tooling, but compilation targets Java 11 — never use Java 21 language features.

---

## Context Files in `.github/instructions/`

Always consult these files for detailed, domain-specific guidance. They override general best practices.

| File | Applies To | Purpose |
|---|---|---|
| `java.instructions.md` | `**/*.java` | Java 11 patterns, naming conventions, common bug patterns, code smells, static analysis integration |
| `springboot.instructions.md` | `**/*.java`, `**/*.kt` | Spring Boot application structure, dependency injection, REST controllers, configuration |
| `testing.instructions.md` | `**/*Test.java`, `**/*Tests.java`, `**/*IT.java` | JUnit 4 testing standards, assertion patterns, coverage requirements |
| `security.instructions.md` | All files | Security best practices, OWASP guidelines, secrets management, input validation |
| `containerization-docker-best-practices.instructions.md` | `**/Dockerfile`, `**/Dockerfile.*`, `**/*.dockerfile`, Docker Compose files | Multi-stage builds, layer optimization, security scanning, runtime best practices |
| `kubernetes-manifests.instructions.md` | `k8s/**/*.yaml`, `manifests/**/*.yaml`, `charts/**/templates/**/*.yaml` | Labeling conventions, security contexts, pod security, resource management, probes |
| `kubernetes-deployment-best-practices.instructions.md` | All Kubernetes resources | Pods, Deployments, Services, Ingress, ConfigMaps, Secrets, health checks, scaling, RBAC |
| `github-actions-ci-cd-best-practices.instructions.md` | `.github/workflows/*.yml`, `.github/workflows/*.yaml` | Workflow structure, jobs, steps, secrets management, caching, matrix strategies, deployment |
| `git.instructions.md` | `**` (all files) | Commit message conventions, branch hygiene, PR best practices |
| `code-review.instructions.md` | All files | Code review checklist, quality standards |
| `performance.instructions.md` | All files | Performance optimization guidelines |
| `documentation.instructions.md` | All files | Documentation standards and formats |
| `update-docs-on-code-change.instructions.md` | `**/*.{md,js,ts,java,...}` | When and how to update documentation when code changes |

---

## Architectural Patterns

### Layered Architecture (Strict Boundaries)

This project follows a strict **layered architecture** with clear dependency rules:

```
┌─────────────────────────────────────────────┐
│  controller/                                │  ← REST endpoints, @ControllerAdvice
│    ↓ (calls)                                │
│  service/                                   │  ← Business logic interfaces
│    service/impl/                            │  ← Concrete implementations
│    ↓ (calls)                                │
│  repository/                                │  ← Data access (Spring Data, JPA)
│    ↓ (uses)                                 │
│  domain/                                    │  ← Core business types
│    entity/     (JPA @Entity)                │
│    dto/        (Request/Response objects)   │
│    mapper/     (Entity ↔ DTO conversion)    │
│    enums/      (Domain enumerations)        │
└─────────────────────────────────────────────┘

Cross-cutting concerns (used by all layers):
- config/      (Spring @Configuration beans)
- exception/   (Custom exception hierarchy)
- security/    (Auth filters, JWT, UserDetails)
- util/        (Stateless helpers only)
```

**Hard Rules**:
- Controllers **never** import repositories — only services
- Entities **never** cross layer boundaries — always convert to DTOs at controller/service boundary
- Service interfaces in `service/`, implementations in `service/impl/`
- Each layer only depends on the layer directly below it

### Package Structure (Full Blueprint)

Consult `Project_Folders_Structure_Blueprint.md` for the complete directory visualization and file placement patterns.

```
src/main/java/com/example/
  config/          # @Configuration, @Bean definitions
  controller/      # @RestController, @RequestMapping
    advice/        # @ControllerAdvice, exception handlers
  service/         # Business logic interfaces
    impl/          # Concrete @Service implementations
  repository/      # Spring Data repositories
  domain/
    entity/        # @Entity JPA entities
    dto/           # Data Transfer Objects
    mapper/        # Entity ↔ DTO mappers (MapStruct)
    enums/         # Domain enumerations
  exception/       # Custom exception hierarchy
  security/        # Auth filters, JWT, UserDetails
  util/            # Stateless helpers

src/test/java/com/example/  # Mirrors main/ exactly
  controller/
  service/
  repository/
  integration/     # Full-stack integration tests
```

---

## Java Code Patterns (Observed in Codebase)

### Null Safety (from `HelloWorld.java`)

Always check `null` **before** calling `.isEmpty()` or other methods:

```java
// CORRECT — observed pattern
if (name == null || name.isEmpty()) {
    return "Hello, World!";
}

// INCORRECT — will throw NullPointerException
if (name.isEmpty() || name == null) {  // ❌
    return "Hello, World!";
}
```

**General null-handling rules** (from `java.instructions.md`):
- Avoid returning or accepting `null` where possible
- Use `Optional<T>` for possibly-absent return values
- Use `Objects.requireNonNull(param, "message")` to fail fast
- Use `Objects.equals(a, b)` for safe equality checks

### Javadoc Style (Observed Pattern)

**Class-level Javadoc** — single-line description, no `@author` tag:

```java
/**
 * A simple Hello World application
 */
public class HelloWorld {
```

**Method-level Javadoc** — `@param` for every parameter, `@return` if non-void:

```java
/**
 * Returns a greeting message
 * @param name the name to greet
 * @return greeting message
 */
public String getGreeting(String name) {
    // implementation
}
```

### Naming Conventions (from `java.instructions.md`)

| Element | Convention | Example |
|---|---|---|
| Classes/Interfaces | `UpperCamelCase` | `UserService`, `UserRepository` |
| Methods | `lowerCamelCase` (verbs) | `getUserById`, `saveUser` |
| Variables | `lowerCamelCase` (nouns) | `userName`, `orderTotal` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_RETRIES`, `DEFAULT_TIMEOUT` |
| Packages | `lowercase` | `com.example.service.impl` |
| Test Methods | `test<Method><Scenario>` | `testGetUserByIdWhenUserExists` |

### Resource Management

Always close resources using try-with-resources:

```java
// CORRECT
try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
    return reader.readLine();
}
```

---

## Testing Patterns (from `HelloWorldTest.java` and `testing.instructions.md`)

### Framework & Structure

**Framework**: JUnit 4.13.2 (**not JUnit 5**)

```java
import org.junit.Test;
import static org.junit.Assert.*;

public class HelloWorldTest {

    @Test
    public void testGetGreetingWithName() {
        HelloWorld hello = new HelloWorld();
        String result = hello.getGreeting("Java");
        assertEquals("Hello, Java!", result);
    }
}
```

**Key imports** (always use these):
- `org.junit.Test` — **not** `org.junit.jupiter.api.Test`
- `org.junit.Assert.*` — **not** `org.junit.jupiter.api.Assertions.*`

### Test Naming Convention

**Pattern**: `test<MethodName><Scenario>` in camelCase

Examples from codebase:
- `testGetGreetingWithNull`
- `testGetGreetingWithEmptyString`
- `testGetGreetingWithSpecialCharacters`

### Assertion Patterns

**Always put expected value first**:

```java
// CORRECT — matches codebase pattern
assertEquals("Hello, World!", result);

// INCORRECT — backwards
assertEquals(result, "Hello, World!");  // ❌
```

### Test Coverage Requirements

**Minimum coverage for every method**:
1. **Happy path** — expected input, expected outcome
2. **Null input** — if method accepts reference types
3. **Empty/boundary input** — empty strings, collections, zero
4. **Edge cases** — special characters, whitespace, long inputs

**JaCoCo requirement**: Line coverage ≥ 80% — enforced as a hard build gate.

---

## Developer Workflows

### Maven Commands

```bash
mvn clean verify          # Full build + quality gates (use before committing)
mvn test                  # Run tests only (fast feedback)
mvn package -DskipTests   # Build JAR (not recommended for production)
mvn dependency:resolve    # Download dependencies (DevContainer post-create)
```

**Pre-commit checklist**:
1. `mvn clean verify` passes
2. JaCoCo coverage ≥ 80%
3. Checkstyle: zero violations
4. SpotBugs: zero violations

---

## CI/CD Pipeline (5-Workflow Chain)

### Pipeline Flow

```
Pull Request
     ↓
pr-validation.yml (cache, test, lint, SAST, secrets)
     ↓ (merge to main/develop)
ci.yml (build JAR, OWASP, SBOM)
     ↓ (workflow_run)
container.yml (Docker build, Trivy scan, push ACR)
     ↓ (workflow_run)
deploy.yml (staging → production with approval)
```

### Critical Workflow Constraints

**❌ NEVER change these** (breaks workflow_run triggers):

| File | Field | Current Value | Why |
|---|---|---|---|
| `ci.yml` | `name:` | `"CI"` | Referenced by `container.yml` trigger |
| `container.yml` | `name:` | `"Container"` | Referenced by `deploy.yml` trigger |

**Other critical rules**:
- Image tags: `sha-xxxxxxx` format — **never `:latest`**
- Deploy workflow: `cancel-in-progress: false` (CRITICAL — interrupting kubectl rollout corrupts pods)
- Container workflow: `cancel-in-progress: true` (safe — only image build)
- PR Validation workflow: `cancel-in-progress: true` (efficient — supercede on new push)
- CI workflow: `cancel-in-progress: false` (protected branches, artifact must complete)
- Rollback: `if: failure()` uses `kubectl rollout undo` (NOT `if: always()`)
- Production: **main branch only** (`head_branch == 'main'` gate)
- Artifact download: always use `run-id: ${{ github.event.workflow_run.id }}` — never default
- Commit SHA: use `workflow_run.head_sha` — never `github.sha` (wrong in workflow_run context)

### Secrets & Variables

**GitHub Secrets**:
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (OIDC)
- `GITLEAKS_LICENSE` (private repos)

**GitHub Variables**:
- `ACR_LOGIN_SERVER`, `ACR_REPOSITORY` (container push)
- `AKS_CLUSTER_NAME_STAGING/PROD`, `AKS_RESOURCE_GROUP_STAGING/PROD`
- `APP_NAME`, `STAGING_HEALTH_URL`, `PRODUCTION_HEALTH_URL`

---

## Agents & Implementation Plans

### Available Agents (`.github/agents/`)

Use these agents for specific implementation tasks. Always invoke the right agent before writing code manually.

| Agent | File | Purpose |
|---|---|---|
| `@architect` | `architect.agent.md` | Architecture decisions, ADRs, layer boundary enforcement |
| `@azure-devops-specialist` | `azure-devops-specialist.agent.md` | OIDC auth, ACR push, AKS RBAC, kubectl context |
| `@ci-workflow-builder` | `ci-workflow-builder.agent.md` | Implement/update `ci.yml` (Plan 2) |
| `@cicd-prerequisites-doc-builder` | `cicd-prerequisites-doc-builder.agent.md` | Implement/update `docs/cicd-prerequisites.md` (Plan 7) |
| `@container-workflow-builder` | `container-workflow-builder.agent.md` | Implement/update `container.yml` (Plan 3) |
| `@debugger` | `debugger.agent.md` | Troubleshoot CI/CD failures, Maven errors, pod startup issues |
| `@dependabot-config-builder` | `dependabot-config-builder.agent.md` | Manage `dependabot.yml` (Plan 6) |
| `@deploy-workflow-builder` | `deploy-workflow-builder.agent.md` | Implement/update `deploy.yml` (Plan 4) |
| `@dockerfile-builder` | `dockerfile-builder.agent.md` | Implement/update `Dockerfile` (Plan 5) |
| `@github-actions-expert` | `github-actions-expert.agent.md` | General GitHub Actions questions |
| `@maven-docker-bridge` | `maven-docker-bridge.agent.md` | Validates build-once principle (no Maven/JDK in container workflow) |
| `@pr-validation-workflow-builder` | `pr-validation-workflow-builder.agent.md` | Implement/update `pr-validation.yml` (Plan 1) |
| `@reviewer` | `reviewer.agent.md` | Code and documentation review |
| `@se-security-reviewer` | `se-security-reviewer.agent.md` | Security gate validation, OWASP, Trivy, Gitleaks |
| `@workflow-chain-validator` | `workflow-chain-validator.agent.md` | **Critical**: validates `workflow_run` trigger chain integrity |

### Implementation Plans (`.github/plans/`)

Seven plans define the complete CI/CD pipeline. Reference these when implementing or modifying pipeline components.

| Plan | File | Deliverable | Primary Agent |
|---|---|---|---|
| Plan 1 | `plan1-pr-validation.md` | `pr-validation.yml` | `@pr-validation-workflow-builder` |
| Plan 2 | `plan2-ci.md` | `ci.yml` | `@ci-workflow-builder` |
| Plan 3 | `plan3-container.md` | `container.yml` | `@container-workflow-builder` |
| Plan 4 | `plan4-deploy.md` | `deploy.yml` | `@deploy-workflow-builder` |
| Plan 5 | `plan5-dockerfile.md` | `Dockerfile` | `@dockerfile-builder` |
| Plan 6 | `plan6-dependabot.md` | `dependabot.yml` | `@dependabot-config-builder` |
| Plan 7 | `plan7-cicd-prerequisites.md` | `docs/cicd-prerequisites.md` | `@cicd-prerequisites-doc-builder` |

### Agent Selection Pattern

When modifying CI/CD files, **always invoke the matching agent + validators**:

```bash
# Modifying ci.yml
@ci-workflow-builder <task>
@maven-docker-bridge verify build-once principle
@workflow-chain-validator check CI workflow name

# Modifying container.yml
@container-workflow-builder <task>
@maven-docker-bridge verify no Maven in container workflow
@azure-devops-specialist validate Azure OIDC configuration
@workflow-chain-validator check Container workflow chain

# Modifying deploy.yml
@deploy-workflow-builder <task>
@azure-devops-specialist verify AKS RBAC roles
@workflow-chain-validator check Deploy workflow chain
```

Consult `.github/agents/IMPLEMENTATION-MATRIX.md` for the full agent-to-plan-to-instruction mapping.

---

## Quality Gates (Must Not Regress)

| Gate | Threshold | Enforced In | Failure Action |
|---|---|---|---|
| JaCoCo line coverage | **≥ 80%** | PR validation, CI | Build fails |
| OWASP Dependency-Check | **CVSS < 7** | CI | Build fails, uploads SARIF |
| Trivy Container Scan | **No CRITICAL/HIGH** | Container | Build fails, uploads SARIF |
| CodeQL SAST | *Advisory only* | PR, CI | Uploads to Security tab |
| Gitleaks Secrets | **No secrets** | PR validation | Build fails |
| Checkstyle | **Zero violations** | PR validation | Build fails |
| SpotBugs | **Zero violations** | PR validation | Build fails |
| License Check | **No GPL-2.0/AGPL-3.0** | PR validation | Build fails, comments on PR |

---

## Docker & Kubernetes Patterns

### Docker Image Pattern (from cicd-pipeline-guide.md)

**Build strategy**: Single-stage runtime image — JAR is pre-built by Maven.

```dockerfile
FROM eclipse-temurin:21-jre-alpine
RUN adduser -D -u 1001 appuser
USER appuser
COPY target/app.jar /app/app.jar
WORKDIR /app
HEALTHCHECK --interval=30s --timeout=3s CMD wget --spider http://localhost:8080/actuator/health || exit 1
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Consult `.github/instructions/containerization-docker-best-practices.instructions.md` for advanced patterns.

### Kubernetes Deployment Pattern

Consult `.github/instructions/kubernetes-manifests.instructions.md` and `kubernetes-deployment-best-practices.instructions.md`.

---

## Commit Message Conventions (from `git.instructions.md`)

### Format

```
<type>[optional scope]: [optional gitmoji] <short description>

[optional body — explain what changed and why]

[optional footer — references, BREAKING CHANGE]
```

**Rules**:
- Subject ≤ 50 chars, imperative mood, lowercase, no period
- Separate body with blank line, wrap at ~72 chars

### Types

`feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`

### Examples

```
feat(service): :sparkles: add user search by email

fix: :bug: handle null name in getGreeting

ci(workflows): :construction_worker: add OWASP dependency-check gate
```

---

## Documentation Update Rules

When code changes affect behavior, commands, or APIs, update:

| Change Type | Update File(s) |
|---|---|
| Architecture decision | `docs/adr/` (new ADR) |
| Workflow behavior | `docs/cicd-pipeline-guide.md` |
| Public API | `docs/api/` (OpenAPI spec) |
| CLI command | `README.md` |

### ADR Format

Follow [Nygard template](https://github.com/joelparkerhenderson/architecture-decision-record/blob/main/templates/decision-record-template-by-michael-nygard/index.md). Sequential numbering: `0001-use-layered-architecture.md`.

---

## Common Pitfalls & How to Avoid Them

### Java Language Features

❌ **DON'T** use Java 12+ features:
- Records → use regular classes
- Pattern matching → use traditional casts
- Text blocks → use string concatenation
- Switch expressions → use traditional switch

✅ **DO** use Java 11 features:
- `var` (local variable type inference)
- `Optional<T>` (null handling)
- Streams API, lambdas, method references

### Testing

❌ **DON'T**:
- Use JUnit 5 imports (`org.junit.jupiter.*`)
- Put actual value first: `assertEquals(actual, expected)` ❌

✅ **DO**:
- Use JUnit 4: `org.junit.Test`, `org.junit.Assert.*`
- Put expected first: `assertEquals("expected", actual)`

### Architecture

❌ **DON'T**:
- Import repositories in controllers
- Return entities from controllers

✅ **DO**:
- Follow: controller → service → repository
- Use DTOs at controller boundary

---

## Key Takeaways

1. **Java 11 only** — no records, sealed, pattern matching, text blocks
2. **JUnit 4 only** — `org.junit.Test`, not `org.junit.jupiter.*`
3. **Strict layering** — controller → service → repository → domain
4. **DTO boundaries** — entities never cross to controllers
5. **80% coverage** — hard gate, no exceptions
6. **Test naming** — `test<Method><Scenario>` camelCase
7. **Expected first** — `assertEquals(expected, actual)`
8. **Null before isEmpty()** — always check null first
9. **Javadoc required** — all public methods
10. **Never rename** — `name: CI` or `name: Container` (immutable workflow_run triggers)
11. **Immutable tags** — `sha-xxxxxxx`, never `:latest`
12. **Update docs** — immediately when code changes behavior
13. **Conventional commits** — `<type>(scope): description`
14. **Context files first** — `.github/instructions/` override general practices
15. **Match existing patterns** — consistency over innovation
16. **Agent-first** — use the matching agent from `.github/agents/` before writing CI/CD code manually
17. **Validate chain** — always run `@workflow-chain-validator` after any workflow name change
18. **Build-once** — JAR built once in `ci.yml`; container workflow downloads artifact, never re-compiles
19. **workflow_run context** — use `workflow_run.head_sha` and `workflow_run.head_branch` (not `github.sha`/`github.ref`)
20. **Plans define intent** — consult `.github/plans/` before implementing any pipeline component

---

**For detailed domain-specific guidance, always consult the relevant file in `.github/instructions/`.**
````
