# AI Developer Brief (how to implement in the right order)

## The one rule
Ship the smallest working loop:
**init DB → import workouts → schedule week → export**

Do not start iOS work until that loop is solid.

## First PR (target)
- Add repo skeleton + CLI scaffolding
- Add DB migrations + migration runner
- Add `doctor` command
- Add stub import that creates `raw_workout` rows from `.md` files

## Second PR
- Add parsing for 3 common patterns:
  - AMRAP
  - EMOM
  - Straight sets
- Create templates/blocks/items when parse confidence is high

## Third PR
- Add scheduling tables + `generate-plan` with simple rules
- Add export to JSON

## Engineering constraints
- Local-only first: SQLite at a path you pass into the CLI
- Migrations must be deterministic and idempotent
- Never lose raw workout text on import
- Parsing must fail gracefully (store errors; keep raw)

## Intent taxonomy
Use the dedicated taxonomy doc as the single source of truth:
`docs/data/intent-taxonomy.md`.

Good: reuse an existing label (`conditioning` → `intervals`).
Bad: invent a near-duplicate label (`conditioning` → `tabata intervals`).

## Testing minimum
- Apply migrations from scratch
- Import fixture workouts
- Generator produces stable output given stable seed
