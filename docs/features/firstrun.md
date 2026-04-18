---
title: firstrun
status: living
purpose: Behavioral contract + QA scenarios for firstrun
covers:
  - app/Packages/Features/FirstRun/Sources/FeaturesFirstRun/FirstRunViewModel.swift
  - app/Packages/Features/FirstRun/Sources/FeaturesFirstRun/FirstRunView.swift
---

# firstrun

## What it does
Presents a welcome card with URL + bearer-token inputs. On "connect" tap, `FirstRunViewModel.connect()` validates the URL, fires `GET /api/version` as a handshake, persists the (url, token) pair to `TokenStore` only after 200, then fires `GET /api/sync/pull` (no `since`) to prime the cache and surface "N sessions · M exercises". On success, invokes `onComplete` which the shell uses to advance to `bootstrapping`. Failures render an inline banner under the welcome card; inputs remain editable for retry. See `docs/sync.md` § "First-run UX" for the contract.

## State surface
- **Inputs:** `url: String`, `token: String` (two-field — diverges from `docs/sync.md`'s single-payload QR design; two-field wins for v1 per `open-questions.md` § "FirstRun connection string format")
- **Outputs / side effects:** `TokenStore.saveConnection(url:token:)` (only after /api/version 200), `onComplete()` closure fired on success
- **State transitions:** `.welcome → .connecting → .syncingFirstPull(nil) → .syncingFirstPull(summary) → .complete`, or any step → `.failed(reason)` which keeps the welcome card rendered with a banner

## What it deliberately doesn't do
- Does not map pull DTOs to Domain — uses a minimal `PullProbe` that counts `workouts` + `exercises` only (`FirstRunViewModel.swift:287-322`). Full mapping is `AppBootstrap`'s job.
- Does not save token before `/api/version` returns 200 (`FirstRunViewModel.swift:190-207` — comment: "we do not want to persist a token that produces 401 on every subsequent call")
- Does not retry automatically — user taps retry. No exponential backoff, no timeout tuning.
- Does not implement QR scan — `QRStubSheet` says "qr scan coming in v1.1" (`FirstRunView.swift:225-252`)
- Does not dismiss keyboard on field blur — no explicit `.submitLabel` / `.onSubmit` wiring

## Edge cases handled in code
- Re-entrancy guard early-returns if `state` ∈ `{.connecting, .syncingFirstPull, .complete}` (`FirstRunViewModel.swift:173-178`). View-side `disabled: viewModel.isConnectInFlight` on the connect button (`FirstRunView.swift:113-118`) is belt-and-braces.
- URL trimmed of whitespace + newlines (`validatedURL()`, `FirstRunViewModel.swift:236`)
- Token trimmed of whitespace + newlines before use (`FirstRunViewModel.swift:183`)
- Scheme-less URLs rejected (`"foo.bar"` parses but has no scheme — `validatedURL()` filters at `:240`)
- Hostless URLs rejected (`:241`)
- Empty URL after trim → `.invalidURL`
- `TokenStore.saveConnection` throw → treated as `.unreachable` so user can retry (`:203-208`)
- Version decode failure → `.decode` — "server responded but the shape didn't match" (proves it's not a workoutdb server at that URL)

## Known issues / gaps
- `open-questions.md` § "FirstRun `connect()` re-entrancy" — MUST-FIX identified 2026-04-18, fixed via the re-entrancy guard above. Named regression `testRapidDoubleTapConnectOnlyInvokesPipelineOnce` closes bug-018.
- `open-questions.md` § "App shell double-bootstrap race" — fixed this session; FirstRun's `onComplete` no longer double-fires bootstrap (see `bootstrap.md`).
- Fixed this session: naive datetime decode at bootstrap caused silent FirstRun → empty state (see `bootstrap.md`).
- Fixed this session: UUID-case mismatch on `/api/sync/results` (see `push-queue.md`) — orthogonal to FirstRun but surfaced during first-run push after sync.
- Not built: trailing-slash normalization — `https://host/` vs `https://host` are passed to `URLSessionTransport` as-is. Behavior depends on the transport's path joining.

## QA scenarios

### S1. Happy path: valid URL + token
- **setup:** fresh install, server reachable at `https://host.ts.net` with a valid bearer
- **steps:** paste URL, paste token, tap "connect"
- **expected:** "connecting…" card → "syncing your program" card with "N sessions · M exercises" → shell advances to bootstrap loading → Today renders

### S2. Happy path: whitespace-wrapped paste
- **setup:** clipboard holds `"  https://host.ts.net  \n"` and `"  tok123  \n"`
- **steps:** paste into both fields, tap "connect"
- **expected:** same as S1 — trimming is on both sides

### S3. Invalid URL shape
- **setup:** fresh install
- **steps:** type `foo.bar` (no scheme) in URL, type any token, tap "connect"
- **expected:** welcome card stays, banner reads "that doesn't look like a valid url. try https://host.ts.net."

### S4. Empty URL
- **setup:** fresh install
- **steps:** leave URL blank, type token, tap "connect"
- **expected:** `.invalidURL` banner (no network call made)

### S5. Rejected token (401)
- **setup:** server reachable, token is wrong
- **steps:** paste URL + bad token, tap "connect"
- **expected:** banner "token rejected — check the token you pasted." `TokenStore` is NOT written (verify by relaunch → returns to FirstRun)

### S6. Unreachable server
- **setup:** URL points at dead host (e.g. `https://nope.ts.net`)
- **steps:** paste, tap "connect"
- **expected:** banner "couldn't reach the server. check the url and try again." Inputs retained.

### S7. Server responds but wrong shape
- **setup:** URL points at any JSON-returning host that isn't workoutdb (e.g. `https://httpbin.org/get`)
- **steps:** paste, tap "connect"
- **expected:** banner "server responded but the shape didn't match — is this the right server?"

### S8. Rapid double-tap "connect" (bug-018 fix)
- **setup:** any valid config
- **steps:** tap "connect" twice as fast as possible
- **expected:** single pipeline runs. Button is `.disabled` while `isConnectInFlight`. No duplicate `TokenStore.saveConnection` call, no duplicate pull.
- **notes:** re-entrancy guard in `connect()` backstops the view-side disable. If you can force two concurrent Tasks programmatically, the second no-ops. Pinned by `testRapidDoubleTapConnectOnlyInvokesPipelineOnce` — the scripted transport enqueues exactly one happy path and asserts call counts stay at 2 (one version + one pull).

### S9. Retry after failure
- **setup:** just failed with `.tokenRejected`
- **steps:** edit token, tap "connect" again
- **expected:** same pipeline re-runs from `.welcome` path (failed state is an allowed entry in `connect()`)

### S10. Pull succeeds but count is 0/0
- **setup:** valid auth, server has no workouts or exercises yet
- **steps:** connect
- **expected:** "syncing your program" card shows "0 sessions · 0 exercises", then `onComplete` fires. Shell typically lands in `.empty` state after bootstrap.
- **notes:** see `bootstrap.md` S4 for shell handling

### S11. http vs https
- **setup:** server at `http://192.168.1.2:8000` (LAN, no TLS)
- **steps:** paste http URL, connect
- **expected:** works — no scheme restriction in `validatedURL()`. ATS may block in release builds.

### S12. URL with trailing slash
- **setup:** paste `https://host.ts.net/` (trailing slash)
- **steps:** connect
- **expected:** not explicitly normalized; URLSessionTransport handles path joining. If requests fail, check whether `/api/version` is being hit as `//api/version`.
- **notes:** unclear from code whether transport normalizes; not built into `validatedURL()`

### S13. QR tap (stub)
- **setup:** any state
- **steps:** tap "scan qr"
- **expected:** sheet appears: "qr scan coming in v1.1". Tap "got it" dismisses.

### S14. Keyboard not dismissed on field blur
- **setup:** focused URL field with text
- **steps:** tap outside the field
- **expected:** keyboard persists (not built — no tap-to-dismiss gesture)

### S15. Background during connecting
- **setup:** valid config, tap connect, immediately background the app
- **steps:** return to foreground after 10s
- **expected:** depends on URLSession task lifecycle — not explicitly handled. Likely lands in `.failed(.unreachable)` if the task was killed, or `.complete` if it finished.
- **notes:** unclear from code — no explicit background-task handling
