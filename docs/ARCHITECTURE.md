# Architecture Documentation

## AI-Cloudx Agent Architecture

This document describes the architecture of the AI-Cloudx Agent system.

## System Overview

The AI-Cloudx Agent is a full-stack AI agent system with:
- **Backend:** Python Flask application with RQ workers
- **Frontend:** React + Vite + Tailwind CSS
- **Queue System:** Redis + RQ (Redis Queue)
- **Deployment:** Supports local (systemd) and Kubernetes (Helm)

## Component Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AI-Cloudx Agent                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Frontend    │  │  Dashboard   │  │   Worker     │  │
│  │  (React)     │  │  (Flask)     │  │   (RQ)       │  │
│  └──────┬───────┘  └──────┬──────┘  └──────┬───────┘  │
│         │                  │                 │          │
│         └──────────────────┼─────────────────┘          │
│                            │                            │
│                    ┌───────▼────────┐                   │
│                    │     Redis      │                   │
│                    │   (Queue)      │                   │
│                    └────────────────┘                   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Frontend (React)

**Location:** `frontend/`

**Technology:**
- React
- Vite (build tool)
- Tailwind CSS

**Responsibilities:**
- User interface
- API communication
- Real-time updates

### 2. Dashboard (Flask)

**Location:** `ai-agent/dashboard/`

**Technology:**
- Flask (Python web framework)
- Gunicorn (WSGI server)

**Responsibilities:**
- REST API endpoints
- Web interface
- Health checks (`/healthz`)

**Endpoints:**
- `/healthz` - Health check
- `/api/*` - API endpoints

### 3. Worker (RQ)

**Location:** `ai-agent/worker/`

**Technology:**
- RQ (Redis Queue)
- Python

**Responsibilities:**
- Process background jobs
- Task execution
- Queue management

### 4. Coordinator

**Location:** `ai-agent/coordinator.py`

**Responsibilities:**
- Orchestrate AI tasks
- Manage builder/fixer workflow
- Coordinate between components

### 5. AI Components

**Location:** `ai-agent/ai/`

**Components:**
- `adapter.py` - AI adapter interface
- Builder - Code building logic
- Fixer - Code fixing logic

## Deployment Architecture

### Local/Systemd Mode

```
┌─────────────────────────────────────┐
│         Systemd Service             │
│    (aiagent.service)                │
├─────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐│
│  │  Dashboard    │  │   Worker     ││
│  │  (Gunicorn)   │  │   (RQ)       ││
│  └──────┬───────┘  └──────┬───────┘│
│         │                  │        │
│         └──────────┬───────┘        │
│                    │                │
│            ┌───────▼──────┐         │
│            │    Redis     │         │
│            │  (Local)      │         │
│            └───────────────┘         │
└─────────────────────────────────────┘
```

### Kubernetes/Helm Mode

```
┌─────────────────────────────────────────────────┐
│              Kubernetes Cluster                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────┐      ┌──────────────┐         │
│  │   Ingress    │      │  cert-manager│         │
│  │   (nginx)    │      │              │         │
│  └──────┬───────┘      └──────────────┘         │
│         │                                        │
│  ┌──────▼──────────────────────────┐            │
│  │      AI-Agent Deployment        │            │
│  │  ┌──────────┐  ┌──────────┐     │            │
│  │  │ Dashboard│  │  Worker  │     │            │
│  │  │  Pods    │  │   Pods   │     │            │
│  │  └────┬─────┘  └────┬─────┘     │            │
│  │       │             │            │            │
│  │       └──────┬──────┘            │            │
│  │              │                    │            │
│  │      ┌───────▼──────┐             │            │
│  │      │ Redis Pod    │             │            │
│  │      └──────────────┘             │            │
│  └──────────────────────────────────┘            │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Data Flow

### Request Flow (Local Mode)

1. User → Frontend (React)
2. Frontend → Dashboard API (Flask)
3. Dashboard → Redis Queue
4. Worker → Processes task
5. Worker → Updates status
6. Frontend → Polls for updates

### Request Flow (Kubernetes Mode)

1. User → Ingress
2. Ingress → Dashboard Service
3. Dashboard Pod → Redis Service
4. Worker Pod → Processes task
5. Worker Pod → Updates status
6. Frontend → Polls for updates

## Installation Architecture

### Installer Hierarchy

```
installer_master.sh (orchestrator)
    ├── installer_local.sh (local mode)
    │   ├── Install dependencies
    │   ├── Create /opt/ai-agent
    │   ├── Setup Python venv
    │   ├── Install systemd service
    │   └── Run smoke tests
    │
    └── installer_kube.sh (kube mode)
        ├── Install cert-manager
        ├── Install ingress-nginx
        ├── Install Redis
        ├── Deploy Helm chart
        └── Run smoke tests
```

## Module Structure

### DevOps Modules

**Location:** `devops/`

- `helm/aiagent/` - Helm chart (canonical)
- `systemd/` - Systemd service files
- `tools/` - Deployment tools
  - `healthcheck.sh` - Health check functions
  - `post_deploy_smoke.sh` - Smoke test wrapper
  - `production_checks.sh` - Production readiness
- `smoke_tests/` - Smoke test scripts

### Application Modules

**Location:** `ai-agent/modules/`

- `ui.sh` - UI helper functions
- `installer_helpers.sh` - Installer utilities
- `logging.sh` - Logging utilities
- `kube_bootstrap.sh` - Kubernetes bootstrap

## Security Architecture

### Local Mode
- Service runs as `aiagent` user (not root)
- Configuration in `/etc/ai-agent/env` (600 permissions)
- Health endpoint on localhost only

### Kubernetes Mode
- Pods run as non-root user
- Secrets via Kubernetes secrets
- Network policies (if configured)
- TLS via cert-manager

## Monitoring Architecture

### Health Checks
- Liveness probe: `/healthz`
- Readiness probe: `/healthz`
- Systemd: Service status
- Kubernetes: Pod status

### Logging
- Application logs: Journald (local) or Pod logs (kube)
- Installer logs: `/var/log/aiagent_*.log`
- Service logs: `journalctl -u aiagent.service`

## Scalability

### Local Mode
- Single instance
- Vertical scaling only
- Limited by server resources

### Kubernetes Mode
- Horizontal scaling via replicas
- Auto-scaling (if configured)
- Load balancing via ingress
- Multi-node deployment

## Backup and Recovery

### Backup Components
- Installation directory: `/opt/ai-agent`
- Configuration: `/etc/ai-agent/env`
- Systemd services: `/etc/systemd/system/aiagent.service`
- Kubernetes: Helm releases, ConfigMaps, Secrets

### Recovery Process
1. Stop services
2. Restore from backup
3. Restore configuration
4. Restart services
5. Verify health

## Related Documentation

- [Installation Guide](INSTALLATION.md)
- [Deployment Guide](DEPLOYMENT.md)
- [Upgrade Guide](UPGRADE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

