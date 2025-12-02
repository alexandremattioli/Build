#!/usr/bin/env python3
import argparse, json, os, socket, sys, time, uuid, hmac, hashlib, subprocess, signal, logging, shutil
from datetime import datetime
import ipaddress
from collections import Counter

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

PORT=50555
MAGIC=b"BUILD/HELLO/v1"
HACKERBOOK_ACK_PATH = '/var/lib/build/hackerbook_acknowledged'
HACKERBOOK_URL = 'https://github.com/shapeblue/hackerbook'
STATE_PATH = '/var/lib/build/hive_state.json'

# Known build servers and coordinator
BUILD_MARKERS = {
    '10.1.3.175': 'build1',
    '10.1.3.177': 'build2',
}
COORDINATOR_IP = '10.1.3.175'

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

def make_msg(kind:str, extra=None):
    payload={
        'kind': kind,
        'node_id': node_id,
        'hostname': hostname,
        'primary_ip': primary,
        'candidate_ip': args.candidate,
        'ts': datetime.utcnow().isoformat()+"Z",
    }
    if extra:
        payload.update(extra)
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

def send_with_retry(sock, message, address, retries=3):
    for attempt in range(retries):
        sock.sendto(message, address)
        if attempt < retries - 1:
            time.sleep(0.5 * (2 ** attempt))

def get_health(identity):
    role = (identity or {}).get('role')
    status = {'ok': True}
    try:
        if role == 'cloudstack-builder':
            mvn_ok = subprocess.run(['bash','-lc','mvn -v'], capture_output=True).returncode == 0
            free_gb = shutil.disk_usage('/').free / (1024**3)
            status.update({'maven': mvn_ok, 'disk_free_gb': int(free_gb)})
        elif role == 'controller':
            ans_ok = subprocess.run(['bash','-lc','ansible --version'], capture_output=True).returncode == 0
            status.update({'ansible': ans_ok})
    except Exception as e:
        status['error'] = str(e)
    return status

def bridge(event, data):
    try:
        subprocess.run([
            '/usr/bin/python3', '/opt/build-agent/message_bridge.py', event, json.dumps(data)
        ], check=False)
    except Exception:
        pass

def save_state(peers, identity):
    try:
        os.makedirs('/var/lib/build', exist_ok=True)
        with open(STATE_PATH, 'w') as f:
            json.dump({'peers': peers, 'identity': identity, 'saved_at': datetime.utcnow().isoformat()+"Z"}, f)
    except Exception as e:
        logger.warning(f"Failed to save state: {e}")

def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except Exception:
        return None

def signal_handler(sig, frame):
    logger.info("Shutting down gracefully...")
    try:
        save_state(peers, identity)
    except Exception:
        pass
    try:
        sock.close()
    except Exception:
        pass
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

sock=socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(('', PORT))
except OSError as e:
    logger.error(f"Failed to bind to port {PORT}: {e}")
    sys.exit(1)
sock.settimeout(2.0)

# Attempt to load cached peers
cached = load_state() or {}
peers = cached.get('peers', [])
if peers:
    logger.info(f"Loaded {len(peers)} cached peer(s) from state")

# Phase 1: discover peers (refresh)
hello=make_msg('HELLO')
for _ in range(3):
    send_with_retry(sock, hello, (bcast, PORT), retries=2)
    time.sleep(0.3)

start=time.time()
while time.time()-start < 5:
    try:
        data, addr = sock.recvfrom(8192)
        msg=json.loads(data.decode('utf-8'))
        if not valid(msg):
            continue
        pl=msg['payload']
        if pl.get('node_id') == node_id:
            continue
        if pl.get('kind')=='HELLO':
            sock.sendto(make_msg('WELCOME'), (addr[0], PORT))
            if not any(p['node_id']==pl['node_id'] for p in peers):
                peers.append({'ip': addr[0], 'last_seen': time.time(), **pl})
        elif pl.get('kind')=='WELCOME':
            if not any(p['node_id']==pl['node_id'] for p in peers):
                peers.append({'ip': addr[0], 'last_seen': time.time(), **pl})
    except socket.timeout:
        continue
    except Exception as e:
        logger.warning(f"Error receiving message: {e}")
        continue

logger.info(f"Discovered {len(peers)} peer(s)")
bridge('node_discovered', {'hostname': hostname, 'role': (cached.get('identity') or {}).get('role'), 'peer_count': len(peers)})

# Phase 2: ask peers "who am I?"
identity_path='/var/lib/build/identity.json'
if os.path.exists(identity_path):
    with open(identity_path) as f:
        identity=json.load(f)
    logger.info(f"Already identified as: {identity.get('role','<unknown>')}")
else:
    identity=None
    if peers:
        logger.info("Asking peers for role assignment...")
        identify_req=make_msg('IDENTIFY', {'request':'who_am_i'})
        for _ in range(2):
            send_with_retry(sock, identify_req, (bcast, PORT), retries=2)
            time.sleep(0.2)
        
        suggestions=[]
        start=time.time()
        while time.time()-start < 8:
            try:
                data, addr = sock.recvfrom(8192)
                msg=json.loads(data.decode('utf-8'))
                if not valid(msg):
                    continue
                pl=msg['payload']
                if pl.get('kind')=='ADVICE':
                    suggestions.append({
                        'from': pl.get('hostname'),
                        'role': pl.get('suggested_role'),
                        'packages': pl.get('packages',[]),
                        'config': pl.get('config',{}),
                        'reason': pl.get('reason','')
                    })
                    logger.info(f" <- {pl.get('hostname')}: become '{pl.get('suggested_role')}' ({pl.get('reason','')})")
            except socket.timeout:
                continue
            except Exception as e:
                logger.warning(f"Error receiving advice: {e}")
                continue
        
        if suggestions:
            role_votes=[s['role'] for s in suggestions if s.get('role')]
            consensus=Counter(role_votes).most_common(1)
            if consensus:
                chosen_role=consensus[0][0]
                matches=[s for s in suggestions if s['role']==chosen_role]
                identity={
                    'role': chosen_role,
                    'packages': matches[0].get('packages',[]),
                    'config': matches[0].get('config',{}),
                    'assigned_by': [s['from'] for s in matches],
                    'assigned_at': datetime.utcnow().isoformat()+"Z"
                }
                build_name = BUILD_MARKERS.get(primary)
                identity['build_server'] = build_name
                identity['is_coordinator'] = (primary == COORDINATOR_IP)

                os.makedirs('/var/lib/build', exist_ok=True)
                with open(identity_path,'w') as f:
                    json.dump(identity, f, indent=2)
                logger.info(f"Consensus: I am a '{chosen_role}'")
                logger.info(f"Packages: {', '.join(identity['packages']) if identity['packages'] else '<none>'}")
                bridge('identity_assigned', {'hostname': hostname, 'role': chosen_role})
                
                if identity['packages']:
                    logger.info("Installing packages...")
                    try:
                        subprocess.run(['apt-get', 'update'], check=True, capture_output=True)
                        subprocess.run(
                            ['apt-get', 'install', '-y', '--no-install-recommends'] + identity['packages'],
                            check=True,
                            env={**os.environ, 'DEBIAN_FRONTEND': 'noninteractive'},
                            capture_output=True
                        )
                        logger.info("Package installation complete")
                        bridge('packages_installed', {'hostname': hostname, 'count': len(identity['packages'])})
                    except subprocess.CalledProcessError as e:
                        logger.error(f"Package installation failed: {e}")
                        bridge('package_install_failed', {'hostname': hostname, 'error': str(e)})
            else:
                logger.warning("No role consensus reached; will retry on next run.")
        else:
            logger.warning("No advice received from peers; operating as unassigned node.")
    else:
        logger.info("No peers found; this may be the first node (founder role).")
        identity={
            'role': 'founder',
            'packages': [],
            'config': {},
            'assigned_by': ['self'],
            'assigned_at': datetime.utcnow().isoformat()+"Z"
        }
        build_name = BUILD_MARKERS.get(primary)
        identity['build_server'] = build_name
        identity['is_coordinator'] = (primary == COORDINATOR_IP)

        os.makedirs('/var/lib/build', exist_ok=True)
        with open(identity_path,'w') as f:
            json.dump(identity, f, indent=2)
        bridge('founder', {'hostname': hostname})

# Enforce hackerbook acknowledgment
if not os.path.exists(HACKERBOOK_ACK_PATH):
    banner = "=" * 60
    logger.warning(banner)
    logger.warning("HACKERBOOK REQUIRED: Read the ShapeBlue Hackerbook before proceeding")
    logger.warning(HACKERBOOK_URL)
    logger.warning(f"After reading, acknowledge: sudo touch {HACKERBOOK_ACK_PATH}")
    logger.warning(banner)
    if identity.get('role') != 'founder':
        logger.error("Blocking further operation until hackerbook acknowledged.")
        from pathlib import Path
        Path(HACKERBOOK_ACK_PATH).touch(exist_ok=True) if os.environ.get('ALLOW_AUTO_ACK')=='1' else None
        save_state(peers, identity)
        sys.exit(2)
    else:
        logger.warning("Founder allowed to proceed BUT MUST acknowledge before cluster expansion.")

# Persist peer list snapshot
os.makedirs('/var/lib/build', exist_ok=True)
with open('/var/lib/build/peers.json','w') as f:
    json.dump({
        'self': {
            'hostname': hostname,
            'primary_ip': primary,
            'candidate_ip': args.candidate,
            'role': identity.get('role') if identity else None,
            'build_server': identity.get('build_server') if identity else None,
            'is_coordinator': identity.get('is_coordinator') if identity else None,
        },
        'peers': peers
    }, f, indent=2)

for p in peers:
    logger.info(f" - {p.get('hostname')} @ {p.get('ip')} ({p.get('primary_ip')})")

# --- Heartbeat loop ---
logger.info("Entering heartbeat loop (30s interval)")
last_cleanup = time.time()
while True:
    hb = make_msg('HEARTBEAT', {'identity': identity, 'health': get_health(identity)})
    try:
        sock.sendto(hb, (bcast, PORT))
    except Exception as e:
        logger.warning(f"Failed to send heartbeat: {e}")

    end = time.time() + 2
    while time.time() < end:
        try:
            data, addr = sock.recvfrom(8192)
            msg=json.loads(data.decode('utf-8'))
            if not valid(msg):
                continue
            pl=msg['payload']
            if pl.get('node_id') == node_id:
                continue
            for pp in peers:
                if pp.get('node_id') == pl.get('node_id'):
                    pp['last_seen'] = time.time()
                    pp['role'] = (pl.get('identity') or {}).get('role', pp.get('role'))
                    break
            else:
                peers.append({'ip': addr[0], 'last_seen': time.time(), **pl})
        except socket.timeout:
            break
        except Exception:
            break

    if time.time() - last_cleanup > 60:
        before = len(peers)
        peers = [pp for pp in peers if (time.time() - pp.get('last_seen', 0)) < 300]
        after = len(peers)
        if after != before:
            logger.info(f"Cleaned peers: {before}->{after}")
        save_state(peers, identity)
        last_cleanup = time.time()

    time.sleep(30)
