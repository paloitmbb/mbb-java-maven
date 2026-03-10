# CI/CD Pipeline Prerequisites

> **Last Updated**: 2026-03-05
> **Pipeline Version**: 1.0
> **Maintained By**: DevOps Team

## Overview

This document outlines all **one-time setup requirements** for the CI/CD pipeline. Complete every section before triggering any workflow. Most steps require repository admin access to GitHub and Owner/Contributor access to Azure.

---

## Table of Contents

1. [GitHub Advanced Security (GHAS)](#1-github-advanced-security-ghas)
2. [GitHub Repository Environments](#2-github-repository-environments)
3. [Required Secrets and Variables](#3-required-secrets-and-variables)
4. [Azure Workload Identity Federation](#4-azure-workload-identity-federation)
5. [Kubernetes Namespace Configuration](#5-kubernetes-namespace-configuration)
6. [Workflow Name Reference Table](#6-workflow-name-reference-table)
7. [Verification Checklist](#7-verification-checklist)

---

## 1. GitHub Advanced Security (GHAS)

### Enablement Path

Navigate to: **Settings → Security & Analysis → Enable all**

Or enable features individually:

1. **Dependency Graph** — always on for public repos; enable under Security & Analysis for private repos
2. **Dependabot alerts** — requires Dependency Graph
3. **Dependabot security updates** — auto-raises PRs to fix vulnerable deps
4. **Code scanning (CodeQL)** — enable default setup or let the workflow manage it
5. **Secret scanning** — enable with push protection to block secrets before they land in git

### GHAS Features → Pipeline Jobs

| GHAS Feature | Where It Runs | Behaviour |
|---|---|---|
| CodeQL code scanning | `pr-validation.yml` (`codeql` job on every PR) + `ci.yml` (`codeql` job on push to main/develop + weekly **Sunday 21:00 UTC** / Monday 05:00 UTC+8) | Results appear in the Security tab. PRs from forks skip this job (no secret access). |
| Secret scanning (push protection) | GitHub-native enforcement on every push | Complemented by the `secrets-scan` job in `pr-validation.yml` (Gitleaks), which deep-scans git history for leaked credentials. |
| Dependency graph + Dependabot alerts | `ci.yml` `sbom` job submits the full Maven dependency snapshot via `maven-dependency-submission-action`; `.github/dependabot.yml` schedules automated update PRs | Dependabot alert emails are sent to repo admins. |

### Notes

- CodeQL analysis results are uploaded as SARIF to the Security tab — they do not fail the workflow by default; adjust `fail-on-error` in the workflow if you want hard failures.
- Gitleaks (`secrets-scan`) **does** fail `pr-validation.yml` if a secret pattern is detected. It requires the `GITLEAKS_LICENSE` secret for private repositories and GitHub organisation-owned repos.

---

## 2. GitHub Repository Environments

Environments gate deployments and scope secrets. Create them before running the deploy workflow.

### How to Create

1. Go to **Settings → Environments → New environment**
2. Type the environment name exactly as shown below
3. Configure protection rules as specified

### Staging Environment

| Setting | Value |
|---|---|
| **Name** | `staging` |
| **Deployment branches** | `develop`, `main` |
| **Required reviewers** | None |
| **Wait timer** | 0 minutes |
| **Environment secrets** | None (uses repository-level secrets) |

### Production Environment

| Setting | Value |
|---|---|
| **Name** | `production` |
| **Deployment branches** | `main` only |
| **Required reviewers** | **≥ 2 reviewers** (mandatory — enforced before `deploy-production` job starts) |
| **Wait timer** | 0 minutes (reviewer approval is the gate) |
| **Environment secrets** | None (uses repository-level secrets) |

> **Important**: The `production` environment name is referenced literally in `deploy.yml` (`environment: production`). Do not rename it.

---

## 3. Required Secrets and Variables

### How to Set

| Type | Path |
|---|---|
| **Secrets** | Settings → Secrets and variables → Actions → **Secrets** tab → New repository secret |
| **Variables** | Settings → Secrets and variables → Actions → **Variables** tab → New repository variable |

### Secrets

| Secret Name | Purpose | Used By | How to Obtain |
|---|---|---|---|
| `AZURE_CLIENT_ID` | Azure OIDC federated identity — identifies the GitHub Actions workload | `container.yml`, `deploy.yml` | Azure Portal → Azure Active Directory → App registrations → [your app] → Overview → **Application (client) ID** |
| `AZURE_TENANT_ID` | Azure Active Directory tenant | `container.yml`, `deploy.yml` | Azure Portal → Azure Active Directory → Overview → **Tenant ID** |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription for ACR and AKS resources | `container.yml`, `deploy.yml` | Azure Portal → Subscriptions → [your subscription] → **Subscription ID** |
| `GITLEAKS_LICENSE` | Gitleaks enterprise/org licence — required for private repos and GitHub Org-owned repos; not needed for public personal repos | `pr-validation.yml` (`secrets-scan` job) | Gitleaks dashboard at [gitleaks.io](https://gitleaks.io) or set to any non-empty placeholder for community edition |

### Variables

| Variable Name | Purpose | Used By | Example Value |
|---|---|---|---|
| `ACR_LOGIN_SERVER` | Azure Container Registry hostname | `container.yml` | `myregistry.azurecr.io` |
| `ACR_REPOSITORY` | Repository path within the ACR | `container.yml` | `hello-java` or `apps/hello-java` |
| `APP_NAME` | Kubernetes Deployment name and container name (must match manifest) | `deploy.yml` | `hello-java` |
| `AKS_CLUSTER_NAME_STAGING` | AKS cluster name for staging deployments | `deploy.yml` | `aks-staging` |
| `AKS_RESOURCE_GROUP_STAGING` | Azure resource group containing the staging AKS cluster | `deploy.yml` | `rg-staging` |
| `AKS_CLUSTER_NAME_PROD` | AKS cluster name for production deployments | `deploy.yml` | `aks-production` |
| `AKS_RESOURCE_GROUP_PROD` | Azure resource group containing the production AKS cluster | `deploy.yml` | `rg-production` |
| `STAGING_HEALTH_URL` | Base URL for staging health check after deployment | `deploy.yml` | `https://staging.example.com` |
| `PRODUCTION_HEALTH_URL` | Base URL for production health check after deployment | `deploy.yml` | `https://app.example.com` |

> **Note**: Health check URLs are appended with `/actuator/health` inside the deploy workflow. Provide the base URL without a trailing slash.

---

## 4. Azure Workload Identity Federation

Workload Identity Federation lets GitHub Actions authenticate to Azure using short-lived OIDC tokens — **no stored passwords or long-lived credentials**.

### 4.1 Create the Azure AD App Registration

```bash
# Create the App Registration
az ad app create --display-name "GitHub-Actions-OIDC-hello-java"

# Capture the Application (client) ID
APP_ID=$(az ad app list \
  --display-name "GitHub-Actions-OIDC-hello-java" \
  --query "[0].appId" -o tsv)

echo "Save this as AZURE_CLIENT_ID: $APP_ID"
```

### 4.2 Create the Service Principal

```bash
az ad sp create --id "$APP_ID"

# Capture the Service Principal Object ID — used for all role assignments.
# Using the Object ID (not the App ID) avoids graph-lookup race conditions
# in tenants with replication lag.
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
echo "Save SP_OBJECT_ID for role assignments: $SP_OBJECT_ID"
```

### 4.3 Assign Azure RBAC Roles

> **Prerequisite — Azure RBAC on AKS**: The `Azure Kubernetes Service RBAC Writer`
> role only takes effect when the AKS cluster was provisioned with
> `--enable-azure-rbac`. On clusters using standard Kubernetes RBAC, this
> Azure role assignment is silently ignored and `kubectl set image` will return
> `Forbidden`. Verify with:
> ```bash
> az aks show --name <CLUSTER> --resource-group <RG> \
>   --query "aadProfile.enableAzureRbac"
> # Expected: true
> ```
> If the cluster has `enableAzureRbac: false` or `null`, use a Kubernetes
> `Role` + `RoleBinding` (or `ClusterRole` + `ClusterRoleBinding`) instead.

```bash
# --- ACR: allow GitHub Actions SP to push images ---
ACR_ID=$(az acr show --name <YOUR_ACR_NAME> \
  --resource-group <YOUR_ACR_RG> \
  --query id -o tsv)

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "AcrPush" \
  --scope "$ACR_ID"

# --- ACR: allow AKS kubelet managed identity to pull images at runtime ---
# This is separate from the GitHub Actions SP. Without this, pods will fail
# with ImagePullBackOff after 'kubectl set image' updates the tag.
az aks update \
  --name <AKS_CLUSTER_NAME_STAGING> \
  --resource-group <AKS_RESOURCE_GROUP_STAGING> \
  --attach-acr <YOUR_ACR_NAME>

az aks update \
  --name <AKS_CLUSTER_NAME_PROD> \
  --resource-group <AKS_RESOURCE_GROUP_PROD> \
  --attach-acr <YOUR_ACR_NAME>

# --- Staging AKS: allow GitHub Actions SP to run kubectl commands ---
AKS_STAGING_ID=$(az aks show \
  --name <AKS_CLUSTER_NAME_STAGING> \
  --resource-group <AKS_RESOURCE_GROUP_STAGING> \
  --query id -o tsv)

# ARM-level: allows az aks get-credentials to fetch kubeconfig
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "$AKS_STAGING_ID"

# Kubernetes-level (requires --enable-azure-rbac on cluster):
# Grants write access to Deployments, Pods, Services within the cluster scope.
# Note: Use "Azure Kubernetes Service RBAC Admin" if Cluster Admin (superuser) is not required.
az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service RBAC Admin" \
  --scope "$AKS_STAGING_ID"

# --- Production AKS: allow GitHub Actions SP to run kubectl commands ---
AKS_PROD_ID=$(az aks show \
  --name <AKS_CLUSTER_NAME_PROD> \
  --resource-group <AKS_RESOURCE_GROUP_PROD> \
  --query id -o tsv)

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service Cluster User Role" \
  --scope "$AKS_PROD_ID"

az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Azure Kubernetes Service RBAC Admin" \
  --scope "$AKS_PROD_ID"
```

### 4.4 Configure Federated Credentials

Add one credential per branch and one for the production environment:

```bash
# main branch — used by container.yml and deploy.yml (production)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "GitHub-Actions-Main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# develop branch — used by container.yml and deploy.yml (staging from develop)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "GitHub-Actions-Develop",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/develop",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# production environment — used by deploy.yml (deploy-production job)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters '{
    "name": "GitHub-Actions-Production-Env",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:YOUR-ORG/YOUR-REPO:environment:production",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

> Replace `YOUR-ORG/YOUR-REPO` with the exact `owner/repository` slug. Any mismatch causes a silent OIDC login failure.

### 4.5 Retrieve and Save All Three Secret Values

```bash
# Client ID (already captured)
echo "AZURE_CLIENT_ID: $APP_ID"

# Tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "AZURE_TENANT_ID: $TENANT_ID"

# Subscription ID
SUB_ID=$(az account show --query id -o tsv)
echo "AZURE_SUBSCRIPTION_ID: $SUB_ID"
```

Copy all three values into GitHub repository secrets as described in [Section 3](#3-required-secrets-and-variables).

---

## 5. Kubernetes Namespace Configuration

### Prerequisites

- AKS clusters provisioned (staging and production)
- Local `kubectl` configured, or use Azure Cloud Shell
- `kubeconfig` contexts named to match cluster names

### Create Namespaces

```bash
# Staging cluster
az aks get-credentials \
  --name <AKS_CLUSTER_NAME_STAGING> \
  --resource-group <AKS_RESOURCE_GROUP_STAGING>

kubectl create namespace staging

# Production cluster
az aks get-credentials \
  --name <AKS_CLUSTER_NAME_PROD> \
  --resource-group <AKS_RESOURCE_GROUP_PROD>

kubectl create namespace production
```

### Apply Kubernetes Manifests

The deploy workflow uses `kubectl set image` to update an **existing** Deployment. The manifests must be applied once before the first pipeline run:

```bash
# Staging
kubectl apply -f k8s/deployment.yaml  --namespace staging
kubectl apply -f k8s/service.yaml     --namespace staging
kubectl apply -f k8s/ingress.yaml     --namespace staging

# Production
kubectl apply -f k8s/deployment.yaml  --namespace production
kubectl apply -f k8s/service.yaml     --namespace production
kubectl apply -f k8s/ingress.yaml     --namespace production
```

### Deployment Manifest Requirements

The Kubernetes Deployment must satisfy these constraints for the pipeline to work:

| Requirement | Detail |
|---|---|
| **Deployment name** | Must exactly match the `APP_NAME` variable |
| **Container name** | Must exactly match the `APP_NAME` variable |
| **Image placeholder** | An initial image tag is required; the pipeline overwrites it via `kubectl set image` |
| **Health endpoint** | Container must expose `/actuator/health` on port `8080` (Spring Boot Actuator) |
| **Readiness probe** | `httpGet: /actuator/health` — ensures traffic only reaches healthy pods |

Example Deployment spec excerpt:

```yaml
spec:
  selector:
    matchLabels:
      app: hello-java        # must match APP_NAME
  template:
    spec:
      containers:
        - name: hello-java   # must match APP_NAME
          image: myregistry.azurecr.io/hello-java:initial
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /actuator/health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
```

---

## 6. Workflow Name Reference Table

> ⚠️ **IMMUTABLE** — The `name:` field values in the table below are referenced by downstream `workflow_run` triggers. Changing them causes the pipeline chain to break **silently** (no error, no execution).

### Chain Map

```
push to main/develop
        │
        ▼
 ci.yml  (name: "CI")
        │  workflow_run: workflows: ['CI']
        ▼
 container.yml  (name: "Container")
        │  workflow_run: workflows: ['Container']
        ▼
 deploy.yml  (name: "Deploy")
```

### Name Reference Table

| Workflow File | `name:` Value | Referenced By | If Changed |
|---|---|---|---|
| `pr-validation.yml` | `PR Validation` | Nothing (head of chain) | Safe to change |
| `ci.yml` | **`CI`** | `container.yml` trigger | `container.yml` never runs |
| `container.yml` | **`Container`** | `deploy.yml` trigger | `deploy.yml` never runs |
| `deploy.yml` | `Deploy` | Nothing (tail of chain) | Safe to change |

### Why This Matters

```yaml
# .github/workflows/container.yml
on:
  workflow_run:
    workflows: ['CI']     # ← Must exactly match ci.yml's name: CI
    types: [completed]
    branches: [main, develop]

# .github/workflows/deploy.yml
on:
  workflow_run:
    workflows: ['Container']     # ← Must exactly match container.yml's name: Container
    types: [completed]
```

There is no validation — a rename simply means the downstream workflow never finds a matching trigger and silently stops being scheduled.

### Verification Command

```bash
# Verify immutable names are intact (requires yq)
yq eval '.name' .github/workflows/ci.yml        # Expected: CI
yq eval '.name' .github/workflows/container.yml # Expected: Container
```

---

## 7. Verification Checklist

Use this checklist after completing all sections to confirm the pipeline is ready to run.

### GitHub Settings

- [ ] Code scanning (CodeQL) enabled under Security & Analysis
- [ ] Secret scanning with push protection enabled
- [ ] Dependency Graph enabled
- [ ] Dependabot alerts enabled
- [ ] Environment `staging` created with deployment branches `develop` and `main`, no required reviewers
- [ ] Environment `production` created, restricted to `main` branch only, ≥ 2 required reviewers configured
- [ ] Secret `AZURE_CLIENT_ID` added to repository secrets
- [ ] Secret `AZURE_TENANT_ID` added to repository secrets
- [ ] Secret `AZURE_SUBSCRIPTION_ID` added to repository secrets
- [ ] Secret `GITLEAKS_LICENSE` added to repository secrets (required for private/org repos)
- [ ] Variable `ACR_LOGIN_SERVER` added (e.g. `myregistry.azurecr.io`)
- [ ] Variable `ACR_REPOSITORY` added (e.g. `hello-java`)
- [ ] Variable `APP_NAME` added (e.g. `hello-java`)
- [ ] Variable `AKS_CLUSTER_NAME_STAGING` added
- [ ] Variable `AKS_RESOURCE_GROUP_STAGING` added
- [ ] Variable `AKS_CLUSTER_NAME_PROD` added
- [ ] Variable `AKS_RESOURCE_GROUP_PROD` added
- [ ] Variable `STAGING_HEALTH_URL` added (base URL, no trailing slash)
- [ ] Variable `PRODUCTION_HEALTH_URL` added (base URL, no trailing slash)

### Azure Configuration

- [ ] Azure AD App Registration created
- [ ] Service Principal created for the App Registration
- [ ] `AcrPush` role assigned on the ACR resource scope (for GitHub Actions SP)
- [ ] AKS kubelet managed identity attached to ACR via `az aks update --attach-acr` (staging)
- [ ] AKS kubelet managed identity attached to ACR via `az aks update --attach-acr` (production)
- [ ] Staging AKS cluster provisioned with `--enable-azure-rbac` (required for RBAC Writer role)
- [ ] Production AKS cluster provisioned with `--enable-azure-rbac` (required for RBAC Writer role)
- [ ] `Azure Kubernetes Service Cluster User Role` assigned on staging AKS cluster
- [ ] `Azure Kubernetes Service RBAC Writer` assigned on staging AKS namespace scope
- [ ] `Azure Kubernetes Service Cluster User Role` assigned on production AKS cluster
- [ ] `Azure Kubernetes Service RBAC Writer` assigned on production AKS namespace scope
- [ ] Federated credential created for `main` branch
- [ ] Federated credential created for `develop` branch
- [ ] Federated credential created for `production` environment
- [ ] Client ID, Tenant ID, Subscription ID all saved as GitHub secrets

### Kubernetes

- [ ] Staging AKS cluster accessible via `kubectl`
- [ ] Production AKS cluster accessible via `kubectl`
- [ ] Namespace `staging` exists in staging AKS
- [ ] Namespace `production` exists in production AKS
- [ ] Deployment manifest applied to staging namespace (name matches `APP_NAME`)
- [ ] Deployment manifest applied to production namespace (name matches `APP_NAME`)
- [ ] Container name in Deployment spec matches `APP_NAME`
- [ ] `/actuator/health` endpoint reachable on port `8080`
- [ ] Readiness and liveness probes configured in Deployment spec

### Workflow Name Integrity

- [ ] `ci.yml` has `name: CI` (exact value, no extra spaces or casing)
- [ ] `container.yml` has `name: Container` (exact value)
- [ ] `container.yml` triggers on `workflows: ['CI']`
- [ ] `deploy.yml` triggers on `workflows: ['Container']`

---

## Troubleshooting

### Container Workflow Does Not Trigger After CI Passes

**Symptom**: `ci.yml` completes successfully but `container.yml` never starts.

**Cause**: The `name:` field in `ci.yml` does not exactly match `CI`.

**Fix**:
```bash
grep "^name:" .github/workflows/ci.yml
# Must output:  name: CI
```

---

### Deploy Workflow Does Not Trigger After Container Passes

**Symptom**: `container.yml` completes but `deploy.yml` never starts.

**Cause**: The `name:` field in `container.yml` does not exactly match `Container`.

**Fix**:
```bash
grep "^name:" .github/workflows/container.yml
# Must output:  name: Container
```

---

### Azure OIDC Login Fails (`clientId or tenantId not valid`)

**Cause**: The federated credential subject does not match the runtime context.

**Check**:
- Branch-based subject: `repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main`
- Environment-based subject: `repo:YOUR-ORG/YOUR-REPO:environment:production`
- Verify org/repo slug is lowercase and matches exactly

---

### Deployment Health Check Fails After Rollout

**Cause**: Spring Boot Actuator is not on the classpath.

**Fix** — add to `pom.xml`:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

---

### `kubectl set image` Fails With `not found`

**Cause**: The Deployment does not exist yet in the target namespace, or the name does not match `APP_NAME`.

**Fix**: Apply the manifest manually (see [Section 5](#5-kubernetes-namespace-configuration)) and confirm `APP_NAME` matches the Deployment metadata name.

---

## Maintenance

| Frequency | Task |
|---|---|
| Quarterly | Review Azure role assignments; remove unused federated credentials |
| Annually | Rotate `GITLEAKS_LICENSE` if using enterprise licence |
| Per new workflow | Add any new secrets/variables to this document and the verification checklist |
| Per new branch | Add a new federated credential in Azure AD for the branch |
| On AKS upgrade | Re-verify `kubectl` connectivity and RBAC assignments |

---

## References

### Internal

- [CI/CD Pipeline — Plain English Guide](cicd-pipeline-guide.md) — plain language overview of all workflows
- [spec/spec-process-cicd-pr-validation.md](../spec/spec-process-cicd-pr-validation.md) — PR Validation workflow specification
- [spec/spec-process-cicd-ci.md](../spec/spec-process-cicd-ci.md) — CI workflow specification
- [spec/spec-process-cicd-container.md](../spec/spec-process-cicd-container.md) — Container workflow specification
- [spec/spec-process-cicd-deploy.md](../spec/spec-process-cicd-deploy.md) — Deploy workflow specification

### External

- [GitHub OIDC with Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Workload Identity Federation](https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)
- [Azure Kubernetes Service RBAC](https://learn.microsoft.com/en-us/azure/aks/manage-azure-rbac)
- [GitHub Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Gitleaks](https://gitleaks.io)
- [Dependabot configuration options](https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file)
- [SLSA Provenance](https://slsa.dev/provenance/v0.1)
