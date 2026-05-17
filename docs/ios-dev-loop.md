---
title: iOS dev loop for Claude Code
status: accepted
date: 2026-04-18
purpose: How Claude (or another coding agent) drives the iOS app build → launch → inspect → interact → screenshot → iterate loop. Names the recommended tool (XcodeBuildMCP) and documents the ad-hoc fallback that works without it.
covers:
  - app/
  - docs/
---

# iOS dev loop for Claude Code

The iOS app (`app/WorkoutDB.xcodeproj`) is generated from `app/project.yml` via XcodeGen. Once the Xcode project exists, an agent working on the app needs to build, launch in the Simulator, see what renders, drive gestures, read logs, and iterate. This doc picks the tool stack and documents the fallback.

## Recommended stack — install this before long iteration sessions

**Primary tools** (the ones that make the loop actually tight):

1. **Xcode 26.3+** — Apple's own agentic bridge lives here. The Xcode UI can expose an MCP bridge to external agents (previews, issue navigator, project-aware edits).
2. **Claude Code** (this tool) or **Codex CLI** — the coding agent.
3. **XcodeBuildMCP** — the MCP server that turns Xcode / simctl / device-control into structured tool calls. Install it globally so both Macs expose the same `xcodebuildmcp` command.
4. **Xcode's external-agent MCP bridge**, enabled from within Xcode.

**What the MCP tools give you** (each is a real Claude Code tool call, not a shell one-liner):

| Tool | What it does |
|---|---|
| `discover_projs` / `list_schemes` | Project + scheme discovery without parsing xcodeproj guts |
| `build_run_sim` | Build + install + launch on a named simulator in one call |
| `snapshot_ui` | UI / accessibility tree with coordinates — the big one for "agent looks at the UI" |
| `tap` / `swipe` / `type_text` / `long_press` | Structured gesture input — no cliclick, no idb, no coordinate math |
| `screenshot` | Capture the current simulator state |
| `lldb_attach` | Debugger access from the agent |
| `xcode_ide` tools | Previews, issue navigator, project outline when the Xcode IDE bridge is on |

**Why this beats pixel-driving:** the accessibility tree gives the agent stable, semantic handles. `tap(on: "log set 1")` survives layout changes; `cliclick 400 1200` doesn't.

## Ad-hoc fallback — what to do when XcodeBuildMCP isn't wired

Works today with only Xcode + Command Line Tools. Every iteration is a shell command.

### Build + run

```bash
DEVICE=$(xcrun simctl list devices available | grep 'iPhone 16 Pro' | head -1 | sed -E 's/.*\(([-A-F0-9]+)\).*/\1/')

xcodebuild -project app/WorkoutDB.xcodeproj -scheme WorkoutDB \
  -destination "id=$DEVICE" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath /tmp/wdb-build build

APP=$(find /tmp/wdb-build/Build/Products -name "WorkoutDB.app" -type d | head -1)

xcrun simctl terminate "$DEVICE" com.ericfeunekes.WorkoutDB 2>/dev/null
xcrun simctl uninstall "$DEVICE" com.ericfeunekes.WorkoutDB
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.ericfeunekes.WorkoutDB [--launch-args...]
```

### See what rendered

```bash
xcrun simctl io "$DEVICE" screenshot /tmp/shot.png
# Then Read /tmp/shot.png — Claude Code handles PNG via the Read tool.
```

### Gesture input — no good path without MCP

Two workarounds that exist in this repo:

1. **`cliclick`** (`brew install cliclick`) — clicks physical screen coordinates. Requires the user to grant Accessibility permission in System Settings. Pixel-coordinate fragile.
2. **Debug launch arguments** — the app shell honours `--start-active`, `--jump-rest`, `--jump-complete` in `#if DEBUG` to jump to specific routes. Added as an expedient; see `app/WorkoutDB/WorkoutDBApp.swift`. This is the most reliable fallback for screenshot verification of specific screens.

Neither is a substitute for `snapshot_ui` + `tap` from XcodeBuildMCP. When iteration volume starts burning minutes per screen, install MCP.

### `idb` (Meta)

Ideal for CLI-only setups, but the install went south on this machine due to a cert issue on the Facebook brew tap (`brew tap facebook/fb` failed with "error setting certificate verify locations"). Listed here as a known-available option elsewhere; not usable in this environment.

## Watch apps — narrower path

Watch automation is less mature:

- XcodeBuildMCP's UI tools are **documented for iOS simulator specifically**, not watchOS. Build + scheme + log tools work on watch; gesture tools may not.
- Appium's watchOS support has unresolved issues with modern architectures.
- `xcrun simctl` for watchOS sims supports build/install/launch/screenshot but not tap.

Practical rule: use **XCTest UI tests** for watch behavior. Agent writes the test, runs it, reads the result. Don't expect the same tap-screenshot-tap loop on watch that works on iPhone.

## Decision guide

| Goal | Use |
|---|---|
| Fast iteration on iPhone UI | **XcodeBuildMCP** (install it) |
| Quick one-shot check, MCP not yet wired | Shell + screenshot + Read (fallback) |
| Specific screen state for screenshot | `--start-active` / `--jump-rest` / `--jump-complete` launch args |
| WatchOS behavior | XCTest UI test, not gesture automation |
| Cross-platform (Android too) or WebDriver-style | Appium — only if those constraints exist |
| Can't find a structured tool for a weird Xcode GUI gap | Claude computer-use (beta) as a last resort |

## Installing XcodeBuildMCP

### Status

Configured as a single global command. `.mcp.json` and `.codex/config.toml` both call `xcodebuildmcp` directly, matching the original setup.

The portability boundary is: both Macs must have `xcodebuildmcp` on the agent PATH. Do not commit machine-specific paths, Volta paths, npm prefix paths, simulator UUIDs, or usernames into MCP config.

The MCP server env includes `/usr/local/bin` and `/opt/homebrew/bin` in `PATH` so either Intel/Homebrew or Apple Silicon/Homebrew global npm installs resolve the same bare `xcodebuildmcp` command.

### First-time install on each Mac

```bash
# Install the shared MCP command.
npm install -g xcodebuildmcp

# Verify the tool registry.
make xcode-mcp-tools
```

### The committed `.mcp.json`

```json
{
  "mcpServers": {
    "xcodebuild": {
      "type": "stdio",
      "command": "xcodebuildmcp",
      "args": ["mcp"],
      "env": {
        "XCODEBUILDMCP_ENABLED_WORKFLOWS": "simulator,simulator-management,ui-automation,debugging,logging,project-discovery,xcode-ide,utilities,swift-package"
      }
    }
  }
}
```

**Why the env var matters:** `xcodebuildmcp mcp` with no env loads a narrower workflow set. The env list above unlocks `ui-automation` (tap, swipe, snapshot-ui, screenshot, type-text), `debugging` (LLDB, breakpoints), `logging` (sim log capture), `xcode-ide` (Xcode bridge), and SwiftPM helpers. With `xcodebuildmcp` 2.5.2, `make xcode-mcp-tools` reports 69 canonical tools.

### Xcode IDE bridge (optional but useful)

In Xcode 26.3+ under **Xcode → Settings → Internal (or Agents)**, toggle "Allow external agents to access Xcode tools." This unlocks the `xcode-ide` workflow's IDE-only capabilities (previews, issue navigator).

This machine check on 2026-05-17 found macOS 26.5 with Xcode 16.4 selected. That is enough for SwiftPM and Simulator basics, but not enough for Apple's Xcode 26.3+ external-agent bridge. Upgrade/select Xcode 26.3+ before relying on `xcode-ide` tools.

### Restart gotcha

Claude Code and Codex load MCP tool registries at session start. After installing `xcodebuildmcp`, installing local skills, or changing `.mcp.json` / `.codex/config.toml`, restart the agent app/session to pick up the new tools.

### Verify after restart

In the next session, these tool calls should succeed:

```
mcp__xcodebuild__simulator-list()                    → list of simulators
mcp__xcodebuild__project-discovery-discover-projs()  → finds WorkoutDB.xcodeproj
mcp__xcodebuild__simulator-list-schemes(project=...) → lists all schemes
mcp__xcodebuild__simulator-build-and-run(
    scheme="WorkoutDB",
    destination="iPhone 16 Pro")
mcp__xcodebuild__ui-automation-snapshot-ui()         → hierarchy + coords
mcp__xcodebuild__ui-automation-tap(label="log set 1")
mcp__xcodebuild__ui-automation-screenshot()          → PNG bytes
```

The exact tool name format is `mcp__<server>__<workflow>-<tool>` in Claude Code. Use `ToolSearch("xcodebuild")` within a session to discover the live names.

The `.xcodebuildmcp/config.yaml` file intentionally stores only portable defaults: relative project path, scheme, configuration, bundle ID, and simulator platform. Pick the simulator per run by name from the live simulator list; never commit a simulator UUID.

## Runtime proof recipes

Use these when `docs/TESTING.md` or a feature doc asks for runtime proof.
Keep runs focused: one claim, one simulator/device, one artifact directory
under `scratch/qa-runs/<YYYY-MM-DD>-<slug>/`.

Before starting, run:

```bash
make qa-runtime-ready
```

This verifies XcodeBuildMCP plus the local `xctrace`, `simctl`, and `leaks`
tool surface. It does not capture evidence by itself.

### Timer gauntlet

Use DEBUG routes to reach timer-heavy states quickly:

- `--start-active` for Active route proof
- `--jump-rest` for Rest route proof
- `--jump-complete` for completion proof

For simulator QA, capture `snapshot_ui` at each route boundary, screenshots at
meaningful states, logs/telemetry when state is part of the claim, and a short
recording for `img ask --video`.

### ETTrace

Use ETTrace for CPU/render/layout claims. Capture one focused flow such as
launch -> Today, Active set start -> log -> Rest, Rest countdown -> next, or a
History scroll/filter path. Preserve the processed trace or JSON summary in the
run directory and summarize:

- app build and simulator/device
- route and exact user flow
- before/after comparison if optimizing
- hottest app-owned symbols or SwiftUI update paths
- caveats that keep the result from proving more than the focused flow

Do not add temporary trace hooks to production code. If temporary instrumentation
is unavoidable, remove it before closeout.

### Memgraph / leaks

Use memgraph/leaks proof for object-lifetime claims. Good focused flows:

- open/dismiss edit sheets repeatedly
- save-and-done, then start the next workout
- History list -> detail -> back
- Settings reset/change-server
- background/foreground with push flusher active

The closeout summary should name app-owned leaked or retained types, ownership
paths where available, and whether the evidence is a true leak, expected
lifetime, or inconclusive grouped retention.

## When the fallback is fine

- You're taking one or two screenshots as a sanity check on a specific change.
- You only need to verify the app builds and launches.
- The screen you're verifying can be reached via a launch argument.

## When to upgrade to MCP

- You're doing UI iteration — comparing design fidelity, trying multiple variants.
- You need to exercise a flow with real gesture input (tap a card → expand → edit → confirm).
- You're running XCTest UI tests and want the agent to read test output structurally.
- Any agent session that will spend more than ~20 minutes on UI work.

## References

- XcodeBuildMCP README and tool list.
- Apple's Xcode 26.3 external-agent docs.
- OpenAI native-iOS guidance recommending CLI-first with XcodeBuildMCP for deeper automation.
- Anthropic computer-use: beta desktop automation, useful as a fallback only.
