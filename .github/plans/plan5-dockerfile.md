
---

### File 5: `.github/plans/plan5-dockerfile.md`

```markdown
# Plan 5: Dockerfile

## Plan Metadata
- **Plan Number**: 5
- **Filename**: plan5-dockerfile.md
- **Created**: 2026-03-03
- **Based On**: .github/prompts/java-maven-cicd-pipeline.prompt.md
- **Instructions Considered**:
  - .github/instructions/git.instructions.md

## Objective

Create a thin, single-stage runtime `Dockerfile` (no multi-stage Maven build). The pre-built JAR from CI is placed in the Docker build context by the `build-image` job in `container.yml`. Non-root user, Alpine JRE base, `wget` healthcheck, `exec` entrypoint.

## Scope

**In Scope**:
- `Dockerfile` at repository root
- Single-stage runtime image only

**Out of Scope**:
- Multi-stage build (violates build-once principle)
- Maven or JDK in the image

## pom.xml Prerequisites

| Requirement | Purpose |
|---|---|
| `spring-boot-maven-plugin` configured | Produces executable fat JAR |
| Spring Boot Actuator dependency | `/actuator/health` endpoint for HEALTHCHECK |

## Task Breakdown

### Task 001: Create Dockerfile
- **ID**: `task-001`
- **Dependencies**: []
- **Estimated Time**: 15 minutes
- **Description**: Create the thin runtime Dockerfile with all required elements.
- **Actions**:
  1. Create file `Dockerfile` at repository root
  2. Base image: `FROM eclipse-temurin:21-jre-alpine`
  3. Build args: `ARG APP_VERSION=unknown`, `ARG BUILD_DATE=unknown`
  4. OCI labels: `org.opencontainers.image.title`, `.version=${APP_VERSION}`, `.revision=${APP_VERSION}`, `.created=${BUILD_DATE}`, `.source`
  5. Non-root user: `RUN addgroup -g 1001 appgroup && adduser -u 1001 -G appgroup -D -h /app appuser`
  6. `WORKDIR /app`
  7. `COPY target/app.jar /app/app.jar` — pre-built JAR from build context
  8. `USER appuser`
  9. `EXPOSE 8080`
  10. `ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"`
  11. `HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD wget -qO- http://localhost:8080/actuator/health || exit 1` — use `wget` (not `curl`, Alpine JRE doesn't include curl)
  12. `ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]` — `exec` so Java becomes PID 1
- **Outputs**: File `Dockerfile`
- **Validation**:
  - No `FROM maven` or `FROM *-jdk-*` (JRE only)
  - No `mvn` command anywhere
  - `wget` used in HEALTHCHECK (not `curl`)
  - `exec` in ENTRYPOINT
  - Non-root user UID 1001
  - Single FROM statement (single stage)
- **Rollback**: `rm Dockerfile`

---

### Task 002: Validate Dockerfile
- **ID**: `task-002`
- **Dependencies**: [`task-001`]
- **Estimated Time**: 5 minutes
- **Description**: Validate the Dockerfile for correctness and compliance.
- **Actions**:
  1. Run `docker build --check .` or `hadolint Dockerfile` (if available)
  2. Verify single FROM statement
  3. Verify no `RUN apt-get`, `RUN apk add curl` (keep image minimal)
  4. Verify USER is non-root
  5. Verify HEALTHCHECK uses `wget`
  6. Verify ENTRYPOINT uses `exec`
- **Validation**: All checks pass
- **Rollback**: N/A

## Files to Create/Modify

| File Path | Type | Purpose | Related Tasks |
|-----------|------|---------|---------------|
| `Dockerfile` | Create | Thin runtime container image | task-001, task-002 |

## Verification Commands

```bash
# Check for multi-stage (should be 0 additional FROM)
grep -c "^FROM" Dockerfile  # should be exactly 1

# Check for Maven/JDK (should find none)
grep -i "maven\|jdk" Dockerfile && echo "FAIL" || echo "PASS"

# Check for wget healthcheck
grep "wget" Dockerfile && echo "PASS" || echo "FAIL"

# Check for exec in entrypoint
grep "exec java" Dockerfile && echo "PASS" || echo "FAIL"

# Check non-root user
grep "USER appuser" Dockerfile && echo "PASS" || echo "FAIL"