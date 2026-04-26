---
title: Workout app — UX feedback + change spec
captured: 2026-04-25
synthesized: 2026-04-26
source: ~/ai notes/_inbox/workout-app-feedback-2026-04-25.md
status: draft (PM-synthesized; not yet reviewed by Eric)
---

# Workout app — change spec from 2026-04-25 feedback

26 numbered items from a real session. Top half is the synthesized, dev-ready spec grouped by priority. Bottom half is the raw feedback verbatim so the original context travels with it.

**Repo-staleness caveat.** This spec was written against a checkout that's 1–2 days behind Eric's working tree. Anything I flag as "bug" or "missing" needs **verify against current code** before scheduling — the latest may already address it. Items that touch the schema explicitly call out the assumption I made about the current shape so Eric can reconcile.

**Conventions.**
- `[PM decision: …]` = a call I made that wasn't explicit in the feedback. Eric can flag any to revisit.
- `[verify]` = behavior that may already be implemented; check before scheduling.
- `[schema]` = touches the data model — needs a coordinated cutover per `docs/MIGRATIONS.md`.
- Every item links back to its raw feedback number (#N) at the end.

---

## TL;DR

Three Must-fix bugs (#5, #12, #16). One large, coordinated UX redesign across four screens (Preview / Active / Rest / Transition — items #1, #2, #3, #6, #7, #8, #10, #14, #15, #17, #20). Three coordinated data-model additions (`set_log.skipped`, `set_log.side`, `block.intent`). Two items left explicitly open as design work (#22 modifier modeling, #24 in-app chat). One nice-to-have (#9 ETA).

---

## Priority 0 — Must-fix bugs and pure UX wins

Small, isolated, high pain-per-fix. Schedule first.

### P0-1. Rest timer `"waiting to start"` state — remove (#5) [verify]
The rest-timer card displays `"waiting to start"` after the workout has started. That string is only meaningful pre-start.

**Acceptance:**
- After `SessionState.route` transitions out of `.today`, the rest face never renders the `"waiting to start"` copy.
- Valid in-workout rest states are exactly: programmed rest countdown, transition between blocks, transition between sets within a block.
- Mid-workout rest face replaces dead copy with the dot-grid from #14 (P1-7) or, if dot grid isn't ready in this slice, a neutral `"REST"` label.

[verify] — search `RestView.swift` for the literal string. May already be removed.

---

### P0-2. "Done" button tap target on preview screens (#12)
Eric: "almost three taps to register." Same problem on the preview that surfaces when tapping `"What's next?"` from the active screen — Done button is greyed out and equally hard to hit.

**Acceptance:**
- Tap target ≥ 44×44 pt (Apple HIG minimum).
- Hit area matches visible area (no shrunken touch region).
- Disabled-state styling is visually distinct from enabled state — see P0-3.
- Audit any shared button component used on both `WorkoutPreviewView` and the "What's next?" preview.

**Likely root cause:** shared `DSButton` (or equivalent) with low-contrast active-state token. Fix the component, the duplicated bug evaporates.

---

### P0-3. "Log" / "Done" button rendered greyed-out but functional (#16) — same root cause as P0-2
Visual confirmation from screenshot `019dc997-IMG_3224.png`: the bottom CTA reads `"log station"` in low-contrast peach/coral on dark background. Reads as disabled.

**Acceptance:**
- Primary CTA (Log / Done) uses a high-contrast color token in its enabled state — saturation + weight clearly distinct from the disabled state.
- Disabled state is visually distinct, lower-contrast, with a small affordance (lock icon, opacity step) so it reads as "not yet" rather than "not at all."
- One token-pair fix flows to every screen using `DSButton` (active-set, log sheet, preview Done, "What's next?" Done).

[PM decision: treat P0-2 and P0-3 as a single ticket. The bug is the same — primary-CTA contrast + tap-target contract on `DSButton`.]

---

### P0-4. Bodyweight is a default, not a constraint (#21) [verify]
The weight field on a bodyweight-tagged exercise must always be editable — for weighted dips, weighted pull-ups, goblet squats from a bodyweight squat, etc.

**Acceptance:**
- Active screen: weight field on a bodyweight item starts with the seed (nil → "BW") but is tappable and editable.
- Editing produces a `set_log` row with `weight = entered_value, weight_unit = preferred_unit` and the prescribed shape's bodyweight semantics preserved (i.e. `weight_unit` from the SetPlan).
- Wired through the bottom-sheet edit panel from P1-2 (#6).

[verify] — schema already supports this. Per `docs/prescription.md` § "Bodyweight and weighted bodyweight": weighted bodyweight items use `load_kg` as the *added* weight; `SetPlan.loadKg: Double?` allows nil = unloaded BW. **This is a UX confirmation, not a schema change.** Verify the active-set numpad doesn't lock when the seeded `loadKg` is nil.

---

### P0-5. Skip button always present alongside log/done (#4)
Whenever a block / set is active, a Skip button must exist alongside Log / Done. Also between sets (rest screen).

**Acceptance:**
- Active face: Skip is a visible action on the bottom bar, separate from Log/Done. On a single-exercise set it sits as a tertiary action; on a superset, it integrates with the layout from P1-9 (#20).
- Rest face: Skip is reachable from the rest screen and advances past the next set without logging.
- Skipping marks the set with a new state. **Decision (Eric, 2026-04-25): proper schema add — `skipped: Bool` on `set_log`, with migration.** No notes-bridge fallback. Server migration + SwiftData migration + parity contract test per `docs/MIGRATIONS.md`.

[schema] — see Cross-cutting § Schema implications.

---

### P0-6. "What's next?" preview includes remaining work in *current* block (#13)
Tapping "What's next?" currently skips ahead to the next block. The mental model is "what do I still have to do" = remaining sets in current block + everything ahead.

**Acceptance:**
- `WhatsNextSheet` (or whatever the surface is named) lists: remaining sets of current block, then upcoming blocks in order.
- Clear visual separation between "current block — N sets remaining" and "upcoming blocks."
- Tapping any row scrolls the underlying preview / scrolling column (#15 / P1-3) to that location.

---

## Priority 1 — Coordinated UX redesigns

These cluster into a few related screens. Implement together where the cluster note says so — they share data plumbing.

### P1-1. Decouple "open workout" from "start workout" (#1, #2, #3)
Tapping a workout from `Today` opens a **preview**, not an active session. The preview is editable; `Start` is a separate explicit action.

**Acceptance:**
- New `WorkoutPreviewView` is the destination for `Today → tap workout`. Workout status stays `planned` until the user taps **Start**.
- Preview shows the full workout (every block, every item, every set) in a scrolling column.
- From the preview, the user can:
  1. Tap a workout_item → bottom-sheet edit panel (P1-2) → swap exercise, change rep scheme, change load, change set count.
  2. Long-press / swipe a block → Delete (`[PM decision: swipe-to-delete with confirm; matches #15 row interactions for consistency]`).
  3. Tap **Start** → workout transitions to `.active`, route flips to `.active` view.
- Edits made from preview persist to the local workout cache and push to server via the existing PUT `/api/workouts/:id` path so the next pull sees them.
- Edits do **not** mutate the original Claude-authored shape on the server beyond what's already in the PUT contract — preview edits ARE workout-row edits.

**Coordination:** P1-1 + P1-2 ship together. Without the bottom sheet there's no edit affordance from preview.

[PM decision: preview-edit and active-mid-workout-edit (#7) reuse the **same** bottom-sheet component. One sheet, two contexts.]

[verify] — `Today → Start` is currently auto-start. Confirm the route in `Features/Today/`.

---

### P1-2. Bottom-sheet edit panel for any set (#6, #7)
Logging and editing pop a bottom sheet, not inline-under-reps. Reusable across:
- Active set on Active face
- Past set on Rest screen ("just-did" pills)
- Any set in the scrolling column (#15) — past, current, future
- Any block / set in preview (#1)
- Any logged set post-workout (#26)

**Acceptance:**
- One component: `SetEditSheet` (rename if a better one fits Eric's design system).
- Inputs: target `set_log_id` (or `(workout_item_id, set_index)` for not-yet-logged), edit mode (`pending` vs `past`), and the surfacing screen's context.
- Fields rendered: reps (numpad), weight (numpad + unit), RIR (row picker), notes (text field). For carries: distance OR duration (numpad + unit). All optional per the prescription's shape — see P1-7 for carry-specific UI.
- Read-only when no field is editable for the current shape (e.g. EMOM minute placeholder).
- Inline display under reps/sets stays as the read-only summary; the sheet is the single edit surface.
- Apply-to-all affordance (per P1-3) lives in the sheet for weight changes.

**Coordination:** P1-1, P1-3, P1-4, P1-10, P1-13 all consume this component.

---

### P1-3. Active-screen scrolling column with swipe / apply-to-all (#15)
Replace the current "current set + next exercise card + 30% empty space" with a scrolling column of every set in the current block.

**Layout:**
- One row per set in the current block. Supersets show all slots within a set as visually grouped (indent or paired markers — `[PM decision: vertical bracket on the left of grouped rows; matches #14 dot grid orientation]`).
- Current set: highlighted, sticky position-aware (auto-snaps near vertical center as the user advances).
- Past sets: greyed, but tappable → `SetEditSheet` in `past` mode.
- Future sets: fully visible (target 2–3 fit on screen); set N+far is below the fold but reachable by scroll.
- Floating "scroll back to current" pill appears whenever the highlighted set is offscreen; tap snaps back.

**Row interactions:**
- **Tap** → `SetEditSheet` (P1-2). For pending: open as `pending`; for past: open as `past` (corrective).
- **Swipe-left** → reveals **Skip** (orange) + **Swap** (neutral). Skip marks the set skipped; Swap opens the alternative picker.
- **Long-press** → details: history for this exercise, prior loads for this user, notes.
- **After Swap commit:** prompt **"Apply to all sets in this block?"** with `Just this set` / `All remaining` / `Cancel`. **Decision (Eric, 2026-04-25):** future sets only — never overwrites past logged sets. "All remaining" replaces every non-`done` SetPlan in the item; past `set_log` rows keep their `performed_exercise_id`.
- **Weight edit in sheet:** same prompt. **Decision (Eric, 2026-04-25):** applies to remaining sets across the **block**, not just the item. In practice the cross-item case isn't a problem — different items in the block already have their own prescriptions, and supersets are by definition different exercises (or same exercise with different prescriptions). The edit propagates to remaining sets of the same exercise/item; other items keep their own values.

**Acceptance:**
- The view's data source is the existing `SessionState.items[blockIndex]` SetPlan/ItemLog list — no new wire payload needed.
- Apply-to-all writes through `editPendingSet` for each affected set with `adjust = "manual"` (existing reducer mutation, see `SessionReducer+Handlers.swift`).

**Coordination:** P1-3 supersedes the current `ActiveView` "next exercise" card. Pairs with P1-4 (visual hierarchy of the focal block above the column).

---

### P1-4. Active-set screen visual hierarchy (#17)
Reference: screenshot `019dc997-IMG_3224.png` — Eric's words: *"20 lb but I had to look around to figure out what it was."*

**New top-down hierarchy:**
1. **Focal unit (top, hero):** `<Exercise name> — <load> × <reps>` rendered as one composition. Exercise name is at minimum the same visual weight as the weight number. No more "Incline Dumbbell Curl" buried in the corner above a giant unlabeled "20 lb."
2. **Set / round context (below focal, supporting):** "ROUND 3 OF 3" + set timer. Smaller than the focal unit.
3. **Superset structure (below context, when applicable):** when the block is `superset` / `circuit` / `for_time` / `amrap`, the focal unit is wrapped in a "superset slot N of M" frame, with the other slots in this round listed beneath as muted rows. The current "NEXT EXERCISE" card is replaced by this multi-slot view.
4. **Scrolling column (below superset frame):** P1-3 — past, current, future sets in the block.
5. **Bottom CTA bar:** P1-9 — Done + Next-Exercise buttons in the right proportions.

**Implication for the rendering layer:** The Active face needs to know `(timing_mode, slot_count_in_round, current_slot_index)` from the current block. All present in `SessionState.Structure`; just a rendering change.

**Acceptance:**
- Single exercise inside a `straight_sets` block: focal + context + scrolling column + full-width Done. No superset frame.
- Superset / circuit / AMRAP / for_time: focal + context + superset frame (slot N of M with peers visible) + scrolling column + split bottom bar (P1-9).
- The active screen is information-dense by design — the empty 30% is allocated to the column and the superset frame.

**Coordination:** P1-3, P1-4, P1-9 ship together. They share screen real estate and a single layout pass should land them.

---

### P1-5. Block-edit access during workout (#7)
While the workout is active, the user can open the bottom-sheet edit panel for **any** block / set — current, future, or past.

**Acceptance:**
- Active scrolling column (P1-3) covers the *current* block.
- A separate "all blocks" surface (e.g. tap "What's next?" from active, or a dedicated "Plan" tab in the active session) shows the full workout summary with edit affordances per block.
- Past-block edits write `set_log` corrections (existing past-set-edit path, see `docs/features/past-set-edit.md`); future-block edits write `editPendingSet`-style adjustments to the SetPlan structure of the unstarted block.
- "Future block" edits (swap exercise, change rep scheme) propagate to the workout via the same PUT `/api/workouts/:id` contract used by preview edits in P1-1.

[PM decision: a future-block exercise swap *during* the active session does NOT spawn an alternative — it edits the `workout_item.exercise_id` for the upcoming block. Mid-session swap on the *current* block remains alternative-based via existing exercise-swap path.]

---

### P1-6. Workout summary "you-are-here" indicator (#8)
The full workout summary view (whatever surface it lives on — preview view, "Plan" tab during active, or the post-workout summary) shows where the user is.

**Acceptance:**
- A clear visual marker (highlighted row, bold rule, "▶ now" annotation) on the current block / set.
- Marker updates as the user progresses through sets.
- Single rule: same component renders the marker whether viewed mid-workout or post-workout (post-workout marker shows the last logged set / completion point).

---

### P1-7. Rest-screen dot-grid progress (#14)
Replace the "waiting to start" dead copy (P0-1) with a 2-D dot grid that visualizes block structure + position.

**Layout:**
- **Horizontal axis = sets remaining in this block.** A 5-set straight_sets block renders 5 dots on one row.
- **Vertical axis = exercises within a set (slot count).** A normal exercise = 1 row. A 2-exercise superset = 2 rows of dots. A 3-exercise circuit = 3 rows.
- **Dot states:**
  - Filled / accent → completed
  - Outlined / accent → current (the "you are here" dot)
  - Hollow → remaining
- A 2-exercise × 3-round superset, currently 1.5 rounds in (just finished round 2's first slot), renders:
  ```
  ●●○         ← exercise 1: rounds 1, 2 done; round 3 pending
  ●○○         ← exercise 2: round 1 done; round 2 current; round 3 pending
  ```
  (current state = ◉ on row 2, column 2.)

**Acceptance:**
- Component takes `(slots_per_round, total_rounds, current_slot, current_round, completed_slots)`. All present in `SessionState.Structure.advancementByBlock` + `cursor`.
- Replaces the existing 1-D `●●●` progress dot row on the active and rest faces for round-robin blocks. Single-exercise straight_sets blocks render a single row (1-D, equivalent to today's UI).
- Per-side exercises render as 2 vertical rows when `per_side: true` is set on the prescription — see P1-8.

**Coordination:** P1-7 and P1-4 share the data shape; build the dot-grid component once, render it on both Active (above the scrolling column) and Rest (replacing the dead "waiting" copy).

---

### P1-8. Per-side reps explicit + render as slots (#19) [schema]
"10 reps" must never be ambiguous. Per-side and total are different.

**UI acceptance:**
- Display "10 reps **per side**" when the prescription carries `per_side: true`. Display "10 reps **total**" otherwise (or just "10 reps" — the absence is the convention).
- In the dot grid (P1-7), per-side exercises render as 2 vertical rows (left, right) — the user advances via P1-9's Next button through `left → right → next set`.
- Per-side weight: render "30 lb per hand" or equivalent when applicable.

**Schema:** **two `set_log` rows per set** — one per side. **Decision (Eric, 2026-04-25):** asymmetry between left and right is real and load-bearing. Example: single-arm DB bench press where one arm can't match the other's load. Need to log left and right independently — different reps, different load, different RIR per side.

Migration: introduce a `side` column on `set_log` (enum: `left`, `right`, `bilateral`). For non-per-side logs, `side = bilateral`; for per-side, two rows with `side = left` and `side = right` per set. Server migration + SwiftData migration + parity contract test per `docs/MIGRATIONS.md`.

[verify] — confirm `per_side` is read by the active-set rendering layer, not just the prescription parser.

---

### P1-9. Superset progression: Done + Next-Exercise buttons (#20)
**Layout rules:**
- **Single-exercise set** (block advancement = `setMajor` AND no `per_side`): full-width **Done** button. Current behavior.
- **Multi-slot set** (block advancement = `roundRobin` OR `per_side: true`): split bottom bar — **Done** at ~1/5 width on the left; **Next exercise** taking ~4/5 on the right. Tap-next-next-next progresses through slots within the round; Done finishes the entire current set / round and triggers rest.

**Tracking:**
- `[PM decision: timing per slot is captured by stamping `set_log.started_at` and `set_log.completed_at` per slot using the existing fields. Round-robin already advances cursor on `.advanceFromRest`; the work-start anchor (`SessionState.workStartedAt`) becomes per-slot rather than per-set. No new schema.]`

**Acceptance:**
- Bottom bar layout reads `(advancement_mode, slot_count)` from the active block and switches.
- Tapping "Next" on the last slot of the round = tapping "Done": advances cursor to the next round's first slot (or to rest if cursor exceeds rounds).
- Logging stays at rest per #11 / P1-10. Next-Exercise does not pop a log sheet.

[verify] — confirm `SessionState.workStartedAt` is currently stamped at the round level vs slot level. This may need a small reducer change.

---

### P1-10. Logging happens at rest, not mid-superset (#11) [verify]
Mid-superset, the active face never pops a log entry form.

**Acceptance per `docs/prescription.md` § Superset:**
- Active face during superset: shows current slot + peer slots (P1-4), **no log entry**.
- Rest face: shows the per-slot log inputs for every slot in the just-completed round (3-slot superset → 3 sets of inputs on one rest screen).
- All logging within a round happens on that round's rest screen.

**History-edit path for after-the-fact corrections:**
- A History view exposes every logged set.
- Tapping a logged set opens `SetEditSheet` (P1-2) in `past` mode.
- The sheet may surface a follow-up question when the logged value diverges from the plan: e.g. "you logged 8 reps but the plan was 10 — was that intentional?" — captured as a `notes` annotation. `[PM decision: defer the follow-up-question feature to v1.1+; it's a chat-with-Claude feature in disguise, see #24 / P3-2.]`

[verify] — per `prescription.md`, "User does not log mid-round — logging happens on the shared rest screen for all items of that round." If Eric saw a log screen pop mid-superset, it's a regression worth investigating before treating it as a redesign.

---

### P1-11. Rest timer starts immediately, never pauses (#23)
Refines #11 / P1-10. The rest clock and the log UI are independent.

**Acceptance:**
- The instant a set is marked done (Done button on Active, or auto-advance), `state.restEndsAt = now + restDuration` and the rest face renders with the timer running.
- The log sheet (P1-2) opens **on top of** the rest face for "log the just-completed slot(s)." The timer continues to tick down regardless of whether the sheet is open, in the middle of an edit, or dismissed.
- Backgrounding, foregrounding, dismissing the sheet, opening swap, opening any other sheet — none of these may pause the rest timer.
- No code path on the active → rest transition pauses the timer.

**Implementation note:** `restEndsAt` is already an absolute `Date` per `docs/features/execute-loop.md`. The rule here is about UI flow paths, not the timer itself — audit every path that opens a modal during rest and confirm none of them stop the timer.

[verify] — confirm via search for any `pause`-style timer call in `RestView` / `ExecutionViewModel`.

---

### P1-12. Between-block transition shows the complete next block (#10)
When a block finishes, the transition screen previews the **complete** next block — exercise, sets, reps, weight, equipment, anything else needed for setup.

**Acceptance:**
- New `BlockTransitionView` (or a state on the existing rest face for `block_end → block_start`).
- Renders: block name, intent (per #25 / P2-1), every workout_item with full prescription (sets, reps, load, RIR target, equipment cue if available), timing mode + key config (e.g. "30s rest between sets").
- "Start next block" CTA replaces "advance" — explicit, since prep happened during the rest.
- If the prescription has `notes` on items (Claude's setup cue: "preload 95 lb"), surface them prominently.

**Coordination:** Pairs with P1-11 — the rest timer ticks down through the transition view; user can dismiss to ride out remaining rest before tapping Start.

---

### P1-13. Carries: weight + distance (or time) editable (#18)
Loaded carries (suitcase, farmer's, etc.) need both weight and distance/time prominent and editable.

**Acceptance:**
- The active face's focal unit (P1-4) renders the carry's primary metric: `<weight> × <distance>` for distance carries, `<weight> × <duration>` for time carries.
- `SetEditSheet` (P1-2) routes to a carry-specific input layout: weight numpad + distance/duration numpad, both editable.
- The prescription shape distinguishes rep-based from carry-based — `[PM decision: use the existing prescription_json conventions: distance carries → {load_kg, distance_m}; time carries → {load_kg, duration_sec}. The app reads the keys present and renders the appropriate UI. No schema migration needed — these keys are already valid in prescription_json (see docs/prescription.md § "Per-timing-mode shapes").]`
- Per-side carries (suitcase) honor `per_side: true` per P1-8.

[verify] — confirm `SetPlan` carries `distance_m` / `duration_sec` fields and that `SetLog` writes them. Spec says yes; check.

---

### P1-14. Post-workout: every field editable (#26)
After save & done, every logged set is editable — reps, weight, time, distance, RIR, notes, skipped status. Nothing is read-only.

**Acceptance:**
- History detail view shows every set in the completed workout.
- Tapping a set opens `SetEditSheet` (P1-2) in `past` mode — same component as in-workout past-set-edit.
- Edits write through the existing past-set-edit path (`docs/features/past-set-edit.md`): same-UUID upsert; corrections do **not** retrigger autoreg.
- Skipped sets editable too — change `skipped → reps + weight` retroactively, or vice versa.

[verify] — `docs/features/history.md` says the edit sheet shipped (bug-015 / bug-051). Confirm coverage extends to all fields including notes and skipped status.

---

## Priority 2 — New work

### P2-1. Block intent as a first-class field (#25) [schema]
Every block carries an explicit intent. Without it, after-action review is unfalsifiable.

**Decision (Eric, 2026-04-25): intent is a freeform qualitative description, NOT an enum.** Goals (the existing structured concept — max sets / max reps / etc.) handle the structured side. Intent captures the *why* in the level of nuance an enum can't:

> "Give some leg strength exposure without affecting the core, so you can go into core hard afterwards."
> "Hit some legs while doing core — hammering core throughout."

These two are different intents on a block that might have the same exercises. An enum can't carry that distinction. Tag sets miss it too.

**Schema change:**
- Add `block.intent` (TEXT, nullable) to the `block` table. Server migration + SwiftData migration + schema parity contract test + spec update — coordinated cutover per `docs/MIGRATIONS.md`.
- Wire-format: `block.intent` is a freeform string; null = "intent not declared" (legacy / Claude punted).
- Server write policy: accept null indefinitely. `docs/prescription.md` owns the authoring requirement that new Claude-authored blocks should carry intent; this is not a server rejection rule.
- App render policy: if intent is null, render no placeholder copy.
- No starter taxonomy — Claude (the conversation layer) generates the intent text per block when authoring the prescription. The app reads and displays it; doesn't validate against a closed set.

**Goals vs intent (separate concepts):**
- **Goals** — structured target for the block (max sets, max reps, hit X RIR, etc.). Already exists per Eric's note. Drives the prescription's numeric targets.
- **Intent** — qualitative purpose. Drives mid-workout judgment ("is this block serving its intent? should I swap?") and post-workout review.

`[PM decision: scope intent to BLOCKS only, not the workout. A workout can mix intents. A workout-level intent could be derived from the block intent histogram or from the prescription header — defer that derivation to Claude's analysis layer, not the app.]`

**UI acceptance:**
- Preview screen (P1-1): each block displays its intent prominently above the block name.
- Active face: intent is visible on the focal unit's metadata line (small caption alongside "ROUND N OF M"). User can scan during work and decide whether to mid-workout-swap.
- Post-workout: intent surfaces in the history detail and in any "did this block hit its intent?" prompt (P3-2).

**Authoring side:**
- `docs/prescription.md` gets a new section: `## Block intent`. Claude must populate `intent` on every block in v1.1+ pushes; legacy null is allowed.
- Schema seeder for development sets sensible defaults for fixtures.

**Coordination:** Schema migration per `docs/MIGRATIONS.md` § seven-step cutover.

---

### P2-2. Estimated time-to-completion (#9)
Nice-to-have. Sum of: remaining work-time + remaining programmed rest + transitions.

**Acceptance:**
- Renders on the workout summary view (P1-6) as "ETA: 23 min remaining."
- Updates as the user progresses; recomputed on each `.advance` mutation.
- Computation:
  - For each remaining set: `work_time_estimate = reps × per_rep_estimate` (default `[PM decision: 3 sec/rep, configurable per timing mode if it ever needs to be]`).
  - For each remaining rest: `rest_duration_sec`.
  - For each remaining block transition: `[PM decision: 60 sec flat estimate]`.
  - Cardio blocks: `target_duration_sec` if authored, else `target_distance_m / target_pace_sec_per_km`.
- Stretch: refine per-rep estimate from rolling history of recent set durations once it exists.

`[PM decision: defer until P0/P1 lands. Low risk, low blocking, but earns its keep only if the rest of the screen is solid.]`

---

## Priority 3 — Open design / future work

### P3-1. Equipment / modifier modeling (#22) [schema] [open design]
Eric explicitly flagged this as a design question, not a spec item. **No decision yet — leave open until an ADR is written.**

**The questions to resolve in the ADR:**
1. **When does an implement / modifier change the *exercise identity* vs. become an *attribute* on the same exercise?**
   - Banded Pallof press → different exercise, or same exercise with band attribute?
   - Banded deadlift → same as above?
   - KB suitcase carry vs DB suitcase carry → same exercise (Eric thinks yes)?
2. **Machine-stack exercises** — is the unit the **stack pin number** (machine-specific) or a **calibrated weight** (requires per-machine calibration data)?
3. **Implement interchangeability** — for KB ↔ DB on a carry, do we capture implement for history filtering or just track weight?

**Eric's stated heuristic (from the feedback, his words):**
- Same movement, different implement, same load semantics → same exercise.
- Same movement, modifier that changes the load curve (bands, chains) → flag as a modifier on the same exercise; capture modifier separately.
- Same movement, dramatically different equipment that changes mechanics → different exercise.

**Spec-time action items** `[PM decision: don't lock the schema until the ADR is written. Concrete next step:]`
- Open `docs/decisions/ADR-2026-04-XX-equipment-modifiers.md` with the three questions above.
- Ship a **draft prescription extension** in `docs/prescription.md` § Modifiers as a parametric shape: `{modifier: {kind: "band", tension_kg_at_top: 20}}` that lives in `prescription_json` (no schema change, JSON-blob extension). Use it in fixtures so the shape can be exercised; promote to first-class schema when the ADR locks.
- Until then: log machine-stack exercises with `load_kg = pin_value` and a `notes = "machine: <id>"` annotation. Crude but lossless.

**Do NOT:** rush a schema migration here. The wrong abstraction will outlive the right one for years.

---

### P3-2. In-app chat with Claude / Codex (#24) [future] [open design]
Future feature. Eric's spec: "not a near-term build but worth designing the data flow now so notes/descriptions aren't built as a dead-end field."

**What's in scope of the design exercise (not the build):**
- **Touchpoints:**
  1. Notes field on a logged set: free-text, persisted on `set_log.notes`, optionally piped to Claude with the set's context (block intent, prescribed vs actual, RIR).
  2. Standalone chat surface (tab or sliding panel) — accepts free-form text mid-workout.
- **Capabilities Claude needs:**
  1. Read current workout state (current block, intent, completed sets, planned sets ahead).
  2. Read recent history (last N sessions for relevant exercises).
  3. Propose mid-workout edits — swap an exercise, change rep / weight target, restructure remaining blocks. Each proposal is a structured diff against the current workout.
  4. User accepts / rejects each proposal.

**Spec-time action items** `[PM decision: open a design doc, not a build ticket:]`
- Open `docs/design/in-app-chat.md` (sketch) or an ADR (`ADR-2026-04-XX-in-app-claude-chat.md`) with:
  1. Data the chat surface receives (workout state, intent, history slice).
  2. Proposal format — a structured "patch" against the workout (`workout_item` swap, prescription mutate, block delete, block insert).
  3. Accept / reject mechanics — does an accepted proposal write through the existing PUT `/api/workouts/:id` path, or a new endpoint?
  4. Sync model — chat happens locally to the app (Anthropic API call), server side, or via the home server as a relay?
  5. What gets persisted on `set_log.notes` vs sent to Claude only.
- Until the doc is written, **don't** build a notes field that pretends Claude is downstream — keep `set_log.notes` as a plain text field for now, with the design hook reserved.

---

## Cross-cutting concerns

### Schema implications

| Item | Schema touch | Notes |
|---|---|---|
| #4 / P0-5 Skip | `set_log.skipped: Bool` (or status enum) | Mini-migration. Coordinate with SwiftData. |
| #19 / P1-8 Per-side asymmetry | `set_log.side: Text` (`left` / `right` / `bilateral`) | Required for two-row left/right logging. `bilateral` means both sides worked together; it is not a missing value. Server analytics must collapse sides to the intended set before aggregate calculations. |
| #25 / P2-1 Block intent | `block.intent: Text?` | Freeform qualitative text. Full coordinated cutover (server + SwiftData + schema/openapi.json + parity test + spec). |
| #22 / P3-1 Modifiers | Defer; sketch as JSON-blob extension first | No migration until ADR locks. |
| #24 / P3-2 In-app chat | No v1 schema change; design doc only | Future schema may extend `set_log.notes` semantics. |

**Verify before scheduling any schema work** — the repo I'm working from is 1–2 days stale. Confirm the current `block` and `set_log` shape before authoring migrations.

### Coordination — ship together

- **Cluster A — Preview redesign:** P1-1, P1-2, P1-5, P1-6.
- **Cluster B — Active screen redesign:** P1-3, P1-4, P1-7, P1-9. (P1-2 is a prereq.)
- **Cluster C — Rest face rules:** P0-1, P1-7, P1-10, P1-11, P1-12. Most are behavioral / verification; the dot grid is the new component.
- **Cluster D — Bug component fixes:** P0-2, P0-3 (one ticket).
- **Cluster E — Carry support:** P1-13, plus P1-2 (sheet) and P1-4 (focal unit).

### Verify-against-current-code list

These items may already be partially or fully addressed. Audit before scheduling:
- P0-1 (#5) — `"waiting to start"` removal
- P0-4 (#21) — bodyweight weight field editable
- P1-8 (#19) — per_side rendering on active face
- P1-9 (#20) — `workStartedAt` per slot vs per round
- P1-10 (#11) — log sheet popping mid-superset (current spec says it doesn't)
- P1-11 (#23) — any timer-pause path during rest
- P1-13 (#18) — `SetPlan.distance_m` / `duration_sec` plumbing
- P1-14 (#26) — full-field edit coverage in History detail

---

## Decisions log (resolved 2026-04-25 in Dispatch)

The PM raised six questions; Eric resolved them in conversation. All updates pulled into the spec sections above.

1. **#15 Apply-to-all on Swap** → future sets only. Never rewrites past logged sets. Resolved in P1-3.
2. **#15 Apply-to-all on weight edit** → remaining sets in the **block**. The cross-item case isn't a real risk because different items in the block already have their own prescriptions, and superset slots are by definition different exercises (or same with different prescriptions). The edit propagates to remaining sets of the same exercise/item. Resolved in P1-3.
3. **#19 Per-side log model** → **two rows**. Eric's example: single-arm DB bench, one arm can't always match the other's load. Need to log left/right independently (different reps, load, RIR per side). Schema migration required — `side` column on `set_log`. Resolved in P1-8.
4. **#25 Block intent** → **NOT an enum.** Freeform qualitative TEXT field. Eric's framing: "give some leg strength exposure without affecting your core" vs. "hit legs while hammering core throughout" — same exercises, different intents, an enum can't carry that. Goals (the existing structured concept) handle the structured side; intent is qualitative. Resolved in P2-1.
5. **#4 Skip semantics** → proper schema add (`skipped: Bool` on `set_log`) with migration. No notes-bridge. Resolved in P0-5.
6. **#22 + #24** → both stay as documented feedback in this spec. **No ADRs yet** — Eric's words: "We're not doing ADRs or anything yet. You're just documenting all my feedback so far." Resolved in P3-1 / P3-2.

**PM lesson** (Eric called this out): four of these six (#1, #2, #3, #4) were answerable from the raw feedback if read carefully. Specifically:
- #19 (two rows) was implicit in the original phrasing "treat the left as one and the right as another."
- #25 (no enum) was implicit in the rich qualitative descriptions Eric gave for hypothetical block intents.
- #15 apply-to-all scope was reasoned-out from the obvious answer ("why would you change past logged sets?").
- Future PM passes should resolve more from intent and reserve interview slots for genuine ambiguity.

---

## Item-by-item index

Cross-reference: every numbered feedback item maps to at least one spec item.

| Feedback # | Title | Spec item(s) |
|---|---|---|
| #1 | Decouple open / start | P1-1 |
| #2 | Edit from preview | P1-1, P1-2 |
| #3 | Remove blocks from preview | P1-1 |
| #4 | Skip button always present | P0-5 |
| #5 | "Waiting to start" copy bug | P0-1 |
| #6 | Bottom-sheet edit panel | P1-2 |
| #7 | Edit any block during workout | P1-5 |
| #8 | "You are here" indicator | P1-6 |
| #9 | ETA | P2-2 |
| #10 | Transition shows full next block | P1-12 |
| #11 | Don't pop log mid-superset | P1-10 |
| #12 | Done button tap target | P0-2 |
| #13 | "What's next?" includes current block remaining | P0-6 |
| #14 | Dot grid 2-D progress | P1-7 |
| #15 | Active scrolling column + swipe + apply-to-all | P1-3 |
| #16 | Log button greyed-out styling | P0-3 |
| #17 | Active-set visual hierarchy | P1-4 |
| #18 | Carries: weight + distance editable | P1-13 |
| #19 | Per-side explicit | P1-8 |
| #20 | Done + Next-Exercise buttons | P1-9 |
| #21 | Bodyweight default not constraint | P0-4 |
| #22 | Equipment / modifier modeling | P3-1 (open) |
| #23 | Rest timer never pauses | P1-11 |
| #24 | In-app chat with Claude | P3-2 (open) |
| #25 | Block intent | P2-1 |
| #26 | Post-workout: edit everything | P1-14 |

---
---

# Appendix — raw feedback (verbatim)

Source file: `~/ai notes/_inbox/workout-app-feedback-2026-04-25.md` · captured 2026-04-25 · 26 items.

## 1. Decouple "open workout" from "start workout"

Current: clicking into a workout starts it.
Want: clicking in should open a **preview** showing the full workout. **Start** is a separate, explicit action from the preview screen.

## 2. Edit exercises and rep schemes from preview

In the preview, allow swapping exercises and changing rep schemes (and other parameters). Eric wants this *before* starting, not blocked behind a separate "edit workout" mode.

## 3. Allow removing blocks (basic structural edits, not full goal editing)

From the preview, allow deleting individual blocks. Not asking for goal-changing or full plan editing — just "I don't want this one, swap or remove it" level of control.

## 4. Skip button always present

Whenever a block is active, a **skip** button must exist alongside the existing **log** / **done** controls. Also between sets.

## 5. Fix rest timer state — "waiting to start" is wrong mid-workout

Current rest timer shows **"waiting to start"** even after the workout has been started.
Once the workout is in progress, "waiting to start" is incoherent — the only valid states are the **programmed rest period** or **transition between blocks/sets**. Remove the "waiting to start" state from the in-workout timer entirely.

## 6. Logging an exercise should open a bottom-sheet edit panel

Current: tapping to log/edit shows the numbers inline under the reps/sets row. It's visually crowded and confusing about what's editable vs. displayed.
Want: a **bottom sheet overlay** with a clear, dedicated edit panel for the exercise. Inline numbers stay as the read-only display; editing happens in the sheet.

## 7. Block edit panel always accessible during a workout

While in an active workout, Eric should always be able to open the block edit panel — not just for the current block. Specifically:
- Edit **future blocks** (things still to do — e.g., swap an exercise, adjust the planned rep scheme)
- Edit **prior blocks** (logged sets — e.g., correct a rep count or weight after the fact)

This implies the in-workout view exposes the full block list (not just the current block) with edit affordances, and the bottom-sheet pattern from #6 is reused.

## 8. Workout summary should show current position

In the full workout summary view, indicate **exactly where I am** — which block / set is current. A clear progress marker (highlighted row, "you are here" indicator, etc.) so Eric can scan the whole plan and immediately see where he is in it.

## 9. Estimated time to completion (nice-to-have)

Show an **ETA** for finishing the full workout. Sum of: remaining work time (sets × rep duration estimate) + remaining programmed rests + transitions. Updates as he progresses. Stretch goal — but a high-value glanceable.

## 10. Between-block transition should preview the upcoming block in full

When a block finishes, the transition screen should show the **complete next block** — exercise, sets, reps, weight, equipment, anything else needed to set up. The point: Eric uses the rest between blocks to physically prep (load plates, fetch DBs, change machine) and needs to see everything required at a glance, not piecemeal once the next block starts.

## 11. Don't pop the log screen mid-superset; log at rest, edit via history

Mid-superset (transitioning between the paired exercises) is the wrong moment to interrupt with a logging UI. The current behavior pops the log screen during the superset flow — kill that.

Logging belongs at **rest** (between rounds / between sets), not during active movement.

For after-the-fact corrections, expose a **history view** of what's been logged. Clicking into a history entry opens a **history edit** sheet that can ask follow-up questions if needed (e.g., "you logged 8 reps but the plan was 10 — was that intentional?").

Implication: the active superset view shows what to do next, not a log entry form. Log inputs appear only when the rest timer kicks in or when the user explicitly opens the history view.

## 12. Done button has a bad tap target (preview screens)

On the **workout preview screen**, the Done button is hard to hit — Eric says it takes almost three taps to register. Same problem on the preview that surfaces when clicking the **"What's next?"** block from the exercise view: the Done button there is **greyed out** and equally hard to click.

Likely a hit-area / disabled-state styling bug, possibly affecting the same button component across both screens. Audit:
- Tap target size (should meet Apple's 44pt minimum)
- Whether the button is actually disabled when it appears greyed-out, or just styled to look that way
- Hit testing — the visible area may not match the touch area

## 13. "What's next?" preview should also show what's remaining in the current block

When Eric taps "What's next?" from the exercise view, the resulting preview should include **what's remaining in the block he's currently in**, not just the upcoming block(s). Right now it skips ahead. The mental model: "what do I still have to do" = current block's remaining sets + everything ahead.

## 14. Rest-screen progress dots — grid showing block structure + position

During the rest period, replace the dead "waiting for next" copy (see #5) with a **dot grid** that visualizes where Eric is inside the current block.

Layout:
- **Horizontal axis = sets remaining in this block** (e.g., 5 dots for a 5-set block; 4th set's dot is the next/active one).
- **Vertical axis = exercises within a set** (1 row for a normal exercise, 2+ rows for a superset).
- A superset of 2 exercises × 3 sets renders as a 2-row × 3-column grid of dots.

Filled / hollow / accent states indicate completed / current / remaining. Eric should be able to glance and see "I'm halfway through set 3 of 5, on the second exercise of the superset."

## 15. Exercise view layout — fill the empty space with the full set list, with swipe actions and apply-to-all edits

The current exercise view leaves a lot of blank space below the active preview. Use it to show the rest of the block — past, present, future — in a single scrolling column.

### Layout
- One row per set in the current block. Supersets show all "slots" inside the set with a visual distinction (e.g., grouped/indented or paired markers) so it's obvious those exercises belong to the same set.
- The **current set is highlighted** and stays focused as the user scrolls.
- **Completed sets above** the current one, **greyed out** but tappable for editing.
- **Upcoming sets below**, fully visible (2–3 fit on screen at a time).
- Example, a block of 8 sets, currently on set 4:
  - Top: sets 1–3 greyed (with their logged values)
  - Middle: set 4 highlighted (active)
  - Bottom: sets 5–7 visible, set 8 below the fold
- A **"scroll back to current"** floating button appears whenever the user has scrolled away from the active row, snapping back to it.

### Interactions per row
- **Tap** a row → opens the bottom-sheet edit panel (per #6) for that set.
- **Swipe** a row → reveals **Skip** and **Swap** action buttons.
  - **Skip**: marks that set skipped, advances to next.
  - **Swap**: opens exercise picker. After swap, prompt with **"Apply to all sets in this block?"** — yes replaces every set; no replaces only this one.
- **Long-press** a row → opens deeper details (history for this exercise, prior loads, notes).
- For weight edits in the bottom sheet: same **"Apply to all"** affordance — change just this set, or propagate to all remaining sets in the block.

### Why
- Reduces taps for the most common edits (swap exercise, change weight).
- Makes the structure of supersets / sets visible at all times instead of one-set-at-a-time.
- Apply-to-all eliminates the most annoying repetitive edit during a working set.

## 16. Log button looks greyed-out but is functional — fix the styling

When logging an exercise, the **Log** button at the bottom is rendered greyed-out as if disabled, but it actually works on tap. Confusing — Eric initially didn't know it was clickable.

Fix: make it look enabled. Distinguish "available" vs. "disabled" states clearly. Likely the same root cause as #12 (Done button greyed-out on previews) — could be a shared button component or theme using a too-low-contrast active state.

Audit the button component's color tokens — make sure the active/enabled state has enough contrast against the background and is visually distinct from the disabled state.

**Visual confirmation from screenshot (`019dc997-IMG_3224.png`):** The "log station" button is rendered in a low-contrast peach/coral on a dark background. Reads as a disabled or de-emphasized state — needs higher saturation and/or weight to read as a primary CTA.

## 17. Active-set screen needs a clearer visual hierarchy — current exercise should be the focal point

Reference: screenshot `019dc997-IMG_3224.png` (Incline Dumbbell Curl, Round 3 of 3, "log station" CTA).

Current layout (top → bottom):
1. Exercise name ("Incline Dumbbell Curl") — small, top-left
2. "ROUND 3 OF 3" + "hold exercise to swap" — small caption
3. Set elapsed timer — large card
4. Three progress dots (●●●)
5. Big "20 lb" / "10 reps" floating in the middle of the screen with no label
6. "NEXT EXERCISE" card (small)
7. ~30% of the screen is empty space
8. "log station" button at the bottom

The problem Eric flagged:
> "20 lb but I had to look around to figure out what it was."

The exercise name is divorced from the weight/reps numbers. The biggest visual element on the screen (the "20 lb / 10 reps") doesn't say what exercise it's for. The exercise name is shrunken to the corner like a section header instead of the headline.

Wanted hierarchy:
1. **Current exercise — the focal point.** Exercise name + weight + reps as a single, large, central unit. "Incline Dumbbell Curl — 20 lb × 10 reps" should read as one thing, with the exercise name at least as prominent as the weight.
2. **Set / round context** below the focal point (Round 3 of 3, set timer if needed) — supporting info, not headline.
3. **Superset structure broken out properly.** The current example is a **3-exercise superset** but the UI shows only the active exercise + a single "NEXT EXERCISE" card. There's no signal that we're in a superset, no view of the other exercises in the round, no breakdown of round / superset slot / set within the slot.
4. **Below the current exercise:** what's coming up — first the rest of the superset (the remaining exercises in this round), then the rest of the block, then what happens after the block (rest + next block summary, per #10).
5. Use the empty space (lower half of the screen) for that breakdown — currently wasted.

Implication for the data model: the screen needs to know it's inside a superset and what the round structure is, then render slots with their own labels rather than collapsing the round into "current + next exercise."

This is the visual-hierarchy companion to #15 (which is about the scrolling column of sets). Together they describe a much more information-dense, focally clear active-set screen.

## 18. Loaded carries (suitcase, farmer's, etc.) — expose weight AND distance, both editable

For carries like the **suitcase carry**, the active-set screen had no way to **show** or **adjust** the weight, and Eric isn't sure if distance is editable at all yet.

Carries have a different prescription shape than rep-based exercises:
- **Weight** (per side or total — see #19)
- **Distance** (e.g. 20 m) OR **time** (e.g. 30 s) as the work unit
- **Sides** (some carries are unilateral — suitcase — others bilateral — farmer's walk)

Required:
- Surface weight and distance/time prominently in the focal block (per #17).
- Make both editable from the bottom-sheet edit panel (#6).
- The schema should distinguish "rep-based" from "carry-based" prescriptions and route to the right input UI per type.

## 19. Per-side vs total reps — explicit distinction, not ambiguous "10 reps"

Currently a unilateral exercise (e.g. single-arm DB row, suitcase carry) just says "10 reps" — Eric can't tell if that means 10 per side or 10 total.

Fix:
- Make per-side vs. total an explicit attribute on the prescription.
- Render explicitly: "10 reps **per side**" or "10 reps **total**" — never ambiguous.
- For per-side exercises, **treat each side as its own slot**, exactly like a superset-internal slot. So "10 reps left, 10 reps right" reads as two slots in a single set, with the dot grid (#14) showing both.
- Same applies to per-side weight (e.g. one DB at 30 lb in suitcase carry → render "30 lb per hand" or similar).

## 20. Superset progression — Done + Next-Exercise buttons, with proportional layout

During a superset, Eric wants to advance through the exercises by tapping a **Next** button — clicking through next, next, next — so the app can track time per exercise within the round. Alongside that, a **Done** button to finish the current set entirely (still no editing in this flow — logging stays at rest, per #11).

Button layout:
- **Single-exercise set:** Done button takes the **full width** at the bottom (current behaviour, fine).
- **Superset / multi-slot set:** split the bottom bar — **Done** on the left at ~**1/4 to 1/5 of the width**; **Next exercise** taking the rest. Reading: small "I'm finishing this round" affordance, big "advance to the next slot" primary action.

Implication: the data model needs to know it's mid-round and which slot is active, and the bottom bar adjusts its layout accordingly.

## 21. Bodyweight is still a weight — allow overrides

Bodyweight defaults to zero added load — fine. But the UI should always allow Eric to **set a non-zero weight** on a bodyweight-tagged exercise (weighted pull-ups via belt, weighted dips, goblet squats from bodyweight squat, etc.).

Implication: bodyweight is a *default*, not a *constraint*. The weight field stays editable; the prescription just seeds it at zero (or "BW") for bodyweight-tagged exercises. Track the actual load entered, even when the planned prescription was bodyweight.

## 22. Open design question — how to model equipment / modifiers (bands, machines, implements)

Eric flagged this as something to design, not specify yet. Capturing the question with examples:

- **Machine cable / weight-stack exercises** (e.g. **Pallof press** — Eric did 10 sets per side at 70 lb / 60 lb on the stack). The "weight" is the stack pin position, which is implement-specific.
- He could have done the same Pallof press **with bands** instead — band tension isn't a clean weight number; how does that get tracked?
- **Suitcase carry** — KB vs DB doesn't really matter; weight is weight. Implement is interchangeable.
- **Deadlift + bands** (banded deadlift) — bands add tension at the top. Is that a weight modifier, a different exercise, or a separate "band tension" attribute on the same lift?

The design question to resolve:
- When does an implement / modifier change the **exercise identity** (banded Pallof press = different exercise) vs. become an **attribute** on the same exercise (deadlift with X-band tension on top of Y bar weight)?
- For machine-stack exercises, is the unit the **stack pin** number (which depends on the machine) or a **calibrated weight** (which requires per-machine calibration data)?
- For interchangeable implements (KB vs DB on a suitcase carry), do we just track weight and ignore implement, or capture implement for history filtering?

No answer here yet. Worth an explicit design doc / decision record before locking the schema.

---

**Eric's likely default heuristic** (his words to extract — not put in his mouth):
- Same movement, different implement, same load semantics → same exercise.
- Same movement, modifier that changes the load curve (bands, chains) → flag as a modifier on the same exercise; capture modifier separately.
- Same movement, dramatically different equipment that changes mechanics → different exercise.

## 23. Rest timer starts immediately — never blocks on logging

When a set ends and rest is next, the **rest timer starts the moment the set is marked done** — not after Eric finishes logging or editing.

The timer and the log UI are independent: the clock ticks down while the log sheet is open. If Eric finishes logging in 10 seconds and the rest period is 90, he sees 80 seconds remaining. If he doesn't log at all, the rest still counts down on schedule. **No path through the workout flow may pause the rest timer.**

This refines #11 — yes logging happens at rest, but the rest *clock* is independent of whether Eric is mid-log. The log just happens to be the most natural thing to do during rest.

## 24. In-app chat with Claude / Codex — surface AI assistance contextually

Future feature. Build a chat surface inside the app where Eric can send messages to Claude (or a Codex equivalent) about what's happening during a workout.

Touchpoints:
- The description / notes field on a logged set — anything Eric writes there is logged AND piped to Claude, who can suggest adjustments (e.g. "core was fried, couldn't hit RIR target — should we swap something?")
- Standalone chat surface (probably a tab or a sliding panel) for free-form questions and adjustments mid-workout
- Claude can propose mid-workout edits: swap an exercise, change rep/weight targets, restructure remaining blocks based on stated intent (see #25)

Implication: the app needs a structured way to send Claude (a) the current workout state, (b) Eric's free-text input, (c) the intent per block, and receive back proposed edits that Eric can accept/reject.

This isn't a near-term build but worth designing the data flow now so notes/descriptions aren't built as a dead-end field.

## 25. Each block has a stated intent — drives effectiveness check and mid-workout swaps

Every block in a prescription needs an **explicit intent** — what is this block *for*? Without it, Eric can't tell after the fact whether the block was effective or not.

Concrete example (yesterday's block):
- Exercises: goblet squat, suitcase carry, Pallof press
- Eric's experience: hit the core hard, really liked the goblet squat, **but** couldn't get close to 6 reps × 2 RIR max because his core was too tired to brace.
- The interpretation depends entirely on intent:
  - **If the intent was "core block":** success — exactly what was wanted.
  - **If the intent was "leg strength, with core as a finisher":** failure — leg work was capped by core fatigue. Would have wanted a leg press or similar leg-isolation primary instead.

Implications:
- Intent is a **first-class field on each block** in the prescription. Examples: `core-focused`, `leg strength`, `conditioning`, `recovery`, `hypertrophy-quad`, etc. Probably a tag set, not a freeform string.
- During the workout, intent is **visible** so Eric can mid-workout-swap if a block isn't serving its intent.
- After the workout, the chat / notes feature (#24) can ask "did this block hit its intent?" — and Claude can use that signal to retune future programming.
- Without intent captured, after-action review is unfalsifiable: Eric can't tell if a tough block "worked" or "failed."

## 26. Post-workout: edit everything

After Eric closes out a workout, he needs to be able to go back and edit **everything** — every skipped set, every logged weight, every rep count, every time, every distance, every note. Nothing about the closed-workout record should be read-only.

Reinforces #11 (history view + edit sheet for after-the-fact corrections) but explicitly: the edit affordance applies to the entire workout post-close, not just the active session.

---

## Replay-friendly summary (one-liners)

1. Preview-then-start (don't auto-start on tap)
2. Edit exercises and rep schemes from preview
3. Remove blocks from preview
4. Skip button always available alongside log/done — including between sets
5. Rest timer shouldn't say "waiting to start" once workout is running
6. Logging/editing should pop a bottom-sheet, not inline-under-reps
7. During a workout, edit any block (future or prior), not just the current one
8. Summary view should show current position (you-are-here indicator)
9. Estimated time-to-completion for the whole workout (nice-to-have)
10. Between-block transition shows the complete next block (full setup info, not piecemeal)
11. No log screen mid-superset — log at rest; history view + edit sheet for after-the-fact corrections
12. Done button has bad tap target on preview screens (and looks greyed out on the "What's next?" preview)
13. "What's next?" preview should include remaining items in the current block, not just upcoming
14. Rest-screen dot grid — horizontal = sets in block, vertical = exercises in set (superset = multiple rows)
15. Exercise view = scrolling column of all sets (past greyed, current highlighted, future visible) + swipe-to-Skip/Swap + "Apply to all" on swap and weight edits + scroll-back-to-current button
16. Log button is functional but rendered greyed-out — same root cause likely as #12; fix enabled-state styling
17. Active-set screen needs a clearer visual hierarchy — current exercise (name + weight + reps) is the focal point, with superset structure broken out below; current screen makes "20 lb" float without saying what it's for
18. Loaded carries need weight + distance (or time) shown and editable — the prescription schema needs to distinguish rep-based from carry-based
19. Per-side vs total reps must be explicit — "10 reps" is ambiguous; per-side exercises render as left/right slots like a mini-superset
20. Superset progression: Done + Next-Exercise buttons. Single-exercise = full-width Done. Multi-slot = ~1/5 Done on left, ~4/5 Next on right. Click-next-next-next tracks per-exercise time
21. Bodyweight is a default, not a constraint — weight field stays editable so weighted variants (vest, belt, goblet) get logged correctly
22. Open design question — how to model equipment/modifiers (machine stacks, bands, implements). Not solved; flagged for a decision record before locking the schema
23. Rest timer starts immediately when a set ends — independent of logging. No flow path may pause it
24. Future: in-app chat with Claude/Codex. Notes/descriptions feed into Claude; Claude suggests mid-workout adjustments
25. Each block carries an explicit **intent** (core / leg strength / conditioning / etc.) — drives effectiveness review and mid-workout swap decisions
26. Post-workout: every field on every set is editable — skipped, weight, reps, time, distance, notes. Nothing is read-only after close
