# Review Checklists

**Pick ONE checklist based on your baseline.** Don't combine them all - that leads to unfocused reviews. Understand what you're reviewing against, then use the appropriate checklist.

## Choosing Your Checklist

| If reviewing against... | Use... |
|------------------------|--------|
| A plan | Plan Review Checklist |
| A PR description | PR Review Checklist |
| Architectural standards | Architecture Review Checklist |
| Requirements/acceptance criteria | Requirements Review Checklist |
| Security requirements | Use the `security-skill` instead |
| General quality (no baseline) | Quality Review Checklist |

---

## Plan Review Checklist

Use when code was implemented from a plan.

- [ ] Every plan step has corresponding code
- [ ] Verification steps were run and passed
- [ ] Deviations from plan are documented (not hidden)
- [ ] Interfaces match what plan specified
- [ ] No scope creep beyond plan
- [ ] If plan specified risk-first ordering, was it followed?

**Note:** You can flag plan defects separately. "Code matches the plan, but the plan missed X."

---

## PR Review Checklist

Use when reviewing a pull request against its description.

- [ ] PR description accurately describes changes
- [ ] Code does what description claims
- [ ] No unmentioned functionality
- [ ] Tests cover claimed behavior (not just implementation)
- [ ] Breaking changes are noted
- [ ] Backward compatibility considered (existing clients, data contracts)
- [ ] Migration/rollback approach documented if needed

---

## Architecture Review Checklist

Use when reviewing for architectural conformance.

- [ ] Follows existing patterns in codebase
- [ ] Stays within its layer/module boundaries
- [ ] Dependencies point in correct direction (no circular deps)
- [ ] Consistent naming with rest of codebase
- [ ] No new patterns without justification
- [ ] Error handling follows established propagation patterns
- [ ] Logging/observability follows conventions
- [ ] Config access follows established patterns
- [ ] Public interfaces are documented (TSDoc/JSDoc/docstrings)

---

## Requirements Review Checklist

Use when reviewing against requirements or acceptance criteria.

- [ ] All acceptance criteria are met
- [ ] Edge cases from requirements are handled
- [ ] Error states from requirements are implemented
- [ ] Performance requirements met (if specified)
- [ ] Tests verify each requirement
- [ ] No gold-plating (features beyond requirements)

---

## Quality Review Checklist

Use when there's no specific baseline - just assessing code quality.

- [ ] Code is readable in one pass without explanation
- [ ] Functions do one thing
- [ ] Names are clear, consistent, and intention-revealing
- [ ] Error handling is present and meaningful
- [ ] Edge cases are handled (nulls, empty, boundaries)
- [ ] Tests exist and verify behavior (not implementation)
- [ ] Tests are feasible without heavy mocking
- [ ] No dead code or commented-out blocks
- [ ] TODOs are tracked or justified (not abandoned)

---

## Severity Guide

When giving feedback, prefix with severity:

| Prefix | Meaning | Blocks Merge? |
|--------|---------|---------------|
| **Blocker** | Bug, security issue, broken functionality | Yes |
| **Should fix** | Missing error handling, unclear code | Ideally |
| **Nit** | Style, naming preferences | No |
| **Question** | Seeking understanding | No |
