# DI + Side‑Effect Isolation

**Rule:** isolate side effects into small wrappers and inject them.

## Pattern

1) Wrap the side effect (DB call, HTTP call, file write) in a small function/class.
2) Inject it into the unit under test.
3) Unit tests cover pure logic around the side effect.
4) Integration tests validate the wrapper against real dependencies.

## Why it works

- Makes fakes trivial to supply
- Avoids over‑mocking
- Keeps unit tests pure and fast
- Improves integration test fidelity
