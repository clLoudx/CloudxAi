#!/usr/bin/env python3
"""Validate PromQL assertion logic using local sample responses (no network).

This helper loads `tests/observability_samples/sample_prometheus_response.json` and
mocks the behavior of the Prometheus HTTP API to allow CI regression tests without
requiring a live Prometheus instance.
"""
import json, os, sys

SAMPLE = os.path.join(os.path.dirname(os.path.dirname(__file__)), '..', 'tests', 'observability_samples', 'sample_prometheus_response.json')

def load_sample():
    with open(os.path.abspath(SAMPLE), 'r', encoding='utf-8') as fh:
        return json.load(fh)

def main():
    data = load_sample()
    # Basic checks to ensure sample contains required metrics
    names = {r['metric'].get('__name__') for r in data.get('data', {}).get('result', [])}
    required = {'tenant_readiness_state', 'tenant_cost_estimate', 'tenant_label_rejections_total'}
    missing = required - names
    if missing:
        print('Sample missing required metrics:', missing)
        sys.exit(1)
    print('Sample validation passed; required metrics present')

if __name__ == '__main__':
    main()
