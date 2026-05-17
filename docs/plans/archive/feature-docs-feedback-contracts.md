---
title: Feature docs feedback contracts implementation plan
status: completed
last_reviewed: 2026-04-26
purpose: Rewrite feature documentation around the 2026-04-25 workout feedback as target contracts with explicit current gaps and proof rules.
covers:
  - FEEDBACK-AND-SPEC-2026-04-25.md
  - scratch/feature-docs-update-approach.md
  - docs/features.md
  - docs/features/INDEX.md
  - docs/feature-gap-map.md
  - docs/features/
  - docs/set-edit-sheet.md
  - docs/QA.md
---

# Feature Docs Feedback Contracts Implementation Plan

## Unit Statement

Convert the 2026-04-25 workout feedback into durable target-contract feature docs, a feature-gap map, and proof rules that let later implementation plans understand what is intended, what is already built, and what still needs proof.

## Boundaries Touched

- Product feedback record: `FEEDBACK-AND-SPEC-2026-04-25.md`.
- Planning scratch record: `scratch/feature-docs-update-approach.md`.
- Feature-doc doctrine and navigation: `docs/features.md`, `docs/features/INDEX.md`, `docs/AGENTS.md`, `docs/spec.md`.
- Feature contracts: `docs/features/execute-loop.md`, `docs/features/today.md`, `docs/features/past-set-edit.md`, `docs/features/history.md`, plus new `docs/features/workout-preview.md` and `docs/features/block-transition.md`.
- Authoring vocabulary: `docs/prescription.md`, including block intent and the target/current-doc doctrine.
- Cross-cutting UI contract: new `docs/set-edit-sheet.md`.
- Gap sequencing: `docs/feature-gap-map.md`.
- Future design routing: `docs/open-questions.md`, especially for in-app Claude/chat.
- QA proof semantics: `docs/QA.md`.
- Closeout and workflow hygiene: `docs/runbooks/closeout.md`, plus `docs/WORKFLOW.md` if stale skill aliases keep docs-link validation red.

## Dependencies And Preconditions

- The feature-planning direction in `scratch/feature-docs-update-approach.md` is the source for scope and sequencing.
- Feature docs now describe target behavior, not only current implementation.
- `Current gaps` is the required wording for target behavior that is unimplemented or unproven.
- `docs/feature-gap-map.md` mirrors current gaps and gives priority-derived default phases; implementation planning may later reshuffle.
- `docs/set-edit-sheet.md` is the root-level cross-cutting UI contract. Do not create `docs/interfaces/`.
- Schema decisions are locked for docs purposes:
  - `set_log.skipped BOOLEAN NOT NULL DEFAULT 0`
  - `set_log.side TEXT NOT NULL DEFAULT 'bilateral'` with `left | right | bilateral`
  - `block.intent TEXT NULL`
- `block.intent` null policy is locked: server accepts null, authoring docs require intent for new Claude-authored blocks, and the app renders no placeholder when intent is null.
- Past-mode SetEditSheet edits must preserve the existing past-set-edit invariant: mark `.manual` and never call the driver's autoreg proposal path.
- This unit writes documentation and plans only. It does not implement app code, schema migrations, or simulator QA fixes.

## Uncertainty Reduction Summary

Architecture/history:

- Code/document inspection: `docs/features/INDEX.md` previously framed feature docs as "what the code does today"; this conflicts with the confirmed target-contract doctrine and must be rewritten.
- Code/document inspection: `docs/features/past-set-edit.md` carries the load-bearing past-edit/autoreg invariant; `docs/set-edit-sheet.md` must carry it forward when it becomes the shared edit contract.
- Code/document inspection: `docs/QA.md` exists and is the right home for the `verified` proof definition.
- Code/document inspection: current docs validation has repo-wide pre-existing front-matter/size debt; this unit should make touched files front-matter compliant but should not expand into a repo-wide doc lint cleanup. `docs/prescription.md` already exceeds the size guideline and remains a known debt because this unit must update the authoring vocabulary.

Blast radius:

- The docs pass changes routing and review behavior for future implementation plans. It must update navigators and closeout rules so later agents find and maintain the gap map.
- The feature-gap map is a planning input, not an implementation plan. It must not contain step-by-step build instructions.
- The schema cutover plan is durable backlog work, not scratch. It should be drafted under `docs/plans/backlog/` and kept out of `plans/active/` until selected.

Contract and testing:

- Documentation correctness is an agent/instruction-artifact boundary. Proof needs content consistency checks, link/routing checks, and independent review, not just normal code tests.
- `check_docs.py docs` is currently not a green gate because of pre-existing repo-wide failures. For this unit, it is a regression signal: touched files must not introduce new front-matter failures. The expected remaining touched-file hit is the pre-existing `docs/prescription.md` size warning.
- `check_skill_links.py docs` currently fails on stale skill aliases in `docs/WORKFLOW.md`. Because this unit updates docs workflow/routing, fixing those aliases is in scope and the skill-link check should be green after this unit.

## Approach

Execute the docs pass in dependency order:

1. Verify feedback items that may already be implemented.
2. Lock docs doctrine, status semantics, gap-map semantics, and QA proof semantics.
3. Write new target contracts and the schema backlog plan.
4. Rewrite existing feature docs to target-contract shape with explicit current gaps.
5. Run content, link, docs-hygiene, and independent review proof.

Keep the pass lean. Do not implement app behavior, do not start schema migrations, and do not convert the gap map into a detailed implementation plan.

## Steps

1. Run the blocking verify sweep.
   - Inspect P0-1, P0-2, P0-3, P0-4, P0-6, P1-8, P1-9, P1-10, P1-11, P1-13, and P1-14.
   - Append one verification row per item to `FEEDBACK-AND-SPEC-2026-04-25.md`.
   - Mirror each result into the owning feature doc's `Current gaps` section and into `docs/feature-gap-map.md`.
   - Keep P0-2, P0-3, and P1-11 open unless there is simulator observation or a pinned UI test.
2. Finalize doctrine and routing docs.
   - Ensure `docs/features.md` is the doctrine page for target contracts, current gaps, proof, and implementation-plan handoff.
   - Ensure `docs/features/INDEX.md` is the feature index and status model.
   - Ensure `docs/QA.md` defines accepted `verified` proof artifacts.
   - Ensure `docs/runbooks/closeout.md` requires feature-doc and gap-map updates when gaps close.
   - Update `docs/AGENTS.md`, `docs/spec.md`, `docs/prescription.md`, `docs/open-questions.md`, and `docs/WORKFLOW.md` routing references as needed.
3. Write new docs.
   - Add `docs/features/workout-preview.md`.
   - Add `docs/features/block-transition.md`.
   - Add `docs/set-edit-sheet.md`.
   - Add or update `docs/feature-gap-map.md`.
4. Rewrite existing feature docs.
   - Rewrite `docs/features/execute-loop.md` to target shape.
   - Rewrite `docs/features/today.md`, `docs/features/past-set-edit.md`, and `docs/features/history.md` as target contracts with explicit `Current gaps`.
   - Update `docs/prescription.md` with `## Block intent`, the `block.intent`
     authoring rule, exercise-level unilateral authoring, the reserved
     `set_log.side` field, and the new target/current documentation doctrine.
   - Split `post-workout-edit.md` only if the rewritten `history.md` lands within 10 lines of the 200-line smell threshold in either direction; otherwise fold post-workout edit into `history.md`.
5. Draft the schema cutover backlog plan.
   - Add `docs/plans/backlog/plan_schema-2026-04-26-skipped-side-intent.md`.
   - Include migration scope, the reserved `set_log.side` field, block-intent
     null policy, proof map, and escalation triggers.
   - Keep it out of `docs/plans/active/`.
6. Validate and review.
   - Run the proof map below.
   - Dispatch or run an independent read-only review focused on internal consistency, stale references, missing gaps, and whether the proof map matches repo conventions.
   - Address real findings and rerun focused checks.

## Completion Milestones

- [ ] Verify sweep deferred to
  `docs/plans/backlog/feedback-verify-sweep-2026-04-25.md`; do not treat
  feedback items needing simulator/UI proof as resolved until that plan runs.
- [x] Doctrine/routing docs updated.
- [x] New docs written.
- [x] Existing feature docs rewritten.
- [x] Schema cutover backlog plan drafted.
- [x] Proof map complete.
- [x] Independent review complete.
- [x] Review findings addressed.
- [x] Closeout complete.
- [x] Final report ready.

## Proof Map

### Content Consistency

- Check: `rg -n "docs/interfaces|interfaces/set-edit|planned behavior changes|One first-class data-model|Enum\\?|None for v1|set_log.side.*n/a|side = n/a|docs/features/\\*\\.md describe what the code does today" FEEDBACK-AND-SPEC-2026-04-25.md scratch/feature-docs-update-approach.md docs`
- Boundary class and why: agent/instruction artifact. These docs drive future agent behavior; stale wording is the failure mode.
- Proves: the rejected doc location, stale schema summary, old post-workout pointer language, and old side/default vocabulary did not survive the rewrite.
- User/reviewer verification: command exits 1 or returns only intentionally quoted historical text. Any active-doc hit is a defect.
- Risk remaining: grep cannot prove semantic completeness; independent review covers that.

### Gap Map Coverage

- Check: manually compare `FEEDBACK-AND-SPEC-2026-04-25.md` item index (#1-#26) to `docs/feature-gap-map.md`.
- Boundary class and why: cross-document contract. The feedback spec is the backing record; the gap map is the planning view.
- Proves: every feedback item is represented as implemented/resolved, current gap, later polish, or future design.
- User/reviewer verification: each feedback number appears in exactly one or more appropriate gap rows, with no unexplained omissions.
- Risk remaining: a future implementation plan may reshuffle phases; that is allowed.

### Feature-Doc Contract Shape

- Check: inspect each touched feature doc for target behavior, state surface, deliberate non-goals, current gaps, and QA/proof scenarios.
- Boundary class and why: agent/instruction artifact and user-facing documentation. These docs are the acceptance surface for implementation.
- Proves: feature docs can be read as target contracts rather than current-code notes.
- User/reviewer verification: a reviewer can answer "what should this feature do?" and "what is still open?" without reading the feedback appendix.
- Risk remaining: some implementation details may still be discovered during later code work; those become implementation-plan findings, not docs-pass blockers.

### Link And Routing Hygiene

- Check: `rg -n "feature-gap-map|set-edit-sheet|workout-preview|block-transition|QA.md|features/INDEX" docs README.md AGENTS.md`
- Boundary class and why: cross-document navigation. Agents need durable routes into the new docs.
- Proves: new docs are discoverable from navigators and related feature contracts.
- User/reviewer verification: every new durable doc has at least one incoming route from a navigator or owning feature doc.
- Risk remaining: grep is not a full markdown link checker; manual path checks below cover file existence.

### File Existence And Path Checks

- Check: `test -f docs/features/workout-preview.md && test -f docs/features/block-transition.md && test -f docs/set-edit-sheet.md && test -f docs/feature-gap-map.md && test -f docs/plans/backlog/plan_schema-2026-04-26-skipped-side-intent.md`
- Boundary class and why: filesystem/docs artifact boundary.
- Proves: all promised durable docs exist at the agreed paths.
- User/reviewer verification: command exits 0.
- Risk remaining: existence does not prove content quality; content consistency and review cover that.

### Docs Hygiene

- Check: `git diff --check -- FEEDBACK-AND-SPEC-2026-04-25.md scratch/feature-docs-update-approach.md docs/features.md docs/features/INDEX.md docs/feature-gap-map.md docs/QA.md docs/runbooks/closeout.md docs/AGENTS.md docs/spec.md docs/prescription.md docs/open-questions.md docs/WORKFLOW.md docs/features/execute-loop.md docs/features/today.md docs/features/past-set-edit.md docs/features/history.md docs/features/workout-preview.md docs/features/block-transition.md docs/set-edit-sheet.md docs/plans/backlog/plan_schema-2026-04-26-skipped-side-intent.md`
- Boundary class and why: docs hygiene.
- Proves: no whitespace errors in touched docs.
- User/reviewer verification: command exits 0.
- Risk remaining: none for whitespace.

### Docs Front Matter And Skill Links

- Check: `uv run .codex/skills/documentation-maintenance/scripts/check_docs.py docs`
- Boundary class and why: docs automation.
- Proves: touched docs do not introduce front-matter failures; known repo-wide size debt remains visible instead of hidden.
- User/reviewer verification: full command may still fail on pre-existing repo-wide doc debt. Expected remaining touched-file hit: `docs/prescription.md` exceeds 800 lines, a pre-existing size debt accepted because this unit adds authoring semantics there.
- Risk remaining: repo-wide check remains red until separate documentation-maintenance debt is addressed; `docs/prescription.md` still needs a future split.

- Check: `uv run .codex/skills/documentation-maintenance/scripts/check_skill_links.py docs`
- Boundary class and why: docs automation / skill routing.
- Proves: skill references in docs resolve.
- User/reviewer verification: command exits 0 after this unit; `docs/WORKFLOW.md` stale aliases are fixed in scope.
- Risk remaining: none if green; otherwise residual doc-harness debt remains outside this unit.

### Independent Review

- Check: independent read-only review of the changed docs.
- Boundary class and why: agent/instruction artifact. Same-author self-review is weak for spec and docs changes.
- Proves: the plan/spec/docs are internally consistent, no feedback item is lost, and proof obligations match the target-contract doctrine.
- User/reviewer verification: review returns no blocking findings, or all real findings are addressed and rechecked.
- Risk remaining: review may surface product scope questions. If so, escalate instead of editing around them.

## Independent Review

- Artifact: the final diff across feedback spec, approach doc, feature docs, gap map, QA docs, navigators, and schema backlog plan.
- Reviewer: independent Codex/cxd read-only review, or equivalent different-context review lane following the repo workflow.
- Reopen condition: any finding that shows a feedback item was dropped, a target contract contradicts the backing spec, a proof status overclaims evidence, or the docs route an implementer to the wrong file.

## Closeout

- Domain docs still accurate: `docs/features.md`, `docs/features/INDEX.md`, `docs/feature-gap-map.md`, `docs/QA.md`, and `docs/prescription.md`.
- Routing surfaces updated: `docs/AGENTS.md`, `docs/spec.md`, `docs/open-questions.md`, and `docs/WORKFLOW.md` as needed.
- Docs/comments/records: `FEEDBACK-AND-SPEC-2026-04-25.md` contains verify rows; `scratch/feature-docs-update-approach.md` no longer contains unresolved reviewer comments.
- Task/checklist closure: update this plan's milestones before final report.
- Final proof summary: report files changed, proof commands, any pre-existing checker failures, and remaining proof-only uncertainty.

## Closeout Result

- File existence checks for the promised new docs passed.
- `docs/feature-gap-map.md` covers feedback IDs #1 through #26.
- `git diff --check` passed for Phase 1 paths.
- `uv run .codex/skills/documentation-maintenance/scripts/check_skill_links.py docs` passed.
- `uv run .codex/skills/documentation-maintenance/scripts/check_docs.py docs`
  remains red on pre-existing repo-wide front-matter and size debt outside the
  new Phase 1 docs and just-fixed touched feature docs.
- Codex review thread `019dca4d-d8cc-7a43-9ec1-b0aedce5b488` returned `Clean
  for Phase 1 commit` after two fix/review loops.
- Simulator QA was not applicable because this phase changed docs/contracts
  only and did not change user-facing app runtime behavior.

## Recovery Context

- Unit statement: Convert 2026-04-25 workout feedback into target-contract feature docs with current gaps, gap-map sequencing, and proof semantics.
- Implementation lane or owner: main agent or documentation worker briefed from this plan.
- Review lane or owner: independent read-only review after the docs diff is complete.
- Next thing to resume if blocked: continue at the first unchecked milestone above; do not rediscover scope from chat history.
- Proof still expected: content grep, feedback-to-gap-map coverage check, path checks, `git diff --check`, docs hygiene checks, skill-link check, and independent review.
- Closeout still expected: update milestones here, summarize proof, and preserve any unresolved proof-only uncertainty.

## Residual Uncertainty / Accepted Risks

- What is open: P0-2/P0-3 visual/tap-target status and P1-11 timer-flow status cannot be resolved by code inspection.
  - Why accepted: this is a docs implementation unit; simulator proof belongs to the later implementation/QA unit.
  - Signal that this risk has landed: any doc marks those items `verified` without simulator observation or pinned UI test evidence.
- What is open: full `check_docs.py docs` is red because of pre-existing repo-wide front-matter and size debt, including the already-large `docs/prescription.md`.
  - Why accepted: fixing every existing docs hygiene failure, or splitting the prescription vocabulary while also changing its semantics, is a separate documentation-maintenance unit and would swamp this feedback-docs pass.
  - Signal that this risk has landed: a touched file appears with a new front-matter failure, or a touched file other than the already-large `docs/prescription.md` appears in the size-failure list after this unit.

## Escalation Triggers

- A verify-sweep item contradicts the feedback spec enough to change acceptance criteria rather than just current-gap status.
- A feature doc rewrite reveals target behavior that is still product-ambiguous, not implementation-ambiguous.
- `history.md` plus post-workout edit cannot stay comfortably under the feature-doc size guideline; split to `docs/features/post-workout-edit.md` instead of forcing the fold.
- Schema planning discovers a need for a fourth column or a non-cutover migration strategy.
- Independent review finds a dropped feedback item, contradictory target contract, or overclaimed proof status.
- A docs validation failure appears in a touched file and cannot be resolved without expanding into repo-wide docs lint cleanup.
