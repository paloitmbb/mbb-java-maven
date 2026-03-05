# =============================================================================
# Runtime image — single-stage only (build-once principle)
# The CI pipeline (container.yml) places the pre-built app.jar in target/
# before running `docker build`. No Maven/JDK compilation happens here.
# =============================================================================
FROM eclipse-temurin:21-jre-alpine

# ---------------------------------------------------------------------------
# Build-time arguments (supplied by the container.yml workflow)
# ---------------------------------------------------------------------------
ARG APP_VERSION=unknown
ARG BUILD_DATE=unknown

# ---------------------------------------------------------------------------
# OCI image annotations
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.title="Hello Java Maven Application"
LABEL org.opencontainers.image.description="Simple Hello World Java Maven project"
LABEL org.opencontainers.image.version="${APP_VERSION}"
LABEL org.opencontainers.image.revision="${APP_VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.source="https://github.com/your-org/mbb-java-maven"
LABEL org.opencontainers.image.authors="Your Team <team@example.com>"
LABEL org.opencontainers.image.licenses="MIT"

# ---------------------------------------------------------------------------
# Non-root user: UID/GID 1001 (principle of least privilege)
# Alpine uses BusyBox addgroup/adduser — syntax differs from Debian useradd
# ---------------------------------------------------------------------------
RUN addgroup -g 1001 appgroup && \
    adduser -u 1001 -G appgroup -D -h /app appuser

# ---------------------------------------------------------------------------
# Working directory — owned by appuser after chown below
# ---------------------------------------------------------------------------
WORKDIR /app

# ---------------------------------------------------------------------------
# Copy the pre-built JAR (produced by `mvn package` in the CI build job)
# The container.yml build-image step renames hello-java-*.jar → app.jar
# ---------------------------------------------------------------------------
COPY target/app.jar /app/app.jar

# ---------------------------------------------------------------------------
# Ensure the JAR is owned by the non-root user (no world-writable files)
# ---------------------------------------------------------------------------
RUN chown appuser:appgroup /app/app.jar && \
    chmod 440 /app/app.jar

# ---------------------------------------------------------------------------
# Switch to non-root user — all subsequent instructions run as appuser
# ---------------------------------------------------------------------------
USER appuser

# ---------------------------------------------------------------------------
# Expose default Spring Boot / application port
# ---------------------------------------------------------------------------
EXPOSE 8080

# ---------------------------------------------------------------------------
# Container-aware JVM tuning
#   +UseContainerSupport : respect cgroup memory/CPU limits (Java 8u191+)
#   MaxRAMPercentage=75.0: cap heap at 75 % of container RAM (leaves OS headroom)
#   java.security.egd   : non-blocking entropy → faster startup on Linux
# ---------------------------------------------------------------------------
ENV JAVA_OPTS="-XX:+UseContainerSupport \
    -XX:MaxRAMPercentage=75.0 \
    -Djava.security.egd=file:/dev/./urandom"

# ---------------------------------------------------------------------------
# Health check
#   - Uses wget (curl is NOT available in eclipse-temurin Alpine JRE images)
#   - Targets Spring Boot Actuator /actuator/health endpoint
#   - start-period=60s gives the JVM time to complete startup before probing
# ---------------------------------------------------------------------------
HEALTHCHECK --interval=30s \
    --timeout=5s \
    --start-period=60s \
    --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1

# ---------------------------------------------------------------------------
# Entrypoint — exec replaces the shell so Java becomes PID 1 and receives
# SIGTERM directly (enables graceful shutdown; avoids 10-second hard kill)
# ---------------------------------------------------------------------------
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
