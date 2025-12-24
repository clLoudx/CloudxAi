
# Local client fixture for chaos tests
import pytest
pytestmark = pytest.mark.chaos
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../src/app')))
import importlib.util
import pathlib
ai_dashboard_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../ai-agent/dashboard'))
sys.path.insert(0, ai_dashboard_dir)
spec = importlib.util.spec_from_file_location("app", os.path.join(ai_dashboard_dir, "app.py"))
if spec and spec.loader:
    app_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_mod)
    app = app_mod.app
else:
    raise ImportError("Could not load app.py from ai-agent/dashboard for Flask app import.")

@pytest.fixture
def client():
    return app.test_client()
import pytest
from unittest.mock import AsyncMock

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../../src/app/tests')))



# --- Chaos test for Flask healthz endpoint ---
def test_ready_all_healthy(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"
