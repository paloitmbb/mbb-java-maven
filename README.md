<div align="center">

# ☕ Hello Java Maven

[![CI](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/ci.yml/badge.svg)](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/ci.yml)
[![Container](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/container.yml/badge.svg)](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/container.yml)
[![PR Validation](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/pr-validation.yml/badge.svg)](https://github.com/paloitmbb/mbb-java-maven/actions/workflows/pr-validation.yml)
[![Java 11](https://img.shields.io/badge/Java-11-blue?style=flat-square&logo=openjdk)](https://openjdk.org/projects/jdk/11/)
[![Maven 3.8+](https://img.shields.io/badge/Maven-3.8+-C71A36?style=flat-square&logo=apachemaven)](https://maven.apache.org/)

[Overview](#overview) • [Features](#features) • [Getting Started](#getting-started) • [CI/CD Pipeline](#cicd-pipeline) • [Architecture](#architecture)

</div>

---

## Overview

A production-grade **Java 11 Maven application** blueprint focused on a sophisticated CI/CD pipeline. It demonstrates a complete "Commit-to-Cloud" journey using GitHub Actions, security scanning, and automated deployment to **Azure Kubernetes Service (AKS)**.

While the application code is minimal, the repository serves as a reference for:
- 🛡️ **DevSecOps**: Shifting security left with parallel scanning and gating.
- 📦 **Build Once**: Producing immutable artifacts passed through the pipeline.
- ☸️ **GitOps-Ready**: Automated Kubernetes rollouts with rolling update strategies.

> [!TIP]
> This repository is a template. You can use it as a starting point for building robust Java microservices with high-maturity CI/CD requirements.

---

## Features

- **Java 11 Stack**: Optimized for compatibility and performance using Maven.
- **Layered Quality Gates**:
  - **Static Analysis**: SpotBugs and Checkstyle (Google Style).
  - **Code Coverage**: Enforced ≥ 80% line coverage via JaCoCo.
  - **Security Scanning**: CodeQL, Gitleaks, Trivy, and OWASP Dependency-Check.
- **Production-Ready Docker**: Multi-stage, non-root Alpine JRE image with health checks.
- **Kubernetes Native**: Deployment manifests with resource limits, liveness/readiness probes, and HPA-ready.
- **5-Stage CI/CD**: Seamless flow from PR validation to container building and AKS deployment.

---

## Getting Started

### Local Development Prerequisites

- [JDK 11](https://adoptium.net/temurin/releases/?version=11)
- [Maven 3.8+](https://maven.apache.org/download.cgi)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### Build and Test

```bash
# Compile and run unit tests
mvn clean test

# Run full verification (Checkstyle, SpotBugs, JaCoCo coverage)
mvn clean verify

# Package the application
mvn package
```

### Local Container Run

```bash
docker build -t hello-java .
docker run -p 8080:8080 hello-java
```

---

## CI/CD Pipeline

The project implements a high-maturity pipeline chain documented in the [CI/CD Pipeline Guide](docs/cicd-pipeline-guide.md).

| Stage | Trigger | Key Actions |
|---|---|---|
| **PR Validation** | Pull Request | Build, Test, CodeQL, Gitleaks, Dependency Review |
| **CI** | Push to `main`/`develop` | OWASP Scan, SBOM generation, Production JAR upload |
| **Container** | CI Success | Build Docker image, Trivy scan, Push to Registry |
| **Deploy** | Container Success | K8s manifest patching, Rollout to AKS |

> [!IMPORTANT]
> To enable the full pipeline in your fork, see the [CI/CD Prerequisites](docs/cicd-prerequisites.md) for OIDC and Secret configuration.

---

## Architecture

The project follows a standard Clean Architecture boundary:
`Controller → Service → Repository → Domain`.

```text
├── .github/workflows/    # CI/CD Pipeline definitions
├── docs/                 # Detailed guides and prerequisites
├── k8s/                  # Kubernetes deployment manifests
├── spec/                 # Formal process specifications
└── src/                  # Java 11 application source and tests
```

### Security & Compliance

This repository follows the **Build-Once** principle:
1. The `CI` workflow builds the `.jar` exactly once.
2. The `Container` workflow uses the *same* `.jar` to build the image.
3. This ensures that what was tested and scanned is exactly what is deployed.

---

## Troubleshooting

Refer to the [Quickstart Guide](quickstart.md) or the [Troubleshooting section](docs/cicd-pipeline-guide.md#troubleshooting) in the documentation if you encounter issues with the pipeline.
