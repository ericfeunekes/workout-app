---
name: stacked-prs
description: Use when creating, reviewing, or merging a chain of dependent PRs. Covers Git Town setup, naming conventions, review order, and PR descriptions.
---
# Stacked PRs

GitHub-native workflow for splitting large features into reviewable, mergeable slices. Uses Git Town to manage the branch mechanics.

## When to Use This Skill

- Creating a stack of related PRs for a feature
- Reviewing stacked PRs (bottom-up order)
- Syncing a stack after changes
- Merging stacked PRs in order

## Setup (One-Time)

### Install Git Town

```bash
# macOS
brew install git-town

# Configure for this repo
git config --local git-town.main-branch main
git config --local git-town.sync-feature-strategy rebase
git config --local git-town.forge-type github
```

### Repo Settings (GitHub)

1. Enable "Automatically delete head branches"
2. Set merge strategy to "Squash and merge" only

## Core Conventions

### Naming

**Branch:** `stack/<keyword>/<order>-<slug>`
```
stack/billing/01-refactor-ledger
stack/billing/02-add-proration
stack/billing/03-docs-tests
```

**PR Title:** `[<keyword> <number>] <short title>`
```
[billing 1] Refactor ledger calculation
[billing 2] Add proration rules
[billing 3] Tests + docs + cleanup
```

### Issue Linkage

- `Refs #123` for PRs 1..N-1
- `Closes #123` only on the final PR

### The Two Guardrails

1. **Each PR targets its parent branch in the stack** (first PR targets `main` or an agreed base)
2. **Every PR title starts with `[keyword <number>]`**

## Creating a Stack with Git Town

```bash
# Start from main
git checkout main
git pull

# Create first branch in stack
git town hack stack/billing/01-refactor-ledger
# ... make changes, commit ...

# Create second branch (stacked on first)
git town append stack/billing/02-add-proration
# ... make changes, commit ...

# Create third branch (stacked on second)
git town append stack/billing/03-docs-tests
# ... make changes, commit ...

# Create PRs for all branches in stack (opens compare pages)
git town propose
```

## Creating PRs (Git Town + GitHub CLI)

`git town propose` opens compare pages; it does not create PRs. Use the GitHub UI or the GitHub CLI to finalize.

Recommended flow (fast, consistent):
1. Run `git town propose --stack` to open compare pages.
2. Create PRs in the browser, or use `gh pr create` for each branch.
3. After PR1 exists, update PR2+ descriptions to reference the prior PR.

Example CLI flow:

```bash
# PR1
gh pr create --base <parent-branch> --head <branch> --title "[miniapp 1] Plan docs" --body-file <body.md>

# PR2 (after PR1 exists)
gh pr create --base <pr1-branch> --head <branch> --title "[miniapp 2] Mini-app scaffolding" --body-file <body.md>
gh pr edit <PR_NUMBER> --body "## Stack\n[miniapp 2] — depends on #<PR1>\n\n<rest of body>"
```

## Syncing a Stack

When main changes or you need to update the stack:

```bash
# Syncs all branches in your stack with main and each other
git town sync
```

This rebases each branch onto its parent automatically.

## Merging a Stack

```bash
# Ship the bottom PR (must target main)
git town ship stack/billing/01-refactor-ledger

# After PR1 merges, sync to update bases
git town sync

# Ship next PR
git town ship stack/billing/02-add-proration

# Continue until stack is merged
```

Or merge via GitHub UI - GitHub auto-retargets when branches are deleted.

## PR Description Template

Every PR needs to describe what it does, even with Git Town handling branches:

```markdown
## Stack
[billing 2] — depends on #123

## Issue
Refs #456

## Summary
Add proration calculation for mid-cycle billing changes.

## Changes
- Add `calculateProration()` to billing service
- Handle partial month scenarios
- Add proration tests

## Testing
- Unit tests for proration edge cases
- Manual test with sample invoices

## Notes for reviewers
- Review [billing 1] first if you haven't
- Key logic in `src/billing/proration.ts`
```

## Reviewers

Use CODEOWNERS or repo-specific reviewer lists. Avoid hardcoding names in shared skills.

## Review Order

Reviewers should:
1. Start at `[keyword 1]` (the bottom of the stack)
2. Work up through the stack
3. Leave comments on the PR where the change should happen

## Quick Commands

| Task | Command |
|------|---------|
| Start new stack | `git town hack stack/<keyword>/01-<slug>` |
| Add to stack | `git town append stack/<keyword>/02-<slug>` |
| Create PRs | `git town propose` |
| Sync all | `git town sync` |
| Merge bottom PR | `git town ship <branch>` |
| See stack status | `git town status` |

## References

- `references/stacked-prs.md` - Complete workflow without Git Town (manual approach)
- [Git Town documentation](https://www.git-town.com/)

## Related Skills

- review
