# Test Pyramid (Core)

This is the core, tool‑agnostic test pyramid. Use it to decide where a test belongs and what should run in each band.

## Layers (most → least frequent)

1) **Unit** — pure logic, no side effects
2) **Component/Service** — single module with injected fakes
3) **Integration** — real dependency or local sandbox
4) **Contract** — schema/interface parity
5) **Smoke** — live sanity checks
6) **E2E** — critical user workflows across systems
7) **Performance** — throughput/latency regressions on dedicated infra
8) **Chaos** — controlled fault injection (on‑demand)

## Cross‑cutting checks
Security scans, dependency checks, config/IaC validation, linting, migration safety.

## Execution bands

- **Local fast**: unit + component + deterministic contracts
- **PR/CI**: fast + deterministic integration, no secrets
- **Nightly**: full integration + perf + heavy E2E
- **On‑demand**: live smoke/E2E
