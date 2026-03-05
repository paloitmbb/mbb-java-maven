# CI/CD Pipeline Implementation Agents - Quick Start Guide

> **Last Updated**: 2026-03-05
> **Purpose**: Complete agent-driven implementation of Java Maven CI/CD pipeline
> **Status**: Production Ready

## 🎯 How to Use This Guide

You have **7 implementation plans** and **10 specialized agents** ready to generate production-quality code. Simply reference the agent for each plan, and it will create all necessary files following best practices.

## 📋 Implementation Roadmap

### Recommended Implementation Order

```
1. Prerequisites Doc (Plan 7) → Understand requirements
2. PR Validation (Plan 1) → Fast feedback on PRs
3. Dockerfile (Plan 5) → Container foundation
4. CI Workflow (Plan 2) → Build artifact
5. Container Workflow (Plan 3) → Image build & scan
6. Deploy Workflow (Plan 4) → AKS deployment
7. Dependabot (Plan 6) → Automated updates
```

## 🤖 Agent Quick Reference

### Main Implementation Agents (One per Plan)

| Plan | Agent Name | Use When | Files Created |
|---|---|---|---|
| **Plan 1** | `@pr-validation-workflow-builder` | Implement PR validation workflow | `.github/workflows/pr-validation.yml` |
| **Plan 2** | `@ci-workflow-builder` | Implement CI workflow | `.github/workflows/ci.yml` |
| **Plan 3** | `@container-workflow-builder` | Implement container workflow | `.github/workflows/container.yml` |
| **Plan 4** | `@deploy-workflow-builder` | Implement deploy workflow | `.github/workflows/deploy.yml` |
| **Plan 5** | `@dockerfile-builder` | Create optimized Dockerfile | `Dockerfile` |
| **Plan 6** | `@dependabot-config-builder` | Setup Dependabot | `.github/dependabot.yml` |
| **Plan 7** | `@cicd-prerequisites-doc-builder` | Document prerequisites | `docs/cicd-prerequisites.md` |

### Helper/Specialist Agents

| Agent Name | Expertise | Used By | Invoke When |
|---|---|---|---|
| `@maven-docker-bridge` | Build-once principle, artifact handoff | Plans 2, 3, 5 | Validating Maven→Docker flow |
| `@azure-devops-specialist` | Azure OIDC, ACR, AKS | Plans 3, 4, 7 | Azure-specific configurations |
| `@workflow-chain-validator` | workflow_run triggers, name validation | Plans 2, 3, 4 | Validating pipeline chain |

## 🚀 Quick Start: Implement All Plans

### Step 1: Prerequisites Documentation (Plan 7)
**Command**:
```
@cicd-prerequisites-doc-builder implement Plan 7
```

**What it does**:
- Creates `docs/cicd-prerequisites.md`
- Documents all secrets/variables needed
- Provides Azure OIDC setup commands
- Lists workflow chain dependencies

**Review**: Verify all Azure credentials are available before proceeding.

---

### Step 2: PR Validation Workflow (Plan 1)
**Command**:
```
@pr-validation-workflow-builder implement Plan 1
```

**What it does**:
- Creates `.github/workflows/pr-validation.yml`
- Sets up 6 jobs: setup-cache, build-and-test, code-quality, codeql, secrets-scan, dependency-review
- Configures Maven caching strategy
- Integrates with GHAS

**Test**: Open a PR to `main` or `develop` and verify all 6 jobs run.

---

### Step 3: Dockerfile (Plan 5)
**Command**:
```
@dockerfile-builder implement Plan 5
```

**What it does**:
- Creates `Dockerfile` (single-stage, runtime-only)
- Uses Eclipse Temurin 21 JRE Alpine
- Non-root user (UID 1001)
- wget-based HEALTHCHECK
- Container-aware JVM tuning

**Test**: `docker build -t hello-java:test .` (after running `mvn package`)

---

### Step 4: CI Workflow (Plan 2)
**Command**:
```
@ci-workflow-builder implement Plan 2
```

**What it does**:
- Creates `.github/workflows/ci.yml`
- Implements build-once principle
- Produces `app-jar` artifact
- Runs OWASP, SBOM, CodeQL scans

**Validate**:
```bash
@workflow-chain-validator check if CI workflow name is exact
```

**Test**: Push to `main` and verify `app-jar` artifact created.

---

### Step 5: Container Workflow (Plan 3)
**Command**:
```
@container-workflow-builder implement Plan 3
```

**What it does**:
- Creates `.github/workflows/container.yml`
- Downloads `app-jar` from CI (no Maven compilation)
- Builds Docker image, runs Trivy scan
- Pushes to ACR with SHA-based tags
- Creates deploy-metadata artifact

**Validate**:
```bash
@maven-docker-bridge verify build-once principle
@workflow-chain-validator check if Container triggers on CI
```

**Test**: Push to `main`, verify Container triggers after CI completes.

---

### Step 6: Deploy Workflow (Plan 4)
**Command**:
```
@deploy-workflow-builder implement Plan 4
```

**What it does**:
- Creates `.github/workflows/deploy.yml`
- Sequential deploy: staging → production
- Production requires ≥2 approvers
- Health checks + automated rollback
- `cancel-in-progress: false` (safe deploys)

**Validate**:
```bash
@workflow-chain-validator check if Deploy triggers on Container
@azure-devops-specialist verify AKS RBAC roles
```

**Test**: Push to `main`, approve production deploy after staging succeeds.

---

### Step 7: Dependabot Configuration (Plan 6)
**Command**:
```
@dependabot-config-builder implement Plan 6
```

**What it does**:
- Creates `.github/dependabot.yml`
- Maven ecosystem with Spring Boot grouping
- GitHub Actions ecosystem
- Weekly Monday schedule (different times)

**Test**: Insights → Dependency graph → Dependabot → Check for updates

---

## 🔍 Validation Commands

### Validate Entire Pipeline
```bash
# 1. Validate workflow chain
./scripts/validate-workflow-chain.sh

# 2. Validate build-once principle
./scripts/validate-build-once.sh

# 3. YAML lint all workflows
yamllint .github/workflows/*.yml

# 4. Check workflow names (critical!)
yq eval '.name' .github/workflows/ci.yml        # Must be: CI
yq eval '.name' .github/workflows/container.yml  # Must be: Container

# 5. Verify artifact names match
grep "name: app-jar" .github/workflows/ci.yml
grep "name: app-jar" .github/workflows/container.yml
```

## 🎪 Example Agent Conversations

### Simple Implementation
```
Human: Implement Plan 1: PR Validation

Agent: @pr-validation-workflow-builder
[Agent reads plan1-pr-validation.md]
[Agent creates .github/workflows/pr-validation.yml with all 6 jobs]
[Agent validates with yamllint]
✅ Created pr-validation.yml with setup-cache, build-and-test, code-quality,
   codeql, secrets-scan, dependency-review jobs.

Suggested commit: ci(workflows): :construction_worker: add pr-validation workflow
```

### With Validation
```
Human: Implement Plan 2: CI Workflow, then validate the workflow chain

Agent: @ci-workflow-builder
[Creates .github/workflows/ci.yml]
✅ Created ci.yml with name: CI

Agent: @workflow-chain-validator
[Runs validation script]
✅ CI workflow name is exactly 'CI'
✅ Produces app-jar artifact
✅ Ready for Container workflow integration

Suggested commit: ci(workflows): :construction_worker: add ci workflow with build-once artifact
```

### Azure-Specific Setup
```
Human: I need help setting up Azure OIDC for the Container and Deploy workflows

Agent: @azure-devops-specialist
[Provides Azure CLI commands for App Registration, Service Principal,
 Federated Credentials, RBAC roles]
✅ Created step-by-step guide in docs/azure-oidc-setup.md

Next steps:
1. Run the Azure CLI commands
2. Save Client ID, Tenant ID, Subscription ID to GitHub secrets
3. Implement Plans 3 and 4
```

## 🛡️ Safety Checks Before Going Live

### Pre-Deployment Checklist
- [ ] All 7 plans implemented
- [ ] `yamllint` passes on all workflows
- [ ] Workflow chain validated (CI → Container → Deploy)
- [ ] Build-once principle verified (no Maven in container.yml)
- [ ] Azure OIDC configured (all 3 secrets set)
- [ ] GitHub environments created (staging, production)
- [ ] Production environment requires ≥2 reviewers
- [ ] All 9 variables configured (ACR_*, AKS_*, APP_NAME, *_HEALTH_URL)
- [ ] Kubernetes manifests deployed to AKS
- [ ] Health endpoint `/actuator/health` accessible
- [ ] GHAS enabled (CodeQL, Secret Scanning, Dependency Graph)
- [ ] Dependabot PRs tested and merged successfully
- [ ] Rollback tested in staging

## 📚 Reference Documentation

### Must-Read Before Implementation
1. `docs/cicd-pipeline-guide.md` - Pipeline overview
2. `.github/copilot-instructions.md` - Java 11 constraints, naming conventions
3. `.github/plans/plan*-*.md` - Detailed task breakdowns

### Critical Instruction Files
- `.github/instructions/github-actions-ci-cd-best-practices.instructions.md`
- `.github/instructions/java.instructions.md`
- `.github/instructions/containerization-docker-best-practices.instructions.md`
- `.github/instructions/kubernetes-deployment-best-practices.instructions.md`
- `.github/instructions/security.instructions.md`
- `.github/instructions/git.instructions.md`

## 🚨 Critical Constraints (Non-Negotiable)

| Constraint | Reason | Impact if Violated |
|---|---|---|
| Workflow `name: CI` exact | Container triggers via `workflows: ['CI']` | Container never triggers |
| Workflow `name: Container` exact | Deploy triggers via `workflows: ['Container']` | Deploy never triggers |
| Artifact `name: app-jar` exact | Container downloads `app-jar` | Artifact not found error |
| Java 11 source/target | pom.xml compiler config | Compilation failures |
| Java 21 for GitHub Actions | Runner compatibility | Modern tooling support |
| Single-stage Dockerfile | Build-once principle | Violates architecture |
| No Maven in container.yml | Build-once principle | Duplicate compilation |
| `cancel-in-progress: false` for deploy | Deployment safety | Mid-flight cancellation risk |
| Non-root user UID 1001 | Container security | Security violation |
| `wget` in HEALTHCHECK | Alpine JRE lacks curl | Health check fails |

## 🆘 Troubleshooting Quick Links

| Issue | Diagnostic Agent | Solution |
|---|---|---|
| Container workflow not triggering | `@workflow-chain-validator` | Check `name: CI` exact |
| Artifact not found | `@maven-docker-bridge` | Verify `app-jar` name matches |
| Azure login failure | `@azure-devops-specialist` | Check federated credential subject |
| Image tag mismatch | `@container-workflow-builder` | Use `workflow_run.head_sha` |
| Deploy cancels mid-flight | `@deploy-workflow-builder` | Set `cancel-in-progress: false` |
| Dockerfile security fail | `@dockerfile-builder` | Verify non-root user, JRE base |

## 📞 Getting Help

### For Implementation Questions
```
@<agent-name> help with <specific task>
```

### For Architecture Review
```
@reviewer review the pipeline architecture
```

### For Security Audit
```
@se-security-reviewer audit the CI/CD security gates
```

### For Debugging
```
@debugger troubleshoot <workflow-name> failure
```

---

## 🎓 Learning Path

### Beginner (First Time)
1. Read this guide
2. Implement Plan 7 (prerequisites doc)
3. Implement Plan 1 (PR validation - standalone)
4. Test PR validation by opening a test PR
5. Implement Plans 5, 2, 3, 4, 6 in order
6. Test full pipeline with push to `develop`

### Intermediate (Confident)
1. Implement all plans in one session
2. Use validation agents between each plan
3. Test staging deployment
4. Review and merge

### Advanced (Pipeline Expert)
1. Implement all plans
2. Customize for specific needs (e.g., multi-region deploy)
3. Add auto-merge for Dependabot patch updates
4. Configure Slack notifications
5. Optimize for faster feedback

---

**Ready to Start?**

Run: `@cicd-prerequisites-doc-builder implement Plan 7` to begin!
