# Plan Templates

Templates for different types of planning work. Choose based on task complexity and type.

## Standard Plan (Most Common)

For features, changes, or fixes that require 5-7 steps.

```markdown
# Plan: [Feature Name]

## Goal
[1-2 sentences: observable outcome + how we know it's done]

## Constraints
- Non-goals: [what we're explicitly NOT doing]
- Dependencies: [external blockers, approvals needed]
- Boundaries: [what must not change]
- Owners: [who approves, if cross-team]

## Discovery Notes
[Key findings from exploration: paths, patterns, constraints discovered]

## Interface / Contract
[Public signatures, API shapes, or schema changes - define BEFORE steps]

## Risks / Unknowns
[List BEFORE steps - these inform step ordering]
- [Risk 1] → [mitigation or validation approach]
- [Unknown 1] → [how to resolve before/during implementation]

## Steps

- [ ] **Step 1:** [Verb + object]
  - Files: [list affected files]
  - Verify: [command or observation to confirm]

- [ ] **Step 2:** [Verb + object]
  - Files: [list]
  - Verify: [how to confirm]

[... 5-7 steps total ...]

## Handoff (if for another agent)
- Entry points: [files to open first]
- Next action: [what to do after plan completion]

## Notes
[Space for implementation discoveries, deviations, decisions made]
```

### Plan Quality Gate

Before executing, verify:
- [ ] All high-risk assumptions validated or first step validates them
- [ ] Public interfaces defined
- [ ] Each step has specific verification
- [ ] No step larger than one vertical slice

## Multi-Phase Plan

For large features requiring multiple phases or milestones. Create a directory instead of a single file.

```
scratch/plan_<feature>/
├── 00_overview.md      # Goals, phases, success criteria
├── 01_phase_foundation.md
├── 02_phase_implementation.md
├── 03_phase_integration.md
└── notes.md            # Running discoveries, decisions
```

### 00_overview.md

```markdown
# Plan: [Feature Name]

## Goal
[Overall outcome and success criteria]

## Phases
1. **Foundation** - [1 sentence summary]
2. **Implementation** - [1 sentence summary]
3. **Integration** - [1 sentence summary]

## Constraints
- Non-goals: [list]
- Dependencies: [list]
- Owners: [who approves]

## Critical Risks
[Top 3 risks that could derail the entire effort]

## Completion Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] All phases complete and verified

## Handoff
- Entry points: [files to open first]
- Next action: [what happens after completion]
```

### Phase Files (01_phase_*.md)

```markdown
# Phase 1: Foundation

## Objective
[What this phase accomplishes]

## Prerequisites
- [ ] [What must be true before starting]

## Interface / Contract
[Interfaces defined in this phase]

## Risks
[Phase-specific risks]

## Steps
- [ ] **Step 1:** [Verb + object]. **Verify:** [how]
- [ ] **Step 2:** [Verb + object]. **Verify:** [how]
[...]

## Exit Criteria
- [ ] [What must be true to move to next phase]

## Notes
[Discoveries, deviations, decisions]
```

## Bug Fix Plan

Lightweight template for bug fixes.

```markdown
# Bug Fix: [Brief description]

## Problem
[What's broken, who's affected, reproduction steps]

## Investigation Focus
[Where to look first - NOT a confirmed root cause until verified]

## Fix
- [ ] **Reproduce:** [Write failing test or repro steps]
- [ ] **Isolate:** [Find exact location/condition - verify root cause]
- [ ] **Fix:** [Minimal change description]
- [ ] **Verify:** [Run test, check regression]

## Risks
- [Any risk of breaking related functionality]
```

## Refactor Plan

For refactoring work that must maintain behavior.

```markdown
# Refactor: [What's being refactored]

## Goal
[Why this refactor, what improves]

## Invariants (Critical)
[What must NOT change - behavior, interfaces, contracts, performance bounds]
- [ ] [Invariant 1]
- [ ] [Invariant 2]

## Baseline
- [ ] All tests pass: `[command]`
- [ ] Baseline metrics captured: [if relevant]

## Risks
[What could go wrong, how to detect]

## Steps
Each step must leave system in passing state.

- [ ] **Step 1:** [Smallest atomic move]. **Verify:** tests pass, invariants hold
- [ ] **Step 2:** [Next move]. **Verify:** tests pass, invariants hold
[...]

## Recovery
If any step breaks tests or invariants:
1. Revert that step immediately
2. Investigate before retrying
```

## Spike / Exploration Plan

For exploratory work where output is learning, not code.

```markdown
# Spike: [Question to answer]

## Hypothesis
[What we think might be true]

## Timebox
[Hard limit: e.g., 2 hours, 1 day - STOP when reached]

## Experiments
- [ ] **Experiment 1:** [What to try, what to observe]
- [ ] **Experiment 2:** [What to try, what to observe]
[...]

## Success Criteria
Answer one of:
- Hypothesis confirmed → [next action]
- Hypothesis rejected → [alternative approach]
- Inconclusive → [what more is needed]

## Findings
[Document discoveries as you go]

## Outcome
[Decision or new plan based on findings]
```

## Data Migration Plan

For schema changes or data migrations.

```markdown
# Migration: [What's being migrated]

## Goal
[What changes, why, success criteria]

## Pre-flight Checks
- [ ] Backup verified: [backup command/location]
- [ ] Rollback tested: [rollback procedure]
- [ ] Staging validated: [staging environment tested]

## Invariants
[Data constraints that must hold after migration]
- [ ] [Invariant 1: e.g., no data loss]
- [ ] [Invariant 2: e.g., referential integrity]

## Strategy
[Approach: big bang, dual-write, backfill, etc.]
[Consider: data volume, throughput impact, downtime requirements]

## Steps
- [ ] **Step 1:** [Migration step]. **Verify:** [validation query/check]
- [ ] **Step 2:** [Migration step]. **Verify:** [validation query/check]
[...]

## Rollback Plan
If any step fails:
1. [How to revert]
2. [How to verify data integrity after revert]

## Post-migration
- [ ] Verify all invariants
- [ ] Monitor for [time period]
- [ ] Clean up: [old columns, temp tables, etc.]
```

## Infrastructure / Ops Plan

For changes that affect running systems.

```markdown
# Infra: [Change description]

## Goal
[What changes, why]

## Pre-flight
- [ ] Permissions verified: [what access needed]
- [ ] Rollback plan documented: [how to undo]
- [ ] Monitoring in place: [what to watch]

## Risks
[What could go wrong, blast radius]

## Steps
- [ ] **Step 1:** [Change]. **Verify:** [health check]
- [ ] **Step 2:** [Change]. **Verify:** [health check]
[...]

## Rollback Plan
If any step fails:
1. [How to revert]
2. [How to verify revert worked]

## Post-change
- [ ] Verify functionality: [smoke test]
- [ ] Monitor for [time period]: [what to watch]
- [ ] Document in: [runbook, ADR, etc.]
```

## Documentation / Skill Plan

For documentation or skill creation work.

```markdown
# Doc: [What's being documented]

## Audience
[Who will read this, what do they need]

## Scope
- Include: [what topics]
- Exclude: [what's out of scope]

## Existing Content
- [List related docs to review or update]

## Steps
- [ ] **Inventory:** Review existing content
- [ ] **Outline:** Draft structure
- [ ] **Draft:** Write content with examples
- [ ] **Validate:** Test against use cases
- [ ] **Review:** Get feedback

## Quality Checks
- [ ] Examples are realistic and tested
- [ ] No conflicts with existing docs
- [ ] Matches audience needs
```
