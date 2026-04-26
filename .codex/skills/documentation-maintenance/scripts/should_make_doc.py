"""Score whether a new document or folder is warranted."""

from __future__ import annotations

QUESTIONS = [
    ("How often will this be needed? (0 never, 1 occasional, 2 frequent)", 0),
    ("What is the blast radius if it is wrong? (0 small, 1 team, 2 multi-team/prod)", 0),
    ("Minutes saved per reader? (0 <2, 1 2-10, 2 >10)", 0),
    ("Stability of knowledge? (0 churny, 1 moderate, 2 stable)", 0),
    ("Audience breadth? (0 one maintainer, 1 one team, 2 multi-team)", 0),
    ("External dependency or contract? (0 none, 1 internal, 2 external/public)", 0),
]


def main() -> int:
    score = 0
    for prompt, _ in QUESTIONS:
        try:
            score += int(input(prompt + " "))
        except Exception:
            pass
    print(f"Score: {score}")
    if score < 6:
        print("→ Keep the knowledge near code or link to the source of truth.")
    elif score < 9:
        print("→ Create docs/<topic>.md using templates/page.md.")
    else:
        print("→ Create docs/<topic>/ with index.md and focused subpages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
