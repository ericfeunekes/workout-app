---
title: Setmark Icon Masters
status: draft
purpose: Source assets and rendered review artifacts for app and exercise icons.
---

# Icon Masters

This folder holds the editable source assets for the Setmark icon language.

- `app-icon-master.svg` is the launcher icon master. Export app catalog PNGs from this file.
- `app-icon-contact-sheet.svg` compares the local candidates and selected master, then renders the selected master at real iOS sizes.
- `exercise-icons.svg` is the first 24x24 symbol sheet for block and exercise icons.
- `renders/` contains generated review PNGs and contact sheets. Regenerate these after editing SVG masters.
- `app/WorkoutDB/Assets.xcassets/AppIcon.appiconset/` contains the generated iOS app icon PNGs.
- `DSExerciseIconView` in the DesignSystem package mirrors the accepted SVG grammar for in-app SwiftUI use.

Rules:

- Keep exercise icons on a 24x24 viewBox with rounded caps/joins.
- Use existing design colors only: ink `#f5f1e8`, accent `#d28766`, accent ink `#e8a896`, warn `#d6a23a`, success `#6bb896`.
- Review every icon at 48, 32, 24, and 20 px before accepting it.
- Do not add per-exercise icons until the category icons still read clearly at 24 px.
