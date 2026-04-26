---
name: planning
description: Use when approaching complex tasks that benefit from structured planning before implementation. This includes multi-step features, architectural changes, refactors, or any work where the path forward is uncertain. Not needed for straightforward tasks under 3 obvious steps.
---
# Planning

The discipline of deciding what to do before doing it. This skill covers when to plan, how to plan effectively, and common pitfalls to avoid.

## When to Plan vs Just Do

**Just Do (no plan needed)** - ALL of these must be true:
- Task has < 3 obvious steps
- Can write the exact test case without looking anything up
- Low uncertainty AND low scope
- Failure is easily reversible
- Examples: rename field, add validation, fix typo, update types

**Plan First** - ANY of these triggers planning:
- Don't know where state lives
- Unknown side effects or unclear ownership
- High uncertainty OR high scope
- External dependencies or approvals needed
- Examples: add new feature, change architecture, refactor module, cross-system changes

**Can't write verification for a step?** Stop planning. Switch to a Spike first.

**Decision Formula:** `Uncertainty + Scope > Threshold`

| Uncertainty | Scope | Action |
|-------------|-------|--------|
| Low | Low | Just Do |
| Low | High | Plan (track progress) |
| High | Low | Plan (prevent breakage) |
| High | High | Plan (essential) |

## Plan Scope

Choose based on complexity:

| Scope | When | Template |
|-------|------|----------|
| **Light** | 3-4 steps, low risk | Inline checklist, no file |
| **Standard** | 5-7 steps, moderate complexity | `scratch/plan_<slug>.md` |
| **Multi-phase** | 8+ steps, milestones needed | `scratch/plan_<slug>/` directory |

## Planning Process

**Timebox:** Cap planning at 15-30 minutes. If still unclear, run a Spike instead.

1. **Explore** - Map the territory (codebase, state, data flow)
2. **Surface patterns** - How is similar work done here?
3. **Confirm understanding** - Verify before drafting
4. **Draft plan** - Structure per templates below
5. **Pre-mortem** - "If this fails, where?" Put risks BEFORE steps.
6. **Collaborate** - Get at least one other agent to review (see Multi-Agent Planning)
7. **Iterate** - Revise based on feedback until consensus
8. **Execute** - Update plan as you go

**Step 6 is not optional.** Every plan must be reviewed by another agent before execution. This catches blind spots and produces better plans.

**Stop and re-plan trigger:** If a step invalidates assumptions or the plan changes >20%, pause and revise the plan before continuing.

## Core Planning Principles

### 1. Verification-Driven Steps

Every step must answer: "How do I know this is done correctly?"

Verification can be: tests, staging checks, metrics, logs, or observable behavior—not just print statements.

**Bad:** "Add caching to the API client"

**Good:** "Add cache decorator to `ApiClient.fetchData`. **Verify:** Second call in test shows cache hit in metrics."

### 2. Risk-First Ordering

Do the riskiest/most uncertain thing first. If step 1 fails, the plan is invalid—save time.

- Don't build UI for an API that might not work
- Validate external dependencies before building on them
- Prototype the uncertain part before scaffolding around it

### 3. Vertical Slices Over Layers

Plan end-to-end threads, not horizontal layers. Each step should deliver a tiny working slice.

**Bad (layer-by-layer):**
1. Create all models
2. Create all views
3. Create all controllers
4. Wire everything together

**Good (vertical slice):**
1. Single endpoint returns hardcoded data
2. Endpoint reads from database
3. Add validation
4. Add error handling

### 4. Living Plans

Plans are state, not documentation. Update when reality diverges.

- Stop and rewrite rather than hack code to fit a broken plan
- Check off steps as completed
- Add notes when discoveries change the approach
- Flag deviations before implementing them

### 5. Interface-First

Lock contracts before implementation.

- Function signatures, API shapes, schemas first
- Enables meaningful review of the plan
- Prevents rework when boundaries shift

### 6. Bounded Scope

Make explicit:
- What are we doing? (goals)
- What are we NOT doing? (non-goals)
- What external things could block us? (dependencies)
- Who owns/approves? (stakeholders, if cross-team)

## Plan Structure

For most implementation work:

```markdown
# Plan: [Feature Name]

## Goal
- Observable outcome + acceptance criteria

## Constraints
- Non-goals, boundaries, dependencies, approvals needed

## Discovery Notes
- Key findings from exploration (paths, patterns, constraints)

## Interface / Contract
- Public signatures, API shapes, or schema changes

## Risks / Unknowns
- [risk] → [how to validate/mitigate]

## Steps (5-7 max)
1. [Verb + object]. **Verify:** [how to confirm]
2. [Verb + object]. **Verify:** [how to confirm]
...

## Handoff (if for another agent)
- Entry points: [files to open first]
- Next action: [what to do after plan completion]
```

For complex multi-phase work, see `references/plan-templates.md`.

## Plan Quality Gate

Before executing, verify:
- [ ] Goal is clear and testable
- [ ] Risks identified and ordered first
- [ ] Dependencies and blockers listed
- [ ] Each step has specific verification
- [ ] No step larger than one vertical slice
- [ ] Scope is bounded (non-goals stated)
- [ ] Rollback approach if risky
- [ ] **Plan reviewed by at least one other agent** (mandatory)

## Task-Specific Planning

### Bug Fix
1. Reproduce (write failing test)
2. Investigate (find exact line/condition)
3. Fix (minimal change)
4. Verify (run test + regression check)

### New Feature
1. Discover twin functionality (how is similar work done?)
2. Define contract (interface/schema)
3. Implement minimal slice (end-to-end)
4. Extend behavior
5. Add tests
6. Integration check

### Refactor
1. Define invariants (what must NOT change)
2. Baseline (run all tests, capture metrics if relevant)
3. Smallest atomic move
4. Verify (tests pass, invariants hold)
5. Repeat

### Exploratory / Spike
1. Timebox (set hard limit)
2. Hypothesis testing
3. Document findings
4. Output is a plan or decision, not code

## Anti-Patterns to Avoid

See `references/anti-patterns.md` for detailed examples. Key ones:

| Anti-Pattern | Sign | Fix |
|--------------|------|-----|
| Vague Steps | "Make it work", "Hook up DB" | Verb + object, falsifiable |
| Happy Path Tunnel | Error handling is Step 6 | Integrate error handling per step |
| Pseudo-code Plans | 50 lines of syntax | Describe behavior, not code |
| Refactor Bombs | "Refactor X to support Y" | Isolate refactors as prerequisites |
| Invisible Middle | Detailed setup, hand-waved core | Equal detail throughout |
| Skipping Discovery | Planning without reading code | Explore before planning |
| Over-decomposition | 20+ tiny steps | 5-7 steps, split if more needed |

## Multi-Agent Planning

**Collaboration is mandatory.** Every plan must be reviewed by at least one other agent before execution. This is not optional—it's how we catch blind spots, challenge assumptions, and reach better solutions.

### Who Plans

- **If you are Claude:** Draft the plan. Claude excels at planning and architectural thinking.
- **If you are Codex or Gemini with Claude CLI access:** Ask Claude to draft the plan via `claude` CLI.
- **If no Claude access:** Draft the plan yourself using this skill.

### Understanding the Outcome First

Before drafting a plan, deeply understand what the user is trying to achieve. This is iterative dialogue, not a questionnaire.

- **Ask one or two questions at a time.** Follow up based on their answers. Ten rounds of focused questions beats one list of thirty.
- **Explore the codebase.** Read the relevant code. Understand how similar things are done. Surface what you find to the user.
- **Confirm understanding.** Reflect back what you think the goal is. Let them correct you. Repeat until aligned.

The outcome drives everything. A complex solution is fine when it's truly the best path to the outcome. Simplicity is the default, not a religion.

### Collaborative Review Process

After drafting, don't just ask colleagues for feedback—engage in real collaboration.

**The goal is to challenge each other.** Push toward the right solution, not just any solution:

- **Simplicity by default.** Question whether each step is truly necessary. Prune more than you add when possible.
- **Complexity when warranted.** Don't fear a complex solution if that's what the outcome requires. The test is whether it's the minimal complexity needed.
- **Architectural fit.** Work with the existing architecture, not against it. Understand how similar things are done in this codebase.
- **Reduce future debt.** Consider maintainability and robustness, but stay within the plan's scope.
- **Find the minimal path.** What's the smallest change that achieves the goal?

**Single source of truth:** The canonical plan lives in `scratch/plan_*.md`. All edits happen there—no parallel versions.

**Timebox reviews:** Cap each review round at 10-20 minutes. Aim for "good enough," not perfect.

1. **Request independent review.** Ask each available agent to read the codebase and form their own conclusions. Tell them to use their planning skill:
   ```
   "Use your planning skill. Read the code in [paths].
   Review this plan critically. What's missing? What assumptions are wrong?
   Come to your own conclusion before responding."
   ```

2. **Maintain session continuity.** Use `--resume <session-id>` to continue conversations. Context builds over turns.

3. **Iterate together.** When feedback arrives:
   - Don't just implement suggestions blindly
   - Ask clarifying questions
   - Challenge their assumptions
   - Propose alternatives
   - Work back and forth until consensus

4. **Reach agreement.** The plan is ready when all available agents agree it's complete.

**Conflict resolution:** If disagreement persists:
- Document the tradeoffs and dissenting views in the plan
- The agent owning the task (running the plan) makes the final call
- For stylistic conflicts, defer to existing repo conventions

**Without Claude:** If Claude CLI isn't available, still require at least one independent review (Codex ↔ Gemini cross-review).

**Shared skills:** Other agents have access to the same skills. Tell them to use relevant skills explicitly (e.g., "Use your planning skill to review this plan").

**Security:** Never share secrets, credentials, or PII in cross-agent prompts.

### CLI Patterns

```bash
# Claude: draft plan
claude -p "Draft a plan for [task]. Write to scratch/plan_<slug>.md"

# Codex: independent review (maintain session)
codex exec -o /tmp/review.md -C <repo> "Review the plan in scratch/plan_*.md.
Read the relevant code. What's missing or wrong?"
# Continue conversation:
codex exec resume <session-id> "I've updated based on your feedback. Check again."

# Gemini: critical analysis
gemini -m gemini-3-pro-preview --resume <session-id> "Review critically.
What edge cases did we miss?"
```

### Agent Strengths

| Agent | Best For |
|-------|----------|
| **Claude** | Planning, architecture, documentation, synthesis |
| **Codex** | Deep code analysis, implementation details, patterns |
| **Gemini Pro** | Critical review, edge cases, correctness |
| **Gemini Flash** | Quick checks, broad pattern matching |

### Collaboration is Required

**Every plan gets reviewed.** No exceptions. Even "obvious" plans benefit from a second perspective.

| Plan Type | Minimum Review |
|-----------|----------------|
| Light plan | One quick review from any available agent |
| Standard plan | Full review with iteration until consensus |
| Multi-phase/architectural | Multiple agents, each reviewing independently |

**If no other agents are available:** Document this explicitly in the plan and flag it to the user. The plan should still be reviewed by the user before execution.

## Resources

### references/

- `plan-templates.md` - Templates for different plan types
- `anti-patterns.md` - Detailed anti-pattern examples with fixes
- `when-to-plan.md` - Decision framework with examples
