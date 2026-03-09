# Production Pipeline Versioning & Deployment Strategy

## Problem Statement
Current pipeline lacks coherent version management across artifact (JAR), Docker image, and Kubernetes deployment across three branches (development, staging, production). Need unified versioning strategy that:
1. Uses consistent semantic version base (1.0.0) with environment suffixes (-dev, -stag, -prod)
2. Maintains different commit SHAs per branch (naturally different = correct)
3. Supports three environment tiers with clear promotion path: development → staging → production
4. Ensures compliance audit trail with explicit environment and immutable commit references

---

## Current State Analysis

### ✅ What Works
- **CI Pipeline** (pr-validation.yml, ci.yml): Builds & tests correctly, uses Maven versioning
- **Container Pipeline** (container.yml):
  - Uses commit SHA for image tags (`app:${COMMIT_SHA}`)
  - Produces deploy-metadata artifact with image tag/digest
  - Proper Trivy scanning & SLSA provenance
- **Deploy Pipeline** (deploy.yml):
  - Reads image tag from deploy-metadata artifact (good!)
  - Has staging → production promotion
  - Proper branch gating (main only for prod)

### ❌ What's Missing
1. **No environment-suffixed versioning**: Need to distinguish development, staging, production artifacts
   - pom.xml: Always `1.0.0` (single source of truth)
   - Build pipeline: Append `-dev`, `-stag`, or `-prod` based on branch

2. **No three-branch deployment strategy**:
   - development branch (auto-deploy to dev environment)
   - staging branch (tested before production, manual approval to prod)
   - main/production branch (immutable, production-only)

3. **No Kubernetes manifests found**:
   - No k8s/ or manifests/ directory
   - No way to update image tags in deployments

4. **No version tagging strategy with compliance focus**:
   - No handling of environment-specific artifact versions
   - No clear audit trail showing which version went where
   - Missing commit SHA tracking per branch

5. **Disconnected artifact versions across branches**:
   - Maven jar version (1.0-SNAPSHOT)
   - Docker image tag (commit SHA only, no environment context)
   - Kubernetes image spec (needs manual update)
   - No clear environment path: dev → stag → prod

---

## Proposed Solution: Environment-Suffixed Semantic Versioning (dev/stag/prod)

### 🎯 Version Hierarchy (Branch-Based)

```
development branch (commit sha-dev123)
    ↓
┌──────────────────────────────────────────────────────┐
│  pom.xml: 1.0.0 (single source of truth)            │
│  Branch env: dev                                      │
│  Artifact: hello-java-1.0.0-dev.jar                 │
│  Docker tag: v1.0.0-dev.sha-dev123                  │
│  Deployment: Automated to development environment    │
└─────────────────┬──────────────────────────────────┘
                  ↓
staging branch (commit sha-stag456)
    ↓
┌──────────────────────────────────────────────────────┐
│  pom.xml: 1.0.0 (same)                              │
│  Branch env: stag                                     │
│  Artifact: hello-java-1.0.0-stag.jar                │
│  Docker tag: v1.0.0-stag.sha-stag456               │
│  Deployment: Manual approval gate → production       │
└─────────────────┬──────────────────────────────────┘
                  ↓
main/production branch (commit sha-prod789)
    ↓
┌──────────────────────────────────────────────────────┐
│  pom.xml: 1.0.0 (same)                              │
│  Branch env: prod                                     │
│  Artifact: hello-java-1.0.0-prod.jar                │
│  Docker tag: v1.0.0-prod.sha-prod789               │
│  Git tag: v1.0.0 (immutable reference)              │
│  Deployment: Production environment (live)           │
└──────────────────────────────────────────────────────┘
```

### Key Principle: **Different SHAs Per Branch = Correct**

Each branch has different commits (code merges at different times), therefore naturally different SHAs:
```
development: sha-dev123 ──┐
                          └→ v1.0.0-dev.sha-dev123

staging: sha-stag456 ──┐
                       └→ v1.0.0-stag.sha-stag456

production: sha-prod789 ──┐
                          └→ v1.0.0-prod.sha-prod789
```

This is **correct and expected**, not confusing. Version string shows environment, SHA proves exact commit.

### 📝 Implementation Steps (Todos)

#### Phase 1: Version Management Setup
1. **Setup semantic versioning in pom.xml**
   - Set version: `1.0.0` (single source of truth for all branches)
   - Keep consistent across all three branches

2. **Create version metadata artifact in CI**
   - Extract Maven version from pom.xml: `1.0.0`
   - Extract branch name: `development`, `staging`, or `main`
   - Extract commit SHA: `${GITHUB_SHA:0:7}`
   - Write artifact: `version.txt` with branch-suffixed format
   - Include: app-version, branch, commit-sha, build-timestamp

3. **Update container.yml to use environment-suffixed tags**
   - Read version and branch from CI artifact
   - Build tag format: `v${VERSION}-${BRANCH}.sha-${COMMIT_SHA}`
   - Example tags:
     - `v1.0.0-dev.sha-abc1234` (development branch)
     - `v1.0.0-stag.sha-stag456` (staging branch)
     - `v1.0.0-prod.sha-prod789` (production branch)
   - Push with full tag to Docker registry

#### Phase 2: Kubernetes Manifest Creation
4. **Create k8s directory structure**
   - k8s/base/ - Common resources (Deployment, Service, ConfigMap)
   - k8s/overlays/development/ - Dev-specific patches (replicas, resources)
   - k8s/overlays/staging/ - Staging-specific patches
   - k8s/overlays/production/ - Production-specific patches (HA, monitoring)

5. **Create base Deployment manifest**
   - Deployment with placeholder for image: uses Kustomize image substitution
   - ConfigMap for environment variables (API endpoints, log levels, etc.)
   - Service for network exposure (ClusterIP/LoadBalancer based on env)
   - Health probes (liveness/readiness)
   - Resource requests/limits

6. **Create Kustomize overlays for each environment**
   - Development: minimal replicas (1-2), lower resource limits, debug logging
   - Staging: production-like replicas (2-3), prod-like resource limits
   - Production: high availability (3+), production resource limits, monitoring enabled
   - Each overlay sets the image tag: `v1.0.0-dev`, `v1.0.0-stag`, or `v1.0.0-prod`

#### Phase 3: Deploy Pipeline Enhancement
7. **Update deploy.yml to patch K8s manifests**
   - Download version artifact from CI
   - Extract version, branch, and commit SHA
   - Apply Kustomize overlay for target environment: `kubectl apply -k k8s/overlays/staging/`
   - Use Kustomize `set image` command to inject correct tag
   - Validate manifests before deployment

8. **Add version verification step**
   - After kubectl apply, verify running image matches deployed version
   - Cross-check: container image tag = deploy-metadata tag
   - Log deployment version for audit trail

#### Phase 4: Promotion Pipeline (Branch Strategy)
9. **Three-branch promotion flow** (implemented via Git branch rules)
   - Development branch: Auto-deploy on merge, no approval
   - Staging branch: Manual approval gate before merging to main
   - Main/Production branch: Auto-deploy to production, immutable
   - Git tag: Tag main branch with v1.0.0 after successful production deployment

10. **Update GitHub branch protection rules**
    - Main branch: Require PR reviews before merge (from staging only)
    - Staging branch: Require PR reviews before merge (from development only)
    - Protection rules enforce promotion path: dev → stag → prod

---

## Detailed Workflow Changes

### ci.yml Changes
**Current**: No version extraction
**New**:
- Extract version from pom.xml: `1.0.0`
- Detect branch: `development`, `staging`, or `main`
- Extract commit SHA: first 7 characters
- Create artifact: `version.txt` containing branch-suffixed format
- Store metadata for container pipeline to consume

Example artifact content:
```
APP_VERSION=1.0.0
BRANCH=development
COMMIT_SHA=abc1234
IMAGE_TAG=v1.0.0-dev.sha-abc1234
```

### container.yml Changes
**Current**: Pushes as `registry/repo:sha-abc1234`
**New**:
- Download version artifact from CI
- Build environment-suffixed tag: `v1.0.0-dev.sha-abc1234` (varies by branch)
- Push single tag (which contains all information)
- Store deploy-metadata artifact with exact image tag

### deploy.yml Changes
**Current**: Manual kubectl commands, uses commit SHA directly
**New**:
- Download version artifact from CI
- Download deploy-metadata (image tag)
- Apply Kustomize overlays: `kubectl apply -k k8s/overlays/staging/`
- Kustomize automatically patches image: `registry/repo:v1.0.0-stag.sha-stag456`
- Verify deployment health
- Log version for audit trail

### Branch-Specific Workflow Triggers
**development branch**:
- On merge: Auto-run ci.yml → container.yml → deploy to development environment
- No approval required

**staging branch**:
- On merge: Auto-run ci.yml → container.yml
- Manual deployment to staging (via GitHub environment approval)
- Manual approval gate before merging to main

**main/production branch**:
- On merge: Auto-run ci.yml → container.yml → auto-deploy to production
- Post-deployment: Git tag the commit as `v1.0.0`
- Immutable: This version is now live

---

## File Structure After Implementation

```
mbb-java-maven/
├── .github/
│   └── workflows/
│       ├── pr-validation.yml (unchanged)
│       ├── ci.yml (add version extraction by branch)
│       ├── container.yml (add environment-suffixed tagging)
│       └── deploy.yml (add kustomize overlays)
├── k8s/
│   ├── base/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   └── overlays/
│       ├── development/
│       │   ├── kustomization.yaml
│       │   └── patch-replicas.yaml
│       ├── staging/
│       │   ├── kustomization.yaml
│       │   └── patch-replicas.yaml
│       └── production/
│           ├── kustomization.yaml
│           └── patch-replicas.yaml
├── scripts/
│   └── extract-version.sh (extract version by branch)
├── pom.xml (version: 1.0.0)
└── ...
```

---

## Versioning Strategy Details

### Version Format
```
v1.0.0-{ENV}.sha-{COMMIT}

v1.0.0        = Semantic version (from pom.xml, constant across all branches)
{ENV}         = Environment: dev, stag, or prod (set by branch)
{COMMIT}      = First 7 chars of commit SHA (unique per branch)

Examples:
v1.0.0-dev.sha-abc1234    (development branch, commit abc1234)
v1.0.0-stag.sha-stag456   (staging branch, commit stag456)
v1.0.0-prod.sha-prod789   (production branch, commit prod789)
```

### Maven Artifact Format
```
hello-java-1.0.0-{ENV}.jar

Examples:
hello-java-1.0.0-dev.jar   (development)
hello-java-1.0.0-stag.jar  (staging)
hello-java-1.0.0-prod.jar  (production)
```

### Image Tag Strategy
| Branch | Image Tag | When | Use |
|--------|-----------|------|-----|
| development | `v1.0.0-dev.sha-abc1234` | After merge to dev | Deploy to dev environment |
| staging | `v1.0.0-stag.sha-stag456` | After merge to staging | Test in staging, manual approval to prod |
| main | `v1.0.0-prod.sha-prod789` | After merge to main | Deploy to production, create git tag v1.0.0 |

### Kustomize Overlay Patching
```yaml
# k8s/overlays/development/kustomization.yaml
images:
  - name: hello-java
    newTag: v1.0.0-dev.sha-abc1234  # Set by deploy.yml from CI artifact

# k8s/overlays/staging/kustomization.yaml
images:
  - name: hello-java
    newTag: v1.0.0-stag.sha-stag456

# k8s/overlays/production/kustomization.yaml
images:
  - name: hello-java
    newTag: v1.0.0-prod.sha-prod789
```

### Git Tagging (Production Only)
After successful deployment to production:
```bash
git tag v1.0.0 <main-commit-sha>
git push origin v1.0.0
```

This creates an immutable reference to production commit.

---

## Benefits of This Approach

✅ **Single Source of Truth**: Version flows from pom.xml → container tag → K8s manifest
✅ **Environment Separation**: Staging uses latest, production uses semantic versions
✅ **Rollback Simplicity**: Can rollback by updating image tag in overlay
✅ **Audit Trail**: Full version history in git tags + artifact metadata
✅ **GitOps-Ready**: Manifests can be committed; automation updates image refs
✅ **CI/CD Chain Integrity**: Same image promoted staging → prod
✅ **Developer Friendly**: Clear version semantics (v1.2.3 vs sha-abc1234)

---

## Open Questions (Confirm with User)

1. **Semantic Versioning**: Do you want automatic versioning (patch bump per release) or manual?
2. **Kustomize vs Helm**: Prefer Kustomize (simpler) or Helm (more flexible)?
3. **Release Workflow**: Implement optional release.yml for git tag-triggered builds?
4. **Staging Image Tag**: Use `:develop-latest` or `:sha-<hash>`?
5. **Current K8s Manifests**: Are there existing manifests I should update, or start fresh?
6. **SNAPSHOT vs Release**: Should develop branch use SNAPSHOT versions or develop-specific tags?

---

## Next Steps

1. **Confirm design** with answers to open questions above
2. **Implement Phase 1**: Version extraction in CI
3. **Implement Phase 2**: Create k8s manifests with Kustomize overlays
4. **Implement Phase 3**: Update deploy.yml to use manifests
5. **Test**: Deploy to staging/prod and verify version consistency
6. **Document**: Update README with version/deployment strategy

