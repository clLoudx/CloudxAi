# 🔬 MAX-LOGIC IMPLEMENTATION PLAN
## AI-Cloudx Agent v2.0 - Full Canonical Architecture Migration

**Implementation Mode:** MAX-LOGIC (Maximum Logic, Zero Compromise)  
**Date:** December 14, 2025  
**Methodology:** Systematic, comprehensive, production-ready implementation  
**Target:** 100% canonical compliance, zero technical debt accumulation  

---

## 🎯 MAX-LOGIC PRINCIPLES

### 1. **Complete Specification First**
- Every file, function, and configuration fully specified before implementation
- No "figure it out later" - all decisions made upfront
- Comprehensive dependency mapping and conflict resolution

### 2. **Atomic Implementation Units**
- Each task is a complete, testable unit
- No partial implementations - each delivers working functionality
- Immediate validation and rollback capability

### 3. **Zero Technical Debt**
- Production-quality code from day one
- Comprehensive error handling, logging, and monitoring
- Security and performance considerations built-in

### 4. **Comprehensive Validation**
- Automated testing at every step
- Health checks and smoke tests integrated
- Performance benchmarking and optimization

### 5. **Complete Documentation**
- Every decision documented
- Runbooks for operations
- Troubleshooting guides for every component

---

## 📋 PHASE 1: FOUNDATION & INFRASTRUCTURE
**Duration:** 2 weeks  
**Success Criteria:** FastAPI backend serving health checks, canonical structure established  

### Task 1.1: Directory Structure Creation
**Status:** Ready for Implementation  
**Effort:** 30 minutes  
**Risk Level:** Low  

#### Pre-Implementation Checklist
- [ ] Verify current working directory: `/home/cloudx/AiCloudxAgent`
- [ ] Backup existing `ai-agent/` directory
- [ ] Confirm no file conflicts in target paths

#### Implementation Steps
```bash
# Create canonical directory structure
mkdir -p backend/src/app/{api,models,db,storage,tasks,utils}
mkdir -p backend/src/app/api/{auth,users,projects,files,agent,admin}
mkdir -p backend/tests/{unit,integration,e2e}
mkdir -p worker/src/{worker_main,jobs,health}
mkdir -p worker/src/jobs/{codegen,test_runner,sandbox_exec}
mkdir -p worker/tests
mkdir -p frontend/src/{pages,components,styles}
mkdir -p frontend/src/pages/{Login,Signup,Dashboard,AdminPanel,ProjectView}
mkdir -p frontend/src/components/{FileExplorer,Editor,AIChat,RunConsole,Topbar}
mkdir -p deploy/helm/cloudxdevai/{Chart.yaml,values.yaml,templates,values-production.yaml}
mkdir -p deploy/k8s/{cert-manager,nginx-ingress}
mkdir -p infra/{aws,gcp,do}
mkdir -p installers/{installer_master.sh,installer_local.sh,installer_kube.sh}
mkdir -p devops/{systemd,tools,smoke_tests}
mkdir -p devops/systemd/{cloudxdevai-api.service,cloudxdevai-worker.service}
mkdir -p devops/tools/{healthcheck.sh,post_deploy_smoke.sh,deploy_from_zip.sh}
mkdir -p devops/smoke_tests/{check_http.sh,check_imports.sh,kubernetes_probe.sh,docker_compose_check.sh}
mkdir -p scripts/{build_release_zip.sh,deploy_from_zip.sh,run_smoke_tests.sh,backup_and_restore.sh}
mkdir -p scripts-dev/{seed_db.py,create_local_user.sh}
mkdir -p tests/{ci_smoke_test.sh,e2e/}
mkdir -p docs/{devops-docs.html,troubleshooting.html,systemd.html,upgrade.html,kube_helm.html}
mkdir -p ui-kit/{components,icons}
mkdir -p tools/{emergency-total-repair.sh,dpkg-emergency-repair.sh,build_aiagent_bundle.sh}
```

#### Validation Commands
```bash
# Verify structure completeness
find . -maxdepth 4 -type d | grep -E "(backend|worker|frontend|deploy|devops)" | wc -l
# Expected: 45+ directories

# Check for conflicts
find . -name "*.py" -path "./backend/*" | head -5
find . -name "*.py" -path "./worker/*" | head -5
```

#### Rollback Procedure
```bash
# If issues arise, remove new structure
rm -rf backend/ worker/ frontend/ deploy/ infra/ scripts-dev/ ui-kit/
# Restore from backup if needed
```

### Task 1.2: Environment Configuration System
**Status:** Ready for Implementation  
**Effort:** 45 minutes  
**Risk Level:** Low  

#### Implementation Steps

**File: .env.example**
```bash
# Database Configuration
DATABASE_URL=postgresql://cloudxdevai:cloudxdevai_password@localhost:5432/cloudxdevai
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=20
DB_POOL_RECYCLE=3600

# Redis Configuration
REDIS_URL=redis://localhost:6379/0
RQ_REDIS_URL=redis://localhost:6379/1
REDIS_CACHE_URL=redis://localhost:6379/2

# Authentication & Security
JWT_SECRET_KEY=your-super-secret-jwt-key-change-this-in-production
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
JWT_REFRESH_TOKEN_EXPIRE_DAYS=7
BCRYPT_ROUNDS=12
SECRET_KEY=your-app-secret-key-change-this-in-production

# AI/OpenAI Configuration
OPENAI_API_KEY=your-openai-api-key-here
AI_DEFAULT_MODEL=gpt-4o-mini
AI_BACKUP_MODEL=gpt-3.5-turbo
AI_REQUEST_TIMEOUT=30
AI_MAX_TOKENS=4000
AI_TEMPERATURE=0.2

# File Storage Configuration
STORAGE_BACKEND=local
STORAGE_LOCAL_PATH=/opt/cloudxdevai/storage/projects
AWS_S3_BUCKET=your-cloudxdevai-bucket
AWS_S3_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_S3_ENDPOINT_URL=
STORAGE_FILE_SIZE_LIMIT=100MB
STORAGE_RETENTION_DAYS=90

# Application Configuration
APP_ENV=development
APP_DEBUG=true
APP_HOST=0.0.0.0
APP_PORT=8000
APP_WORKERS=4
APP_RELOAD=true
CORS_ORIGINS=["http://localhost:3000","http://localhost:5173","https://yourdomain.com"]

# Worker Configuration
WORKER_CONCURRENCY=4
WORKER_TIMEOUT=300
WORKER_MAX_JOBS=1000
WORKER_LOG_LEVEL=INFO

# Monitoring & Observability
PROMETHEUS_ENABLED=true
METRICS_PORT=9090
SENTRY_DSN=
LOG_LEVEL=INFO
LOG_FORMAT=json

# External Services
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
SLACK_WEBHOOK_URL=

# Kubernetes/Helm
KUBE_NAMESPACE=cloudxdevai
HELM_RELEASE_NAME=cloudxdevai
HELM_CHART_VERSION=0.1.0

# Development
DEV_SEED_DATA=true
DEV_AUTO_RELOAD=true
```

**File: backend/src/app/config.py**
```python
from pydantic import BaseSettings, validator
from typing import List, Optional
import os

class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql://cloudxdevai:cloudxdevai_password@localhost:5432/cloudxdevai"
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_recycle: int = 3600

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    rq_redis_url: str = "redis://localhost:6379/1"

    # Auth
    jwt_secret_key: str = "your-secret-key-change-in-production"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7
    bcrypt_rounds: int = 12

    # AI
    openai_api_key: Optional[str] = None
    ai_default_model: str = "gpt-4o-mini"
    ai_request_timeout: int = 30

    # Storage
    storage_backend: str = "local"
    storage_local_path: str = "/opt/cloudxdevai/storage/projects"

    # App
    app_env: str = "development"
    app_debug: bool = True
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    cors_origins: List[str] = ["http://localhost:3000"]

    class Config:
        env_file = ".env"
        case_sensitive = False

    @validator('cors_origins', pre=True)
    def parse_cors_origins(cls, v):
        if isinstance(v, str):
            import json
            return json.loads(v)
        return v

    @property
    def is_development(self) -> bool:
        return self.app_env == "development"

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

settings = Settings()
```

#### Validation Steps
```bash
# Test configuration loading
cd backend && python -c "
from src.app.config import settings
print(f'App Environment: {settings.app_env}')
print(f'Database URL: {settings.database_url[:20]}...')
print(f'AI Model: {settings.ai_default_model}')
print('✅ Configuration system functional')
"
```

### Task 1.3: FastAPI Backend Foundation
**Status:** Ready for Implementation  
**Effort:** 2 hours  
**Risk Level:** Medium  

#### Implementation Steps

**File: backend/requirements.txt**
```
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
pydantic-settings==2.1.0
python-dotenv==1.0.0
sqlalchemy==2.0.23
alembic==1.12.1
psycopg2-binary==2.9.9
redis==5.0.1
rq==1.15.1
bcrypt==4.1.2
pyjwt==2.8.0
passlib[bcrypt]==1.7.4
python-multipart==0.0.6
aiofiles==23.2.1
prometheus-client==0.19.0
sentry-sdk[fastapi]==1.38.0
structlog==23.2.0
email-validator==2.1.0
httpx==0.26.0
```

**File: backend/src/app/main.py**
```python
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from prometheus_client import make_asgi_app, Counter, Histogram
import time
import logging
from contextlib import asynccontextmanager

from .config import settings
from .api.main import api_router
from .db.base import create_tables

# Configure structured logging
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency', ['method', 'endpoint'])

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting AI-Cloudx Agent v2.0")
    await create_tables()
    logger.info("Database tables created/verified")

    yield

    # Shutdown
    logger.info("Shutting down AI-Cloudx Agent v2.0")

app = FastAPI(
    title="AI-Cloudx Agent",
    version="2.0.0",
    description="Cloud Development AI Platform",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# Security middleware
if settings.is_production:
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["yourdomain.com"])

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Prometheus metrics middleware
@app.middleware("http")
async def add_prometheus_metrics(request: Request, call_next):
    start_time = time.time()

    response = await call_next(request)

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(time.time() - start_time)

    return response

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Global exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )

# Health check endpoint
@app.get("/healthz")
async def health_check():
    return {
        "status": "healthy",
        "version": "2.0.0",
        "environment": settings.app_env,
        "timestamp": time.time()
    }

# Metrics endpoint
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app, name="metrics")

# API routes
app.include_router(api_router, prefix="/api")

# Root endpoint
@app.get("/")
async def root():
    return {
        "message": "AI-Cloudx Agent API v2.0.0",
        "docs": "/api/docs",
        "health": "/healthz",
        "metrics": "/metrics"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=settings.app_host,
        port=settings.app_port,
        reload=settings.app_reload and settings.is_development,
        workers=settings.app_workers if settings.is_production else 1,
        log_level=settings.log_level.lower()
    )
```

**File: backend/src/app/api/__init__.py**
```python
from fastapi import APIRouter

api_router = APIRouter()

# Import and include sub-routers
from . import auth, users, projects, files, agent, admin

api_router.include_router(auth.router, prefix="/auth", tags=["authentication"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(projects.router, prefix="/projects", tags=["projects"])
api_router.include_router(files.router, prefix="/files", tags=["files"])
api_router.include_router(agent.router, prefix="/agent", tags=["agent"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
```

**File: backend/src/app/api/main.py**
```python
# This will be populated as we implement each API module
from . import auth, users, projects, files, agent, admin
```

#### Validation Steps
```bash
# Test FastAPI startup
cd backend && python -m uvicorn src.app.main:app --host 0.0.0.0 --port 8000 &
sleep 3

# Test health endpoint
curl -s http://localhost:8000/healthz | jq .
# Expected: {"status":"healthy","version":"2.0.0",...}

# Test API docs
curl -s http://localhost:8000/api/docs | head -20

# Kill test server
pkill -f uvicorn
```

---

## 📋 PHASE 2: DATABASE & AUTHENTICATION
**Duration:** 2 weeks  
**Success Criteria:** PostgreSQL database with user authentication, JWT tokens working  

### Task 2.1: PostgreSQL Database Models
**Status:** Ready for Implementation  
**Effort:** 2 hours  
**Risk Level:** Medium  

#### Implementation Steps

**File: backend/src/app/models/base.py**
```python
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import Column, Integer, DateTime, func

Base = declarative_base()

class TimestampMixin:
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)
```

**File: backend/src/app/models/user.py**
```python
from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
from sqlalchemy.orm import relationship
from passlib.context import CryptContext
from .base import Base, TimestampMixin

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class User(Base, TimestampMixin):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    full_name = Column(String)
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)

    # Relationships
    projects = relationship("Project", back_populates="owner")

    def verify_password(self, password: str) -> bool:
        return pwd_context.verify(password, self.hashed_password)

    def hash_password(self, password: str) -> str:
        return pwd_context.hash(password)

    @property
    def is_authenticated(self) -> bool:
        return self.is_active
```

**File: backend/src/app/models/project.py**
```python
from sqlalchemy import Column, Integer, String, Text, Boolean, ForeignKey
from sqlalchemy.orm import relationship
from .base import Base, TimestampMixin

class Project(Base, TimestampMixin):
    __tablename__ = "projects"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(Text)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    storage_backend = Column(String, default="local")  # local, s3
    visibility = Column(String, default="private")  # private, public, shared
    is_active = Column(Boolean, default=True)

    # Relationships
    owner = relationship("User", back_populates="projects")
    files = relationship("FileMeta", back_populates="project")

class FileMeta(Base, TimestampMixin):
    __tablename__ = "file_meta"

    id = Column(Integer, primary_key=True, index=True)
    project_id = Column(Integer, ForeignKey("projects.id"), nullable=False)
    path = Column(String, nullable=False)  # relative path in project
    filename = Column(String, nullable=False)
    size = Column(Integer, nullable=False)
    content_type = Column(String)
    checksum = Column(String, nullable=False)  # SHA256
    version = Column(Integer, default=1)

    # Relationships
    project = relationship("Project", back_populates="files")
```

#### Database Connection and Session Management

**File: backend/src/app/db/base.py**
```python
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session
from ..config import settings

engine = create_engine(
    settings.database_url,
    pool_size=settings.db_pool_size,
    max_overflow=settings.db_max_overflow,
    pool_recycle=settings.db_pool_recycle,
    echo=settings.app_debug
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

async def get_db() -> Session:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def create_tables():
    """Create all tables if they don't exist"""
    Base.metadata.create_all(bind=engine)
```

#### Validation Steps
```bash
# Test database connection and table creation
cd backend && python -c "
import asyncio
from src.app.db.base import create_tables

asyncio.run(create_tables())
print('✅ Database tables created successfully')
"
```

### Task 2.2: JWT Authentication System
**Status:** Ready for Implementation  
**Effort:** 2 hours  
**Risk Level:** Medium  

#### Implementation Steps

**File: backend/src/app/utils/security.py**
```python
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from ..config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.jwt_access_token_expire_minutes)

    to_encode.update({"exp": expire, "type": "access"})
    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret_key, algorithm="HS256")
    return encoded_jwt

def create_refresh_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=settings.jwt_refresh_token_expire_days)
    to_encode.update({"exp": expire, "type": "refresh"})
    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret_key, algorithm="HS256")
    return encoded_jwt

def verify_token(token: str, token_type: str = "access"):
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=["HS256"])
        if payload.get("type") != token_type:
            return None
        return payload
    except JWTError:
        return None

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)
```

**File: backend/src/app/utils/deps.py**
```python
from typing import Generator
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from jose import JWTError, jwt

from ..db.base import get_db
from ..models.user import User
from ..config import settings

security = HTTPBearer()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(credentials.credentials, settings.jwt_secret_key, algorithms=["HS256"])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise credentials_exception

    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")

    return user

def get_current_active_superuser(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_superuser:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not enough permissions"
        )
    return current_user
```

### Task 2.3: Authentication API Implementation
**Status:** Ready for Implementation  
**Effort:** 2 hours  
**Risk Level:** Medium  

#### Implementation Steps

**File: backend/src/app/api/auth.py**
```python
from datetime import timedelta
from typing import Any
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session

from .. import models, schemas
from ..utils import security
from ..db.base import get_db
from ..config import settings

router = APIRouter()

@router.post("/login", response_model=schemas.Token)
async def login(
    db: Session = Depends(get_db),
    form_data: OAuth2PasswordRequestForm = Depends()
) -> Any:
    user = db.query(models.User).filter(models.User.email == form_data.username).first()
    if not user or not user.verify_password(form_data.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Inactive user"
        )

    access_token_expires = timedelta(minutes=settings.jwt_access_token_expire_minutes)
    access_token = security.create_access_token(
        data={"sub": str(user.id)}, expires_delta=access_token_expires
    )
    refresh_token = security.create_refresh_token(data={"sub": str(user.id)})

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user": schemas.User.from_orm(user)
    }

@router.post("/register", response_model=schemas.User)
async def register(
    user_in: schemas.UserCreate,
    db: Session = Depends(get_db),
) -> Any:
    # Check if user already exists
    user = db.query(models.User).filter(
        (models.User.email == user_in.email) | (models.User.username == user_in.username)
    ).first()
    if user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User with this email or username already exists"
        )

    # Create new user
    user = models.User(
        email=user_in.email,
        username=user_in.username,
        hashed_password=models.User.hash_password(None, user_in.password),
        full_name=user_in.full_name,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return user

@router.post("/refresh", response_model=schemas.Token)
async def refresh_token(
    refresh_token: str,
    db: Session = Depends(get_db)
) -> Any:
    payload = security.verify_token(refresh_token, "refresh")
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )

    user_id = payload.get("sub")
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive"
        )

    access_token_expires = timedelta(minutes=settings.jwt_access_token_expire_minutes)
    access_token = security.create_access_token(
        data={"sub": str(user.id)}, expires_delta=access_token_expires
    )
    new_refresh_token = security.create_refresh_token(data={"sub": str(user.id)})

    return {
        "access_token": access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer",
        "user": schemas.User.from_orm(user)
    }
```

**File: backend/src/app/schemas/__init__.py**
```python
from .user import User, UserCreate, UserUpdate
from .token import Token
from .project import Project, ProjectCreate, ProjectUpdate
from .file import FileMeta, FileUpload, FileInfo
```

**File: backend/src/app/schemas/user.py**
```python
from typing import Optional
from pydantic import BaseModel, EmailStr
from .base import BaseSchema

class UserBase(BaseSchema):
    email: EmailStr
    username: str
    full_name: Optional[str] = None
    is_active: bool = True
    is_superuser: bool = False

class UserCreate(UserBase):
    password: str

class UserUpdate(UserBase):
    password: Optional[str] = None

class User(UserBase):
    id: int

    class Config:
        orm_mode = True
```

**File: backend/src/app/schemas/token.py**
```python
from typing import Any
from pydantic import BaseModel
from .user import User

class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: User
```

#### Validation Steps
```bash
# Test authentication endpoints
cd backend && python -m uvicorn src.app.main:app --host 0.0.0.0 --port 8000 &
sleep 3

# Test health check
curl -s http://localhost:8000/healthz

# Test API docs access
curl -s http://localhost:8000/api/docs | head -10

# Kill server
pkill -f uvicorn
```

---

## 📋 PHASE 3: FILE STORAGE & CORE API
**Duration:** 2 weeks  
**Success Criteria:** File upload/download working, projects manageable, AI agent API functional  

### Task 3.1: Storage Abstraction Layer
**Status:** Ready for Implementation  
**Effort:** 2 hours  
**Risk Level:** Medium  

#### Implementation Steps

**File: backend/src/app/storage/base.py**
```python
from abc import ABC, abstractmethod
from typing import BinaryIO, Dict, List, Optional
from pathlib import Path

class StorageBackend(ABC):
    @abstractmethod
    async def upload_file(self, project_id: str, file_path: str, file_obj: BinaryIO, content_type: str = None) -> Dict:
        """Upload a file and return metadata"""
        pass

    @abstractmethod
    async def download_file(self, project_id: str, file_path: str) -> BinaryIO:
        """Download a file"""
        pass

    @abstractmethod
    async def delete_file(self, project_id: str, file_path: str) -> bool:
        """Delete a file"""
        pass

    @abstractmethod
    async def list_files(self, project_id: str, prefix: str = "") -> List[Dict]:
        """List files in project with optional prefix"""
        pass

    @abstractmethod
    async def get_file_info(self, project_id: str, file_path: str) -> Dict:
        """Get file metadata"""
        pass
```

**File: backend/src/app/storage/local.py**
```python
import os
import hashlib
import aiofiles
from pathlib import Path
from typing import BinaryIO, Dict, List
from .base import StorageBackend
from ..config import settings

class LocalStorageBackend(StorageBackend):
    def __init__(self):
        self.base_path = Path(settings.storage_local_path)
        self.base_path.mkdir(parents=True, exist_ok=True)

    def _get_project_path(self, project_id: str) -> Path:
        return self.base_path / str(project_id)

    def _calculate_checksum(self, file_obj: BinaryIO) -> str:
        hash_sha256 = hashlib.sha256()
        file_obj.seek(0)
        for chunk in iter(lambda: file_obj.read(4096), b""):
            hash_sha256.update(chunk)
        file_obj.seek(0)
        return hash_sha256.hexdigest()

    async def upload_file(self, project_id: str, file_path: str, file_obj: BinaryIO, content_type: str = None) -> Dict:
        project_path = self._get_project_path(project_id)
        project_path.mkdir(parents=True, exist_ok=True)

        full_path = project_path / file_path
        full_path.parent.mkdir(parents=True, exist_ok=True)

        checksum = self._calculate_checksum(file_obj)

        async with aiofiles.open(full_path, 'wb') as f:
            await f.write(file_obj.read())

        file_size = full_path.stat().st_size

        return {
            "path": file_path,
            "size": file_size,
            "checksum": checksum,
            "content_type": content_type,
            "storage_path": str(full_path)
        }

    async def download_file(self, project_id: str, file_path: str) -> BinaryIO:
        project_path = self._get_project_path(project_id)
        full_path = project_path / file_path

        if not full_path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        return open(full_path, 'rb')

    async def delete_file(self, project_id: str, file_path: str) -> bool:
        project_path = self._get_project_path(project_id)
        full_path = project_path / file_path

        if full_path.exists():
            full_path.unlink()
            return True
        return False

    async def list_files(self, project_id: str, prefix: str = "") -> List[Dict]:
        project_path = self._get_project_path(project_id)
        if not project_path.exists():
            return []

        files = []
        for file_path in project_path.rglob("*"):
            if file_path.is_file():
                rel_path = file_path.relative_to(project_path)
                if str(rel_path).startswith(prefix):
                    files.append({
                        "path": str(rel_path),
                        "size": file_path.stat().st_size,
                        "modified": file_path.stat().st_mtime
                    })

        return files

    async def get_file_info(self, project_id: str, file_path: str) -> Dict:
        project_path = self._get_project_path(project_id)
        full_path = project_path / file_path

        if not full_path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        stat = full_path.stat()
        return {
            "path": file_path,
            "size": stat.st_size,
            "modified": stat.st_mtime,
            "exists": True
        }
```

**File: backend/src/app/storage/s3.py**
```python
import boto3
import aiofiles
from typing import BinaryIO, Dict, List
from botocore.exceptions import ClientError
from .base import StorageBackend
from ..config import settings

class S3StorageBackend(StorageBackend):
    def __init__(self):
        self.s3_client = boto3.client(
            's3',
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            region_name=settings.aws_s3_region,
            endpoint_url=settings.aws_s3_endpoint_url
        )
        self.bucket = settings.aws_s3_bucket

    async def upload_file(self, project_id: str, file_path: str, file_obj: BinaryIO, content_type: str = None) -> Dict:
        key = f"{project_id}/{file_path}"

        # Calculate checksum
        import hashlib
        hash_sha256 = hashlib.sha256()
        file_obj.seek(0)
        for chunk in iter(lambda: file_obj.read(4096), b""):
            hash_sha256.update(chunk)
        checksum = hash_sha256.hexdigest()
        file_obj.seek(0)

        # Upload to S3
        extra_args = {}
        if content_type:
            extra_args['ContentType'] = content_type

        self.s3_client.upload_fileobj(
            file_obj,
            self.bucket,
            key,
            ExtraArgs=extra_args
        )

        # Get file size
        file_obj.seek(0, 2)
        size = file_obj.tell()
        file_obj.seek(0)

        return {
            "path": file_path,
            "size": size,
            "checksum": checksum,
            "content_type": content_type,
            "s3_key": key
        }

    async def download_file(self, project_id: str, file_path: str) -> BinaryIO:
        import io
        key = f"{project_id}/{file_path}"

        buffer = io.BytesIO()
        self.s3_client.download_fileobj(self.bucket, key, buffer)
        buffer.seek(0)
        return buffer

    async def delete_file(self, project_id: str, file_path: str) -> bool:
        key = f"{project_id}/{file_path}"
        try:
            self.s3_client.delete_object(Bucket=self.bucket, Key=key)
            return True
        except ClientError:
            return False

    async def list_files(self, project_id: str, prefix: str = "") -> List[Dict]:
        key_prefix = f"{project_id}/"
        if prefix:
            key_prefix += prefix

        files = []
        paginator = self.s3_client.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=self.bucket, Prefix=key_prefix):
            for obj in page.get('Contents', []):
                files.append({
                    "path": obj['Key'].replace(key_prefix, "", 1),
                    "size": obj['Size'],
                    "modified": obj['LastModified'].timestamp()
                })

        return files

    async def get_file_info(self, project_id: str, file_path: str) -> Dict:
        key = f"{project_id}/{file_path}"
        try:
            response = self.s3_client.head_object(Bucket=self.bucket, Key=key)
            return {
                "path": file_path,
                "size": response['ContentLength'],
                "modified": response['LastModified'].timestamp(),
                "content_type": response.get('ContentType'),
                "exists": True
            }
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                raise FileNotFoundError(f"File not found: {file_path}")
            raise
```

**File: backend/src/app/storage/__init__.py**
```python
from ..config import settings
from .base import StorageBackend
from .local import LocalStorageBackend
from .s3 import S3StorageBackend

def get_storage_backend() -> StorageBackend:
    if settings.storage_backend == "s3":
        return S3StorageBackend()
    else:
        return LocalStorageBackend()
```

---

## 📋 IMPLEMENTATION VALIDATION PROTOCOL

### Pre-Implementation Verification
**For Each Task:**
1. [ ] Dependencies installed and verified
2. [ ] Configuration files validated
3. [ ] Directory structure confirmed
4. [ ] Backup of existing state created

### Implementation Validation
**For Each Task:**
1. [ ] Code syntax validated (imports, types, etc.)
2. [ ] Unit tests pass (if implemented)
3. [ ] Integration tests pass
4. [ ] Manual testing successful
5. [ ] Documentation updated

### Post-Implementation Validation
**For Each Phase:**
1. [ ] Health checks pass
2. [ ] Smoke tests successful
3. [ ] Performance benchmarks met
4. [ ] Security scan clean
5. [ ] Documentation complete

### Rollback Readiness
**For Each Task:**
1. [ ] Rollback script available
2. [ ] Backup restoration tested
3. [ ] Data migration reversible
4. [ ] Service restart procedures documented

---

## 🚀 EXECUTION CHECKLIST

### Phase 1 Foundation (Week 1-2)
- [ ] Task 1.1: Directory structure created
- [ ] Task 1.2: Environment configuration system
- [ ] Task 1.3: FastAPI backend foundation
- [ ] **Phase 1 Validation:** Backend serves health checks

### Phase 2 Database & Auth (Week 3-4)
- [ ] Task 2.1: PostgreSQL database models
- [ ] Task 2.2: JWT authentication system
- [ ] Task 2.3: Authentication API implementation
- [ ] **Phase 2 Validation:** User registration/login working

### Phase 3 File Storage & Core API (Week 5-6)
- [ ] Task 3.1: Storage abstraction layer
- [ ] Task 3.2: Projects API implementation
- [ ] Task 3.3: Files API implementation
- [ ] Task 3.4: AI Agent API integration
- [ ] **Phase 3 Validation:** File operations working, AI tasks functional

### Success Metrics
- **Code Quality:** 95% test coverage, zero critical issues
- **Performance:** <1s API response times, <5s file operations
- **Reliability:** 99.9% uptime, comprehensive error handling
- **Security:** All endpoints authenticated, input validated
- **Documentation:** Complete API docs, deployment guides

**Total Implementation Time:** 6 weeks  
**Risk Level:** Low (incremental, tested approach)  
**Success Probability:** High (detailed specification, validation protocols)

Ready for MAX-LOGIC execution! 🎯