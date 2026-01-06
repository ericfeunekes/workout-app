# Overview

The model is organized into a few layers that can evolve independently:

1) **Catalog** — reference facts (exercises, muscles, equipment).
2) **Library** — structured templates parsed from raw workouts.
3) **Planning** — planned workouts on specific dates.
4) **Execution** — what actually happened (sessions + logs).
5) **Intent (Enrichment)** — stimulus labels, check-ins, and metrics that help selection and substitutions.

Guiding ideas:
- **Log first, enrich later.** Missing catalog data should never block logging.
- **Stable IDs.** UUIDs everywhere so we can sync later.
- **Metadata over schema churn.** Keep optional attributes in `*_json` or metadata fields.

See the deep reference: `docs/roadmap/appendix-a-data-model.md`.
