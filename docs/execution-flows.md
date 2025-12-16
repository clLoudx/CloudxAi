# Execution Flows Documentation

## AI-Cloudx Agent Repository

**Generated:** 2025-01-27  
**Analysis Method:** Max-Logic (Parse → Cross-reference → Infer → Validate)

---

## Overview

This document maps all execution flows in the AI-Cloudx Agent repository, showing how different components interact during installation, deployment, and operation.

---

## Flow 1: Local Installation (Systemd Mode)

### Entry Point
`installer_master.sh` (without `--kube-deploy` flag)

### Execution Sequence

```mermaid
flowchart TD
    A[installer_master.sh] --> B[preflight_checks]
    B --> C[install_base_packages]
    C --> D[run_local_helpers]
    D --> E{Local Mode?}
    E -->|Yes| F[create aiagent user]
    F --> G[call installer.sh]
    G --> H[install_dependencies]
    H --> I[prepare /opt/ai-agent]
    I --> J[create Python venv]
    J --> K[install Python packages]
    K --> L[setup systemd service]
    L --> M[copy devops/systemd/aiagent.service]
    M --> N[systemctl enable aiagent]
    N --> O[systemctl start aiagent]
    O --> P[run_post_deploy_smoke]
    P --> Q[Healthcheck /healthz]
    Q --> R{Success?}
    R -->|Yes| S[Installation Complete]
    R -->|No| T[Emergency Repair]
    T --> U[Retry Installation]
```

### Key Components

- **Installer:** `installer_master.sh` → `installer.sh`
- **Target Path:** `/opt/ai-agent` (after standardization)
- **Service:** `devops/systemd/aiagent.service`
- **Verification:** `devops/tools/post_deploy_smoke.sh`

### Dependencies

- `ai-agent/modules/ui.sh` - UI functions
- `ai-agent/modules/installer_helpers.sh` - Helper functions
- `devops/tools/healthcheck.sh` - Health checks
- `devops/systemd/aiagent.service` - Systemd service

---

## Flow 2: Kubernetes Installation (Helm Mode)

### Entry Point
`installer_master.sh --kube-deploy` or `oneclick_cluster_install.sh`

### Execution Sequence

```mermaid
flowchart TD
    A[installer_master.sh --kube-deploy] --> B[preflight_checks]
    B --> C[install_base_packages]
    C --> D[run_local_helpers]
    D --> E[install_helm_and_prereqs]
    E --> F[install kubectl]
    F --> G[install helm]
    G --> H[create namespace]
    H --> I[helm_deploy_chart]
    I --> J[devops/helm/aiagent]
    J --> K[Deploy cert-manager]
    K --> L[Deploy ingress-nginx]
    L --> M[Deploy redis]
    M --> N[Deploy aiagent pods]
    N --> O[wait_for_k8s_resources]
    O --> P{All pods ready?}
    P -->|No| Q[Wait + Retry]
    Q --> P
    P -->|Yes| R[run_production_verify]
    R --> S[run_post_deploy_smoke]
    S --> T[Port-forward to pod]
    T --> U[HTTP check /healthz]
    U --> V{Success?}
    V -->|Yes| W[Deployment Complete]
    V -->|No| X[Emergency Repair]
    X --> Y[Retry Deployment]
```

### Key Components

- **Installer:** `installer_master.sh` (kube mode) or `oneclick_cluster_install.sh`
- **Chart:** `devops/helm/aiagent/` (canonical)
- **Namespace:** `aiagent` (default)
- **Verification:** `devops/tools/post_deploy_smoke.sh` (k8s mode)

### Dependencies

- Helm 3.x
- kubectl
- Kubernetes cluster access
- cert-manager (for TLS)
- ingress-nginx (for ingress)
- Redis (for queue)

---

## Flow 3: One-Click Cluster Installation

### Entry Point
`oneclick_cluster_install.sh`

### Execution Sequence

```mermaid
flowchart TD
    A[oneclick_cluster_install.sh] --> B[Check kubectl/helm]
    B --> C[Create namespace]
    C --> D[Install cert-manager]
    D --> E[Install ingress-nginx]
    E --> F[Install Redis]
    F --> G[Deploy aiagent chart]
    G --> H[devops/helm/aiagent]
    H --> I[Wait for rollout]
    I --> J[run_post_deploy_smoke]
    J --> K[Complete]
```

### Key Components

- **Installer:** `oneclick_cluster_install.sh`
- **Chart:** `devops/helm/aiagent/`
- **Dependencies:** cert-manager, ingress-nginx, redis

---

## Flow 4: CI/CD Pipeline

### Entry Point
`.github/workflows/ci.yml` or `github_actions/workflows/ci.yml`

### Execution Sequence

```mermaid
flowchart TD
    A[GitHub Actions Trigger] --> B[Checkout Code]
    B --> C[Install Dependencies]
    C --> D[Validate Script Syntax]
    D --> E[Run Self-Tests]
    E --> F[Build Release ZIP]
    F --> G[build_release_zip.sh]
    G --> H[Deploy from ZIP]
    H --> I[deploy_from_zip.sh]
    I --> J[Extract to /opt/ci-aiagent]
    J --> K[Run Smoke Tests]
    K --> L[post_deploy_smoke.sh]
    L --> M{Tests Pass?}
    M -->|Yes| N[Publish Release]
    M -->|No| O[Fail Build]
```

### Key Components

- **Workflow:** `.github/workflows/ci.yml`
- **Build:** `build_release_zip.sh`
- **Deploy:** `devops/tools/deploy_from_zip.sh`
- **Test:** `devops/tools/post_deploy_smoke.sh`

---

## Flow 5: Health Check & Smoke Testing

### Entry Point
`devops/tools/post_deploy_smoke.sh`

### Execution Sequence

```mermaid
flowchart TD
    A[post_deploy_smoke.sh] --> B{Mode?}
    B -->|Kubernetes| C[Get pod from namespace]
    C --> D[Port-forward pod:8000]
    D --> E[HTTP check /healthz]
    E --> F{Success?}
    F -->|Yes| G[Cleanup port-forward]
    F -->|No| H[Retry with backoff]
    H --> E
    B -->|Docker| I[Check container health]
    I --> J[Get published port]
    J --> K[HTTP check /healthz]
    K --> F
    B -->|Local| L[Direct HTTP check]
    L --> M[http://127.0.0.1:8000/healthz]
    M --> F
    G --> N[Smoke Test Complete]
```

### Key Components

- **Script:** `devops/tools/post_deploy_smoke.sh`
- **Module:** `devops/tools/healthcheck.sh`
- **Function:** `http_check_with_retry()`

---

## Flow 6: Emergency Repair

### Entry Point
`tools/emergency-total-repair.sh`

### Execution Sequence

```mermaid
flowchart TD
    A[emergency-total-repair.sh] --> B[Detect Installation Path]
    B --> C{Path Found?}
    C -->|No| D[Try /opt/ai-agent]
    C -->|Yes| E[Check venv]
    D --> E
    E --> F{Venv Exists?}
    F -->|No| G[Recreate venv]
    F -->|Yes| H[Check Python packages]
    G --> H
    H --> I{Packages OK?}
    I -->|No| J[Reinstall packages]
    I -->|Yes| K[Check systemd service]
    J --> K
    K --> L{Service Exists?}
    L -->|No| M[Reinstall service]
    L -->|Yes| N[Check service status]
    M --> N
    N --> O{Service Running?}
    O -->|No| P[Restart service]
    O -->|Yes| Q[Run healthcheck]
    P --> Q
    Q --> R{Health OK?}
    R -->|Yes| S[Repair Complete]
    R -->|No| T[Full Reinstall]
    T --> U[Call installer_master.sh]
```

### Key Components

- **Script:** `tools/emergency-total-repair.sh`
- **Target:** `/opt/ai-agent` (after standardization)
- **Actions:** Repair venv, packages, systemd, restart services

---

## Flow 7: Module Loading

### Execution Sequence

```mermaid
flowchart TD
    A[Installer Script] --> B{Load UI Module}
    B --> C[ai-agent/modules/ui.sh]
    C --> D{Load Helper Module}
    D --> E[ai-agent/modules/installer_helpers.sh]
    E --> F{Load Healthcheck}
    F --> G[devops/tools/healthcheck.sh]
    G --> H[Functions Available]
    H --> I[info, ok, warn, err]
    I --> J[auto_repair_wrapper]
    J --> K[http_check_with_retry]
```

### Module Dependencies

- **UI Module:** `ai-agent/modules/ui.sh`
  - Functions: `info()`, `ok()`, `warn()`, `err()`, `title()`
  
- **Helper Module:** `ai-agent/modules/installer_helpers.sh`
  - Functions: `auto_repair_wrapper()`, `retry_limited()`, `safe_backup()`
  
- **Healthcheck Module:** `devops/tools/healthcheck.sh` (canonical)
  - Functions: `http_check_with_retry()`, `tcp_check()`, `post_deploy_smoke()`

---

## Flow 8: Chart Deployment (Helm)

### Execution Sequence

```mermaid
flowchart TD
    A[helm_deploy_chart] --> B[Verify chart_dir exists]
    B --> C[devops/helm/aiagent]
    C --> D[Create namespace]
    D --> E[Patch serviceaccount]
    E --> F{imagePullSecret?}
    F -->|Yes| G[Add imagePullSecret]
    F -->|No| H[Continue]
    G --> H
    H --> I[helm upgrade --install]
    I --> J[Wait for deployment]
    J --> K{Deployment Ready?}
    K -->|No| L[Wait + Retry]
    L --> K
    K -->|Yes| M[Check pods]
    M --> N{All pods ready?}
    N -->|No| O[Wait + Retry]
    O --> N
    N -->|Yes| P[Deployment Complete]
```

### Key Components

- **Chart:** `devops/helm/aiagent/`
- **Release:** `aiagent`
- **Namespace:** `aiagent` (default)
- **Timeout:** 10 minutes

---

## Cross-Flow Dependencies

### Installer → Module → Service → Chart

```
installer_master.sh
  ├── sources: ai-agent/modules/ui.sh
  ├── sources: ai-agent/modules/healthcheck.sh (conflict: should use devops/tools/healthcheck.sh)
  ├── calls: installer.sh (local mode)
  ├── uses: devops/helm/aiagent (kube mode)
  ├── uses: devops/systemd/aiagent.service (local mode)
  └── calls: devops/tools/post_deploy_smoke.sh (verification)
```

### Healthcheck → Smoke Tests → Verification

```
devops/tools/post_deploy_smoke.sh
  ├── sources: devops/tools/healthcheck.sh
  ├── calls: http_check_with_retry()
  └── supports: local, docker, kubernetes modes
```

---

## Failure Modes & Recovery

### Failure Mode 1: Path Mismatch

**Symptom:** Service fails to start, files not found

**Recovery:**
1. Detect path conflict (`/opt/aiagent` vs `/opt/ai-agent`)
2. Run migration script
3. Update systemd service
4. Restart service

### Failure Mode 2: Chart Not Found

**Symptom:** Helm deployment fails, chart directory missing

**Recovery:**
1. Verify chart location (`devops/helm/aiagent`)
2. Update installer references
3. Retry deployment

### Failure Mode 3: Healthcheck Fails

**Symptom:** Smoke tests fail, service not responding

**Recovery:**
1. Check service status
2. Check logs
3. Run emergency repair
4. Retry healthcheck

---

## Max-Logic Validation

### Parse ✅
- All execution flows mapped
- Entry points identified
- Dependencies documented

### Cross-reference ✅
- Flow interactions verified
- Component relationships confirmed
- Failure modes analyzed

### Infer ✅
- Canonical paths determined
- Best practices identified
- Recovery procedures defined

### Test (Planned)
- Each flow will be tested independently
- Integration tests created
- Failure scenarios validated

### Reconstruct (Planned)
- Unified flows designed
- Conflicts resolved
- Dependencies normalized

### Validate (Planned)
- All flows validated against:
  - Existing deployments
  - CI/CD pipelines
  - Production environments

---

## Next Steps

1. Implement path standardization (affects all flows)
2. Consolidate charts (affects kube flows)
3. Unify healthcheck (affects verification flows)
4. Consolidate installers (affects installation flows)
5. Test each flow independently
6. Document rollback procedures

