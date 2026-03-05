# CI/CD Pipeline Implementation - Complete Agent & Resource Matrix

> **Last Updated**: 2026-03-05
> **Purpose**: Comprehensive mapping of plans to agents, instructions, skills, and resources

---

## Plan 1: PR Validation Workflow

### Primary Agent
- **`@pr-validation-workflow-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `github-actions-ci-cd-best-practices.instructions.md` | Workflow structure, caching, parallel jobs | **HIGH** |
| `java.instructions.md` | Maven commands, JUnit 4 patterns, Java 11 constraints | **HIGH** |
| `security.instructions.md` | Gitleaks configuration, CodeQL setup | **MEDIUM** |
| `git.instructions.md` | Commit message format | **MEDIUM** |
| `copilot-instructions.md` | Project-specific patterns | **HIGH** |

### Referenced Skills
| Skill | Used For |
|---|---|
| `create-github-action-workflow-specification` | Documenting the 6-job workflow structure |

### Helper Agents
- None required (standalone workflow)

### Implementation Command
```bash
@pr-validation-workflow-builder implement Plan 1
```

### Success Criteria
- [ ] 6 jobs created: setup-cache, build-and-test, code-quality, codeql, secrets-scan, dependency-review
- [ ] Maven cache strategy implemented
- [ ] All jobs have timeout-minutes
- [ ] `cancel-in-progress: true` for PR efficiency
- [ ] Coverage gate ≥80%

---

## Plan 2: CI Workflow

### Primary Agent
- **`@ci-workflow-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `github-actions-ci-cd-best-practices.instructions.md` | Artifact production, security gates, job orchestration | **HIGH** |
| `security.instructions.md` | OWASP dependency-check, SBOM generation | **HIGH** |
| `java.instructions.md` | Maven lifecycle (verify/package), integration tests | **HIGH** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |
| `copilot-instructions.md` | Build-once principle, artifact naming | **HIGH** |

### Referenced Skills
| Skill | Used For |
|---|---|
| `create-github-action-workflow-specification` | Documenting 4-job CI workflow with artifact flow |

### Helper Agents
| Agent | Validates |
|---|---|
| `@maven-docker-bridge` | app-jar artifact production and naming |
| `@workflow-chain-validator` | `name: CI` exactness for downstream trigger |

### Implementation Command
```bash
@ci-workflow-builder implement Plan 2
@maven-docker-bridge verify build-once principle
@workflow-chain-validator check CI workflow name
```

### Success Criteria
- [ ] `name: CI` exact (immutable)
- [ ] `app-jar` artifact produced
- [ ] `cancel-in-progress: false` for protected branches
- [ ] OWASP scan with CVSS threshold
- [ ] SBOM generated
- [ ] JAR normalized to `target/app.jar`

---

## Plan 3: Container Workflow

### Primary Agent
- **`@container-workflow-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `containerization-docker-best-practices.instructions.md` | BuildKit optimization, Trivy scanning | **HIGH** |
| `github-actions-ci-cd-best-practices.instructions.md` | workflow_run triggers, artifact download | **HIGH** |
| `security.instructions.md` | Trivy configuration, SLSA provenance | **HIGH** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |
| `copilot-instructions.md` | Zero-compilation containerization | **HIGH** |

### Referenced Skills
| Skill | Used For |
|---|---|
| `create-github-action-workflow-specification` | Documenting workflow_run triggered workflow |

### Helper Agents
| Agent | Validates |
|---|---|
| `@maven-docker-bridge` | No Maven/JDK in container workflow |
| `@azure-devops-specialist` | OIDC authentication, ACR push patterns |
| `@workflow-chain-validator` | `name: Container` exactness, workflow_run trigger |

### Implementation Command
```bash
@container-workflow-builder implement Plan 3
@maven-docker-bridge verify no Maven in container workflow
@azure-devops-specialist validate Azure OIDC configuration
@workflow-chain-validator check Container workflow chain
```

### Success Criteria
- [ ] `name: Container` exact (immutable)
- [ ] NO `setup-java` anywhere
- [ ] Downloads `app-jar` with `run-id: workflow_run.id`
- [ ] Uses `workflow_run.head_sha` for commit SHA
- [ ] Trivy scan fails on CRITICAL/HIGH
- [ ] Image pushed to ACR with SHA tag
- [ ] `deploy-metadata` artifact created

---

## Plan 4: Deploy Workflow

### Primary Agent
- **`@deploy-workflow-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `kubernetes-deployment-best-practices.instructions.md` | Deployment strategies, health checks, rollbacks | **HIGH** |
| `kubernetes-manifests.instructions.md` | kubectl commands, rollout patterns | **HIGH** |
| `github-actions-ci-cd-best-practices.instructions.md` | Environment protection, workflow_run | **HIGH** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |
| `copilot-instructions.md` | Deployment safety principles | **HIGH** |

### Referenced Skills
| Skill | Used For |
|---|---|
| `create-github-action-workflow-specification` | Documenting staged deployment workflow |

### Helper Agents
| Agent | Validates |
|---|---|
| `@azure-devops-specialist` | AKS OIDC, kubectl context, RBAC roles |
| `@workflow-chain-validator` | Deploy triggers on Container, workflow name |

### Implementation Command
```bash
@deploy-workflow-builder implement Plan 4
@azure-devops-specialist verify AKS RBAC roles
@workflow-chain-validator check Deploy workflow chain
```

### Success Criteria
- [ ] `cancel-in-progress: false` (critical!)
- [ ] Metadata read from artifact (not re-derived)
- [ ] Production gated by `head_branch == 'main'`
- [ ] Production environment requires ≥2 reviewers
- [ ] Health check with retry logic
- [ ] Rollback uses `if: failure()` (NOT `if: always()`)

---

## Plan 5: Dockerfile

### Primary Agent
- **`@dockerfile-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `containerization-docker-best-practices.instructions.md` | Single-stage builds, layer optimization, security | **HIGH** |
| `security.instructions.md` | Non-root users, minimal base images | **HIGH** |
| `java.instructions.md` | Java 11 runtime requirements | **MEDIUM** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |
| `copilot-instructions.md` | Build-once principle alignment | **HIGH** |

### Referenced Skills
None required (direct Dockerfile generation)

### Helper Agents
| Agent | Validates |
|---|---|
| `@maven-docker-bridge` | No Maven/JDK in Dockerfile |

### Implementation Command
```bash
@dockerfile-builder implement Plan 5
@maven-docker-bridge verify Dockerfile is runtime-only
```

### Success Criteria
- [ ] Single-stage (exactly 1 FROM statement)
- [ ] Eclipse Temurin 21 JRE Alpine base
- [ ] Non-root user UID 1001
- [ ] HEALTHCHECK uses `wget` (not curl)
- [ ] ENTRYPOINT uses `exec`
- [ ] No Maven, no JDK, no compilation
- [ ] OCI labels with build args

---

## Plan 6: Dependabot Configuration

### Primary Agent
- **`@dependabot-config-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `github-actions-ci-cd-best-practices.instructions.md` | Dependabot integration patterns | **MEDIUM** |
| `java.instructions.md` | Spring Boot dependency grouping | **MEDIUM** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |

### Referenced Skills
None required (simple YAML configuration)

### Helper Agents
None required (standalone configuration)

### Implementation Command
```bash
@dependabot-config-builder implement Plan 6
```

### Success Criteria
- [ ] `version: 2` syntax
- [ ] Maven ecosystem configured
- [ ] GitHub Actions ecosystem configured
- [ ] Spring Boot dependencies grouped
- [ ] Weekly Monday schedule (staggered times)
- [ ] Open PR limits set

---

## Plan 7: CI/CD Prerequisites Documentation

### Primary Agent
- **`@cicd-prerequisites-doc-builder`** - Complete implementation agent

### Referenced Instructions
| Instruction File | Why Critical | Priority |
|---|---|---|
| `documentation.instructions.md` | Documentation structure, clarity | **HIGH** |
| `update-docs-on-code-change.instructions.md` | Keeping docs in sync | **HIGH** |
| `github-actions-ci-cd-best-practices.instructions.md` | Secret management, environments | **MEDIUM** |
| `git.instructions.md` | Commit conventions | **MEDIUM** |

### Referenced Skills
| Skill | Used For |
|---|---|
| `create-github-action-workflow-specification` | Documenting workflow chain dependencies |

### Helper Agents
| Agent | Provides Content |
|---|---|
| `@azure-devops-specialist` | Azure OIDC setup commands |
| `@workflow-chain-validator` | Workflow name reference table |

### Implementation Command
```bash
@cicd-prerequisites-doc-builder implement Plan 7
@azure-devops-specialist provide Azure CLI setup commands
@workflow-chain-validator generate workflow chain table
```

### Success Criteria
- [ ] All 7 sections complete
- [ ] All 4 secrets documented
- [ ] All 9 variables documented
- [ ] Azure OIDC setup fully documented
- [ ] Workflow name immutability explained
- [ ] Verification checklist comprehensive

---

## Cross-Cutting Resources

### Always Apply (All Plans)
| Resource | Type | Purpose |
|---|---|---|
| `git.instructions.md` | Instruction | Commit message format |
| `copilot-instructions.md` | Instruction | Project-specific patterns, Java 11 constraints |
| `security.instructions.md` | Instruction | Security-first approach |

### Helper Agents (Cross-Plan)
| Agent | Supports Plans | Primary Function |
|---|---|---|
| `@maven-docker-bridge` | 2, 3, 5 | Validates build-once principle |
| `@azure-devops-specialist` | 3, 4, 7 | Azure OIDC, ACR, AKS expertise |
| `@workflow-chain-validator` | 2, 3, 4 | Validates workflow_run triggers |

### Existing Shared Agents
| Agent | When to Use |
|---|---|
| `@github-actions-expert` | General GitHub Actions questions |
| `@se-security-reviewer` | Security gate validation |
| `@reviewer` | Code/doc review |
| `@debugger` | Troubleshooting failures |
| `@architect` | Architecture decisions |

---

## Implementation Sequence with Agents

```mermaid
graph TD
    Start[Start Implementation] --> P7[@cicd-prerequisites-doc-builder]
    P7 --> P1[@pr-validation-workflow-builder]
    P1 --> P5[@dockerfile-builder]
    P5 -.validate.-> Bridge1[@maven-docker-bridge]
    Bridge1 --> P2[@ci-workflow-builder]
    P2 -.validate.-> Chain1[@workflow-chain-validator]
    Chain1 --> P3[@container-workflow-builder]
    P3 -.validate.-> Bridge2[@maven-docker-bridge]
    P3 -.validate.-> Azure1[@azure-devops-specialist]
    Azure1 --> P4[@deploy-workflow-builder]
    P4 -.validate.-> Chain2[@workflow-chain-validator]
    P4 -.validate.-> Azure2[@azure-devops-specialist]
    Azure2 --> P6[@dependabot-config-builder]
    P6 --> Done[Pipeline Complete]
```

---

## Quick Command Reference

### Full Implementation (Copy-Paste Sequence)
```bash
# 1. Prerequisites
@cicd-prerequisites-doc-builder implement Plan 7

# 2. PR Validation
@pr-validation-workflow-builder implement Plan 1

# 3. Dockerfile
@dockerfile-builder implement Plan 5
@maven-docker-bridge verify Dockerfile is runtime-only

# 4. CI Workflow
@ci-workflow-builder implement Plan 2
@maven-docker-bridge verify build-once principle
@workflow-chain-validator check CI workflow name

# 5. Container Workflow
@container-workflow-builder implement Plan 3
@maven-docker-bridge verify no Maven in container workflow
@azure-devops-specialist validate Azure OIDC configuration
@workflow-chain-validator check Container workflow chain

# 6. Deploy Workflow
@deploy-workflow-builder implement Plan 4
@azure-devops-specialist verify AKS RBAC roles
@workflow-chain-validator check Deploy workflow chain

# 7. Dependabot
@dependabot-config-builder implement Plan 6

# 8. Final Validation
@workflow-chain-validator validate entire pipeline
```

### One-Shot Implementation (Advanced)
```bash
# Implement all plans in sequence with validation
for plan in 7 1 5 2 3 4 6; do
  echo "Implementing Plan $plan..."
  # Agent calls would go here
done
```

---

## Summary Statistics

| Metric | Count |
|---|---|
| **Total Plans** | 7 |
| **Main Implementation Agents** | 7 |
| **Helper/Specialist Agents** | 3 |
| **Total Agents** | 10 |
| **Critical Instructions** | 5 |
| **Supporting Instructions** | 3 |
| **Skills Referenced** | 1 |
| **Files Created** | 8 |
| **Workflows Created** | 4 |
| **Total Implementation Time** | ~2-4 hours |

---

## Next Steps

1. **Review this guide** to understand agent-to-plan mapping
2. **Start with Plan 7** to understand prerequisites
3. **Follow the implementation sequence** using agent commands
4. **Validate after each plan** using helper agents
5. **Test the full pipeline** with a push to develop

**Ready to begin?** Run: `@cicd-prerequisites-doc-builder implement Plan 7`

---

**Document Status**: Complete
**Maintenance**: Update when new plans or agents added
