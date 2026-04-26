# Layer Classification Matrix

Pick the lowest layer that can validate the behavior reliably.

| Layer | What it proves | Dependencies allowed | Example | Anti‑pattern |
|---|---|---|---|---|
| Unit | Pure logic correctness | None | validator, parser, reducer | HTTP calls, DB access
| Component/Service | One module with injected fakes | Fakes/in‑memory | service + fake repo | Real DB/network
| Integration (mocked) | Multi‑module flow w/ mocked external deps | HTTP mocks | API endpoint + respx | Live services
| Integration (containerized) | Real dependency behavior | Docker/local service | Postgres migration + query | Prod endpoints
| Contract | Schema/interface parity | None or mocked | OpenAPI schema checks | Full workflows
| Smoke | Live health/sanity | Live endpoints | /health + auth | Deep workflows
| E2E | Critical user journey | Live or staged | login → action → storage | Broad regression suite
| Performance | Throughput/latency | Dedicated infra | 10K rows transform | Shared CI
| Chaos | Resilience to faults | Controlled env | timeout/partial outage | Daily CI
