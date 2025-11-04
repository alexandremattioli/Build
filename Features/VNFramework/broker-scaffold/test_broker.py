"""
Pytest tests for VNF Broker
"""
import pytest
from fastapi.testclient import TestClient
from unittest.mock import Mock, patch, AsyncMock
import jwt
from datetime import datetime, timedelta

# Mock dependencies before importing broker
@pytest.fixture(autouse=True)
def mock_redis():
    """Mock Redis to avoid requiring running instance"""
    with patch('redis_store.redis.from_url') as mock:
        mock.return_value = Mock()
        yield mock


@pytest.fixture
def client():
    """Create test client"""
    # Import here to apply mocks
    from broker_integrated import app
    return TestClient(app)


@pytest.fixture
def valid_jwt_token():
    """Generate valid JWT token for testing"""
    from broker_integrated import config
    
    payload = {
        'sub': 'test_user',
        'exp': datetime.utcnow() + timedelta(minutes=10)
    }
    
    token = jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)
    return f"Bearer {token}"


@pytest.fixture
def firewall_rule_request():
    """Sample firewall rule request"""
    return {
        "ruleId": "test-rule-001",
        "action": "allow",
        "protocol": "tcp",
        "sourceAddressing": "192.168.1.0/24",
        "destinationAddressing": "10.0.0.0/8",
        "sourcePorts": "any",
        "destinationPorts": "80,443",
        "description": "Test firewall rule"
    }


# =============================================================================
# Health Check Tests
# =============================================================================
def test_health_check(client):
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
    assert "timestamp" in response.json()


# =============================================================================
# Authentication Tests
# =============================================================================
def test_missing_auth_header(client, firewall_rule_request):
    """Test request without Authorization header"""
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 422  # Missing required header


def test_invalid_auth_format(client, firewall_rule_request):
    """Test request with invalid Authorization format"""
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": "InvalidFormat token123",
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 401


def test_expired_token(client, firewall_rule_request):
    """Test request with expired JWT token"""
    from broker_integrated import config
    
    payload = {
        'sub': 'test_user',
        'exp': datetime.utcnow() - timedelta(minutes=10)  # Expired
    }
    
    token = jwt.encode(payload, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM)
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": f"Bearer {token}",
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 401


# =============================================================================
# Request Validation Tests
# =============================================================================
def test_invalid_action(client, valid_jwt_token, firewall_rule_request):
    """Test request with invalid action value"""
    firewall_rule_request["action"] = "invalid"
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 422


def test_invalid_protocol(client, valid_jwt_token, firewall_rule_request):
    """Test request with invalid protocol"""
    firewall_rule_request["protocol"] = "invalid"
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 422


def test_missing_required_field(client, valid_jwt_token):
    """Test request missing required field"""
    incomplete_request = {
        "ruleId": "test-rule-001",
        "action": "allow"
        # Missing protocol, addressing, etc.
    }
    
    response = client.post(
        "/firewall/rules",
        json=incomplete_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    assert response.status_code == 422


# =============================================================================
# Idempotency Tests
# =============================================================================
@patch('broker_integrated.get_dictionary_engine')
def test_idempotency_cache_hit(mock_dict_engine, client, valid_jwt_token, firewall_rule_request):
    """Test idempotency - second request returns cached response"""
    # Mock dictionary engine
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': True,
        'vendor_ref': 'pfsense-rule-123',
        'message': 'Rule created successfully',
        'error_code': None
    })
    mock_dict_engine.return_value = mock_engine
    
    headers = {
        "Authorization": valid_jwt_token,
        "X-VNF-Management-IP": "192.168.1.100",
        "X-VNF-Username": "admin",
        "X-VNF-Password": "password"
    }
    
    # First request
    response1 = client.post("/firewall/rules", json=firewall_rule_request, headers=headers)
    assert response1.status_code == 200
    assert response1.json()["success"] is True
    
    # Second request with same ruleId - should use cache
    response2 = client.post("/firewall/rules", json=firewall_rule_request, headers=headers)
    assert response2.status_code == 200
    assert response2.json() == response1.json()
    
    # Dictionary engine should only be called once
    assert mock_engine.execute_operation.call_count == 1


# =============================================================================
# Dictionary Engine Integration Tests
# =============================================================================
@patch('broker_integrated.get_dictionary_engine')
def test_successful_firewall_rule_creation(mock_dict_engine, client, valid_jwt_token, firewall_rule_request):
    """Test successful firewall rule creation"""
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': True,
        'vendor_ref': 'pfsense-rule-456',
        'message': 'Rule created successfully',
        'error_code': None
    })
    mock_dict_engine.return_value = mock_engine
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["vendorRef"] == "pfsense-rule-456"
    assert data["errorCode"] is None


@patch('broker_integrated.get_dictionary_engine')
def test_vnf_timeout_error(mock_dict_engine, client, valid_jwt_token, firewall_rule_request):
    """Test VNF timeout error handling"""
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': False,
        'vendor_ref': None,
        'message': 'VNF appliance did not respond',
        'error_code': 'VNF_TIMEOUT'
    })
    mock_dict_engine.return_value = mock_engine
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    
    assert response.status_code == 200  # Broker returns 200, error in body
    data = response.json()
    assert data["success"] is False
    assert data["errorCode"] == "VNF_TIMEOUT"


@patch('broker_integrated.get_dictionary_engine')
def test_delete_firewall_rule(mock_dict_engine, client, valid_jwt_token):
    """Test firewall rule deletion"""
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': True,
        'vendor_ref': None,
        'message': 'Rule deleted successfully',
        'error_code': None
    })
    mock_dict_engine.return_value = mock_engine
    
    response = client.delete(
        "/firewall/rules/test-rule-001",
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True


# =============================================================================
# NAT Rule Tests
# =============================================================================
@patch('broker_integrated.get_dictionary_engine')
def test_create_nat_rule(mock_dict_engine, client, valid_jwt_token):
    """Test NAT rule creation"""
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': True,
        'vendor_ref': 'nat-rule-789',
        'message': 'NAT rule created',
        'error_code': None
    })
    mock_dict_engine.return_value = mock_engine
    
    nat_request = {
        "ruleId": "nat-test-001",
        "type": "DNAT",
        "sourceAddress": "any",
        "destinationAddress": "203.0.113.10",
        "translatedAddress": "10.0.0.100",
        "protocol": "tcp",
        "port": "80",
        "translatedPort": "8080",
        "description": "Test NAT rule"
    }
    
    response = client.post(
        "/nat/rules",
        json=nat_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert data["vendorRef"] == "nat-rule-789"


# =============================================================================
# Vendor Selection Tests
# =============================================================================
@patch('broker_integrated.get_dictionary_engine')
def test_custom_vendor_header(mock_dict_engine, client, valid_jwt_token, firewall_rule_request):
    """Test custom vendor selection via header"""
    mock_engine = Mock()
    mock_engine.execute_operation = AsyncMock(return_value={
        'success': True,
        'vendor_ref': 'fortigate-rule-001',
        'message': 'Rule created',
        'error_code': None
    })
    mock_dict_engine.return_value = mock_engine
    
    response = client.post(
        "/firewall/rules",
        json=firewall_rule_request,
        headers={
            "Authorization": valid_jwt_token,
            "X-VNF-Vendor": "FortiGate",
            "X-VNF-Management-IP": "192.168.1.100",
            "X-VNF-Username": "admin",
            "X-VNF-Password": "password"
        }
    )
    
    assert response.status_code == 200
    # Verify vendor was passed to dictionary engine getter
    mock_dict_engine.assert_called_with("FortiGate")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
