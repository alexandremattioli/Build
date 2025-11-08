#!/usr/bin/env python3
"""Advisor daemon: listens for IDENTIFY requests and suggests roles based on cluster state."""
import argparse, json, os, socket, hmac, hashlib, time, sys, signal, logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)

PORT=50555
MAGIC=b"BUILD/HELLO/v1"

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

def suggest_role(peers_count: int) -> dict:
    """Simple heuristic: assign roles based on cluster size."""
    # Example logic - customize for your build system
    if peers_count == 0:
        return {
            'role': 'controller',
            'packages': ['ansible','git','build-essential'],
            'config': {'is_primary': True},
            'reason': 'first node becomes controller'
        }
    elif peers_count < 3:
        return {
            'role': 'builder',
            'packages': ['openjdk-17-jdk','maven','git','build-essential'],
            'config': {'build_slots': 4},
            'reason': 'cluster needs builders'
        }
    else:
        return {
            'role': 'runner',
            'packages': ['python3-pytest','nodejs','npm'],
            'config': {'test_parallel': 2},
            'reason': 'cluster has builders, needs test runners'
        }

def signal_handler(sig, frame):
    logger.info("Shutting down gracefully...")
    sock.close()
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

while True:
    try:
        data, addr = sock.recvfrom(8192)
        msg=json.loads(data.decode('utf-8'))
        if not valid(msg):
            continue
        pl=msg['payload']
        if pl.get('kind')=='IDENTIFY':
            # Count known peers (simplified: based on recent peers.json)
            peers_count=0
            try:
                with open('/var/lib/build/peers.json') as f:
                    peers_data=json.load(f)
                    peers_count=len(peers_data.get('peers',[]))
            except:
                pass
            
            advice=suggest_role(peers_count)
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
