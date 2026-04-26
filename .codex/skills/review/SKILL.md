---
name: review
description: Use when reviewing code - whether against a PR, a plan, architectural standards, or requirements. This skill adapts the review approach based on what you're reviewing against.
---
# Code Review

The discipline of evaluating code changes. The approach adapts based on the baseline: are you reviewing against a plan, a PR description, architectural standards, or general quality?

## When to Use This Skill

- Reviewing a PR against a plan or requirements
- Auditing code for correctness, safety, or maintainability
- Providing structured, severity-ranked feedback

## Before You Review

### Understand the Baseline

What are you reviewing against? This shapes everything:

| Baseline | Primary Question | Focus |
|----------|------------------|-------|
| **A Plan** | Does the code match the plan? | Completeness, deviations, verification steps |
| **PR Description** | Does the code do what it claims? | Scope, correctness, side effects |
| **Architecture** | Does the code fit the system? | Patterns, boundaries, consistency |
| **Requirements** | Does the code meet the need? | Functionality, acceptance criteria |
| **General Quality** | Is this good code? | Readability, maintainability, bugs |

**Pick one baseline.** Don't try to review against everything at once - that leads to unfocused, exhausting reviews. Clarify the baseline before starting.

**Security trigger:** If you encounter auth logic, raw SQL, crypto, or sensitive data handling - **stop reviewing that portion**. Invoke the `security-skill` before continuing. Don't flag and continue; actually switch context.

### When You're Asked to Review

When a colleague (human or agent) asks you to review:

1. **Clarify the baseline.** "What should I review this against - a plan, PR description, or just general quality?"

2. **Form your own opinion first.** Read the code. Come to your own conclusions before responding. Don't just echo what they expect.

3. **Challenge, don't just validate.** Push toward the right solution:
   - Is this the simplest approach?
   - Does it fit the architecture?
   - What could go wrong?

4. **Be direct.** If something is wrong, say so. Don't soften blockers into nits.

### Gather Context First

Don't review blind. Before commenting:

1. **Read the baseline** - plan, PR description, ticket, or requirements
2. **Understand the goal** - what problem is being solved?
3. **Explore related code** - how does similar work look in this codebase?
4. **Check tests** - do they verify behavior (not implementation)?

If the baseline is unclear, ask one or two questions before proceeding.

## Review Mechanics

### Getting the Diff

```bash
# PR diff
gh pr diff <number>

# Local changes
git diff main...HEAD

# Specific files
git diff main...HEAD -- path/to/file.py
```

### Handling Large Reviews

If the review is too large (>500 LOC or >10 files):

1. **Request breakdown.** Ask the author to split into smaller PRs.
2. **Or focus.** Review the riskiest/most critical files first, flag the rest as "not reviewed in depth."
3. **Don't rubber-stamp.** Large reviews that can't be split still need real review - just be explicit about what you did and didn't cover.

### Pre-flight Check

Before deep review, verify basics pass:

```bash
# Check CI status
gh pr checks <number>

# Run tests locally if needed
git checkout <branch> && npm test  # or `uv run pytest`, etc.
```

Don't review code that fails the build or lint checks - that's wasted effort.

### Navigating the Code

1. Start with the entry point (main function, API route, test file)
2. Skim tests early for intent
3. Follow the data flow through the code
4. Return to tests for deep read after understanding the code

## Review Process

Use the multi-pass approach, then apply the baseline-specific checklist from `references/review-checklists.md`.

### 1. First Pass: Does It Work?

Start with correctness against the baseline:

- [ ] Does the code do what it claims?
- [ ] Are all requirements/plan steps addressed?
- [ ] Do the tests verify behavior (not just implementation details)?
- [ ] Are there obvious bugs or logic errors?

### 2. Second Pass: Is It Safe?

Check for risks:

- [ ] Error handling: what happens when things fail?
- [ ] Edge cases: nulls, empty collections, boundaries
- [ ] Performance: N+1 queries, unbounded loops, memory
- [ ] Compatibility: does it break existing clients/contracts?

**Security check:** If you see auth, SQL, crypto, or PII - stop and invoke `security-skill` for that portion.

### 3. Third Pass: Is It Maintainable?

Consider the future reader:

- [ ] Is the code understandable without explanation?
- [ ] Does it follow existing patterns in the codebase?
- [ ] Is complexity justified, or could it be simpler?
- [ ] Are names clear and consistent?

### 4. Final Pass: Scope Check

Guard against scope creep and unrelated changes:

- [ ] Is everything in this change related to the stated goal?
- [ ] Are there drive-by refactors that should be separate?
- [ ] Does it change more than necessary?

## Giving Feedback

### Be Specific and Actionable

**Bad:** "This is confusing"

**Good:** "The `processData` function does three things (parse, validate, transform). Consider splitting into separate functions for clarity."

### Distinguish Severity

Use clear prefixes:

- **Blocker:** Must fix before merge. Bugs, security issues, broken functionality.
- **Should fix:** Important but not blocking. Missing error handling, unclear code.
- **Nit:** Minor preference. Naming, formatting, style.
- **Question:** Not a request, just asking for understanding.

### Praise Good Work

Call out what's done well. Reinforces patterns, builds trust.

### Assume Good Intent

The author made choices for reasons. Ask why before suggesting changes:

"I see you used pattern X here. Was there a reason not to use Y, which we use elsewhere?"

## Baseline-Specific Guidance

After the multi-pass review, apply the appropriate checklist from `references/review-checklists.md`.

### Plan Reviews

When reviewing against a plan, you may use the planning skill's heuristics (risk-first, verification-driven) to evaluate the code - but stay focused on whether the code matches the plan.

**You can flag plan defects.** If the plan itself was flawed (missing steps, wrong assumptions), note this separately: "The code matches the plan, but the plan missed X."

### PR Reviews

If the PR description is vague, ask for clarity before reviewing deeply. A good PR description is part of the contract.

### Architecture Reviews

Reference specific examples from the codebase: "We handle this pattern in `src/auth/` like X."

## Common Review Mistakes

| Mistake | Sign | Fix |
|---------|------|-----|
| Reviewing without context | Comments miss the point | Read baseline first |
| Nitpicking on style | 20 comments about formatting | Focus on substance first |
| Missing the forest for trees | Detailed line comments, missed design flaw | Start with high-level pass |
| Rubber-stamping | "LGTM" with no substance | Actually read the code |
| Blocking on preferences | "I would have done it differently" | Ask if there's a reason |
| Scope creep requests | "While you're here, also..." | Separate concerns |
| Re-litigating the plan | Arguing about plan decisions | Review code adherence, flag plan issues separately |

## Multi-Agent Review

When collaborating with other agents:

- **Tell them to use their review skill.** "Use your review skill to review this code against the plan."
- **Ask for independent conclusions.** "Form your own opinion before responding."
- **Iterate.** Challenge their findings, ask follow-ups, reach consensus.
- **Maintain sessions.** Use session IDs for ongoing collaboration.

See the planning skill's multi-agent section for detailed collaboration patterns.

## Resources

### references/

- `review-checklists.md` - Quick checklists for different review types (plan, PR, architecture, requirements, quality)

## Related Skills

- security
- stacked-prs
- release-engineering
