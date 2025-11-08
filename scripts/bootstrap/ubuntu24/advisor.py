#!/usr/bin/env python3
"""Advisor daemon: listens for IDENTIFY requests and suggests roles based on cluster state.
Enhanced with CloudStack-specific roles and optional VNF broker awareness.
"""
import argparse, json, os, socket, hmac, hashlib, time, sys, signal, logging, subprocess
from datetime import datetime
from collections import Counter

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

PORT=50555
MAGIC=b"BUILD/HELLO/v1"
VNF_BROKER_PORT = 8443  # heuristic

parser=argparse.ArgumentParser()
parser.add_argument('--secret-file', default='/etc/build/shared_secret')
parser.add_argument('--interval', type=int, default=30, help='seconds between cluster scans')
args=parser.parse_args()

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

def load_identity():
    try:
        with open('/var/lib/build/identity.json') as f:
            return json.load(f)
    except:
        return {'role':'advisor','packages':[],'config':{}}

def read_peers():
    try:
        with open('/var/lib/build/peers.json') as f:
            data=json.load(f)
            return data.get('peers', [])
    except Exception:
        return []

def vnf_broker_available():
    # naive check: is local port open/listening? (best-effort)
    try:
        result = subprocess.run(['bash','-lc', f"ss -tln | grep :{VNF_BROKER_PORT}"], capture_output=True)
        return result.returncode == 0
    except Exception:
        return False

def suggest_cloudstack_role(peers):
    # Count current roles
    roles = Counter((p.get('role') or (p.get('identity') or {}).get('role') or 'unknown') for p in peers)
    # Single management server desired
    if roles.get('management-server', 0) == 0:
        return {
            'role': 'management-server',
            'packages': ['mysql-server','nfs-kernel-server','openjdk-17-jdk','git'],
            'config': {'db': 'mysql', 'nfs': True},
            'reason': 'First management server needed'
        }
    # Need CloudStack builders (at least 2)
    if roles.get('cloudstack-builder', 0) < 2:
        return {
            'role': 'cloudstack-builder',
            'packages': ['openjdk-17-jdk','maven','git','build-essential'],
            'config': {'build_threads': 8},
            'reason': 'Increase build capacity'
        }
    # Need hypervisor test host
    if roles.get('kvm-hypervisor', 0) == 0:
        return {
            'role': 'kvm-hypervisor',
            'packages': ['qemu-kvm','libvirt-daemon-system','bridge-utils'],
            'config': {'virt_network': 'default'},
            'reason': 'Provide hypervisor for functional tests'
        }
    # VNF tester if broker available and none assigned
    if vnf_broker_available() and roles.get('vnf-tester', 0) == 0:
        return {
            'role': 'vnf-tester',
            'packages': ['python3-requests','docker.io'],
            'config': {'broker_port': VNF_BROKER_PORT},
            'reason': 'Validate VNF broker operations'
        }
    # Default to test runner
    return {
        'role': 'test-runner',
        'packages': ['python3-pytest','curl','git'],
        'config': {'parallel': 4},
        'reason': 'Expand test execution capacity'
    }

def signal_handler(sig, frame):
    logger.info("Shutting down gracefully...")
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
sock.settimeout(5.0)

identity=load_identity()
my_node_id=os.urandom(8).hex()
hostname=socket.gethostname()

logger.info(f"Advisor running as {identity.get('role')} on {hostname}")
logger.info("CloudStack role advisor active (management-server, cloudstack-builder, kvm-hypervisor, test-runner, vnf-tester)")

while True:
    try:
        data, addr = sock.recvfrom(8192)
        msg=json.loads(data.decode('utf-8'))
        if not valid(msg):
            continue
        pl=msg['payload']
        if pl.get('kind')=='IDENTIFY':
            peers = read_peers()
            advice = suggest_cloudstack_role(peers)
            response_payload={
                'kind': 'ADVICE',
                'node_id': my_node_id,
                'hostname': hostname,
                'suggested_role': advice['role'],
                'packages': advice['packages'],
                'config': advice['config'],
                'reason': advice['reason'],
                'ts': datetime.utcnow().isoformat()+"Z"
            }
            raw=json.dumps(response_payload, separators=(',',':')).encode('utf-8')
            response=json.dumps({'magic':MAGIC.decode(),'payload':response_payload,'sig':sign(raw)}, separators=(',',':')).encode('utf-8')
            sock.sendto(response, (addr[0], PORT))
            logger.info(f"Advised {pl.get('hostname')} -> {advice['role']} ({advice['reason']})")
    except socket.timeout:
        continue
    except KeyboardInterrupt:
        break
    except Exception as e:
        logger.error(f"Error processing message: {e}")
        time.sleep(1)
