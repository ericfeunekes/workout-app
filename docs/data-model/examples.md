# Examples

## Intent taxonomy + plan metadata (YAML)

```yaml
version: 1

intents:
  - name: "conditioning"
    description: "Primary conditioning intent"
  - name: "vo2max"
    parent: "conditioning"
    description: "High-intensity intervals focused on VO2max"
  - name: "hypertrophy"
    description: "Muscle growth intent"
  - name: "pump"
    parent: "hypertrophy"
    description: "High-rep, metabolic focus"

users:
  - name: "Alice"

templates:
  - name: "Day A"
    intent_primary: "conditioning"
    intent_secondary: "vo2max"
    blocks:
      - block_type: "conditioning"
        structure_type: "intervals"
        intent_primary: "conditioning"
        intent_secondary: "vo2max"
        items:
          - exercise: "Row"
            intent_primary: "conditioning"
            intent_secondary: "vo2max"
            prescription:
              time_sec_target: 60

plans:
  - name: "January Block"
    user: "Alice"
    meta:
      phase: "build"
      notes: "VO2 emphasis, maintain strength"
    days:
      - date: 2026-01-06
        template: "Day A"
        start_time: "07:30"
        duration_min: 60
        meta:
          week: 1
          day_label: "W1D1"
```

Notes:
- `meta` at plan/day is free-form and stays out of core logic.
- `intent_primary`/`intent_secondary` use names defined in `intents`.
