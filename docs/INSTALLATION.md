# Installation Guide

## AI-Cloudx Agent Installation

This guide covers installation of the AI-Cloudx Agent in both local (systemd) and Kubernetes modes.

## Prerequisites

### System Requirements
- **OS:** Ubuntu 20.04+ or Debian 11+
- **Memory:** 2GB minimum (4GB+ recommended)
- **Disk:** 2GB+ free space
- **CPU:** 2+ cores recommended

### Required Software
- Python 3.8+
- curl, wget, git
- For Kubernetes mode: kubectl, helm 3.x

## Quick Start

### Local Installation (Systemd)

```bash
# Clone repository
git clone <repository-url> AiCloudxAgent
cd AiCloudxAgent

# Run master installer
sudo ./installer_master.sh --non-interactive
```

### Kubernetes Installation

```bash
# Clone repository
git clone <repository-url> AiCloudxAgent
cd AiCloudxAgent

# Run master installer in kube mode
sudo ./installer_master.sh --kube-deploy \
    --kubeconfig ~/.kube/config \
    --namespace aiagent \
    --non-interactive
```

## Installation Modes

### Mode 1: Local/Systemd Installation

**What it does:**
- Installs to `/opt/ai-agent`
- Creates Python virtual environment
- Sets up systemd service (`aiagent.service`)
- Runs health checks

**Usage:**
```bash
sudo ./installer_master.sh
# or
sudo ./installers/installer_local.sh
```

**After installation:**
- Service runs as `aiagent` user
- Logs: `/var/log/aiagent_local_installer.log`
- Health endpoint: `http://127.0.0.1:8000/healthz`

### Mode 2: Kubernetes/Helm Installation

**What it does:**
- Installs cert-manager (if missing)
- Installs ingress-nginx (if missing)
- Installs Redis (via Helm)
- Deploys AI-Agent Helm chart
- Runs smoke tests

**Usage:**
```bash
sudo ./installer_master.sh --kube-deploy \
    --kubeconfig ~/.kube/config \
    --namespace aiagent \
    --image-pull-secret my-secret \
    --helm-values custom-values.yaml
```

**After installation:**
- Deployed to namespace: `aiagent`
- Helm release: `aiagent`
- Chart: `devops/helm/aiagent/`

## Installation Paths

**Canonical Path:** `/opt/ai-agent` (hyphenated)

The installation uses `/opt/ai-agent` as the canonical path. If you have an existing installation at `/opt/aiagent` (legacy), the installer will detect and migrate it.

## Advanced Options

### Non-Interactive Mode
```bash
sudo ./installer_master.sh --non-interactive
```

### Auto-Repair Mode
```bash
sudo ./installer_master.sh --auto-repair
```

### Dry-Run Mode
```bash
sudo ./installer_master.sh --dry-run
```

### Production Verification
```bash
sudo ./installer_master.sh --kube-deploy \
    --production-verify "kubectl -n aiagent get all"
```

## Post-Installation

### Verify Installation

**Local mode:**
```bash
# Check service status
systemctl status aiagent.service

# Check health endpoint
curl http://127.0.0.1:8000/healthz

# Run smoke tests
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000
```

**Kubernetes mode:**
```bash
# Check pods
kubectl -n aiagent get pods

# Check services
kubectl -n aiagent get svc

# Run smoke tests
./devops/tools/post_deploy_smoke.sh aiagent aiagent-web /healthz 8000
```

### Production Checks

Run production readiness checks:
```bash
# Local mode
./devops/tools/production_checks.sh --mode local

# Kubernetes mode
./devops/tools/production_checks.sh --mode kube --strict
```

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues and solutions.

## Next Steps

- [Deployment Guide](DEPLOYMENT.md)
- [Upgrade Guide](UPGRADE.md)
- [Architecture Documentation](ARCHITECTURE.md)

