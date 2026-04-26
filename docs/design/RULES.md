# Rules — Behavior & Logic

Rules extracted from `src/hifi.jsx`. If Claude needs to extend the prototype, these are the prototype invariants.

Production behavior is governed by `docs/spec.md`, `docs/features/`, and `docs/bugs.md`. Where this file describes older prototype interactions that the app has deliberately scoped out, treat them as design reference rather than implementation requirements.

---

## Architecture — sync model

The app is a local-first client to a user-run server. Programs authored upstream (user + Claude) are pushed to a local/server DB. The app syncs down, but continues to function when the server is unreachable.

- **Server address = identity.** No login, no accounts. Pointing at a different server = different data. Settings screen lets user change/reset the server address.
- **Local-first.** The app works without network. Offline is the **default assumption**, not an error state. No yellow banner, no warning — just a tiny neutral "offline" indicator next to the menu.
- **Sync triggers:** on app open, on log write, and on a gentle retry while foregrounded (~1 min cadence). No aggressive polling.
- **Conflict resolution:** server wins for prescriptions; client wins for logs. Live session is frozen — any upstream re-prescription applies only to the next occurrence.
- **First launch is the one exception** — with no cached data, a server is required to proceed.
- **Reset:** clearing server address wipes local cache. "Reset local data" in Settings.

## RIR (Reps In Reserve)

- **Scale:** 0 to 5
  - `0` = failure / no reps left
  - `1` = could have done 1 more
  - `2` = could have done 2 more
  - etc.
- **Not RPE.** Don't introduce RPE conversions or language.
- **Per exercise, a `targetRir`** is prescribed (typically 1-2 for strength blocks).

---

## Autoreg (autoregulation)

Triggered **after logging a set**, applied to **remaining sets in the current exercise** (configurable via `applyTo`).

### Rule: overshoot (too easy)

Condition: `justSet.rir >= targetRir + overshootAt`
- `overshootAt` defaults to **2** (so RIR >= target+2 triggers)
- Example: target RIR 2, you log RIR 4 → trigger

Action: bump load by `overshootStep` (default **2.5 kg**) for remaining sets. Round to nearest plate (2.5 kg).

### Rule: undershoot (too hard)

Condition: missed reps OR hit failure
- `repsMissed = prescribedReps - actualReps >= undershootAt` (default 2), OR
- `justSet.rir === 0 && targetRir > 0` (hit failure when target was non-zero)

Action: drop load by `undershootStep` (default 2.5 kg) for remaining sets.

### Presentation

- Autoreg proposal appears as a card on the Rest screen
- User can **Accept** (default, applied automatically) or **Undo** → sets `autoregHeld: true` on the exercise
- Once `autoregHeld`, no further autoreg proposals fire for this exercise in this session

### Past-set edits DO NOT retrigger autoreg

Editing a past set (via `PastSetSheet`) is **corrective only** — the record is changed, but no new autoreg runs. This prevents confusing cascading re-adjustments.

---

## Tap-to-edit

Everywhere a value is displayed, it's tappable.

### Past (done) sets
- Tap any cell (load, reps, RIR) in the mini ledger → `PastSetSheet` → numpad or RIR picker
- Subtitle: "Correcting log · no autoreg"

### Pending sets (planned, not yet logged)
- Tap load or reps cell → `PastSetSheet` → numpad
- Subtitle: "Editing plan · just this set"
- RIR cell is **not tappable** on pending rows (no value exists yet)

### Plan sheet (Today → tap exercise)
**Prototype-only reference as of 2026-04-24.** Production Today uses a read-only workout detail sheet plus a copyable Claude adjustment request; it does not mutate plans locally.

- Edit load/reps per set in a compact grid
- Add/remove sets (`+ set` / `− set`)
- "Start this exercise" jumps to active screen at first-pending set
- Edits are **session-local** — the `WORKOUT` template is not touched

### Pre-workout vs mid-workout vs post-workout
All work the same. Same sheet, same behavior. Only the subtitle copy changes.

---

## Persistence

Everything survives reload. Stored in `localStorage`:

| Key | Contents |
|---|---|
| `hifi_log` | Full set log (every set's load/reps/rir/done/adjust) |
| `hifi_cursor` | `{b: blockIdx, s: setIdx}` — where the user is |
| `hifi_route` | `"today" \| "active" \| "rest" \| "complete"` |
| `hifi_note` | Workout-level free-text note |
| `hifi_tweaks` | Tweaks panel state |

**Reset:** the "Reset demo" button (outside the device frame) clears all of the above.

**Save & done (Complete screen):** clears log/cursor/note and returns to Today.

---

## Routing / screen state

Single-page app with a `route` string. No URLs.

Flow:
- `today` → tap Start workout OR tap exercise (via plan sheet) → `active`
- `active` → log set → `rest`
- `rest` → continue → next `active` OR (if last set) `complete`
- `complete` → save & done → `today`
- Any screen → reset demo → `today` (fresh log)

Back navigation:
- `active` → Today (via nav bar) → `today`
- `rest` → no explicit back (forward-only)
- `complete` → Today (via nav bar)

---

## Sheets

Bottom sheets with backdrop. z-index 30 (backdrop) / 31 (sheet).

- **NumPadSheet** — numeric entry with optional unit (kg/reps), scope selector (this set / remaining sets)
- **ScopedNumPad** — same, with explicit scope UI
- **SimpleNumPad** — no scope, used for past-set corrections
- **RirSheet** — 0-5 picker
- **PastSetSheet** — routes to RirSheet or SimpleNumPad based on field
- **PlanSheet** — tall sheet, per-set grid editor, session-local edits
- **HistoryDrawer** — tall sheet, list of past sessions, expandable per session, optionally filtered to one exercise

**Tall sheets** (PlanSheet, HistoryDrawer) have `max-height: 82%` and `overflow-y: auto`. The slide-in animation is disabled via inline style to avoid a CSS cascading issue with repeated renders.

---

## Set data shape

```js
{
  i: 1,              // 1-indexed set number
  load: 102.5,       // kg (or whatever block.unit is)
  reps: 5,
  rir: null,         // null until logged; 0-5 after
  done: false,       // true once logged
  adjust: null,      // null | "up" | "down" | "manual" — why this set differs from block default
}
```

`adjust` drives the inline glyph (↑ ↓ ✎) next to the load value.

---

## Block (exercise) data shape

See `WORKOUT.blocks[]` in `src/hifi.jsx`:

```js
{
  id: "bench",
  name: "Barbell Bench Press",
  scheme: "straight_sets",
  sets: 4, reps: 5, load: 102.5, unit: "kg", rest: 180,
  targetRir: 2,
  autoreg: {
    overshootAt: 2, overshootStep: 2.5,
    undershootAt: 2, undershootStep: 2.5,
    applyTo: "remaining",  // future: "next" | "remaining" | "all-future"
  },
  last: "5×5 @ 100 kg · RIR 2",  // display string; real app would compute
}
```

---

## Copywriting rules

- **Imperative, terse.** "Log set", not "Tap to log your set"
- **No motivational language.** No "crushed it", no "beast mode", no emojis in UI
- **Monospace for numbers.** Inter for labels, Plex Mono for anything numeric
- **Capitalization:** Sentence case in titles, ALL CAPS + letter-spacing for monospace labels (like "LAST TIME — FRI")
- **Units always visible** — "102.5 kg", not "102.5"
- **RIR never abbreviated further** — it IS the abbreviation

---

## Icon system rules

Exercise and block icons must be treated as a small visual system, not one-off generated images.

- **Start from SVG masters.** Keep source icons as editable SVGs; export app-ready assets from those masters.
- **Use the design tokens.** Default linework uses `--ink`; accent marks use existing tokens (`--accent`, `--accent-ink`, `--warn`, `--ok`) rather than new colors.
- **Use a strict grammar.** 24×24 viewBox, rounded caps/joins, consistent stroke weight, no shadows, no perspective, no gradients inside the icon, no tiny anatomical detail.
- **Prefer category/block icons before per-exercise icons.** Strength, conditioning, run, warm-up, rest, timer, bodyweight, dumbbell, barbell, kettlebell, row, bike, and mobility should establish the language before dozens of exercise-specific variants.
- **Differentiate variants with the largest readable shape.** For example, flat dumbbell bench vs. incline dumbbell bench should be distinguished primarily by the bench angle and dumbbell position, not by adding a detailed human figure.
- **Render before accepting.** Every icon batch must be rasterized and visually inspected at 48, 32, 24, and 20 pt. If it fails at 24 pt, simplify or reserve it for larger contexts. 20 pt is a lower bound, not the target.
- **Iterate from screenshots.** The workflow is SVG source → rendered preview/contact sheet → critique → SVG edit → repeat. Do not land blind SVGs without viewing them at target sizes.

Current source: `docs/design/icons/exercise-icons.svg` defines the first 24×24 symbol set and `docs/design/icons/renders/exercise-icons.png` is the contact-sheet proof. The SwiftUI implementation lives in `DSExerciseIconView`. Flat vs. incline bench now reads primarily through bench angle; the flat variant is acceptable at 24 px but should not be pushed below 20 px without simplification.

## App icon rules

The app icon is related to the in-app icon language, but it is not the same asset class. Treat it as a launcher-brand artifact with its own review loop.

- **Start at 1024×1024.** Keep the source master at App Store size, then export the full iOS app icon set from that source.
- **Use the same palette, more boldly.** Base should stay in the warm dark / surface family; foreground marks can use `--accent`, `--accent-ink`, `--warn`, or `--ok`, but the icon must still read as Setmark next to other apps.
- **Avoid tiny UI-icon detail.** A launcher icon can have more depth and mass than a 24×24 glyph, but it still needs one dominant silhouette. Do not pack it with multiple tiny exercise symbols.
- **Test real sizes.** Review at 1024, 180, 120, 87, 80, 60, 40, and 29 px, plus a simulated iOS home-screen tile. If the mark only works at 1024, it is not done.
- **Check mask safety.** Keep the important mark away from rounded-corner crop zones; verify against iOS squircle masking.
- **Compare variants side by side.** App icon candidates should be rendered as a contact sheet before selection. Do not choose a generated app icon from a single full-size preview.
- **Do not land generated PNGs without critique.** As with exercise icons, the workflow is source/generation → rendered size sheet → visual critique → revision → asset catalog export.

Current source: `docs/design/icons/app-icon-master.svg` is the selected launcher master, with `docs/design/icons/renders/app-icon-contact-sheet.png` as the candidate and size proof. Generated iOS app icon assets live in `app/WorkoutDB/Assets.xcassets/AppIcon.appiconset/`. The older local candidates `app/icon_1024.png` and `app/icon_1024_v2.png` remain unselected references.
