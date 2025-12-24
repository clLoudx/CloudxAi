import os
import sys
import time
ROOT = os.path.dirname(os.path.dirname(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

import importlib.util
MOD_PATH = os.path.join(ROOT, 'ai-agent', 'dashboard', 'app.py')
spec = importlib.util.spec_from_file_location('dashboard_app', MOD_PATH)
dashboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dashboard)

errors = []

app = getattr(dashboard, 'app')
app.config['TESTING'] = True
client = app.test_client()

# Test 1: global readyz unaffected by tenant operations
app.config['TESTING'] = True
client = app.test_client()

# Test 1: global readyz unaffected by tenant operations
try:
    r = client.get('/readyz')
    assert r.status_code == 200
    global_status = r.get_json().get('status')

    # attempt to set tenant state (may require API_KEY)
    headers = {'X-API-KEY': os.getenv('API_KEY','')}
    setr = client.post('/tenant/test1/set_ready', json={'ready': False}, headers=headers)
    if setr.status_code not in (200, 401, 429):
        raise AssertionError('unexpected status from set_ready: %s' % setr.status_code)

    r2 = client.get('/readyz')
    assert r2.get_json().get('status') == global_status
    print('Test 1 passed: global readyz unchanged')
except Exception as e:
    errors.append(('global_readyz_unchanged', str(e)))

# Test 2: tenant isolation and inheritance
try:
    global_status = client.get('/readyz').get_json().get('status')
    r = client.get('/tenant/unknown_t/readyz')
    assert r.status_code == 200 and r.get_json().get('status') == global_status

    headers = {'X-API-KEY': os.getenv('API_KEY','')}
    client.post('/tenant/A/set_ready', json={'ready': False}, headers=headers)
    client.post('/tenant/B/set_ready', json={'ready': True}, headers=headers)

    ra = client.get('/tenant/A/readyz')
    rb = client.get('/tenant/B/readyz')
    assert ra.get_json().get('status') == 'not ready'
    assert rb.get_json().get('status') == 'ready'
    print('Test 2 passed: tenant isolation and inheritance')
except Exception as e:
    errors.append(('tenant_isolation', str(e)))

# Test 3: cardinality limit enforcement
try:
    # set small cap
    os.environ['MAX_TENANT_LABELS'] = '3'
    # We must re-import or use existing _ensure_tenant_allowed; reload module
    import importlib
    importlib.reload(dashboard)
    app = dashboard.app
    app.config['TESTING'] = True
    client = app.test_client()
    headers = {'X-API-KEY': os.getenv('API_KEY','')}
    cap = int(os.getenv('MAX_TENANT_LABELS','3'))
    success = 0
    for i in range(cap):
        r = client.post(f'/tenant/t{i}/set_ready', json={'ready': True}, headers=headers)
        if r.status_code == 200:
            success += 1
    # next tenant should be rejected with 429 if API allowed
    r = client.post('/tenant/overflow/set_ready', json={'ready': True}, headers=headers)
    if r.status_code == 200:
        # surprising; count as failure
        raise AssertionError('expected cardinality rejection but got 200')
    print('Test 3 passed: cardinality enforcement (or API locked)')
except Exception as e:
    errors.append(('cardinality', str(e)))

# Summary
if errors:
    print('\nFAILED TESTS:\n')
    for name, msg in errors:
        print(name, msg)
    sys.exit(2)
else:
    print('\nALL TENANT CHECKS PASSED')
    sys.exit(0)
