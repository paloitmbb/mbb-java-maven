# Production Pipeline Versioning Strategy
## Three-Branch Environment-Suffixed Semantic Versioning

**Your Setup**: Multi-branch promotion → Development → Staging → Production (Clear & Compliant) ✅

**Strategy**: Semantic Versioning (1.0.0) with Environment Suffixes (-dev, -stag, -prod) + Branch-Specific Commit SHAs

---

## Core Principle

**One version number (1.0.0) across all branches, different environment suffixes**

Each branch deploys the same logical version with different environment markers and commit SHAs:

```
development branch (sha-dev123)           staging branch (sha-stag456)          production/main (sha-prod789)
        ↓                                        ↓                                     ↓
v1.0.0-dev.sha-dev123                   v1.0.0-stag.sha-stag456              v1.0.0-prod.sha-prod789
   ↓ Auto-deploy                            ↓ Manual approval                       ↓ Auto-deploy to prod
Dev Environment (tested)                Staging Environment (UAT)         Production Environment (live)
   ↓ Merge to staging                       ↓ Merge to main                         ↓ Tag v1.0.0
```

---

## 7 Key Changes Needed

### 1. **pom.xml**: Set Base Version to 1.0.0

```xml
<!-- CURRENT -->
<version>1.0-SNAPSHOT</version>

<!-- CHANGE TO -->
<version>1.0.0</version>
```

**Why**: Single source of truth for all branches. Environment suffix (-dev, -stag, -prod) is added by CI, not in pom.xml.

**How**: This version stays constant. Different branch builds append environment suffix: 1.0.0-dev, 1.0.0-stag, 1.0.0-prod

---

### 2. **ci.yml**: Extract Version + Detect Branch

**Add this step to CI pipeline:**

```yaml
- name: Extract version and branch
  run: |
    VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
    BRANCH=$(echo "${GITHUB_REF#refs/heads/}" | tr '/' '-')  # development, staging, main
    COMMIT_SHA=$(git rev-parse --short HEAD)

    # Determine environment suffix
    if [[ "$BRANCH" == "development" ]]; then
      ENV="dev"
    elif [[ "$BRANCH" == "staging" ]]; then
      ENV="stag"
    elif [[ "$BRANCH" == "main" ]]; then
      ENV="prod"
    else
      ENV="unknown"
    fi

    # Create version artifact
    cat > version.txt <<EOF
APP_VERSION=$VERSION
BRANCH=$BRANCH
ENV=$ENV
COMMIT_SHA=$COMMIT_SHA
IMAGE_TAG=v${VERSION}-${ENV}.sha-${COMMIT_SHA}
EOF

    echo "APP_VERSION=$VERSION" >> $GITHUB_ENV
    echo "ENV=$ENV" >> $GITHUB_ENV
    echo "IMAGE_TAG=v${VERSION}-${ENV}.sha-${COMMIT_SHA}" >> $GITHUB_ENV

- name: Upload version artifact
  uses: actions/upload-artifact@v3
  with:
    name: build-metadata
    path: version.txt
```

**Why**: Container pipeline needs to know which branch/environment for correct image tagging.

**Output example (development branch)**:
```
APP_VERSION=1.0.0
BRANCH=development
ENV=dev
COMMIT_SHA=abc1234
IMAGE_TAG=v1.0.0-dev.sha-abc1234
```

---

### 3. **container.yml**: Use Environment-Suffixed Tags

**Current**:
```
Push: myregistry.azurecr.io/hello-java:sha-abc1234
```

**Change to**:
```
Push: myregistry.azurecr.io/hello-java:v1.0.0-dev.sha-abc1234   (development)
      myregistry.azurecr.io/hello-java:v1.0.0-stag.sha-stag456 (staging)
      myregistry.azurecr.io/hello-java:v1.0.0-prod.sha-prod789 (production)
```

**Implementation**:
```yaml
- name: Download version artifact
  uses: actions/download-artifact@v3
  with:
    name: build-metadata

- name: Extract version
  run: |
    source version.txt
    echo "IMAGE_TAG=$IMAGE_TAG" >> $GITHUB_ENV

- name: Build and push image
  env:
    IMAGE_REGISTRY: myregistry.azurecr.io
    IMAGE_REPO: hello-java
  run: |
    docker build -t ${IMAGE_REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG} .
    docker push ${IMAGE_REGISTRY}/${IMAGE_REPO}:${IMAGE_TAG}

    # Store in deploy-metadata for deploy.yml to use
    echo "IMAGE_TAG=${IMAGE_TAG}" > deploy-metadata.txt

- name: Upload deploy metadata
  uses: actions/upload-artifact@v3
  with:
    name: deploy-metadata
    path: deploy-metadata.txt
```

**Why**:
- Environment is explicit in the tag (clear audit trail)
- Commit SHA is immutable reference to exact code
- Different branches naturally have different SHAs (correct architecture)

---

### 4. **deploy.yml**: Apply Kustomize Overlays

**Current**: Manual kubectl commands, hard-coded deployments

**Change to**: Let Kustomize handle manifest updates per environment

**Implementation**:
```yaml
- name: Download deploy metadata
  uses: actions/download-artifact@v3
  with:
    name: deploy-metadata

- name: Deploy to staging
  if: github.ref == 'refs/heads/staging'
  env:
    ENVIRONMENT: staging
  run: |
    source deploy-metadata.txt

    # Apply Kustomize overlay (automatically patches image tag)
    kubectl apply -k k8s/overlays/staging/

    # Verify deployment
    kubectl rollout status deployment/hello-java -n staging

    # Log for audit
    echo "Deployed $IMAGE_TAG to staging"

- name: Deploy to production
  if: github.ref == 'refs/heads/main'
  env:
    ENVIRONMENT: production
  run: |
    source deploy-metadata.txt

    # Apply Kustomize overlay
    kubectl apply -k k8s/overlays/production/

    # Verify deployment
    kubectl rollout status deployment/hello-java -n production

    # Create git tag for immutable reference
    git tag v1.0.0 ${{ github.sha }}
    git push origin v1.0.0

    # Log for audit
    echo "Deployed $IMAGE_TAG to production"
```

**Why**: GitOps approach, reproducible, environment-specific configs automated

---

### 5. **k8s/**: Create Three-Environment Manifests

**Create this structure**:

```
k8s/
├── base/
│   ├── deployment.yaml          (common template)
│   ├── service.yaml             (common template)
│   ├── configmap.yaml           (common configs)
│   └── kustomization.yaml
│
└── overlays/
    ├── development/
    │   ├── kustomization.yaml   (sets v1.0.0-dev.sha-...)
    │   └── patch-replicas.yaml  (1-2 replicas, debug log level)
    ├── staging/
    │   ├── kustomization.yaml   (sets v1.0.0-stag.sha-...)
    │   └── patch-replicas.yaml  (2-3 replicas, standard log level)
    └── production/
        ├── kustomization.yaml   (sets v1.0.0-prod.sha-...)
        └── patch-replicas.yaml  (3+ replicas, monitoring enabled)
```

**Base Deployment (k8s/base/deployment.yaml)**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-java
spec:
  replicas: 2  # Overridden by overlays
  selector:
    matchLabels:
      app: hello-java
  template:
    metadata:
      labels:
        app: hello-java
    spec:
      containers:
      - name: hello-java
        image: myregistry.azurecr.io/hello-java:v1.0.0  # Placeholder, replaced by Kustomize
        ports:
        - containerPort: 8080
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**Kustomize Overlay (k8s/overlays/production/kustomization.yaml)**:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: production

bases:
  - ../../base

patchesStrategicMerge:
  - patch-replicas.yaml

images:
  - name: myregistry.azurecr.io/hello-java
    newTag: v1.0.0-prod.sha-prod789  # Set dynamically by deploy.yml
```

**Patch (k8s/overlays/production/patch-replicas.yaml)**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-java
spec:
  replicas: 3  # Production HA
  template:
    spec:
      containers:
      - name: hello-java
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
```

**Why**: GitOps pattern, reproducible, environment-specific configs automated

---

### 6. **GitHub Branch Protection**: Enforce Promotion Path

**Setup branch rules to enforce dev → stag → prod flow**:

```
development branch:
  - Auto-deploy on merge (no approval needed)

staging branch:
  - Require PR from development
  - Require approval (manual gate before prod)

main branch:
  - Require PR from staging only
  - Require at least 1 approval
  - Auto-deploy on merge (to production)
```

**Why**: Enforces compliance: code must pass dev, then staging approval, then production

---

### 7. **Maven Artifact Naming**: Add Environment Suffix

**Update pom.xml build configuration:**

```xml
<build>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-jar-plugin</artifactId>
      <version>3.2.0</version>
      <configuration>
        <!-- Artifact names: hello-java-1.0.0-dev.jar, hello-java-1.0.0-stag.jar, etc -->
        <finalName>${project.artifactId}-${project.version}-${env.ENV}</finalName>
      </configuration>
    </plugin>
  </plugins>
</build>
```

**Why**: Self-documenting artifacts in repository

---

## Complete Deployment Flow

```
1. Developer: Creates feature branch from development
   ↓
2. GitHub PR: Tests in PR validation (all checks pass)
   ↓
3. Merge to development branch
   └─ GitHub Actions: ci.yml + container.yml
   ├─ Extract version: 1.0.0, ENV=dev
   ├─ Build Maven artifact: hello-java-1.0.0-dev.jar
   ├─ Build Docker image: v1.0.0-dev.sha-abc1234
   ├─ Push image to registry
   └─ Auto-deploy to development (Kustomize applies k8s/overlays/development/)
   ↓ (Development testing, code review in dev environment)
   ↓
4. Create PR: development → staging
   └─ GitHub Actions: ci.yml + container.yml
   ├─ Extract version: 1.0.0, ENV=stag
   ├─ Build Maven artifact: hello-java-1.0.0-stag.jar
   ├─ Build Docker image: v1.0.0-stag.sha-stag456
   ├─ Push image to registry
   └─ Auto-deploy to staging (Kustomize applies k8s/overlays/staging/)
   ↓ (Staging testing, UAT, manual approval)
   ↓
5. **APPROVAL GATE**: Staging branch requires manual approval before merging to main
   (Quality assurance, UAT sign-off, compliance review)
   ↓
6. Merge to main branch (production)
   └─ GitHub Actions: ci.yml + container.yml + deploy.yml
   ├─ Extract version: 1.0.0, ENV=prod
   ├─ Build Maven artifact: hello-java-1.0.0-prod.jar
   ├─ Build Docker image: v1.0.0-prod.sha-prod789
   ├─ Push image to registry
   ├─ Auto-deploy to production (Kustomize applies k8s/overlays/production/)
   ├─ Create git tag: v1.0.0 (immutable production reference)
   └─ Health check ✅ (verify running image = v1.0.0-prod.sha-prod789)
   ↓
✅ Version 1.0.0 is now in production (development path: dev → stag → prod, all tracked)
```

---

## Version Numbering Rules

### Semantic Versioning: MAJOR.MINOR.PATCH

```
1.2.3
│ │ │
│ │ └─ PATCH (bug fixes, minor improvements) → 1.2.4
│ └─── MINOR (new features, backward compatible) → 1.3.0
└───── MAJOR (breaking changes) → 2.0.0
```

**How to increment**:
- **Patch** (1.2.3 → 1.2.4): For bug fixes. When do you merge? When you fix a bug and want to release it.
- **Minor** (1.2.3 → 1.3.0): For new features (backward compatible). When? When you add a feature and release it.
- **Major** (1.2.3 → 2.0.0): For breaking changes. When? When you fundamentally change the API and release it.

**Your approach**: Manual version update in pom.xml PR (explicit, auditable, safe)

---

## Compliance Audit Trail

**Auditor Question**: "Prove that v1.0.0-prod (sha-prod789) was tested before production"

**Answer** (with git/artifact history):
```
1. Code merged to development branch (sha-dev123)
   ├─ Artifact: hello-java-1.0.0-dev.jar
   ├─ Image: v1.0.0-dev.sha-dev123
   └─ Deployed to dev environment ✓

2. PR: development → staging approved
   Code merged to staging branch (sha-stag456)
   ├─ Artifact: hello-java-1.0.0-stag.jar
   ├─ Image: v1.0.0-stag.sha-stag456
   ├─ Deployed to staging environment ✓
   └─ Manual UAT testing: APPROVED ✓

3. PR: staging → main approved by compliance team
   Code merged to main/production branch (sha-prod789)
   ├─ Artifact: hello-java-1.0.0-prod.jar
   ├─ Image: v1.0.0-prod.sha-prod789
   ├─ Git tag v1.0.0 created (immutable) ✓
   └─ Deployed to production environment ✓

✅ Compliance proof: Same logical version (1.0.0) passed dev → stag → prod with approvals
✅ Immutable reference: git tag v1.0.0 points to exact production commit (sha-prod789)
✅ Audit trail: All three artifacts exist, version history in Git
```

---

## Complete Changes Summary

| File | Change | Why |
|------|--------|-----|
| **pom.xml** | Version: 1.0-SNAPSHOT → 1.0.0 | Single source of truth |
| **ci.yml** | +version extraction, branch detection | Create metadata for downstream |
| **container.yml** | +environment-suffixed tags (v1.0.0-dev, v1.0.0-stag, v1.0.0-prod) | Clear audit trail |
| **deploy.yml** | +Kustomize overlays, branch-specific deployment | GitOps, environment isolation |
| **k8s/** | +new directory, base + 3 overlays (dev/stag/prod) | Reproducible deployments |
| **Branch protection** | enforcement (dev→stag→prod flow) | Compliance gates |

---

## Key Benefits

| Benefit | How |
|---------|-----|
| **Version Clarity** | Same version in pom.xml, Docker, and Kubernetes |
| **Environment Explicit** | Version string shows environment: v1.0.0-dev, v1.0.0-stag, v1.0.0-prod |
| **Compliance Ready** | Audit trail shows promotion path: dev → stag → prod with approvals |
| **Immutable References** | Git tag v1.0.0 = exact production commit (sha-prod789) |
| **Reproducibility** | Checkout git tag v1.0.0 = exact production state |
| **Easy Rollback** | `kubectl rollout undo` or deploy previous tag |
| **GitOps Ready** | All configs in k8s/, Kustomize automation |
| **Financial Compliance** | Different SHAs per branch (correct), clear approval gates |
| **No Manual Errors** | Kustomize handles environment configs, version extraction automated |
| **Team Clarity** | "We're running v1.0.0-prod.sha-prod789 in production" is unambiguous |

---

## Summary

This three-branch strategy with environment-suffixed semantic versioning:

✅ Uses **1.0.0** (constant) + **-dev/-stag/-prod** (branch-specific) + **sha-{commit}** (immutable)
✅ Supports **development → staging → production** promotion path
✅ Enforces **approval gates** at staging → production boundary (financial compliance)
✅ Creates **complete audit trail** (every version tagged in Git with promotion path)
✅ Gives **single source of truth** (pom.xml)
✅ Enables **easy rollback** (previous tags available)
✅ **GitOps ready** (all configs in k8s/, reproducible)
✅ **Different SHAs per branch** = correct architecture (each branch has unique commits)

**Ready to implement when you are!** 🚀
