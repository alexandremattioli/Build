#!/usr/bin/env python3
import argparse, json, os, socket, struct, sys, time, uuid, hmac, hashlib
from datetime import datetime
import ipaddress

PORT=50555
MAGIC=b"BUILD/HELLO/v1"

parser=argparse.ArgumentParser()
parser.add_argument('--iface', required=True)
parser.add_argument('--cidr', required=True)
parser.add_argument('--broadcast', default=None)
parser.add_argument('--candidate', default=None)
parser.add_argument('--secret-file', default='/etc/build/shared_secret')
args=parser.parse_args()

net=ipaddress.ip_network(args.cidr, strict=False)
if not args.broadcast:
    bcast=str(net.broadcast_address)
else:
    bcast=args.broadcast

hostname=socket.gethostname()
primary=str(ipaddress.ip_interface(args.cidr).ip)
node_id=str(uuid.uuid4())

secret=b''
try:
    with open(args.secret_file,'rb') as f:
        secret=f.read().strip()
except Exception:
    pass

def sign(payload: bytes) -> str:
    if not secret: return ''
    mac=hmac.new(secret, payload, hashlib.sha256).hexdigest()
    return mac

def make_msg(kind:str):
    payload={
        'kind': kind,
        'node_id': node_id,
        'hostname': hostname,
        'primary_ip': primary,
        'candidate_ip': args.candidate,
        'ts': datetime.utcnow().isoformat()+"Z",
        'services': ['build-agent','peer-discovery']
    }
    raw=json.dumps(payload, separators=(',',':')).encode('utf-8')
    return json.dumps({'magic':MAGIC.decode(),'payload':payload,'sig':sign(raw)}, separators=(',',':')).encode('utf-8')

def valid(msg: dict) -> bool:
    if msg.get('magic') != MAGIC.decode():
        return False
    pl=msg.get('payload')
    sig=msg.get('sig','')
    if not isinstance(pl, dict):
        return False
    raw=json.dumps(pl, separators=(',',':')).encode('utf-8')
    if secret:
        mac=hmac.new(secret, raw, hashlib.sha256).hexdigest()
        return hmac.compare_digest(mac, sig)
    return True

sock=socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.settimeout(2.0)

hello=make_msg('HELLO')

# send hello bursts
for _ in range(3):
    sock.sendto(hello, (bcast, PORT))
    time.sleep(0.3)

# listen and respond
peers=[]
start=time.time()
while time.time()-start < 10:
    try:
        data, addr = sock.recvfrom(8192)
        msg=json.loads(data.decode('utf-8'))
        if not valid(msg):
            continue
        pl=msg['payload']
        if pl.get('node_id') == node_id:
            continue
        peers.append({'ip': addr[0], **pl})
        # respond to HELLO with WELCOME
        if pl.get('kind')=='HELLO':
            sock.sendto(make_msg('WELCOME'), (addr[0], PORT))
    except socket.timeout:
        continue
    except Exception:
        continue

# persist peer list
os.makedirs('/var/lib/build', exist_ok=True)
with open('/var/lib/build/peers.json','w') as f:
    json.dump({'self': {'hostname': hostname,'primary_ip': primary,'candidate_ip': args.candidate}, 'peers': peers}, f, indent=2)

print(f"Discovered {len(peers)} peer(s)")
for p in peers:
    print(f" - {p.get('hostname')} @ {p.get('ip')} ({p.get('primary_ip')}) kind={p.get('kind')}")
