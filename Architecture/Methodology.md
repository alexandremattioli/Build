# Feature Implementation Methodology

## 1. Problem & Success Criteria
Define the problem statement, scope boundaries, constraints, external dependencies, and explicit non-goals.

Deliverables:
- One-paragraph charter
- Acceptance criteria list (clear, testable)
- Risk register (top 5 risks + mitigations)
- Owner + timeline + escalation path

## 2. Public Contract First (API / CLI / Events)
Design external touchpoints before internals.
- Endpoints / commands / events / scheduled jobs
- Request/response JSON (examples + schemas)
- Error codes + semantics (client vs server vs transient)
- Versioning + idempotency strategy + pagination + rate limits

Deliverables:
- API spec with examples
- Error catalog
- Compatibility + evolution notes

## 3. Data Model & Persistence
Define storage structures early.
- Entities, relationships, invariants (ER diagram mental or sketched)
- Migration scripts (forward + rollback fate)
- Indexing, uniqueness, soft-delete, retention policies

Deliverables:
- DDL / migration scripts
- DAO / repository interfaces
- Initial seed / fixture data (if needed)

## 4. Configuration & Feature Flags
Surface all dynamic knobs.
- Config keys (name, type, default, description)
- Dynamic vs static reload behavior
- Feature flag lifecycle (off → canary → on → guard)

Deliverables:
- ConfigKey definitions
- Flag gating logic
- Operator documentation

## 5. Service Contracts (Internal Interfaces)
Define boundaries before implementation.
- Inputs/outputs, typed domain objects
- Typed errors, retry semantics, timeouts, cancellation
- Side-effect isolation strategy

Deliverables:
- Service interfaces (with JavaDoc / docstrings)
- Error hierarchy / sealed types

## 6. Test Scaffolding Up Front
Bake tests early to drive correctness.
- Happy path + 1-2 edge cases baseline
- Mocks/fakes for external systems
- Deterministic fixtures

Deliverables:
- Unit test harness
- Test data builders / factories
- CI execution hook

### 6.1 Test Categories (Added)
To ensure consistent quality gates, adopt a layered test pyramid for every feature/module:

| Layer | Purpose | Scope | Frequency |
|-------|---------|-------|-----------|
| Static / Lint | Syntax & style correctness | Whole repo | Every push/PR |
| Unit | Fast logic validation | Single function/class | Every push/PR |
| Component | Interactions of 2-3 modules (in-memory) | Narrow slice | Every push/PR |
| Integration | External boundaries (DB, network, broker) | Real infra or container | Nightly + gated merges |
| Contract | Provider/consumer schema & semantics | API/Events | On provider or schema change |
| Smoke | Sanity of deployable artifact start-up | Minimal runtime | Post-build & pre-deploy |
| End-to-End | Real user path & data flow | Full system | Release candidate |
| Performance | Latency/throughput budgets | Hot paths | Release candidate & quarterly |
| Security | AuthZ, injection, secret handling | Sensitive paths | Release candidate & scheduled |
| Chaos/Resilience | Failure handling, recovery | Selected subsystems | Scheduled |

#### Minimum Required Per Feature
- Unit tests for new pure logic (>=80% function coverage for changed lines)
- One component test if cross-module interaction added
- Smoke test ensuring startup of new daemon/CLI entry point
- Contract test when altering externally consumed format (CLI JSON, API, event schema)

#### Test Naming Conventions
```
<scope>/test_<unit_under_test>__<expected_behavior>.py
Examples:
unit/test_role_assigner__selects_first_management_server.py
component/test_peer_identity_flow__consensus_reached.py
smoke/test_agent_startup__exits_zero_help.py
```

#### Execution Profiles
- Quick suite (CI default): unit + component + smoke (<60s target)
- Full suite (nightly): + integration + contract + e2e

#### Skipping & Markers (Pytest)
```python
import pytest
@pytest.mark.slow
@pytest.mark.integration
@pytest.mark.contract
```
CI filters: `pytest -m "not slow"` for quick pass.

#### Flakiness Policy
Any flaky test must be:
1. Quarantined via marker `@pytest.mark.flaky` within 24h
2. Issue created with reproduction details
3. Fixed or removed within 72h

## 7. Core Business Logic (Happy Path)
Implement pure logic first.
- Keep logic side-effect free where possible
- Defer I/O wiring, focus on transformations and decisions

Deliverables:
- Passing happy path tests
- First performance approximation

## 8. Persistence & Queries
Wire storage with transaction safety.
- DAO implementations + transaction boundaries
- Concurrency controls (optimistic/pessimistic)
- Query efficiency review

Deliverables:
- CRUD + domain queries
- Integration tests (fast, isolated DB or container)

## 9. External Integrations
Add broker / HTTP / third-party interactions.
- Client wrappers with timeouts, retries, circuit breakers
- Authentication / token refresh / request validation
- Response validation + graceful degradation

Deliverables:
- Client module
- Contract tests (recorded fixtures) / sandbox mode

## 10. API / Command Wiring
Expose functionality outward.
- Map service results to response DTOs
- Translate exceptions → error codes
- Input validation + sanitation

Deliverables:
- Commands/endpoints with full error handling
- Documentation examples

## 11. Idempotency, Retries, Recovery
Prevent duplicate side-effects.
- Idempotency keys / hash digests
- Duplicate detection / sequence guards
- Compensating actions on partial failure

Deliverables:
- Idempotent operations verified by tests
- Recovery scenarios documented

## 12. Observability
Make behavior visible.
- Structured logging (correlation IDs, request IDs)
- Metrics: QPS, latency percentiles, error rate, saturation
- Tracing spans (if available)

Deliverables:
- Log field conventions
- Metrics + dashboards + alerts

## 13. Security & Permissions
Enforce safe execution.
- AuthN/AuthZ matrix
- Resource scoping (tenant/account/project)
- Input validation + output encoding
- Audit logging for sensitive operations

Deliverables:
- Permission matrix doc
- Security tests / negative cases

## 14. Robustness & Edge Cases
Handle the less-traveled paths.
- Large inputs, empty inputs, null/missing fields
- Timeouts, slow dependencies, race conditions
- Backpressure strategy

Deliverables:
- Edge-case tests
- Load/soak test plan

## 15. Performance & Scalability Pass
Tune and validate.
- Identify hot paths, set latency/throughput budgets
- Indexing, caching, batching, pagination correctness
- Resource usage (CPU/memory) estimates

Deliverables:
- Performance test results
- Tuning notes / capacity assumptions

## 16. Documentation & Examples
Enable users and operators.
- How-to guides (install, configure, operate, troubleshoot)
- API examples (curl, CLI, SDK)
- Runbooks for failure modes

Deliverables:
- User docs / operator runbook
- FAQs / known limitations

## 17. Rollout Plan
Ship safely.
- Migration order, dependency sequencing
- Canary strategy, expansion waves
- Rollback triggers and procedures

Deliverables:
- Rollout checklist
- Escalation + ownership mapping

## 18. Post-Deploy Verification
Validate production health.
- Smoke tests, dashboard review, alert quietness
- Error budget alignment
- Incident drill readiness

Deliverables:
- Verification log
- Follow-up adjustment items

## 19. Maintenance & Next Iterations
Plan longevity.
- Tech debt register
- Refactor candidates
- Roadmap alignment

Deliverables:
- Backlog tickets
- Ownership & SLA notes

---
## Quality Gates (Applied Iteratively)
- Build: PASS/FAIL (compilation, lint)
- Tests: PASS/FAIL (unit/integration/contract)
- Security: PASS/FAIL (authn/authz, validation)
- Performance: PASS/FAIL (budget adherence)
- Documentation: PASS/FAIL (operator readiness)

### Automated Quality Gate Mapping (Added)
| Gate | Enforcement | Tooling | Threshold |
|------|-------------|---------|-----------|
| Build | CI job `build` | compiler + shellcheck | 0 errors |
| Unit Coverage | CI job `test` | pytest + coverage | >= 75% changed lines |
| Lint | CI job `lint` | ruff/flake8/shellcheck | 0 errors (warnings allowed) |
| Security | CI job `security` | bandit + secret scan | 0 HIGH findings |
| Smoke | CI job `smoke` | startup script & py_compile | 100% pass |
| Performance (target) | scheduled | locust/k6/JMH | baseline recorded |

---
## CloudStack / VNF Mapping Quick Reference
- API Contract → Commands (`execute()` wraps errors)
- Data Model → VO + DAO + schema upgrade scripts
- Service Layer → `VnfService` + `VnfServiceImpl` (real logic only)
- External Integration → VNF Broker client (timeouts, retries)
- Configuration → `ConfigKey` + lifecycle wiring
- Observability → log4j2 structured fields + metrics
- Rollout → feature flags, canary networks/accounts, rollback path

---
## Anti-Patterns to Avoid
- Declaring "done" at compile success
- Stub methods that throw NotImplemented in production branch
- Large untested refactors without interface contracts
- Silent failures swallowed without metrics
- One-off scripts instead of documented migrations

---
## Minimal Initial Implementation (If Time-Constrained)
1. API contract + service interfaces
2. Single happy-path method implemented end-to-end
3. Basic logging + one metric
4. One migration + one DAO
5. A smoke test hitting the command
6. Document assumptions

Then iterate toward full methodology.

---
## Checkpoint Rhythm
Recommended checkpoints for a medium feature:
- T0: Charter + contracts
- T+1d: Core logic + happy path test
- T+2d: Persistence + external integration
- T+3d: Edge cases + observability
- T+4d: Rollout + docs + performance pass

---
## Definition of "Implemented" (Strict)
A feature is ONLY "implemented" when:
- All declared public contracts behave as specified
- Business logic executes fully without placeholder throws
- Persistence state changes are durable and correct
- Observability surfaces all critical events
- Tests protect happy path + primary failure modes
- Rollout plan executed or ready

Not implemented if it merely compiles.

---
## Definition of "Ready for Review"
- No TODO throws
- Tests green locally
- Metrics emit baseline signals
- Docs explain usage + recovery

---
## Rapid Triage Flow (If Blocked)
1. Identify class of blocker (build, logic, integration, environment)
2. Reduce scope: implement smallest viable subset
3. Log clearly in README under Blockers section
4. Create follow-up ticket for expansion
5. Continue with next independent module

---
## Value Over Activity Principle
Always prefer delivering one working end-to-end path over 20 partially complete stubs.
If a change cannot be validated (run, test, observed), it isn't progress.

---
## Test Implementation Checklist (Added)
Before merging any feature branch:
- [ ] Unit tests cover new decision branches
- [ ] Smoke test validates daemon/CLI starts (help, py_compile)
- [ ] Negative test included for at least one failure mode
- [ ] Secret handling validated (no accidental print of shared_secret)
- [ ] HMAC logic verified (sign + tamper fail)

*Last updated: 2025-11-08*
