# Phase 4 — Output + Feedback Loop (PDF + scan-friendly logging + manual adjustments)

## Objective
Make the loop usable end-to-end with printable plans and easy re-entry of results.

## 4.1 Printable PDFs (plan + workout sheets)
Generate printable PDF outputs for:
- 28-day plan overview
- per-workout logging sheets

Design requirements:
- fixed layout with clear rows/boxes
- scan-friendly spacing and alignment
- stable field locations for reliable extraction

## 4.2 Scan-friendly input format
Key idea:
- make it easy for an athlete to write results in a constrained way
- re-import with high confidence (even if parsed manually at first)

Examples:
- pre-printed set rows with fixed columns
- checkboxes for simple options
- consistent date + template identifiers

Extraction approach:
- Use a fixed PDF layout and prompt the Gemini CLI to extract specific fields
- Treat Gemini output as structured draft; confirm before import

## 4.3 Manual-first weekly adjustments
After logs are imported:
- surface changes (volume, load, adherence)
- provide helper summaries
- keep final decisions manual

## 4.4 Enrichment (optional add-ons)
Keep these optional and additive:
- stimulus check-ins
- equipment bootstrapping
- substitutions

Acceptance criteria:
- PDF output is stable and readable
- Logged sheets can be re-imported with low ambiguity
- Manual weekly edits are supported without DB edits
