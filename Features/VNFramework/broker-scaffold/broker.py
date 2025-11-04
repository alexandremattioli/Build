"""
VNF Broker - Skeleton Implementation
Python 3.11+, FastAPI-based broker service

Architecture:
- FastAPI for REST endpoints
- Pydantic models for validation (auto-gen from JSON Schema)
- Dictionary engine for vendor translation
- JWT middleware for auth
- mTLS via uvicorn/nginx termination
"""

from fastapi import FastAPI, HTTPException, Depends, Header
from pydantic import BaseModel, Field, validator
from typing import Optional, Dict, Any, List
from datetime import datetime, timedelta
import httpx
import jwt
import hashlib
import json
from pathlib import Path

app = FastAPI(title="VNF Broker", version="0.1.0")

# ============================================================================
# Configuration (loaded from /etc/vnfbroker/broker.yaml in production)
# ============================================================================
class BrokerConfig:
    JWT_SECRET = "changeme"  # env: BROKER_JWT_SECRET (HS256) or keyfile (RS256)
    JWT_ALGORITHM = "HS256"
    JWT_EXPIRY_MINUTES = 5
    IDEMPOTENCY_TTL_HOURS = 24
    VNF_TIMEOUT_SECONDS = 20
    VNF_CONNECT_TIMEOUT = 3
    VNF_READ_TIMEOUT = 10
    RETRY_ATTEMPTS = 2
    DICTIONARY_PATH = Path("/etc/vnfbroker/dictionaries")
    
config = BrokerConfig()

# ============================================================================
# Models (generated from JSON Schema contracts)
# ============================================================================
class AddressSpec(BaseModel):
    cidr: Optional[str] = Field(None, pattern=r"^(any|([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?)$")
    alias: Optional[str] = Field(None, min_length=1, max_length=64)
    
    @validator('cidr', 'alias')
    def exactly_one(cls, v, values):
        if 'cidr' in values and values['cidr'] and v:
            raise ValueError("Specify either cidr or alias, not both")
        return v

class PortSpec(BaseModel):
    src: Optional[str] = Field(None, pattern=r"^(any|[0-9]{1,5}(-[0-9]{1,5})?)$")
    dst: Optional[str] = Field(None, pattern=r"^(any|[0-9]{1,5}(-[0-9]{1,5})?)$")

class CreateFirewallRuleCmd(BaseModel):
    ruleId: Optional[str] = Field(None, min_length=1, max_length=128, pattern=r"^[a-zA-Z0-9_-]+$")
    interface: str = Field(..., min_length=1, max_length=32)
    direction: str = Field(..., pattern=r"^(in|out)$")
    action: str = Field(..., pattern=r"^(allow|deny)$")
    src: Optional[AddressSpec] = None
    dst: Optional[AddressSpec] = None
    protocol: str = Field(..., pattern=r"^(tcp|udp|icmp|any)$")
    ports: Optional[PortSpec] = None
    description: Optional[str] = Field(None, max_length=256)
    enabled: bool = True
    log: bool = False
    priority: Optional[int] = Field(None, ge=0, le=99999)

class ErrorDetail(BaseModel):
    code: str
    message: str
    vendorReason: Optional[str] = None
    retryable: bool = False
    traceId: str

class Diagnostics(BaseModel):
    latencyMs: int
    retries: int
    vendorLatencyMs: Optional[int] = None

class CreateFirewallRuleResponse(BaseModel):
    ok: bool
    ruleId: str
    vendorRef: Optional[str] = None
    warnings: Optional[List[str]] = None
    appliedAt: str  # ISO 8601
    diagnostics: Optional[Diagnostics] = None
    error: Optional[ErrorDetail] = None

# ============================================================================
# Idempotency Store (in-memory for MVP; Redis/DB for production)
# ============================================================================
idempotency_store: Dict[str, CreateFirewallRuleResponse] = {}

def compute_idempotency_hash(cmd: CreateFirewallRuleCmd) -> str:
    """Hash command content for deduplication"""
    payload = cmd.dict(exclude={'ruleId'})
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()

def check_idempotency(cmd: CreateFirewallRuleCmd) -> Optional[CreateFirewallRuleResponse]:
    """Check if this command was already executed"""
    if not cmd.ruleId:
        return None
    return idempotency_store.get(cmd.ruleId)

def store_idempotency(cmd: CreateFirewallRuleCmd, response: CreateFirewallRuleResponse):
    """Cache response for idempotency"""
    if cmd.ruleId:
        idempotency_store[cmd.ruleId] = response

# ============================================================================
# JWT Authentication
# ============================================================================
def verify_jwt(authorization: str = Header(...)) -> dict:
    """Verify JWT and extract claims"""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Invalid authorization header")
    
    token = authorization.split(" ")[1]
    try:
        payload = jwt.decode(token, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
        
        # Check expiry
        exp = payload.get("exp")
        if not exp or datetime.utcnow().timestamp() > exp:
            raise HTTPException(status_code=401, detail="Token expired")
        
        # Check scope
        scope = payload.get("scope", [])
        if "vnf:rw" not in scope and "vnf:r" not in scope:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        
        return payload
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")

# ============================================================================
# Dictionary Engine (simplified; full impl loads YAML + Jinja2)
# ============================================================================
class DictionaryEngine:
    """Translates abstract commands to vendor API calls"""
    
    def __init__(self, vendor: str):
        self.vendor = vendor
        # In production: load from DICTIONARY_PATH / f"{vendor}.yaml"
        # For now: hardcoded pfSense mapping
        
    async def execute_create_rule(self, cmd: CreateFirewallRuleCmd, trace_id: str) -> CreateFirewallRuleResponse:
        """Execute createFirewallRule against vendor API"""
        start_time = datetime.utcnow()
        
        # Build vendor payload (simplified; real impl uses Jinja2 template)
        vendor_payload = {
            "interface": cmd.interface,
            "direction": cmd.direction,
            "action": cmd.action,
            "source": {"address": cmd.src.cidr if cmd.src and cmd.src.cidr else "any"},
            "destination": {"address": cmd.dst.cidr if cmd.dst and cmd.dst.cidr else "any"},
            "protocol": cmd.protocol,
            "enabled": cmd.enabled,
            "log": cmd.log,
        }
        if cmd.description:
            vendor_payload["description"] = cmd.description
        
        # Call vendor API (mock for now)
        try:
            async with httpx.AsyncClient(timeout=config.VNF_TIMEOUT_SECONDS) as client:
                # Real: POST to https://{vnf_host}/api/v1/firewall/rules
                # Mock success response:
                vendor_response = {
                    "status": "success",
                    "data": {
                        "rule_id": cmd.ruleId or "auto-gen-12345",
                        "uuid": "pfsense-uuid-abc123"
                    }
                }
                vendor_latency = 250  # ms
                
        except httpx.TimeoutException:
            return CreateFirewallRuleResponse(
                ok=False,
                ruleId=cmd.ruleId or "unknown",
                appliedAt=datetime.utcnow().isoformat(),
                error=ErrorDetail(
                    code="VNF_TIMEOUT",
                    message=f"VNF did not respond within {config.VNF_TIMEOUT_SECONDS}s",
                    retryable=True,
                    traceId=trace_id
                )
            )
        
        # Map vendor response to standard response
        end_time = datetime.utcnow()
        latency_ms = int((end_time - start_time).total_seconds() * 1000)
        
        return CreateFirewallRuleResponse(
            ok=True,
            ruleId=vendor_response["data"]["rule_id"],
            vendorRef=vendor_response["data"]["uuid"],
            appliedAt=end_time.isoformat(),
            diagnostics=Diagnostics(
                latencyMs=latency_ms,
                retries=0,
                vendorLatencyMs=vendor_latency
            )
        )

# ============================================================================
# REST Endpoints
# ============================================================================
@app.post("/v1/firewall/rules", response_model=CreateFirewallRuleResponse)
async def create_firewall_rule(
    cmd: CreateFirewallRuleCmd,
    claims: dict = Depends(verify_jwt)
) -> CreateFirewallRuleResponse:
    """
    Create a firewall rule on the VNF appliance.
    
    - Requires JWT with scope 'vnf:rw'
    - Idempotent if ruleId is provided
    - Returns standard response with diagnostics
    """
    
    # Check write permission
    if "vnf:rw" not in claims.get("scope", []):
        raise HTTPException(status_code=403, detail="Write permission required")
    
    # Check idempotency
    cached = check_idempotency(cmd)
    if cached:
        return cached
    
    # Generate trace ID
    trace_id = hashlib.sha256(f"{datetime.utcnow().isoformat()}{cmd.ruleId}".encode()).hexdigest()[:16]
    
    # Execute via dictionary engine
    engine = DictionaryEngine(vendor="pfsense")  # TODO: detect from config/header
    response = await engine.execute_create_rule(cmd, trace_id)
    
    # Store for idempotency
    store_idempotency(cmd, response)
    
    return response

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}

@app.get("/v1/firewall/rules/{rule_id}")
async def get_firewall_rule(rule_id: str, claims: dict = Depends(verify_jwt)):
    """Get firewall rule details (placeholder)"""
    # TODO: implement GET via dictionary
    return {"ruleId": rule_id, "status": "not_implemented"}

# ============================================================================
# Startup
# ============================================================================
if __name__ == "__main__":
    import uvicorn
    # Production: use uvicorn with mTLS config
    uvicorn.run(app, host="0.0.0.0", port=8443, log_level="info")
