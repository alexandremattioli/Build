import json
import time


def auth_headers(token='testtoken'):
    return {'Authorization': f'Bearer {token}'}


def test_health_endpoint_ok(app_client):
    client, broker, _ = app_client
    resp = client.get('/health')
    assert resp.status_code == 200
    data = resp.get_json()
    assert data['status'] == 'healthy'
    assert 'redis' in data


def test_create_requires_auth(app_client):
    client, broker, _ = app_client
    payload = {
        'vnfInstanceId': 'vnf-1',
        'ruleId': 'r1',
        'action': 'allow',
        'protocol': 'tcp',
        'sourceIp': '10.0.0.0/24',
        'destinationIp': '192.168.1.0/24',
        'destinationPort': 443,
        'enabled': True
    }
    resp = client.post('/api/vnf/firewall/create', json=payload)
    assert resp.status_code == 401


def test_create_validation_error(app_client):
    client, broker, _ = app_client
    payload = {
        'vnfInstanceId': 'vnf-1',
        'ruleId': 'r1',
        'action': 'allow',
        'protocol': 'tcp',
        'sourceIp': '10.0.0.0/24',
        'destinationIp': '192.168.1.0/24',
        'destinationPort': 70000,  # invalid
        'enabled': True
    }
    resp = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert resp.status_code == 400
    data = resp.get_json()
    assert data['error'] == 'Validation error'


def test_create_firewall_success_and_idempotency(app_client):
    client, broker, _ = app_client
    payload = {
        'vnfInstanceId': 'vnf-1',
        'ruleId': f'r-create-{int(time.time())}',
        'action': 'allow',
        'protocol': 'tcp',
        'sourceIp': '10.0.0.0/24',
        'destinationIp': '192.168.1.0/24',
        'destinationPort': 443,
        'enabled': True
    }
    r1 = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert r1.status_code == 201
    d1 = r1.get_json()
    r2 = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert r2.status_code == 200
    d2 = r2.get_json()
    assert d1['ruleId'] == d2['ruleId']
    assert d1['success'] == d2['success']


def test_rate_limit_blocks_when_exceeded(app_client):
    client, broker, fake = app_client
    # Tighten rate limit
    broker.CONFIG['RATE_LIMIT_REQUESTS'] = 1
    broker.CONFIG['RATE_LIMIT_WINDOW'] = 2

    payload = {
        'vnfInstanceId': 'vnf-rl',
        'ruleId': f'rl-{int(time.time())}',
        'action': 'allow',
        'protocol': 'tcp',
        'sourceIp': '10.0.0.0/24',
        'destinationIp': '192.168.1.0/24',
        'destinationPort': 443,
        'enabled': True
    }
    r1 = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert r1.status_code in (200, 201)
    r2 = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert r2.status_code == 429


def test_circuit_breaker_open_blocks(app_client):
    client, broker, _ = app_client
    broker.circuit_breaker_state['vnf-cb'] = {
        'state': 'open', 'failures': 5, 'last_failure': time.time()
    }
    payload = {
        'vnfInstanceId': 'vnf-cb',
        'ruleId': 'r-cb',
        'action': 'allow',
        'protocol': 'tcp',
        'sourceIp': '10.0.0.0/24',
        'destinationIp': '192.168.1.0/24',
        'destinationPort': 443,
        'enabled': True
    }
    r = client.post('/api/vnf/firewall/create', json=payload, headers=auth_headers())
    assert r.status_code == 503


def test_update_firewall_success(app_client):
    client, broker, _ = app_client
    rid = f'upd-{int(time.time())}'
    payload = {
        'vnfInstanceId': 'vnf-u',
        'ruleId': rid,
        'action': 'deny',
        'protocol': 'udp',
        'sourceIp': '10.0.1.0/24',
        'destinationIp': '192.168.2.0/24',
        'destinationPort': 53,
        'enabled': False
    }
    r = client.put(f'/api/vnf/firewall/update/{rid}', json=payload, headers=auth_headers())
    assert r.status_code == 200
    d = r.get_json()
    assert d['ruleId'] == rid
    assert d['status'] == 'updated'


def test_delete_requires_vnf_instance(app_client):
    client, broker, _ = app_client
    r = client.delete('/api/vnf/firewall/delete/r-del', headers=auth_headers())
    assert r.status_code == 400


def test_delete_firewall_success(app_client):
    client, broker, _ = app_client
    r = client.delete('/api/vnf/firewall/delete/r-del', json={'vnfInstanceId': 'vnf-d'}, headers=auth_headers())
    assert r.status_code == 200
    d = r.get_json()
    assert d['status'] == 'deleted'


def test_list_requires_query_param(app_client):
    client, broker, _ = app_client
    r = client.get('/api/vnf/firewall/list', headers=auth_headers())
    assert r.status_code == 400


def test_list_firewall_success(app_client):
    client, broker, _ = app_client
    r = client.get('/api/vnf/firewall/list?vnfInstanceId=vnf-l', headers=auth_headers())
    assert r.status_code == 200
    d = r.get_json()
    assert d['success'] is True
    assert d['count'] == 0


def test_metrics_endpoints(app_client):
    client, broker, _ = app_client
    rj = client.get('/metrics')
    assert rj.status_code == 200
    rp = client.get('/metrics.prom')
    assert rp.status_code == 200
