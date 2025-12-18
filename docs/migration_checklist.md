# AI-Cloudx Migration Checklist (Zero → Production)

## Phase 0: Backup
- [ ] Backup current repository
- [ ] Backup existing /opt installations
- [ ] Snapshot database (if exists)

## Phase 1: Path Normalization
- [ ] Replace all `/opt/aiagent` → `/opt/ai-agent`
- [ ] Update systemd service paths
- [ ] Verify no hardcoded legacy paths remain

## Phase 2: Helm Consolidation
- [ ] Confirm devops/helm/aiagent is canonical
- [ ] Archive charts/aiagent to .deprecated/
- [ ] Update CI workflows to new path

## Phase 3: Installer Consolidation
- [ ] Keep installer_master.sh
- [ ] Extract installer_local.sh
- [ ] Extract installer_kube.sh
- [ ] Archive all legacy installers

## Phase 4: Smoke Tests
- [ ] Merge root smoke_tests → devops/smoke_tests
- [ ] Ensure CI uses devops/smoke_tests/ci_wrapper.sh
- [ ] Run smoke tests locally

## Phase 5: Healthcheck
- [ ] Merge ai-agent/modules/healthcheck.sh → devops/tools/healthcheck.sh
- [ ] Remove duplicate healthcheck modules

## Phase 6: Systemd
- [ ] Use devops/systemd/aiagent.service only
- [ ] Ensure user=aiagent
- [ ] Reload daemon and test service

## Phase 7: CI/CD
- [ ] CI builds ZIP
- [ ] CI runs smoke tests
- [ ] CI fails on first error

## Phase 8: Validation
- [ ] Local install works
- [ ] K8s install works
- [ ] Upgrade path works
- [ ] Uninstall works

