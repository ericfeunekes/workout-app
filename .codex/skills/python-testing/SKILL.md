---
name: python-testing
description: Boundary-first testing for modern Python apps (agents, FastAPI, pipelines).
---
# Python Testing

Boundary-first testing with hermetic defaults, adapter contracts, and CI-ready profiles.

---

## Start Here (60‑second triage)

Answer three questions; then use the recipe.

1) **What changed?**
   - Pure function → **Recipe A (Unit + Property)**
   - Service / endpoint boundary → **Recipe B (Component + Behavior)**
   - External HTTP client → **Recipe C (Recorded HTTP)**
   - Database or migrations → **Recipe D (Component + Integration + Contract)**
   - Agent behavior/state → **Recipe E (Agent Behavior + Golden + Resilience)**

2) **Risk level?** Choose one: `p0` (critical) · `p1` · `p2`.

3) **I/O tier?** Start **Hermetic**; escalate only if needed (see Escalation).

---

## Pick a Recipe

| Situation | Write these tests now | Markers | I/O tier | Command | Examples |
|---|---|---|---|---|---|
| **A. Pure function / transform** | 1 unit + 1 property test (invariants) | `unit`, `property` | Hermetic | `pytest --profile fast -k <module>` | example:python-testing/test_property_transform.py · reference:python-testing/taxonomy.md |
| **B. Service / endpoint boundary** | 1 component (with fakes) + 1 behavior (public API) | `component`, `behavior`, stack marker (`api`/`agents`/`pipelines`) | Hermetic | `pytest --profile pr -k <service>` | example:python-testing/test_api.py |
| **C. External HTTP client** | 1 behavior with VCR cassette + 1 negative/error case (use respx when you need forced failure modes) | `behavior`, `recorded` | Recorded | `pytest --profile pr -k <client>` | example:python-testing/test_http_client.py · reference:python-testing/http-recording.md |
| **D. DB or migrations** | 1 component (fake repo) + 1 adapter **contract** + 1 integration (container) | `component`, `integration`, `db` | Hermetic → Containers | `pytest --profile nightly -m "integration and db"` | example:python-testing/test_contract_user_repo.py · reference:python-testing/contract-tests.md |
| **E. Agent behavior/state** | 1 behavior (stream/format) + 1 golden + 1 resilience (fault plan) | `behavior`, `golden`, `agents` | Hermetic | `pytest --profile pr -m agents` | example:python-testing/test_agents.py · reference:python-testing/stack-playbooks.md |

**Risk hint:** For `p0`, add an unhappy‑path test (validation, retry, auth failure).

---

## Write It (micro‑checklists)

### Determinism (always)
- Inject **Clock**, **UUID/ID**, **Random**. Use seeded RNG or provided fakes.
- Block network by default; allow only via `@pytest.mark.network`.
- Randomize test order in CI.

See reference:python-testing/determinism-kit.md.

### Fakes & Contracts (service boundaries)
- Prefer first‑class **fakes** over patching.
- Define a **contract test** suite for each port (repo/client). Run against fake and real adapter.

See reference:python-testing/contract-tests.md.

### Escalation (I/O ladder)
- Stay Hermetic → **Recorded HTTP** → **Containers** → **Staging (E2E)** only for critical journeys.

See reference:python-testing/io-policy.md.

---

## Run It (profiles)

- Local feedback: `pytest --profile fast`
- PR gate (diff coverage ≥90%):
  ```bash
  pytest --profile pr --cov --cov-report=xml
  diff-cover coverage.xml --fail-under=90
  ```
- Nightly/full + mutation on critical modules:
  ```bash
  pytest --profile nightly --cov --cov-report=html
  mutmut run --paths-to-mutate=src/core/
  ```

See reference:python-testing/profiles-and-ci.md and reference:python-testing/coverage-strategy.md.

---

## Upgrade Existing Tests (quick wins)

- Replace brittle patches with **fakes + DI**.
- Add **contract tests** for adapters; keep fakes aligned with reals.
- Introduce **golden** snapshots for output formats (ignore unstable fields).
- Quarantine and fix flakes (do not mask with retries).
- Add property/stateful tests for transforms and workflows.

See reference:python-testing/stack-playbooks.md.

---



## Prerequisite

- Use `testing-foundations` for the core testing philosophy and layer definitions.

## References

- reference:python-testing/taxonomy.md
- reference:python-testing/profiles-and-ci.md
- reference:python-testing/io-policy.md
- reference:python-testing/coverage-strategy.md
- reference:python-testing/stack-playbooks.md
- reference:python-testing/contract-tests.md
- reference:python-testing/determinism-kit.md
- reference:python-testing/fault-injection.md
- reference:python-testing/http-recording.md
- reference:python-testing/db-fixtures.md
- reference:python-testing/workflow-stateful-tests.md
