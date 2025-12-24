#!/usr/bin/env python3
"""Generate a weekly beta stability report from BETA_OBSERVATIONS.md

This script is read-only with respect to source files except for creating a new
weekly report in `docs/weekly_reports/` (append-only for reports). It follows the
MAX-LOGIC invariants: observational, additive, no code changes, no CI edits.
"""
from __future__ import annotations
import os, datetime, re

REPO = os.path.abspath(os.path.dirname(os.path.dirname(__file__)))
OBS_PATH = os.path.join(REPO, 'BETA_OBSERVATIONS.md')
OUT_DIR = os.path.join(REPO, 'docs', 'weekly_reports')
os.makedirs(OUT_DIR, exist_ok=True)

def now_datestr():
    t = datetime.datetime.utcnow()
    week_start = (t - datetime.timedelta(days=t.weekday())).date()
    week_end = week_start + datetime.timedelta(days=6)
    return week_start.isoformat(), week_end.isoformat(), t.strftime('%Y%m%dT%H%M%SZ')

def parse_observations():
    try:
        with open(OBS_PATH, 'r', encoding='utf-8') as fh:
            data = fh.read()
    except Exception:
        return []
    # Split by timestamp lines that look like 2025-12-24T..Z
    entries = re.split(r'\n(?=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)', data)
    parsed = []
    for e in entries:
        e = e.strip()
        if not e:
            continue
        parsed.append(e)
    return parsed

def analyze(entries):
    metrics_present = set()
    artifacts = []
    cardinality_rejections = 0
    for e in entries:
        if 'tenant_readiness_state' in e:
            metrics_present.add('tenant_readiness_state')
        if 'tenant_label_rejections_total' in e:
            metrics_present.add('tenant_label_rejections_total')
            # crude count of mentions
            cardinality_rejections += e.count('tenant_label_rejections_total')
        if 'tenant_cost_estimate' in e:
            metrics_present.add('tenant_cost_estimate')
        # artifacts
        for token in ('devops/grafana/dashboards/tenant_readiness_dashboard.json', 'devops/alerts/tenant_alerts.yaml', '.github/workflows/observability.yml'):
            if token in e and token not in artifacts:
                artifacts.append(token)
    return dict(
        metrics_present=sorted(list(metrics_present)),
        artifacts=artifacts,
        cardinality_mentions=cardinality_rejections,
        entries_count=len(entries)
    )

def render_report(week_start, week_end, ts, analysis):
    lines = []
    lines.append(f"# Weekly Beta Stability Report — {week_start} to {week_end}")
    lines.append('')
    lines.append(f"Generated: {ts}")
    lines.append('Author: automation-agent (MAX-LOGIC)')
    lines.append('')
    lines.append('## Executive summary')
    lines.append('This automated weekly stability report summarizes passive, file-based observations for the beta window. No network scraping was performed by this run.')
    lines.append('')
    lines.append('## Key metrics (passive file evidence)')
    lines.append(f"- Observed entries: {analysis['entries_count']}")
    lines.append(f"- Metrics referenced: {', '.join(analysis['metrics_present']) or 'none detected'}")
    lines.append(f"- Cardinality-related mentions: {analysis['cardinality_mentions']}")
    lines.append('')
    lines.append('## Artifacts present (passive evidence)')
    for a in analysis['artifacts']:
        lines.append(f"- {a}")
    lines.append('')
    lines.append('## Notes & recommendations (draft-only)')
    lines.append('- This report is draft-only. For live metric trend analysis, configure the nightly observability scrape in staging per `docs/V1_0_PR_SEQUENCE.md`.')
    lines.append('- If cardinality mentions increase in future runs, open an incident per `BETA_INCIDENT_LOG.md`.')
    lines.append('')
    lines.append('## Evidence (raw excerpts)')
    lines.append('---')
    return '\n'.join(lines)

def main():
    week_start, week_end, ts = now_datestr()
    entries = parse_observations()
    analysis = analyze(entries)
    report = render_report(week_start, week_end, ts, analysis)
    outname = f"weekly_report_{week_start}_to_{week_end}_{ts}.md"
    outpath = os.path.join(OUT_DIR, outname)
    with open(outpath, 'w', encoding='utf-8') as fh:
        fh.write(report)
    print('Weekly report written to', outpath)

if __name__ == '__main__':
    main()
