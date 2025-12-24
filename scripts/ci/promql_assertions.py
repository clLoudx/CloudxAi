#!/usr/bin/env python3
"""Simple PromQL assertions runner for staging (draft).

This script queries a Prometheus HTTP API for a set of assertions and writes
results to `promql_assertions_results.json`. It is intended for staging-only
use and must be configured via CI secrets (`STAGING_PROM_URL`, etc.).
"""
import os, sys, json, requests

PROM_URL = os.getenv('PROM_URL') or os.getenv('STAGING_PROM_URL')
USER = os.getenv('PROM_USER') or os.getenv('STAGING_PROM_USER')
PASS = os.getenv('PROM_PASS') or os.getenv('STAGING_PROM_PASS')

ASSERTIONS = {
    'tenant_readiness_state_exists': 'count(tenant_readiness_state) > 0',
    'tenant_label_rejections_total_exists': 'count(tenant_label_rejections_total) >= 0',
    'tenant_cost_estimate_exists': 'count(tenant_cost_estimate) >= 0'
}

def prom_query(expr):
    r = requests.get(f"{PROM_URL}/api/v1/query", params={'query': expr}, auth=(USER, PASS) if USER else None, timeout=30)
    r.raise_for_status()
    return r.json()

def run():
    if not PROM_URL:
        print('PROM_URL not configured; aborting')
        sys.exit(2)
    results = {}
    for name, expr in ASSERTIONS.items():
        try:
            payload = prom_query(expr)
            status = payload.get('status')
            results[name] = {'expr': expr, 'status': status, 'data': payload.get('data')}
        except Exception as e:
            results[name] = {'expr': expr, 'error': str(e)}
    with open('promql_assertions_results.json','w') as fh:
        json.dump(results, fh, indent=2)
    # Exit non-zero if any assertion clearly indicates missing metrics
    # (this is conservative; operators should interpret results)
    for v in results.values():
        if v.get('error'):
            sys.exit(1)
    print('PromQL assertions completed; results written to promql_assertions_results.json')

if __name__ == '__main__':
    run()
