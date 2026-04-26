# When to Plan

A decision framework for determining whether to plan or just execute.

## The Core Question

Before starting any task, ask: **"Can I write the exact test case right now without looking anything up?"**

- **Yes** → Just do it
- **No** → Plan first

## Decision Matrix

| Uncertainty | Scope | Action | Reason |
|-------------|-------|--------|--------|
| Low | Low | Just Do | Quick win, no risk |
| Low | High | Plan | Track progress, don't lose thread |
| High | Low | Plan | Prevent breakage, validate assumptions |
| High | High | Plan | Essential for success |

## Indicators: Just Do It

Skip planning when ALL of these are true:

- [ ] Task has fewer than 3 obvious steps
- [ ] You know exactly which files to change
- [ ] You know the exact change to make
- [ ] No external dependencies or approvals needed
- [ ] Failure is easily reversible
- [ ] No one else needs to understand the approach

**Examples:**
- Fix a typo in documentation
- Rename a variable for clarity
- Add a simple validation check
- Update a dependency version
- Add a log statement for debugging
- Remove dead code

## Indicators: Plan First

Plan when ANY of these are true:

- [ ] Don't know where the state lives
- [ ] Unknown side effects
- [ ] Multiple components or files affected
- [ ] External dependencies (APIs, services, people)
- [ ] Someone else will implement or review
- [ ] Need to maintain behavior while changing structure
- [ ] First time doing this type of work in this codebase
- [ ] Failure would be hard to detect or reverse

**Examples:**
- Add a new feature
- Change authentication flow
- Refactor a module
- Integrate with external service
- Migrate data schema
- Cross-team or cross-repo changes

## The "Twin" Heuristic

Ask: **"Have I done something exactly like this before in this codebase?"**

- **Yes, recently** → Probably just do it
- **Yes, but it was different** → Light plan (steps only)
- **No** → Full plan with discovery

## The "Handoff" Heuristic

Ask: **"If I stepped away, could someone else continue?"**

- **Yes** → Maybe no plan needed (or it's already implicit)
- **No** → Plan needed (makes the work transferable)

## Uncertainty Signals

**Low uncertainty:**
- You've done this exact thing before
- The pattern is established in the codebase
- There's documentation or examples to follow
- The scope is clearly bounded

**High uncertainty:**
- First time with this technology/pattern
- Unclear requirements
- Multiple valid approaches
- External dependencies you haven't used
- Conflicting information

## Scope Signals

**Low scope:**
- Single file or function
- One component
- No state changes
- Local effects only

**High scope:**
- Multiple files or components
- Database or state changes
- Cross-cutting concerns
- User-facing behavior changes
- Multiple people or teams affected

## Edge Cases

### "Quick Fix" That Keeps Growing

Started as "just fix this one thing" but scope keeps expanding.

**Signal:** You've been "just doing it" for 30+ minutes

**Action:** Stop. Write a quick plan of what's left. Reassess.

### Discovery Task

You don't know enough to plan OR execute.

**Signal:** Every question leads to more questions

**Action:** Timebox exploration. Output is a plan, not code.

### Urgent Production Issue

No time to plan formally.

**Signal:** System is down, users affected

**Action:** Fix first, plan the proper solution after. Document what you did.

### Pair/Mob Programming

Planning happens verbally in real-time.

**Signal:** Active discussion with collaborators

**Action:** Lightweight written plan still helps (shared checklist), but can be minimal.

### Plan vs Explore (Mid-Planning Pivot)

Started planning but realized you don't understand enough.

**Signal:** Can't write verification for a step. Don't know where state lives. Multiple "I think..." statements.

**Action:** Stop planning. Switch to a Spike. The output of a Spike is a plan (or a decision), not code. Return to planning after the Spike completes.

## Quick Reference

```
Task arrives
    ↓
Can write test case now?
    → Yes: Just do it
    → No: ↓

Know where state lives?
    → No: Plan (need discovery)
    → Yes: ↓

< 3 obvious steps?
    → Yes: Just do it
    → No: ↓

External dependencies?
    → Yes: Plan (need coordination)
    → No: ↓

Easily reversible?
    → Yes: Maybe just do it
    → No: Plan (need safety)
```

## The 25% Rule (Heuristic)

This is a rough heuristic, not a hard rule: approximately 25% of tasks are straightforward enough to skip planning.

If you're skipping planning more than 25% of the time, you might be:
- Underestimating complexity
- Missing opportunities for better approaches
- Creating tech debt

If you're planning more than 75% of the time, you might be:
- Over-engineering simple tasks
- Using planning as procrastination
- Not trusting your expertise

Calibrate based on your context—unfamiliar codebases need more planning, well-known ones less.
