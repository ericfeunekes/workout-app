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
Presents a welcome card with URL + bearer-token inputs. On "connect" tap, `FirstRunViewModel.connect()` validates the URL, fires `GET /api/version` as a handshake, persists the (url, token) pair to `TokenStore` only after 200, and invokes `onComplete` which the shell uses to advance to `bootstrapping`. The shell's `AppBootstrap` then owns the first `GET /api/sync/pull` — FirstRun does NOT fire that itself (see "Scope boundary" below). Failures render an inline banner under the welcome card; inputs remain editable for retry. See `docs/sync.md` § "First-run UX" for the contract.

## State surface
- **Inputs:** `url: String`, `token: String` (two-field — diverges from `docs/sync.md`'s single-payload QR design; two-field wins for v1 per `open-questions.md` § "FirstRun connection string format"). Both pre-fillable via `initialURL` / `initialToken` init params, used by the shell's `.empty → Change Server → FirstRun` recovery route so Eric doesn't retype.
- **Outputs / side effects:** `TokenStore.saveConnection(url:token:)` (only after /api/version 200), `onComplete()` closure fired on success
- **State transitions:** `.welcome → .connecting → .complete`, or any step → `.failed(reason)` which keeps the welcome card rendered with a banner. The shell's `BootstrapLoadingView` ("Syncing…") renders during AppBootstrap's first pull.

## Scope boundary — FirstRun validates, AppBootstrap hydrates

FirstRun only fires `/api/version` as a credentials handshake. The first `/api/sync/pull` — the one that populates the cache — is `Shell.AppBootstrap`'s exclusive responsibility. History: an earlier shape had FirstRun ALSO fire `/api/sync/pull` to surface a "N sessions · M exercises" count, while AppBootstrap also pulled immediately after. This duplicated network work AND opened a stranding hazard: if FirstRun's pull succeeded but AppBootstrap's follow-up pull later failed (non-401), the user would land on `.empty` despite valid creds with no way back to FirstRun to edit the server. Eliminating FirstRun's pull closed the hazard at the root.

Pinned by `testFirstRunHandsOffToBootstrapWithoutSecondPull` (FirstRun target) + `testBootstrapFiresExactlyOnePullPerRun` (Shell target).

## What it deliberately doesn't do
- Does not fire `/api/sync/pull` — that's AppBootstrap's job. See "Scope boundary" above.
- Does not save token before `/api/version` returns 200 (`FirstRunViewModel.swift` — comment: "we do not want to persist a token that produces 401 on every subsequent call")
- Does not retry automatically — user taps retry. No exponential backoff, no timeout tuning.
- Does not implement QR scan — `QRStubSheet` says "qr scan coming in v1.1" (`FirstRunView.swift`)
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
- Re-entrancy (bug-018) closed via the guard in `connect()` + `.disabled(isConnectInFlight)` on the view. Pinned by `testRapidDoubleTapConnectOnlyInvokesPipelineOnce`.
- Scope boundary (bug-048) closed: FirstRun only hits `/api/version`; AppBootstrap owns the sole pull. `testFirstRunHandsOffToBootstrapWithoutSecondPull` + `testBootstrapFiresExactlyOnePullPerRun` pin it. `.empty` state gained a "change server" route with URL + token pre-fill so a wrong server URL doesn't trap the user.
- Double-bootstrap race closed: `FirstRun.onComplete` no longer double-fires bootstrap; shell's `didStartBootstrap` guard + inert `BootstrapLoadingView` (no `.task`).
- Naive-datetime decode (bug-002) closed server-side via `UtcDatetime` / `UtcDatetimeIn` serializers.
- UUID-case mismatch (bug-004 / bug-045) closed: every outbound UUID routes through `UUID.wireID` (lowercase).
- Not built: trailing-slash normalization — `https://host/` vs `https://host` are passed to `URLSessionTransport` as-is.

## QA scenarios

### S1. Happy path: valid URL + token
- **setup:** fresh install, server reachable at `https://host.ts.net` with a valid bearer
- **steps:** paste URL, paste token, tap "connect"
- **expected:** "connecting…" card → shell advances to `BootstrapLoadingView` ("Syncing…") while AppBootstrap runs the first pull → Today renders

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
- **expected:** single pipeline runs. Button is `.disabled` while `isConnectInFlight`. No duplicate `TokenStore.saveConnection` call.
- **notes:** re-entrancy guard in `connect()` backstops the view-side disable. If you can force two concurrent Tasks programmatically, the second no-ops. Pinned by `testRapidDoubleTapConnectOnlyInvokesPipelineOnce` — the scripted transport enqueues exactly one happy path and asserts call counts stay at 1 (one `/api/version`).

### S9. Retry after failure
- **setup:** just failed with `.tokenRejected`
- **steps:** edit token, tap "connect" again
- **expected:** same pipeline re-runs from `.welcome` path (failed state is an allowed entry in `connect()`)

### S10. Auth succeeds but server has no workouts
- **setup:** valid auth, server has no workouts or exercises yet
- **steps:** connect
- **expected:** `onComplete` fires → shell's BootstrapLoadingView → AppBootstrap pull returns empty → shell lands in `.empty` state. The "change server" button on `.empty` routes back to FirstRun with URL + token pre-filled (see `bootstrap.md` S4 and the "change server" recovery route in `RootView.changeServer()`).
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

### S16. Bearer-token paste does not surface "Save Password" (qa-040)
- **setup:** iOS simulator or device, fresh install, no stored passwords for the target domain.
- **steps:** paste a 64-char bearer token into the bearer field. Do not submit.
- **expected:** no "Would you like to save this password?" modal appears. The token field still renders as dots and hides on background.
- **notes:** manual-only — iOS's save-password heuristic is not reproducible in a unit test. The fix is `.textContentType(.oneTimeCode)` on the SecureField (see `FirstRunView.swift`); removing that modifier would regress this scenario. The field keeps its secure-rendering behaviour because that comes from `SecureField`, not from `textContentType`.
