import os
import time
import pytest
from ai_agent.dashboard import app as app_module


@pytest.mark.chaos
def test_chaos_tenant_does_not_affect_global(monkeypatch):
    # Small cap for deterministic behavior
    monkeypatch.setenv('MAX_TENANT_LABELS', '10')
    app = app_module.app
    app.config['TESTING'] = True
    client = app.test_client()

    # record global
    global_before = client.get('/readyz').get_json().get('status')

    # Inject chaotic behavior: rapidly toggle tenant readiness in background
    tenant = 'chaos1'
    headers = {'X-API-KEY': os.getenv('API_KEY','')}
    for _ in range(10):
        client.post(f'/tenant/{tenant}/set_ready', json={'ready': False}, headers=headers)
        client.post(f'/tenant/{tenant}/set_ready', json={'ready': True}, headers=headers)
        time.sleep(0.01)

    # After chaos, global must be unchanged
    global_after = client.get('/readyz').get_json().get('status')
    assert global_before == global_after
