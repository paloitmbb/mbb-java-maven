<!-- Inspired by: https://github.com/github/awesome-copilot/blob/main/instructions/java.instructions.md -->
---
applyTo: '**'
description: 'Security best practices for the Java/Maven project and CI/CD pipeline'
---

# Security Guidelines

## Code-Level Security

- **Never** hardcode credentials, API keys, tokens, or passwords in source files, properties files, or commit history.
- Validate and sanitise all external input before processing; never trust data from HTTP requests, environment variables, or files without validation.
- Use parameterised queries / prepared statements — never concatenate user-supplied data into SQL or shell commands.
- Avoid deserialising untrusted data; prefer well-defined DTO mappings over raw object deserialisation.
- Catch only specific exceptions; avoid swallowing `Exception` silently as it can mask security-relevant failures.

## Dependency Security

- OWASP Dependency-Check runs in CI and blocks builds for CVSS ≥ 7 vulnerabilities — do not suppress findings without a documented risk acceptance.
- Review and justify all transitive dependencies; prefer libraries with active maintenance and known CVE histories.
- Keep dependencies up-to-date; use Dependabot or equivalent automated tooling.

## Container & Infrastructure Security

- Container images are scanned with Trivy; no CRITICAL or HIGH CVEs may ship to production.
- Use non-root users in Docker; apply `readOnlyRootFilesystem` and drop unnecessary Linux capabilities.
- Kubernetes workloads must follow the security context rules in `kubernetes-manifests.instructions.md`.

## Secrets Management

- All secrets live in GitHub Actions Secrets or an approved external secret manager (Azure Key Vault).
- Use OIDC (workload identity federation) for Azure authentication; never store long-lived service principal credentials in CI.
- Secrets are never logged, echoed to stdout, or surfaced in workflow outputs.

## CI Quality Gates

- Checkstyle and SpotBugs must produce zero violations on every build.
- Secret scanning with push protection is enabled on this repository.
- License checks block GPL-2.0 and AGPL-3.0 dependencies from entering the dependency tree.
