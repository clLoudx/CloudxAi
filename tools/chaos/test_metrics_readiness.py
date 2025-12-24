import importlib.util
import os
import sys
import time
import re

import pytest
pytestmark = pytest.mark.chaos

# Load dashboard app directly
ai_dashboard_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../ai-agent/dashboard'))
spec = importlib.util.spec_from_file_location("app", os.path.join(ai_dashboard_dir, "app.py"))
if spec and spec.loader:
    app_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_mod)
    app = app_mod.app
else:
    raise ImportError("Could not load dashboard app for tests")

@pytest.fixture
def client():
    return app.test_client()

def _get_metrics_text(client):
    r = client.get('/metrics')
    assert r.status_code == 200
    return r.get_data(as_text=True)

def test_metrics_expose_readiness_metrics(client):
    text = _get_metrics_text(client)
    assert 'readiness_state' in text
    assert 'readiness_transitions_total' in text
    assert 'readiness_check_duration_seconds' in text

def test_toggle_updates_readiness_and_metrics(client):
    # Ensure ready by default or set; call readyz to update metric
    r = client.get('/readyz')
    assert r.status_code == 200
    before = _get_metrics_text(client)
    # Toggle
    r = client.post('/admin/toggle_ready')
    assert r.status_code == 200
    # calling readyz to update metric
    r = client.get('/readyz')
    assert r.status_code == 200
    after = _get_metrics_text(client)
    # readiness_state value should differ (1 -> 0 or 0 -> 1)
    v_before = re.search(r'readiness_state\s+([01])', before)
    v_after = re.search(r'readiness_state\s+([01])', after)
    assert v_before and v_after
    assert v_before.group(1) != v_after.group(1)

def test_reload_module_no_duplicate_metrics():
    # reload module twice via importlib.util to ensure no duplicate registration errors
    import importlib.util
    path = os.path.join(ai_dashboard_dir, 'app.py')
    spec1 = importlib.util.spec_from_file_location('dash_app_1', path)
    m1 = importlib.util.module_from_spec(spec1)
    spec1.loader.exec_module(m1)
    spec2 = importlib.util.spec_from_file_location('dash_app_2', path)
    m2 = importlib.util.module_from_spec(spec2)
    spec2.loader.exec_module(m2)