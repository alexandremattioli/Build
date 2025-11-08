from scripts.bootstrap.ubuntu24.hive_lib import sign, valid, MAGIC
import json

SECRET = b'supersecret'


def make_payload():
    return {'kind': 'HELLO', 'node_id': 'x', 'hostname': 'h', 'primary_ip': '1.2.3.4', 'candidate_ip': None, 'ts': '2025-01-01T00:00:00Z'}


def test_sign_and_valid_roundtrip():
    pl = make_payload()
    raw = json.dumps(pl, separators=(',',':')).encode('utf-8')
    sig = sign(raw, SECRET)
    envelope = {'magic': MAGIC, 'payload': pl, 'sig': sig}
    assert valid(envelope, SECRET) is True


def test_invalid_magic():
    pl = make_payload()
    raw = json.dumps(pl, separators=(',',':')).encode('utf-8')
    sig = sign(raw, SECRET)
    envelope = {'magic': 'WRONG', 'payload': pl, 'sig': sig}
    assert valid(envelope, SECRET) is False


def test_tampered_payload():
    pl = make_payload()
    raw = json.dumps(pl, separators=(',',':')).encode('utf-8')
    sig = sign(raw, SECRET)
    pl['hostname'] = 'evil'
    envelope = {'magic': MAGIC, 'payload': pl, 'sig': sig}
    assert valid(envelope, SECRET) is False
