# Troubleshooting Guide

## AI-Cloudx Agent Troubleshooting

Common issues and solutions for the AI-Cloudx Agent.

## Installation Issues

### Issue: Installer Fails with "Permission Denied"

**Solution:**
```bash
# Ensure running as root
sudo ./installer_master.sh
```

### Issue: "Chart directory not found"

**Solution:**
- Verify chart exists: `ls -la devops/helm/aiagent/`
- Check you're in repository root
- Run: `./generate_devops_and_files.sh` to regenerate charts

### Issue: "Service file missing"

**Solution:**
- Verify service file: `ls -la devops/systemd/aiagent.service`
- Check installation path: `/opt/ai-agent`

## Service Issues

### Issue: Service Won't Start

**Diagnosis:**
```bash
# Check service status
systemctl status aiagent.service

# Check logs
journalctl -u aiagent.service -n 50

# Check if service file exists
ls -la /etc/systemd/system/aiagent.service
```

**Common Causes:**
1. Wrong path in service file
2. Missing dependencies
3. Permission issues
4. Configuration errors

**Solutions:**
```bash
# Verify path
grep WorkingDirectory /etc/systemd/system/aiagent.service

# Check permissions
ls -la /opt/ai-agent

# Reinstall service
sudo cp devops/systemd/aiagent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart aiagent.service
```

### Issue: Service Starts But Crashes

**Diagnosis:**
```bash
# Check recent logs
journalctl -u aiagent.service --since "10 minutes ago"

# Check Python environment
/opt/ai-agent/venv/bin/python --version

# Check dependencies
/opt/ai-agent/venv/bin/pip list
```

**Solutions:**
```bash
# Reinstall Python dependencies
/opt/ai-agent/venv/bin/pip install -r /opt/ai-agent/ai-agent/requirements.txt

# Check configuration
cat /etc/ai-agent/env

# Run emergency repair
sudo ./tools/emergency-total-repair.sh --full-auto
```

## Health Check Issues

### Issue: Health Endpoint Returns 503

**Diagnosis:**
```bash
# Check if service is running
systemctl is-active aiagent.service

# Test endpoint directly
curl -v http://127.0.0.1:8000/healthz

# Check application logs
journalctl -u aiagent.service -n 100
```

**Solutions:**
1. Restart service: `sudo systemctl restart aiagent.service`
2. Check application configuration
3. Verify dependencies are installed

### Issue: Smoke Tests Fail

**Diagnosis:**
```bash
# Run smoke tests with verbose output
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000

# Check healthcheck module
source devops/tools/healthcheck.sh
http_check_with_retry http://127.0.0.1:8000/healthz 5 2
```

**Solutions:**
1. Verify service is running
2. Check firewall rules
3. Verify port 8000 is not blocked
4. Check application logs

## Path Issues

### Issue: "Installation path not found"

**Problem:** Mixed use of `/opt/aiagent` and `/opt/ai-agent`

**Solution:**
```bash
# Detect current installation
ls -la /opt/ai-agent /opt/aiagent

# Migrate if needed
sudo ./tools/emergency-total-repair.sh --full-auto
```

### Issue: Service References Wrong Path

**Solution:**
```bash
# Update service file
sudo sed -i 's|/opt/aiagent|/opt/ai-agent|g' /etc/systemd/system/aiagent.service
sudo systemctl daemon-reload
sudo systemctl restart aiagent.service
```

## Kubernetes Issues

### Issue: Pods Not Starting

**Diagnosis:**
```bash
# Check pod status
kubectl -n aiagent get pods

# Check pod logs
kubectl -n aiagent logs <pod-name>

# Check events
kubectl -n aiagent get events
```

**Solutions:**
1. Check resource limits
2. Verify image pull secrets
3. Check configuration
4. Review pod events

### Issue: Helm Deployment Fails

**Diagnosis:**
```bash
# Check Helm release status
helm -n aiagent status aiagent

# Check Helm history
helm -n aiagent history aiagent

# Dry-run deployment
helm upgrade --install aiagent devops/helm/aiagent -n aiagent --dry-run
```

**Solutions:**
1. Verify chart is valid: `helm lint devops/helm/aiagent`
2. Check namespace exists
3. Verify dependencies (cert-manager, ingress-nginx)
4. Check resource quotas

## Emergency Repair

### Run Full Repair

```bash
sudo ./tools/emergency-total-repair.sh --full-auto \
    --repair-systemd \
    --wget-fallback \
    --self-heal \
    --restart-agent \
    --non-interactive
```

### Repair Specific Components

```bash
# Repair Python environment
sudo ./tools/emergency-total-repair.sh --venv-path /opt/ai-agent/venv

# Repair systemd service
sudo ./tools/emergency-total-repair.sh --repair-systemd

# Repair and restart
sudo ./tools/emergency-total-repair.sh --restart-agent
```

## Diagnostic Commands

### System Health

```bash
# Production checks
./devops/tools/production_checks.sh --mode local --strict

# Service status
systemctl status aiagent.service

# Disk space
df -h

# Memory
free -h
```

### Application Health

```bash
# Health endpoint
curl http://127.0.0.1:8000/healthz

# Smoke tests
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000

# Check imports
./devops/smoke_tests/check_imports.sh
```

### Logs

```bash
# Service logs
journalctl -u aiagent.service -f

# Installer logs
tail -f /var/log/aiagent_local_installer.log

# Application logs (if available)
tail -f /opt/ai-agent/logs/*.log
```

## Common Error Messages

### "Module not found"

**Solution:**
```bash
# Reinstall Python dependencies
/opt/ai-agent/venv/bin/pip install -r /opt/ai-agent/ai-agent/requirements.txt
```

### "Permission denied"

**Solution:**
```bash
# Fix ownership
sudo chown -R aiagent:aiagent /opt/ai-agent

# Fix permissions
sudo chmod 755 /opt/ai-agent
```

### "Port already in use"

**Solution:**
```bash
# Find process using port
sudo lsof -i :8000

# Kill process or change port in configuration
```

## Getting Help

1. Check logs first
2. Run diagnostic commands
3. Review documentation
4. Check GitHub issues
5. Contact support

## Related Documentation

- [Installation Guide](INSTALLATION.md)
- [Deployment Guide](DEPLOYMENT.md)
- [Upgrade Guide](UPGRADE.md)

