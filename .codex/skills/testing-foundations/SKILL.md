---
name: testing-foundations
description: Core testing philosophy and layer classification. Use this skill to decide test layers, apply DI + side-effect isolation, prefer fakes over mocks, and use VCR baseline + respx/MSW fuzzing.
---
# Testing Foundations

Use this skill as the base for all testing work. It defines the test pyramid, layer classification, and the core philosophy:

- Unit tests are for **pure functions**. Don’t chase 100% coverage by mocking everything.
- Isolate side effects behind small wrappers and **inject** them.
- Prefer **fakes/in‑memory** over heavy mocking.
- **Integration tests** provide the strongest signal.
- Use **VCR** to capture real API behavior, then **respx/MSW** to fuzz error cases.

## References

- [references/pyramid.md](references/pyramid.md)
- [references/layer-classification.md](references/layer-classification.md)
- [references/di-side-effects.md](references/di-side-effects.md)
- [references/vcr-and-fuzzing.md](references/vcr-and-fuzzing.md)
