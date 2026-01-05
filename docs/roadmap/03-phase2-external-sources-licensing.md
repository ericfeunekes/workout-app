# Phase 2 — External Sources (license-safe ingestion, optional)

## Objective
Expand your library with external examples *without legal/ToS headaches*.
This is optional in MVP; use only when licensing is clear.

## Strong warning: CrossFit.com scraping
CrossFit’s Terms & Conditions explicitly prohibit scraping/data mining and also prohibit incorporating site content into a database/compilation. Do not build an automated scraper against CrossFit.com unless you have explicit written permission.
- Reference: https://www.crossfit.com/terms-and-conditions

## MVP-safe approach for CrossFit.com
- Store only:
  - workout date
  - URL
  - *your* notes/results
- If you want the workout text in your DB, prefer:
  - sources with explicit permission/license
  - or manual entry that you author yourself (rephrased) rather than copying site content verbatim

## External ingestion architecture
Build “source adapters” with a strict interface:

`Adapter` must output:
- `source_metadata`
- `raw_workout` entries

Adapters to implement first:
1) `local_files` (already done in Phase 1)
2) `manual_links` (you paste a URL + optional notes)
3) `permitted_sources` (only if license/ToS allows automated retrieval)

## Data model support
- Every imported workout must have:
  - `source_id`
  - `original_url` (if applicable)
  - `license_note`
  - `imported_at`

## Acceptance criteria
- You can add a link-only workout in < 10 seconds:
  - `add-link --date 2026-01-04 --url ... --title ...`
- You can later convert link-only entries into full templates via manual entry or from a permitted source.
