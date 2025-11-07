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
*Last updated: 2025-11-07*
