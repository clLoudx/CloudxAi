# Deployment Guide

## AI-Cloudx Agent Deployment Options

This guide covers different deployment options for the AI-Cloudx Agent.

## Deployment Modes

### 1. Local/Systemd Deployment

Best for:
- Single server deployments
- Development environments
- Simple production setups

**Characteristics:**
- Runs as systemd service
- Single process
- Direct file system access
- Simple monitoring

**Deployment:**
```bash
sudo ./installer_master.sh
```

### 2. Kubernetes/Helm Deployment

Best for:
- Production environments
- High availability requirements
- Scalable deployments
- Multi-node clusters

**Characteristics:**
- Containerized deployment
- Horizontal scaling
- Service discovery
- Load balancing

**Deployment:**
```bash
sudo ./installer_master.sh --kube-deploy \
    --kubeconfig ~/.kube/config \
    --namespace aiagent
```

### 3. Docker Compose Deployment

Best for:
- Development
- Testing
- Single-node containerized deployments

**Deployment:**
```bash
cd ai-agent
docker-compose up -d
```

## Deployment Checklist

### Pre-Deployment

- [ ] Run production checks: `./devops/tools/production_checks.sh --mode <local|kube>`
- [ ] Verify disk space (minimum 2GB)
- [ ] Verify network connectivity
- [ ] Check required dependencies
- [ ] Review security settings

### During Deployment

- [ ] Monitor installation logs
- [ ] Verify service startup
- [ ] Check for errors

### Post-Deployment

- [ ] Run smoke tests
- [ ] Verify health endpoints
- [ ] Check service status
- [ ] Review logs
- [ ] Test functionality

## Configuration

### Environment Variables

Configuration is stored in `/etc/ai-agent/env`:

```bash
# Required
OPENAI_API_KEY=sk-xxxx
API_KEY=your-admin-api-key
REDIS_URL=redis://127.0.0.1:6379/0

# Optional
AI_TASK_DIR=/tmp/ai_tasks
FLASK_SECRET=your-secret-key
```

### Helm Values (Kubernetes)

Customize deployment via Helm values:

```yaml
# values-production.yaml
replicaCount: 3
image:
  repository: aiagent_web
  tag: latest
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

Deploy with custom values:
```bash
sudo ./installer_master.sh --kube-deploy \
    --helm-values values-production.yaml
```

## Scaling

### Local Mode
- Single instance only
- For scaling, use Kubernetes mode

### Kubernetes Mode
- Scale deployments:
  ```bash
  kubectl -n aiagent scale deployment aiagent --replicas=3
  ```
- Or update Helm values:
  ```yaml
  replicaCount: 3
  ```

## Monitoring

### Health Checks

**Local:**
- Endpoint: `http://127.0.0.1:8000/healthz`
- Systemd: `systemctl status aiagent.service`

**Kubernetes:**
- Liveness probe: `/healthz`
- Readiness probe: `/healthz`
- Check pods: `kubectl -n aiagent get pods`

### Logs

**Local:**
- Service logs: `journalctl -u aiagent.service`
- Installer logs: `/var/log/aiagent_local_installer.log`

**Kubernetes:**
- Pod logs: `kubectl -n aiagent logs <pod-name>`
- All pods: `kubectl -n aiagent logs -l app=aiagent`

## Backup and Recovery

See [UPGRADE.md](UPGRADE.md) for backup and rollback procedures.

## Security Considerations

1. **File Permissions:**
   - `/etc/ai-agent/env` should be 600
   - Service runs as `aiagent` user (not root)

2. **Network:**
   - Health endpoint should be internal only
   - Use ingress/load balancer for external access

3. **Secrets:**
   - Store API keys securely
   - Use Kubernetes secrets in kube mode
   - Rotate keys regularly

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for deployment issues.

