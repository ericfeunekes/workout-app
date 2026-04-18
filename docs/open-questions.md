---
title: Open questions
status: living
purpose: The living gap register. Items that emerged from consistency passes that aren't yet decided, or are deferred past v1. Each item names what is unresolved, our current working assumption (if any), and the disposition — decide now / defer / resolve in code.
covers:
  - docs/
---

# Open questions

This doc is the single place where unresolved items live. It is maintained, not archived — once an item is decided, it moves into the relevant doc (spec, prescription, sync, app README, or an ADR) and is removed here.

**How to read an item:**
- **Assumption:** what we're implicitly doing right now, when the answer matters. Non-binding; the real decision may differ.
- **Disposition:** `decide-next` (block on a small decision), `defer-to-v1.1+` (explicit postponement), `resolve-in-code` (answer will emerge when the code is written — no doc action until then), or `watchlist` (known latent risk; revisit when it bites).

---

## Schema and data model

### Set-log `updated_at` column
Docs allow past-set edits; the schema has no `set_log.updated_at`. Corrective edits are silently overwriting without provenance.
- **Assumption:** edits overwrite in place; provenance via `adjust` field on the app side only.
- **Disposition:** decide-next. If we want server-side edit history, add `updated_at`. If not, document explicitly that set_logs have no edit timestamp.

### Set-log deletion semantics
Docs say v1 doesn't support delete. If a user eventually needs it, soft-delete (`deleted_at`) vs hard-delete (tombstone push).
- **Assumption:** no delete path at all in v1.
- **Disposition:** defer-to-v1.1+.

### `workout.updated_at` vs prescription-change cascade
A PUT on a workout replaces nested blocks/items. Set logs referencing the old `workout_item_id` become orphans if the item was removed.
- **Assumption:** orphaned set_logs are preserved and remain queryable by `workout_id`; their `workout_item_id` FK stays pointing at a deleted row (needs the FK to be nullable or the delete to be a soft-delete).
- **Disposition:** decide-next. Either make `workout_item` soft-deletable, or forbid replacement of items that have set_logs. This affects the PUT /api/workouts contract.

### `rounds_rep_scheme` not in the prescription doc
Documented in the v2 spec (block-level rep scheme) but not in `docs/prescription.md` except via the Fran example.
- **Disposition:** decide-next. Fold a short section into `docs/prescription.md` § "Per-timing-mode prescription shapes" under `for_time` (and anywhere else it applies).

### Alternative prescription shape cap
An alternative can override any prescription keys. There is no validation that the override produces a shape the block's timing_mode can execute (e.g., swapping a loaded strength item into a bodyweight-reps item inside a straight_sets block).
- **Assumption:** Claude authors alternatives sensibly. App fails gracefully if the shape is wrong.
- **Disposition:** watchlist.

### User_parameter value parsing
`user_parameters.value` is a string. Keys like `bodyweight_kg` imply a float; `preference_rep_range` implies a string. There's no per-key type registry.
- **Assumption:** app parses by key convention. Unknown keys are stored and ignored.
- **Disposition:** resolve-in-code. A key catalog can emerge as the app is built; if it gets large, move to `docs/user_parameters.md`.

### `tags_json` convention on workouts
Free-form JSON array of strings. Used by Claude for analysis grouping.
- **Assumption:** we don't standardize tag values; Claude uses what's useful (`deload`, `week_3`, `push_day`, `test_day`). No validation server-side.
- **Disposition:** resolve-in-code. If Claude's own CLI later wants structured tags (e.g., `{mesocycle: "pull", week: 3}`), revisit.

### Multiple rapid `user_parameters` writes with same key
Offline completion captures `bodyweight_kg`; three sessions offline over 3 days = three rows. "Latest" is `MAX(updated_at)`.
- **Assumption:** works fine — server-side timestamps resolve ordering even if the client writes in batches.
- **Disposition:** watchlist.

### Exercise soft-delete / retirement
No `is_active` or `deleted_at` on `exercise`. Orphaned exercises accumulate.
- **Disposition:** defer-to-v1.1+. Not a problem at single-user scale for a long time.

---

## Sync, connectivity, offline

### Stale session expiry
"Live session is frozen" per sync.md. If the user starts a workout, logs 2 sets, backgrounds the app, and returns 6 days later, the session is still "live" by current rules — even if Claude has since pushed a new prescription for that workout.
- **Assumption:** no automatic expiry; user explicitly reopens or explicitly discards.
- **Disposition:** decide-next. Reasonable options: (a) expire after 24h of inactivity, (b) expire when `server_time` advances past a threshold, (c) never expire, user decides. Pick one when the app is being built.

### Offline completion atomicity
Set_logs and `status_updates` push as separate items in a queue. If the queue partially drains (set_logs succeed, status_update fails), the server sees logs against a workout that's still "active."
- **Assumption:** the server accepts this state and the status_update retries; no harm done.
- **Disposition:** resolve-in-code. Easy to get right in the push queue — batch or sequence so the status_update is last.

### Multiple active workouts
Spec allows `status=active` on more than one workout; app persists one session cursor.
- **Assumption:** starting workout B while A is active either auto-completes A or refuses; the UX picks one.
- **Disposition:** decide-next when the app is built.

### Watch independent of phone
Watch records set start/end locally when paired phone is off. What happens on reconnect.
- **Disposition:** defer-to-v1.1+. Out of scope per ADR-UX-scope.

### Partial-first-sync recovery UI
First-sync crash is all-or-nothing. The welcome → retry path handles this, but the UX for "you were 10% into a 500 MB first sync, try again" isn't sketched.
- **Assumption:** show a generic "Retry sync" after failure; don't expose partial progress.
- **Disposition:** resolve-in-code. *(Shell.AppBootstrap now falls back to cached data on pull failure; FirstRun shows a failure banner with retry. Resolved in code; remove on next sweep.)*

---

## Autoregulation

### Autoreg on `sets_detail` pyramids
Each set has its own prescribed load; autoreg's "remaining" is well-defined (sets after the trigger point). Whether autoreg's `overshoot_step_kg` applies uniformly to each remaining set's prescribed load or to some derived top load is ambiguous when per-set loads vary.
- **Assumption:** autoreg adjusts each remaining set's *own* prescribed load by `step_kg`, preserving the shape of the pyramid.
- **Disposition:** resolve-in-code. Write a test fixture when building the applier.

### Autoreg in cluster sets (`sub_sets`)
Autoreg fires "after a set is logged." In a cluster, does "set" mean the top-level set (5 reps × 4 sub-sets) or each sub-set?
- **Assumption:** top-level set only. Sub-sets are internal to one `set_log` row.
- **Disposition:** decide-next. Worth writing into `docs/prescription.md` § Cluster when the pattern is first used.

### Autoreg on tempo reps
Undershoot rule treats reps as a uniform signal; tempo reps are harder per rep.
- **Assumption:** no special handling. Tempo items usually omit autoreg anyway.
- **Disposition:** watchlist.

### `apply_to` future modes
`"next"` and `"all-future"` are reserved but not specified.
- **Disposition:** defer-to-v1.1+. If Claude wants next-session bumps, it can re-author the prescription — no escalation channel needed yet.

### Retroactive percent_1rm on manual entry
User enters a manual load for a `percent_1rm` set (because the parameter wasn't synced). Later the `user_parameters` catches up. Does the app recompute the set's prescribed load? Record the logged value as authoritative?
- **Assumption:** logged value is authoritative; no retroactive recomputation.
- **Disposition:** resolve-in-code.

---

## Authoring gaps (for a future planning-Claude CLI)

These are authoring patterns the vocabulary doesn't yet support. None block v1 — they emerged from trying to mentally author a real program. Most can be added to `docs/prescription.md` incrementally.

### Dynamic load reference ("today's top set as baseline")
5/3/1-style "top single, then back-off sets at X% of the top" has no shape. `percent_1rm` is static.
- **Disposition:** defer-to-v1.1+. Claude can hardcode loads or re-author after the fact.

### Density sets ("as many sets as possible in 15 min")
No timing mode covers "fixed reps+load, variable number of sets, time-capped."
- **Disposition:** decide-next. Easiest: add `time_cap_sec` to `straight_sets` config. If it proves useful, do it when we see it in a program.

### Time-capped strength ("5×5 in under 30 min")
Same gap as density sets — no timing mode covers fixed-prescription-with-time-cap.
- **Disposition:** decide-next. Resolve alongside the density-sets decision — same shape of answer.

### Complexes
Barbell complex (deadlift + clean + squat + press as one round, N rounds). Superset works for 2 exercises; circuit works but the inter-exercise-rest semantics are wrong (a complex has zero rest between exercises and rest only between rounds).
- **Assumption:** author as `circuit` with `rest_between_exercises_sec: 0, rest_between_rounds_sec: N`. Document this convention when the pattern first appears.
- **Disposition:** decide-next. Small doc addition.

### Rest days / active recovery as schedule items
No distinct entity. A `continuous` Z1 walk isn't distinguishable from a real training session.
- **Assumption:** author as a regular workout with a `tags_json: ["rest_day"]` or `["active_recovery"]` tag.
- **Disposition:** decide-next. Write the tag convention into `docs/prescription.md`.

### Program / mesocycle entity
No `program` table. Grouping is via `tags_json` on workouts.
- **Disposition:** defer-to-v1.1+. Tags are enough at single-user scale.

### Warm-up history exclusion
`is_warmup` is on set_log; the history surface should exclude warm-ups from top-set and avg-RIR computations. Docs say this but the computation contract isn't written.
- **Disposition:** resolve-in-code.

### Conditional / optional blocks ("finisher if you have energy")
No `optional: true` flag.
- **Disposition:** defer-to-v1.1+.

### Asymmetric cluster reps
`sub_sets: 3` implies symmetric reps; rest-pause "10, AMRAP, AMRAP" doesn't fit.
- **Assumption:** use `sets_detail` with three set rows and `drop: true` on 2 and 3 for now.
- **Disposition:** watchlist. Add a dedicated shape if this pattern shows up frequently.

### Multi-level fallback alternatives
Alternatives are a flat list. No "if A unavailable use B, if B unavailable use C."
- **Disposition:** defer-to-v1.1+. Low frequency at single-user scale.

### Intensity / test-day machine-readable flags
Can't mark "this was a 1RM test" distinctly. Tags work but are free-form.
- **Assumption:** use `tags_json: ["test_day", "squat_1rm_test"]` or similar by convention.
- **Disposition:** resolve-in-code as the planning CLI gets built.

---

## App behavior

### In-flight rest timer persistence
Already decided — persist `rest_ends_at` as an absolute timestamp (captured in `app/README.md`). Listed here only so the reasoning is traceable.
- **Disposition:** resolved.

### Editing a completed, synced set from history
Corrective edits to a set in a workout from three weeks ago — is that allowed? Does it push back to the server?
- **Assumption:** yes, allowed, and push. UUIDs make it idempotent.
- **Disposition:** resolve-in-code.

### Body weight freshness
Autoreg doesn't consume `bodyweight_kg`. But if a future prescription shape uses `percent_bw`, stale BW would mislead.
- **Disposition:** watchlist. Revisit when (if) `percent_bw` shapes appear.

---

## Process

### Contract tests for prescription shapes
`docs/TESTING.md` mentions contract tests generically. We now have a growing prescription shape vocabulary in `docs/prescription.md` — specific shapes should get fixture coverage.
- **Disposition:** resolve-in-code. *(FF-6 is live, 23 fixtures cover every shape in EXPECTED_SHAPES. Also: Chunk 5 added Swift-side CorePrescription parsers tested against the same fixtures. Contract is enforced both sides. Remove on next sweep.)*

### Shell package directory placement
Shell lives at `app/Packages/Shell/`, not under `Features/`. The rationale is that SwiftLint's `no_feature_cross_import` rule blocks any file under `Packages/Features/` from importing another Features module, and Shell is the one package that legitimately needs to see both Features/Today and Features/Execution to compose the app on launch. Captured in `docs/architecture/swift-packages.md` but not in an ADR.
- **Assumption:** the name "Shell" is clear enough that future agents won't try to relocate it.
- **Disposition:** decide-next. Land an ADR when there's time — or at least add a one-liner invariant at the top of the swift-packages.md table.

### Autoreg defaults — Settings vs prescription
`Features/Settings` has an "AUTOREG DEFAULTS" section (target_rir, overshoot_step_kg, undershoot_step_kg) backed by UserDefaults. But per-block autoreg lives in `prescription_json` authored by Claude. What's the relationship?
- **Option (a):** Settings defaults are a display-only hint — useful if Claude's push fails to include autoreg config, the app substitutes these. Per-block values always win.
- **Option (b):** Settings defaults are advisory overrides that Claude reads from `user_parameters` and respects.
- **Assumption:** (a) — defaults are for fallback rendering; the authoritative rules come from the prescription.
- **Disposition:** decide-next. Worth a one-line note in `docs/prescription.md` § "Autoregulation" clarifying the precedence.

### Today → Active navigation end-to-end
Every screen (Today, Active, Rest, Complete) has been verified in isolation via debug launch args. The actual user tap path ("start workout" button → route advances → Execution view model loads → ActiveView renders) has compile-time coherence but no runtime verification.
- **Assumption:** it works because `TodayViewModel.start()`, `ExecutionViewModel.start()`, and the routedView switch have all been independently exercised.
- **Disposition:** decide-next. Needs a manual tap-through (or a UI test once XcodeBuildMCP is active next session).

### FirstRun `connect()` re-entrancy (MUST-FIX found 2026-04-18)
Reviewer of FirstRun caught: double-tapping the "connect" DSButton enqueues two concurrent `Task { await connect() }` pipelines. Both can reach TokenStore.save and `onComplete()`, producing duplicate saves + duplicate pulls. 10 tests didn't catch it because they run a single task.
- **Assumption:** needs a re-entrancy guard at the top of `connect()` (early-return if `state != .welcome && state != .failed`), AND/OR disable the DSButton while a connect is in flight.
- **Disposition:** decide-next. Dispatch a targeted fix in the next chunk.

### App shell double-bootstrap race (MUST-FIX found 2026-04-18)
Reviewer of WorkoutDBApp.swift caught: on FirstRun success, `onComplete` sets `phase = .bootstrapping` then calls `runBootstrap()`. Setting the phase also triggers `BootstrapLoadingView().task { runBootstrap() }`, so two bootstraps fire concurrently — two pulls, two cache writes, non-deterministic which `.ready` assignment wins. First-ever-connect UX is wasteful and subtly broken.
- **Assumption:** fix is either "remove `.task` from `BootstrapLoadingView`" (let `onComplete` drive it) or a `didStartBootstrap` flag.
- **Disposition:** decide-next. Dispatch a targeted fix in the next chunk.

### WorkoutCacheImpl.save non-atomicity
Reviewer of Shell surfaced an issue owned by Persistence: `WorkoutCacheImpl.save(...)` loops upserts then calls `modelContext.save()`. A mid-loop throw leaves the in-memory ModelContext dirty with no rollback; disk stays clean only because `save()` hasn't been called yet, but a subsequent successful save would flush the partial state.
- **Assumption:** wrap the loop in a manual transaction scope and `rollback()` on throw. SwiftData has `transaction { }` closure APIs in iOS 17+.
- **Disposition:** decide-next. Fix alongside the concurrency patch.

### Empty-cache state dead end
Reviewer caught: `Shell.BootstrapResult.empty` lands the user on an `EmptyStateView` with no retry button and no way to Settings. Force-quit is the only way forward.
- **Assumption:** add a "try again" `DSButton.primary` that re-runs the bootstrap, and (when Settings has an entry point) a "change server" link.
- **Disposition:** decide-next. Two-line fix; land with the concurrency patch.

### Settings has no entry point yet
Settings is compiled but unreachable — the TodayView gear icon / shell-level entry hasn't been wired.
- **Assumption:** wire a gear icon on the Today header (top-right) that presents SettingsView as a sheet.
- **Disposition:** decide-next. Settings UX is a user-visible feature so this should land before any alpha user.

### Watch → phone message integration (phone-side subscriber missing)
The Features/WatchFaces slice (2026-04-18) wired the watch-side: it subscribes to `WatchBridge.messages()` and sends `.setStarted` / `.setEnded` on tap. But the **phone-side subscriber** that translates those incoming messages into `SessionMutation`s on `ExecutionViewModel` does not exist. Watch taps currently go nowhere on the phone.
- **Assumption:** a small `WatchInbox` observer type owned by Shell, wired on bootstrap, subscribes to `WatchBridge.messages()` and dispatches to the active `ExecutionViewModel`.
- **Disposition:** defer-to-v1.1+. Per Eric's direction, watch work is on hold until hands-on iOS-app feedback — the watch isn't needed for the first real workout.

### Watch `ActiveBlockPayload` lacks `workoutItemID`
WatchFaces generates a local UUID per active-block arrival because the wire payload doesn't carry the item ID. Works for one-round displays; breaks if the phone replaces the active block with another before the watch logs its tap.
- **Assumption:** add `workoutItemID: UUID` to `ActiveBlockPayload` when watch work resumes.
- **Disposition:** defer-to-v1.1+.

### Watch `RestFace` ring anchor resets on payload replacement
Ring total-duration is captured on first render via `@State anchor`. If the phone sends a new `pushRestTimer(endsAt:)` mid-rest, the ring jumps. Phone currently sends one timer per rest, so not a v1 issue.
- **Disposition:** watchlist.

### FakeWatchBridge subscription race in tests
Tests use a 50ms `Task.sleep` to let the detached `Task { await vm.start() }` register its `bridge.messages()` continuation before the test delivers messages.
- **Assumption:** add an `awaitSubscription()` hook on `FakeWatchBridge` that yields until a continuation is registered.
- **Disposition:** watchlist.

### Systemd unit scope — user vs system (server deploy)
`deploy/workoutdb-server.service` is currently system-scope with hardcoded `/opt/workoutdb/.venv/bin/uvicorn`. The new release-dir layout documented in `docs/infrastructure/home-server.md` assumes user-scope systemd with `/opt/workoutdb/current/.venv/...`. Before fleshing out `make deploy`, the unit file needs to match the docs OR the docs need to match the unit. User-scope requires `loginctl enable-linger workoutdb` for autostart; system-scope needs `sudo` for service operations.
- **Assumption:** go with user-scope (matches docs, no sudo in the deploy path).
- **Disposition:** decide-next. Eric's call before we implement the real `make deploy`.

### Tab bar accessibility IDs missing (harder than expected)
SwiftUI `TabView` in `Shell.RootTabView` doesn't expose child tab items as individually-tappable accessibility elements. Tried `.accessibilityIdentifier("tab-today")` on each tab view — the identifier lands on the content view, NOT on the tab bar button. Coordinate-tap still works for MCP automation but `tap(label:)` / `tap(id:)` does not.
- **Assumption:** real fix is either (a) `.accessibilityLabel` on the `Label` inside `.tabItem` plus `.tabItem` customization hooks, (b) switch to a custom tab bar (visible `HStack` of buttons below the content), or (c) use UIKit `UITabBarController` via `UIViewControllerRepresentable`. Worth a short investigation before picking.
- **Disposition:** watchlist. Coordinate-tap is fine for now. Revisit if/when we want UI-test automation of the tab surface.

### HistoryRow swallows NavigationLink taps (fixed 2026-04-18)
E2E on 2026-04-18 surfaced that tapping a history row never pushed the session detail. Root cause: `HistoryRow` was itself a `Button(action: onTap)` nested inside `NavigationLink(value:)` — SwiftUI's inner Button ate the tap and fired the no-op `onTap: {}`. Fix: flattened `HistoryRow` to a plain `VStack` and let the outer `NavigationLink` own the tap. Watchlist note: any future row type that re-introduces an inner `Button` will re-break this.

### Server emitted naive datetimes, breaking app pull (fixed 2026-04-18)
Bootstrap pulled 4 workouts but the UI rendered "No workouts yet." Root cause: SQLite stores the ORM's UTC-aware datetime as naive; Pydantic's default `datetime.isoformat()` dropped the TZ suffix; the Swift `JSONDecoder.workoutDB()` uses `ISO8601DateFormatter` with `.withInternetDateTime` which *requires* a TZ designator, so `created_at`/`updated_at` failed to decode; `PullService` returned a decode error; `AppBootstrap` caught it, fell back to cache, cache was empty, phase went to `.empty`. Fix: added `UtcDatetime = Annotated[datetime, PlainSerializer(_serialize_utc)]` in `server/workoutdb_server/api/schemas.py` and retyped every Read-side datetime field to stamp UTC + emit `Z` suffix. Watchlist: ANY new server field typed `datetime` in a Read/Out model must use `UtcDatetime`, or the exact same silent-fail class recurs.

### Server FK lookup was UUID-case-sensitive, `sync_results` 404'd everything (fixed 2026-04-18)
Every set_log push from the app returned `404 workout_item ... not found`. Root cause: Swift's `UUID.uuidString` emits UPPERCASE; the server stored whatever case the writer sent (lowercase from Claude-authored pushes); SQLite TEXT column FK comparison is case-sensitive by default; `db.get(WorkoutItem, log.workout_item_id)` missed. Fix: `_UuidNormalizingBase` Pydantic mixin that lowercases every `id`/`*_id` string field via `@model_validator(mode="before")`. Every Pydantic schema now inherits it. Watchlist: any future endpoint that does direct DB lookups with a raw string UUID (bypassing a Pydantic model) can still hit this. The canonical form is now "lowercase everywhere on the server."

### RootView holder captured weakly, broke prod-path "start workout" (fixed 2026-04-18)
On the production bootstrap path, tapping "start workout" silently no-op'd — no transition to `.active`. Root cause: `WorkoutDBApp.runBootstrap()` declares `let executionVMHolder = ExecutionViewModelHolder()` and builds a `SessionMutation` binding closure with `[weak executionVMHolder]`. Once `runBootstrap()` returns, the local `let` goes out of scope, ARC drops the holder, the weak capture becomes nil, and every `.start` mutation silently no-ops. Fix: capture strongly — the holder lives inside `TodayContext` inside the `.ready` phase, so it's transitively retained; no back-reference to the binding means no cycle. Watchlist: `[weak]` captures of short-lived locals that *must* outlive the function are a recurring Swift trap — any future binding-construction pattern should capture strongly and rely on view-lifecycle ownership.

### Save & done didn't enqueue status_update on the auto-advance path (fixed 2026-04-18)
After the user logged the last set, auto-advanced to `.complete`, and tapped "save & done", the server's workout row stayed `planned` forever — all set_logs landed but the status transition never did. Root cause: `ExecutionViewModel.complete()` calls `enqueueStatusCompleted()`, but `saveAndDone()` only calls `writeCompletionToLocalCache()`. When the user reaches `.complete` via `.advanceFromRest` (the normal flow — not the explicit "End" button), `complete()` is never called, and `saveAndDone()` never fires the server-side status push. Fix: `saveAndDone()` now calls `enqueueStatusCompleted(at:)` before the `.save` wipe. Watchlist: needs a unit test asserting `saveAndDone()` invokes the status enqueuer exactly once (there's already one for `complete()` — `testCompleteInvokesStatusEnqueuerExactlyOnce`).

### Session detail renders "2..N" set numbers instead of "1..N" (watchlist)
`SessionDetailViewModel.formatSetRow` prepends `log.setIndex + 1` assuming logs are stored 0-based. E2E shows the first set displays as "2" — the execution pipeline is emitting 1-based indexes, so the +1 double-increments. Either the store or the formatter needs to agree on the convention. Fix probably belongs in `ExecutionViewModel.logSet` (emit 0-based) rather than the formatter, since "stored 0-based" is the existing comment.
- **Disposition:** watchlist. Cosmetic-only on the detail screen; doesn't break any list/summary math.

### FirstRun connection string format — URL + token vs unified QR payload
`docs/sync.md` describes the connection string as a single paste-or-QR payload (URL + embedded token). `Features/FirstRun` as shipped has two separate text fields (URL, bearer token). They diverge.
- **Assumption:** two fields is fine for v1 since QR scan isn't wired yet (stubbed); the unified connection-string format can land when the QR scanner lands.
- **Disposition:** defer-to-v1.1+.

### ADR index
`docs/decisions/` has two ADRs now. No README or index.
- **Assumption:** listing ADRs directly in `docs/AGENTS.md` is enough at this scale.
- **Disposition:** watchlist. Add an index file when the count exceeds ~6.

### Stale handoff bundle
`docs/design/` is a snapshot from 2026-04-17. It will drift. Refresh mechanism is in `docs/design/ORIGIN.md` but "when do we refresh" isn't specified.
- **Disposition:** resolve-in-code. Refresh when the design is materially different or when we hit a question only a newer design could answer.

### Telemetry MVP shipped; settings export + debug overlay deferred
The telemetry pipeline landed 2026-04-18 with a fixed 10k-event ring buffer, a handful of emit points (bootstrap / network / today.start / execution mutations), and the `POST /api/telemetry/events` endpoint. Explicitly NOT in the MVP: a Settings "export event bundle" share sheet, a debug overlay / swipe panel that renders the event trail on-device, a retention policy richer than the ring buffer, sampling or rate-limiting, and broader emit coverage (history tabs, settings toggles, watchOS faces).
- **Assumption:** the server-side event log alone is enough to diagnose bug reports; we reach for a local overlay / export only if Eric hits a case where the event trail didn't make it to the server (sustained offline, push-queue failure, app crash before flush).
- **Disposition:** defer-to-v1.1+. Reconsider once we have one or two real-workout bug reports and know which of the deferred surfaces we actually needed.

### Telemetry emit surface is narrow by design
Only `TodayViewModel.start`, the execution intents (`start/logSet/advance/save/autoreg_*`), `SyncAPI.pullLatest`, and the four `AppBootstrap` phases emit events right now. History / Settings / FirstRun / Execution view sheets do not.
- **Assumption:** broader emit coverage lands as features land — each new Feature adds its own emit points, and we don't pre-pollute the view models.
- **Disposition:** resolve-in-code. Each new Feature or reproducible bug is the trigger to add an emit point.

### Telemetry ring buffer is durable but un-pruned beyond the cap
`TelemetryEmitterImpl` caps local `EventModel` rows at 10 000 by pruning the oldest after each insert. There is no time-based retention, no manual "clear local events" action, and no surfaced counter in Settings. Pushed events also stay in the local store — we don't delete on successful push.
- **Assumption:** the 10k cap is fine on a single-user device that also pushes regularly; if we start seeing disk growth we add a "delete acknowledged" path or a retention window.
- **Disposition:** watchlist.
