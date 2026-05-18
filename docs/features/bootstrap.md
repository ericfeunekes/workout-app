---
title: bootstrap
status: verified
last_reviewed: 2026-05-17
purpose: Behavioral contract + QA scenarios for bootstrap
covers:
  - app/Packages/Shell/Sources/Shell/AppBootstrap.swift
  - app/Packages/Sync/Sources/Sync/PullService.swift
  - app/Packages/Sync/Sources/Sync/SyncAPI.swift
  - app/WorkoutDB/WorkoutDBApp.swift
---

# bootstrap

## What it does
On launch (or after FirstRun succeeds), the shell checks `TokenStore.loadConnection()`. If nil → `.firstRun`. If present → `.bootstrapping` + run `AppBootstrap.bootstrap(...)`. Bootstrap: (1) build `SyncAPI` over the saved URL+token, (2) `pullLatest(since: lastSyncAt)`, (3) on success save the `PullResult` into `WorkoutCache` and record `serverTime` as the new `lastSyncAt`, (4) build `TodayContext` via `TodayLoader`, (5) flatten the chosen workout into a `WorkoutContext`, (6) construct `TodayViewModel` + `ExecutionViewModel` + `AppSyncCoordinator`, return `.ready` or `.empty(appSync:)`. If pull returns `.tokenRejected` → throws `AppBootstrapError.tokenRejected`, shell clears TokenStore and routes back to FirstRun. Any other pull error is silently swallowed; the shell falls back to whatever the cache holds. If cache is also empty → `.empty`. See `docs/sync.md` § "Pull protocol" and "App sync ownership and foreground lifecycle".

## State surface
- **Inputs:** saved `(url, token)` from `TokenStore`, `lastSyncAt` from `SyncMetadataStore`, current `Date`
- **Outputs / side effects:** `WorkoutCache.save(PulledDataset)`, `SyncMetadataStore.setLastSyncAt(result.serverTime)`, telemetry events (`bootstrap.start`, `bootstrap.empty`, `bootstrap.ready`, `bootstrap.token_rejected`), `ConnectionManager` state transitions via `SyncAPI.pullLatest`
- **State transitions:** shell `ShellPhase`: `.firstRun | .bootstrapping | .ready(todayVM, executionVM, appSync) | .empty(appSync?) | .debugSeed(...)` (DEBUG only)

## What it deliberately doesn't do
- Does not retry pulls — single attempt per bootstrap. The `PushFlusher`'s 60s cadence is orthogonal; it pushes, not pulls.
- Does not distinguish decode/network/server errors to the user — all non-401 errors fall through to cache (`AppBootstrap.swift:146-150`, comment: "Transport / decode / server errors: fall through silently")
- Does not guard `WorkoutCache.save` against mid-loop throws — known issue in `open-questions.md` § "WorkoutCacheImpl.save non-atomicity"
- Does not own foreground/manual refresh after first render — those pulls are
  coordinated by `AppSyncCoordinator`.

## Edge cases handled in code
- `tokenRejected` rethrown as `AppBootstrapError.tokenRejected`; shell handles by clearing TokenStore and routing to FirstRun.
- Empty cache + failed pull → `.empty` (`AppBootstrap.swift:102`)
- `performLaunchCheck` gated by `didPerformLaunchCheck` so `.onAppear` re-firing doesn't re-run launch (`WorkoutDBApp.swift:185-190`)
- `runBootstrap` gated by `didStartBootstrap` early-return (`WorkoutDBApp.swift:251-252`) — fixes the double-bootstrap race
- `BootstrapLoadingView` is inert — no `.task` modifier — another layer of the double-bootstrap fix (`WorkoutDBApp.swift:155-159`, `375-386`)
- `EmptyStateView.onRetry` clears `didStartBootstrap` before re-entering (`WorkoutDBApp.swift:165-174`)
- Keychain read failure on launch → treat as no connection (`WorkoutDBApp.swift:237-240`)
- `PersistenceFactory.makeDefault` throw → fall back to in-memory; if that also throws → `fatalError` (`WorkoutDBApp.swift:122-139`)
- `executionVMHolder` captured STRONGLY in the session-mutation binding (`WorkoutDBApp.swift:272-284`, `359-368`) — fixed this session; weak capture silently broke "start workout"
- `pull.pull` feeds `since: lastSyncAt` on subsequent launches (`AppBootstrap.swift:135-136`) — server returns only changed rows

## Current gaps

- Settings owns post-bootstrap recovery actions such as sync now, reset local
  data, and change server. Bootstrap still only owns initial hydration.

## QA scenarios

### S1. Fresh launch, no saved token
- **setup:** first install, no keychain entry
- **steps:** launch app
- **expected:** `.firstRun` → FirstRunView rendered

### S2. Fresh launch, saved token, server reachable, has workouts
- **setup:** TokenStore populated, server has ≥1 workout
- **steps:** launch app
- **expected:** `.bootstrapping` (loading spinner ≤1s) → `.ready` → Today tab shows the scheduled workout

### S3. Saved token, server reachable, has NO workouts
- **setup:** TokenStore populated, server's sync/pull returns zero workouts
- **steps:** launch app
- **expected:** pull succeeds, `TodayLoader.load` returns nil (no today workout) → `.empty`. "No workouts yet" card with "try again" button.

### S4. Saved token, server unreachable, cache has workouts (stale)
- **setup:** TokenStore populated, cache contains yesterday's pull, server down
- **steps:** airplane mode → launch
- **expected:** pull fails silently, cache loaded, `.ready` with stale data. No user-visible error.

### S5. Saved token, server unreachable, cache empty
- **setup:** TokenStore populated, cache empty (just completed FirstRun then crashed before first pull; or wiped cache), server down
- **steps:** airplane mode → launch
- **expected:** `.empty` card, "try again" button

### S6. 401 during pull
- **setup:** TokenStore populated with rotated/invalidated token
- **steps:** launch
- **expected:** `AppBootstrapError.tokenRejected` thrown. Shell clears TokenStore, routes to FirstRun. User re-enters creds.
- **notes:** verify the TokenStore clear actually happens — the shell header at `WorkoutDBApp.swift:22-24` describes the intent but the explicit clear call may need tracing through `runBootstrapPipeline`

### S7. Partial decode failure mid-pull
- **setup:** server returns pull JSON with one malformed workout
- **steps:** launch
- **expected:** `PullService.mapResponse` throws `SyncError.decode` at first bad row. `AppBootstrap` eats it, falls through to cache. If cache is populated → `.ready` stale; if empty → `.empty`.

### S8. Double-bootstrap race (regression check)
- **setup:** fresh install, valid creds in FirstRun
- **steps:** complete FirstRun
- **expected:** exactly ONE `/api/sync/pull` fires. Observe via server logs or network inspector. No duplicate cache writes.
- **notes:** regression guard for the fix. Also applicable to `.onAppear` re-fire (backgrounding and returning).

### S9. Rapid retry from empty state
- **setup:** `.empty` is showing
- **steps:** tap "try again" twice rapidly
- **expected:** `EmptyStateView.isRetrying` disables the button after first tap; only one bootstrap pipeline runs (`WorkoutDBApp.swift:415-421`)

### S10. Naive-datetime regression check
- **setup:** server running code from BEFORE this session's fix (or mock server that emits `2026-04-18T12:00:00` without Z)
- **steps:** launch with valid token and populated server
- **expected:** on unfixed server, bootstrap would fall to `.empty` despite workouts existing. On fixed server, datetimes emit with `Z` suffix and decode succeeds.

### S11. Launch arg fast-paths (DEBUG only)
- **setup:** DEBUG build, launch with `--start-active`
- **steps:** launch
- **expected:** `.debugSeed` phase. Bootstrap is bypassed entirely. Seeded ExecutionViewModel is pre-started.
- **notes:** also `--jump-rest`, `--jump-complete` per `WorkoutDBApp.swift:297-355`

### S12. Server time skew
- **setup:** server clock 2h ahead of device
- **steps:** launch, bootstrap completes, `lastSyncAt = result.serverTime` (server's clock)
- **expected:** next pull uses server's clock as `since` — correct. No client-clock drift.

### S13. Relaunch after successful bootstrap
- **setup:** previously bootstrapped, app killed, relaunched
- **steps:** launch
- **expected:** `since=lastSyncAt` sent to server, only delta returned. Cache merged via upsert. Faster load.

### S14. Background during bootstrap
- **setup:** bootstrap in flight
- **steps:** background app mid-pull, return to foreground
- **expected:** URLSession may suspend; pull may fail → fall through to cache. `didStartBootstrap` guard means no second pull triggers on resume.
- **notes:** unclear from code whether suspended task resumes cleanly

### S15. Token rejected during push (not pull)
- **setup:** `.ready`, PushFlusher running, token rotates server-side mid-session
- **steps:** log a set, wait for flush
- **expected:** 401 during push → `PushFlusher` stops its loop and reports `tokenRejected`; `AppSyncCoordinator` emits the token-rejected lifecycle event, stops foreground flushing, and Shell routes to FirstRun. Queued writes remain durable for re-auth.
