# Smoke Tests - Canonical Location

**Location:** `devops/smoke_tests/`  
**Status:** Canonical (all smoke tests consolidated here)

## Overview

This directory contains all smoke tests for the AI-Cloudx Agent. All tests from the root-level `smoke_tests/` directory have been merged here.

## Tests

### check_http.sh
- **Purpose:** HTTP endpoint health checks
- **Usage:** `./check_http.sh <url> <timeout>`
- **Description:** Checks HTTP endpoints with retry logic

### check_imports.sh
- **Purpose:** Python import validation
- **Usage:** `./check_imports.sh [venv_path]`
- **Description:** Verifies that required Python modules can be imported
- **Default venv:** `/opt/ai-agent/venv`

### ci_wrapper.sh
- **Purpose:** CI test wrapper
- **Usage:** `./ci_wrapper.sh [mode]`
- **Description:** Wrapper script for CI/CD pipelines

### docker_compose_check.sh
- **Purpose:** Docker Compose health checks
- **Usage:** `./docker_compose_check.sh`
- **Description:** Verifies Docker Compose services are healthy

### kubernetes_probe.sh
- **Purpose:** Kubernetes pod health checks
- **Usage:** `./kubernetes_probe.sh <namespace> <pod>`
- **Description:** Checks Kubernetes pod readiness and health

### smoke_check.sh
- **Purpose:** Unified smoke test runner
- **Usage:** `./smoke_check.sh [mode]`
- **Description:** Runs appropriate smoke tests based on deployment mode

## Running Tests

### Local Mode
```bash
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000
```

### Kubernetes Mode
```bash
./devops/tools/post_deploy_smoke.sh <namespace> aiagent-web /healthz 8000
```

### Individual Tests
```bash
# HTTP check
./devops/smoke_tests/check_http.sh http://127.0.0.1:8000/healthz 10

# Import check
./devops/smoke_tests/check_imports.sh /opt/ai-agent/venv

# Kubernetes probe
./devops/smoke_tests/kubernetes_probe.sh aiagent aiagent-web
```

## Integration

All smoke tests are integrated via:
- `devops/tools/post_deploy_smoke.sh` - Main smoke test wrapper
- `installers/installer_master.sh` - Calls smoke tests after installation
- CI/CD workflows - Run smoke tests in pipelines

## History

- **2025-01-27:** Consolidated from root `smoke_tests/` directory
- All unique tests merged into canonical location
- Root `smoke_tests/` archived to `.deprecated/`

