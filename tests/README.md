# Testing Guide

## Prerequisites

Install Python 3.8+ and required dependencies:

```bash
pip install psutil
```

## Running Tests

### All Tests
```bash
python run_tests.py
```

### Individual Test Files
```bash
python -m unittest tests.test_system_health
python -m unittest tests.test_monitoring_metrics
python -m unittest tests.test_network_check
python -m unittest tests.test_message_manager
```

### With pytest (if installed)
```bash
pip install pytest
pytest tests/ -v
```

## Test Coverage

- `test_system_health.py` - System resource and git health checks
- `test_monitoring_metrics.py` - Performance metrics collection
- `test_network_check.py` - Network connectivity validation
- `test_message_manager.py` - Message queue and archiving

## Notes

- Tests use temporary directories and mocking to avoid side effects
- Network tests mock socket connections
- All tests are isolated and can run in parallel
