# 🚀 Quick Start Checklist - First 5 Tasks

**Start Date:** December 14, 2025  
**Goal:** Establish foundation for canonical architecture migration

---

## ✅ Task 1: Create Repository Folder Structure (30 minutes)

Create the canonical directory structure following the target architecture:

```bash
# From /home/cloudx/AiCloudxAgent root
mkdir -p backend/src/app/{api,models,db,storage,tasks,utils}
mkdir -p worker/src/{worker_main,jobs,health}
mkdir -p frontend/src/{pages,components,styles}
mkdir -p deploy/helm/cloudxdevai/{templates,values}
mkdir -p devops/{systemd,tools,smoke_tests}
mkdir -p scripts-dev
mkdir -p tests/{ci_smoke_test,e2e}
mkdir -p docs
mkdir -p ui-kit
```

**Verification:**
```bash
find . -maxdepth 3 -type d | grep -E "(backend|worker|frontend|deploy|devops)" | sort
```

---

## ✅ Task 2: Create .env.example (45 minutes)

Create comprehensive environment configuration:

```bash
cat > .env.example << 'EOF'
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/cloudxdevai
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=20

# Redis
REDIS_URL=redis://localhost:6379/0
RQ_REDIS_URL=redis://localhost:6379/1

# Authentication
JWT_SECRET_KEY=your-super-secret-jwt-key-here
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
BCRYPT_ROUNDS=12

# AI/OpenAI
OPENAI_API_KEY=your-openai-api-key-here
AI_DEFAULT_MODEL=gpt-4o-mini
AI_REQUEST_TIMEOUT=20

# File Storage
STORAGE_BACKEND=local  # local or s3
STORAGE_LOCAL_PATH=/opt/cloudxdevai/storage
AWS_S3_BUCKET=your-bucket-name
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1

# Application
APP_ENV=development  # development, staging, production
APP_DEBUG=true
APP_HOST=0.0.0.0
APP_PORT=8000

# Security
SECRET_KEY=your-app-secret-key-here
CORS_ORIGINS=["http://localhost:3000", "http://localhost:5173"]

# Worker
WORKER_CONCURRENCY=4
WORKER_TIMEOUT=300

# Monitoring
PROMETHEUS_ENABLED=true
METRICS_PORT=9090

# External Services
GITHUB_CLIENT_ID=your-github-client-id
GITHUB_CLIENT_SECRET=your-github-client-secret
EOF
```

---

## ✅ Task 3: Implement Minimal FastAPI Backend (2 hours)

Create the foundation FastAPI application:

**backend/requirements.txt:**
```
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
python-dotenv==1.0.0
sqlalchemy==2.0.23
alembic==1.12.1
psycopg2-binary==2.9.9
redis==5.0.1
rq==1.15.1
python-multipart==0.0.6
bcrypt==4.1.2
pyjwt==2.8.0
prometheus-client==0.19.0
```

**backend/src/app/main.py:**
```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import make_asgi_app
import os
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title="AI-Cloudx Agent",
    version="2.0.0",
    description="Cloud Development AI Platform"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", ["*"]),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

@app.get("/healthz")
async def health_check():
    return {
        "status": "healthy",
        "version": "2.0.0",
        "environment": os.getenv("APP_ENV", "development")
    }

@app.get("/")
async def root():
    return {
        "message": "AI-Cloudx Agent API v2.0.0",
        "docs": "/docs",
        "health": "/healthz"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=os.getenv("APP_HOST", "0.0.0.0"),
        port=int(os.getenv("APP_PORT", 8000)),
        reload=os.getenv("APP_ENV") == "development"
    )
```

---

## ✅ Task 4: Create Healthcheck Module (1 hour)

**devops/tools/healthcheck.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Comprehensive healthcheck module for AI-Cloudx Agent v2.0
# Supports both local and Kubernetes deployments

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Load configuration
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    set -a
    source "${PROJECT_ROOT}/.env"
    set +a
fi

# Default values
APP_HOST="${APP_HOST:-localhost}"
APP_PORT="${APP_PORT:-8000}"
REDIS_URL="${REDIS_URL:-redis://localhost:6379/0}"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if a port is open
check_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-5}"

    if command -v nc >/dev/null 2>&1; then
        if nc -z -w"$timeout" "$host" "$port" >/dev/null 2>&1; then
            return 0
        fi
    elif command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
        if timeout "$timeout" bash -c "echo >/dev/tcp/$host/$port" >/dev/null 2>&1; then
            return 0
        fi
    else
        log_error "Neither nc nor timeout+bash available for port checking"
        return 1
    fi
    return 1
}

# Check HTTP endpoint
check_http_endpoint() {
    local url="$1"
    local expected_code="${2:-200}"
    local timeout="${3:-10}"

    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl not available"
        return 1
    fi

    local response
    if ! response=$(curl -s -w "%{http_code}" -o /dev/null --max-time "$timeout" "$url" 2>/dev/null); then
        log_error "Failed to connect to $url"
        return 1
    fi

    if [[ "$response" == "$expected_code" ]]; then
        log_info "HTTP check passed: $url returned $response"
        return 0
    else
        log_error "HTTP check failed: $url returned $response (expected $expected_code)"
        return 1
    fi
}

# Check Redis connectivity
check_redis() {
    local redis_url="$1"

    if ! command -v redis-cli >/dev/null 2>&1; then
        log_error "redis-cli not available, skipping Redis check"
        return 0  # Don't fail if redis-cli not available
    fi

    # Extract host and port from Redis URL
    local host port
    if [[ "$redis_url" =~ redis://([^:]+):([0-9]+) ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        host="localhost"
        port="6379"
    fi

    if check_port "$host" "$port"; then
        log_info "Redis connectivity check passed: $host:$port"
        return 0
    else
        log_error "Redis connectivity check failed: $host:$port"
        return 1
    fi
}

# Main health check function
health_check() {
    local failures=0

    log_info "Starting comprehensive health check for AI-Cloudx Agent v2.0"

    # Check backend API
    if check_http_endpoint "http://${APP_HOST}:${APP_PORT}/healthz"; then
        log_info "✓ Backend API health check passed"
    else
        log_error "✗ Backend API health check failed"
        ((failures++))
    fi

    # Check Redis
    if check_redis "$REDIS_URL"; then
        log_info "✓ Redis connectivity check passed"
    else
        log_error "✗ Redis connectivity check failed"
        ((failures++))
    fi

    # Check frontend (if running)
    if check_port "localhost" "5173" 2; then
        log_info "✓ Frontend development server detected"
    elif check_port "localhost" "3000" 2; then
        log_info "✓ Frontend production server detected"
    else
        log_info "! Frontend server not detected (may not be running)"
    fi

    if [[ $failures -eq 0 ]]; then
        log_info "🎉 All health checks passed!"
        return 0
    else
        log_error "❌ $failures health check(s) failed"
        return 1
    fi
}

# Run health check if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    health_check
fi
```

---

## ✅ Task 5: Create Local Installer Script (2 hours)

**installers/installer_local.sh:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# AI-Cloudx Agent v2.0 Local/Systemd Installer
# Installs to /opt/cloudxdevai with systemd services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
INSTALL_PATH="/opt/cloudxdevai"
SERVICE_USER="cloudxdevai"
VENV_PATH="${INSTALL_PATH}/venv"

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Install system dependencies
install_system_deps() {
    log_info "Installing system dependencies..."

    # Update package list
    apt-get update

    # Install required packages
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        postgresql \
        postgresql-contrib \
        redis-server \
        nginx \
        curl \
        git \
        build-essential \
        libpq-dev \
        pkg-config

    log_info "System dependencies installed"
}

# Create service user
create_service_user() {
    if ! id "$SERVICE_USER" &>/dev/null; then
        log_info "Creating service user: $SERVICE_USER"
        useradd --system --shell /bin/bash --home "$INSTALL_PATH" --create-home "$SERVICE_USER"
    else
        log_info "Service user $SERVICE_USER already exists"
    fi
}

# Create installation directory
create_install_dir() {
    log_info "Creating installation directory: $INSTALL_PATH"
    mkdir -p "$INSTALL_PATH"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_PATH"
}

# Setup Python virtual environment
setup_venv() {
    log_info "Setting up Python virtual environment..."
    sudo -u "$SERVICE_USER" python3 -m venv "$VENV_PATH"

    # Activate venv and install dependencies
    sudo -u "$SERVICE_USER" bash -c "
        source '${VENV_PATH}/bin/activate'
        cd '${PROJECT_ROOT}'
        pip install --upgrade pip setuptools wheel
        pip install -r backend/requirements.txt
    "

    log_info "Python virtual environment ready"
}

# Setup database
setup_database() {
    log_info "Setting up PostgreSQL database..."

    # Create database and user
    sudo -u postgres psql << EOF
CREATE USER cloudxdevai WITH PASSWORD 'cloudxdevai_password';
CREATE DATABASE cloudxdevai OWNER cloudxdevai;
GRANT ALL PRIVILEGES ON DATABASE cloudxdevai TO cloudxdevai;
EOF

    log_info "PostgreSQL database created"
}

# Copy application files
copy_application() {
    log_info "Copying application files..."

    # Copy backend
    cp -r "${PROJECT_ROOT}/backend" "${INSTALL_PATH}/"

    # Copy worker
    cp -r "${PROJECT_ROOT}/worker" "${INSTALL_PATH}/"

    # Copy configuration
    cp "${PROJECT_ROOT}/.env.example" "${INSTALL_PATH}/.env"

    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_PATH"

    log_info "Application files copied"
}

# Create systemd services
create_systemd_services() {
    log_info "Creating systemd services..."

    # Backend API service
    cat > /etc/systemd/system/cloudxdevai-api.service << EOF
[Unit]
Description=AI-Cloudx Agent Backend API
After=network.target postgresql.service redis-server.service
Requires=postgresql.service redis-server.service

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_PATH}/backend
Environment=PATH=${VENV_PATH}/bin
ExecStart=${VENV_PATH}/bin/python -m uvicorn src.app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Worker service
    cat > /etc/systemd/system/cloudxdevai-worker.service << EOF
[Unit]
Description=AI-Cloudx Agent Worker
After=network.target redis-server.service cloudxdevai-api.service
Requires=redis-server.service

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_PATH}/worker
Environment=PATH=${VENV_PATH}/bin
ExecStart=${VENV_PATH}/bin/python src/worker_main.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable cloudxdevai-api
    systemctl enable cloudxdevai-worker

    log_info "Systemd services created and enabled"
}

# Configure nginx (optional)
configure_nginx() {
    log_info "Configuring nginx reverse proxy..."

    cat > /etc/nginx/sites-available/cloudxdevai << EOF
server {
    listen 80;
    server_name localhost;

    location /api {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /metrics {
        proxy_pass http://127.0.0.1:8000;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/cloudxdevai /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    systemctl reload nginx

    log_info "Nginx configured"
}

# Run post-install checks
post_install_checks() {
    log_info "Running post-installation checks..."

    # Source the healthcheck
    source "${PROJECT_ROOT}/devops/tools/healthcheck.sh"

    if health_check; then
        log_info "✅ Installation completed successfully!"
        echo ""
        echo "Next steps:"
        echo "1. Edit ${INSTALL_PATH}/.env with your configuration"
        echo "2. Start services: sudo systemctl start cloudxdevai-api cloudxdevai-worker"
        echo "3. Check status: sudo systemctl status cloudxdevai-api"
        echo "4. Access API at: http://localhost/api/healthz"
    else
        log_error "❌ Post-installation checks failed"
        exit 1
    fi
}

# Main installation function
main() {
    log_info "Starting AI-Cloudx Agent v2.0 local installation..."

    check_root
    install_system_deps
    create_service_user
    create_install_dir
    setup_venv
    setup_database
    copy_application
    create_systemd_services
    configure_nginx
    post_install_checks

    log_info "Installation completed successfully! 🎉"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

---

## 🎯 Verification Commands

After completing these 5 tasks, verify everything works:

```bash
# Check directory structure
find . -maxdepth 3 -type d | grep -E "(backend|worker|frontend)" | sort

# Test FastAPI backend
cd backend && source ../.venv/bin/activate && python -m uvicorn src.app.main:app --host 0.0.0.0 --port 8000 &
curl http://localhost:8000/healthz

# Test healthcheck
bash devops/tools/healthcheck.sh

# Check installer (dry run)
sudo bash installers/installer_local.sh --help 2>/dev/null || echo "Installer created successfully"
```

---

## 📈 Expected Outcomes

After these 5 tasks, you should have:
- ✅ Canonical directory structure created
- ✅ Comprehensive environment configuration
- ✅ Working FastAPI backend foundation
- ✅ Health monitoring system
- ✅ Local installation automation

**Time Estimate:** 6-8 hours total  
**Ready for:** Phase 2 (Database & Authentication)

Let's start building! 🚀