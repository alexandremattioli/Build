# Dashboard Testing

## Browser Tests

Open `docs/tests/dashboard.test.html` in a browser to run automated tests for:

### Test Suites

1. **Server State Detection** (8 tests)
   - Status normalization (success → online, building, etc.)
   - Online/offline/stale detection
   - Timestamp selection logic
   - State classification

2. **Server Filtering** (2 tests)
   - Invalid IP detection (xxx patterns)
   - Valid server counting

3. **Message Metrics** (6 tests)
   - Total message counting
   - Unread message filtering
   - Oldest unread age calculation
   - 1-hour alert threshold
   - 24-hour critical alert threshold
   - Last 24 hours filtering

4. **Utility Functions** (3 tests)
   - Latest timestamp selection
   - Null value filtering
   - Edge case handling

### Running Tests

```bash
# Open in browser
start docs/tests/dashboard.test.html

# Or navigate to:
# http://localhost:8000/docs/tests/dashboard.test.html
```

### Test Results

All tests run in-browser and display:
- ✅ Pass/Fail status for each test
- Summary statistics (passed/failed/total)
- Error messages for failed tests
- Organized by test suite

### Coverage

Tests validate:
- Server status detection (online, stale after 10min, offline after 30min)
- IP filtering (hide servers with xxx IPs)
- Message age calculations and alerts
- Heartbeat vs status timestamp comparison
- Edge cases (null values, empty arrays, invalid data)
