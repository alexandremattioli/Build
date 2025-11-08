import os
import time
import types
import pytest

# Import the broker module
import importlib


class FakePipeline:
    def __init__(self, store):
        self.store = store
        self.ops = []

    def zremrangebyscore(self, key, min_score, max_score):
        self.ops.append(("zremrangebyscore", key, min_score, max_score))
        return self

    def zcard(self, key):
        self.ops.append(("zcard", key))
        return self

    def zadd(self, key, mapping):
        self.ops.append(("zadd", key, mapping))
        return self

    def expire(self, key, ttl):
        self.ops.append(("expire", key, ttl))
        return self

    def execute(self):
        # Very small in-memory simulation for rate limiting pipeline
        results = []
        for op in self.ops:
            if op[0] == "zremrangebyscore":
                _, key, _min, max_age = op
                now = time.time()
                window_start = now - max_age  # broker passes window as 'max'
                self.store.setdefault(key, [])
                self.store[key] = [ts for ts in self.store[key] if ts >= window_start]
                results.append(None)
            elif op[0] == "zcard":
                _, key = op
                self.store.setdefault(key, [])
                results.append(len(self.store[key]))
            elif op[0] == "zadd":
                _, key, mapping = op
                ts = list(mapping.values())[0]
                self.store.setdefault(key, [])
                self.store[key].append(float(ts))
                results.append(None)
            elif op[0] == "expire":
                # No-op for unit tests
                results.append(True)
        self.ops.clear()
        return results


class FakeRedis:
    def __init__(self):
        self.zsets = {}
        self.kv = {}

    def pipeline(self):
        return FakePipeline(self.zsets)

    def get(self, key):
        return self.kv.get(key)

    def setex(self, key, ttl, value):
        self.kv[key] = value
        return True

    def ping(self):
        return True


@pytest.fixture(scope="session")
def broker_module():
    # Import fresh to ensure globals are set per-session
    mod = importlib.import_module(
        "Builder2.Build.Features.VNFramework.python-broker.vnf_broker_enhanced".replace("/", ".").replace("-", "_")
    )
    return mod


@pytest.fixture()
def app_client(monkeypatch):
    # Ensure default log directory exists to avoid FileHandler errors on import
    os.makedirs('/var/log/vnf-broker', exist_ok=True)
    # Import module directly by path to avoid package path issues
    import sys
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    import vnf_broker_enhanced as broker

    # Configure
    broker.CONFIG['DEBUG'] = True
    broker.CONFIG['RATE_LIMIT_REQUESTS'] = 100
    broker.CONFIG['RATE_LIMIT_WINDOW'] = 60
    broker.CONFIG['IDEMPOTENCY_TTL_SECONDS'] = 60
    broker.CONFIG['LOG_FILE'] = os.path.abspath("./test-broker.log")

    # Fake Redis
    fake = FakeRedis()
    monkeypatch.setattr(broker, 'redis_client', fake)

    # Accept a fixed JWT token
    def _ok_jwt(token: str):
        if token == 'testtoken':
            return {'sub': 'tester', 'exp': int(time.time()) + 3600}
        return None

    monkeypatch.setattr(broker, 'validate_jwt', _ok_jwt)

    # Ensure clean circuit breaker state between tests
    broker.circuit_breaker_state.clear()

    app = broker.app
    app.testing = True
    client = app.test_client()
    return client, broker, fake
