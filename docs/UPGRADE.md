# Upgrade Guide

## AI-Cloudx Agent Upgrade Procedures

This guide covers safe upgrade and rollback procedures for the AI-Cloudx Agent.

## Upgrade Process

### Automatic Upgrade

The recommended way to upgrade:

```bash
sudo ./installers/upgrade.sh
```

**What it does:**
1. Detects current installation
2. Creates backup
3. Runs installer_master.sh
4. Verifies health
5. Rolls back on failure

### Manual Upgrade

If you need more control:

```bash
# 1. Create backup
sudo ./installers/upgrade.sh --backup-dir /custom/backup/path

# 2. Run installer
sudo ./installer_master.sh --non-interactive

# 3. Verify
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000
```

## Backup

### Automatic Backup

Upgrade script automatically creates backups:
- Location: `/var/backups/aiagent_upgrade_TIMESTAMP/`
- Includes: installation directory, systemd services, configuration

### Manual Backup

```bash
# Backup installation
tar -czf /backup/aiagent_$(date +%Y%m%d).tar.gz -C /opt ai-agent

# Backup configuration
cp -a /etc/ai-agent /backup/ai-agent-config

# Backup systemd services
mkdir -p /backup/systemd
cp /etc/systemd/system/aiagent.service /backup/systemd/
```

## Rollback

### Automatic Rollback

If upgrade fails, automatic rollback is triggered:

```bash
sudo ./installers/upgrade.sh
# If upgrade fails, rollback happens automatically
```

### Manual Rollback

```bash
sudo ./installers/rollback.sh --backup-dir /var/backups/aiagent_upgrade_TIMESTAMP
```

**What it does:**
1. Stops services
2. Restores installation directory
3. Restores systemd services
4. Restores configuration
5. Restarts services
6. Verifies health

## Upgrade Scenarios

### Scenario 1: Standard Upgrade

```bash
# Simple upgrade
sudo ./installers/upgrade.sh
```

### Scenario 2: Upgrade with Custom Backup

```bash
sudo ./installers/upgrade.sh --backup-dir /custom/backup/path
```

### Scenario 3: Upgrade Without Rollback

```bash
sudo ./installers/upgrade.sh --no-rollback
```

### Scenario 4: Dry-Run Upgrade

```bash
sudo ./installers/upgrade.sh --dry-run
```

## Kubernetes Upgrade

For Kubernetes deployments:

```bash
# Upgrade via Helm
helm upgrade aiagent devops/helm/aiagent -n aiagent

# Or use installer
sudo ./installer_master.sh --kube-deploy --non-interactive
```

## Path Migration

If upgrading from legacy path (`/opt/aiagent`) to canonical path (`/opt/ai-agent`):

1. Upgrade script detects legacy installation
2. Creates backup
3. Installs to canonical path
4. Migrates data if needed

## Verification

After upgrade, verify:

```bash
# Check service status
systemctl status aiagent.service

# Check health endpoint
curl http://127.0.0.1:8000/healthz

# Run smoke tests
./devops/tools/post_deploy_smoke.sh local aiagent-web /healthz 8000

# Run production checks
./devops/tools/production_checks.sh --mode local
```

## Troubleshooting Upgrades

### Issue: Upgrade Fails

1. Check logs: `/var/log/aiagent_upgrade_TIMESTAMP.log`
2. Review backup: `/var/backups/aiagent_upgrade_TIMESTAMP/`
3. Manual rollback if needed

### Issue: Service Won't Start After Upgrade

1. Check service logs: `journalctl -u aiagent.service`
2. Verify configuration: `/etc/ai-agent/env`
3. Check file permissions
4. Rollback if necessary

### Issue: Health Checks Fail

1. Check service status
2. Review application logs
3. Verify dependencies
4. Consider rollback

## Best Practices

1. **Always backup before upgrade**
2. **Test upgrades in staging first**
3. **Monitor during upgrade**
4. **Verify after upgrade**
5. **Keep backups for 30 days**

## Rollback Window

- Backups are kept in `/var/backups/`
- Recommended: Keep backups for 30 days
- Manual cleanup: `rm -rf /var/backups/aiagent_upgrade_*`

## Related Documentation

- [Installation Guide](INSTALLATION.md)
- [Deployment Guide](DEPLOYMENT.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

