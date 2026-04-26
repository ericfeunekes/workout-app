# Stacked PRs (Manual Approach)

This reference describes the manual workflow for stacked PRs without Git Town. Use this as a fallback if Git Town is not available.

## Overview

Stacked PRs split large features into small, reviewable slices that merge sequentially. Each PR builds on the previous one, maintaining a clear dependency chain.

## Branch Naming

```
stack/<keyword>/<order>-<slug>
```

Examples:
- `stack/billing/01-refactor-ledger`
- `stack/billing/02-add-proration`
- `stack/billing/03-docs-tests`

## PR Title Format

```
[<keyword> i/N] <short title>
```

Examples:
- `[billing 1/3] Refactor ledger calculation`
- `[billing 2/3] Add proration rules`
- `[billing 3/3] Tests + docs + cleanup`

## Creating the Stack (Manual)

```bash
# Start from main
git checkout main
git pull

# Create first branch
git checkout -b stack/billing/01-refactor-ledger
# ... make changes ...
git add . && git commit -m "Refactor ledger calculation"
git push -u origin stack/billing/01-refactor-ledger

# Create second branch from first
git checkout -b stack/billing/02-add-proration
# ... make changes ...
git add . && git commit -m "Add proration rules"
git push -u origin stack/billing/02-add-proration

# Create third branch from second
git checkout -b stack/billing/03-docs-tests
# ... make changes ...
git add . && git commit -m "Add tests and docs"
git push -u origin stack/billing/03-docs-tests
```

## Creating PRs

1. Create PR for branch 01 → targets `main`
2. Create PR for branch 02 → targets `stack/.../01-*`
3. Create PR for branch 03 → targets `stack/.../02-*`

## Syncing After Changes

When you need to update a branch in the stack:

```bash
# Update the branch you changed
git checkout stack/billing/01-refactor-ledger
git add . && git commit -m "Address review feedback"
git push

# Rebase downstream branches
git checkout stack/billing/02-add-proration
git rebase stack/billing/01-refactor-ledger
git push --force-with-lease

git checkout stack/billing/03-docs-tests
git rebase stack/billing/02-add-proration
git push --force-with-lease
```

## Merge Order

1. Merge `[keyword 1/N]` first (targets main)
2. GitHub auto-retargets `[keyword 2/N]` to main
3. Merge `[keyword 2/N]`
4. Continue until all PRs are merged

**Critical:** Always merge bottom-up. Never merge a PR that doesn't target main.

## Issue Linkage

- PRs 1 through N-1: `Refs #123`
- Final PR (N/N): `Closes #123`

This ensures the issue only closes when the full feature is merged.

## Review Guidelines

Reviewers should:
1. Start with `[keyword 1/N]`
2. Work up through the stack
3. Leave comments on the PR where the code lives
4. Approve in order (1/N before 2/N)

## Advantages

- Small, focused PRs are easier to review
- Faster review turnaround
- Issues found early in the stack
- Clear progression of changes
- No massive PR at the end

## Common Issues

### Merge Conflicts

If main has diverged:
```bash
git checkout stack/billing/01-refactor-ledger
git rebase origin/main
git push --force-with-lease

# Then rebase each downstream branch
```

### Wrong Base Branch

If a PR accidentally targets the wrong branch:
1. Edit the PR on GitHub
2. Change the base branch
3. The diff will update automatically

### Abandoned Stack

If you need to abandon a stack:
1. Close all PRs
2. Delete all `stack/<keyword>/*` branches
3. The feature can be re-implemented fresh
