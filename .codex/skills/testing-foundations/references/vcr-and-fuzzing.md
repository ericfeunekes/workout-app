# VCR Baseline + respx/MSW Fuzzing

**Baseline:** record real API behavior with VCR to lock in the actual response shapes.

**Fuzzing:** use respx (Python) or MSW (React) to force error modes and edge cases that are hard to trigger live.

## Workflow

1) Record cassettes against a real endpoint (VCR).
2) Commit cassettes; sanitize secrets.
3) Use VCR for deterministic integration checks.
4) Use respx/MSW to inject timeouts, 4xx/5xx, malformed payloads, and partial responses.
5) Re‑record intentionally when API behavior changes.
