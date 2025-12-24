#!/usr/bin/env python3
"""Beta monitor script (observational only)

This script performs passive repository and file checks to gather beta-stabilization
observations and appends them to `BETA_OBSERVATIONS.md`. If an active incident is
detected (missing metric definitions, missing dashboard or alert files), it appends
an entry to `BETA_INCIDENT_LOG.md`.

This is a helper for operators. It performs only local file inspections and does not
make network calls or modify source code. Scheduling should be done externally.
"""
from __future__ import annotations
import os, sys, datetime, json

ROOT = os.path.dirname(os.path.dirname(__file__))
REPO = os.path.abspath(ROOT)

def now_ts():
    return datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'

def file_exists(path):
    return os.path.exists(os.path.join(REPO, path))

def grep_in_file(path, needle):
    p = os.path.join(REPO, path)
    try:
        with open(p, 'r', encoding='utf-8') as fh:
            return needle in fh.read()
    except Exception:
        return False

def append_observation(text):
    p = os.path.join(REPO, 'BETA_OBSERVATIONS.md')
    with open(p, 'a', encoding='utf-8') as fh:
        fh.write('\n' + text + '\n')

def append_incident(entry):
    p = os.path.join(REPO, 'BETA_INCIDENT_LOG.md')
    with open(p, 'a', encoding='utf-8') as fh:
        fh.write('\n' + entry + '\n')

def run_checks():
    ts = now_ts()
    obs = [f"{ts} — automated beta monitor run"]
    incidents = []

    # Check metric definitions referenced in runbook/specs
    checks = {
        'tenant_readiness_state': ('ai-agent/dashboard/app.py', 'tenant_readiness_state'),
        'tenant_label_rejections_total': ('ai-agent/dashboard/app.py', 'tenant_label_rejections_total'),
        'tenant_cost_estimate': ('devops/grafana/dashboards/tenant_readiness_dashboard.json', 'tenant_cost_estimate')
    }

    for name, (file_path, needle) in checks.items():
        present = grep_in_file(file_path, needle)
        obs.append(f"- {name}: {'present' if present else 'MISSING'} (checked {file_path})")
        if not present:
            incidents.append((name, file_path))

    # Check dashboards and alerts exist
    dash = 'devops/grafana/dashboards/tenant_readiness_dashboard.json'
    alerts = 'devops/alerts/tenant_alerts.yaml'
    routing = 'devops/alerts/alertmanager-routing.yaml'
    for path in (dash, alerts, routing):
        if file_exists(path):
            obs.append(f"- artifact: {path} exists")
        else:
            obs.append(f"- artifact: {path} MISSING")
            incidents.append((os.path.basename(path), path))

    # Check CI workflow presence
    ci = '.github/workflows/observability.yml'
    obs.append(f"- ci_workflow_observability: {'present' if file_exists(ci) else 'MISSING'}")
    if not file_exists(ci):
        incidents.append(('observability_workflow', ci))

    # Append observation summary
    summary = '\n'.join(obs)
    append_observation(summary)

    # If incidents, append structured incident entries
    if incidents:
        for name, path in incidents:
            entry = f"{ts} - INCIDENT - trigger: missing_artifact_or_metric - evidence: {name} at {path} - immediate_action: logged"
            append_incident(entry)

    print('Beta monitor run complete. Observations appended to BETA_OBSERVATIONS.md')

if __name__ == '__main__':
    run_checks()
