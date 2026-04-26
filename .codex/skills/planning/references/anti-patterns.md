# Planning Anti-Patterns

Common planning mistakes and how to fix them.

## 1. Vague Steps

**Sign:** Steps like "Make it work", "Hook up the database", "Add the feature"

**Why it's bad:** Not falsifiable. Can't tell when it's done. Leads to scope creep.

**Bad:**
```
1. Create the CLI
2. Add the parser
3. Make it work
```

**Good:**
```
1. Add CLI entry with --input and --output args. Verify: --help shows both args
2. Parse input Markdown via CommonMark library. Verify: parsed AST logged
3. Apply semantic HTML template to AST. Verify: output.html renders correctly
```

**Fix:** Every step is verb + object. Every step has explicit verification.

---

## 2. Happy Path Tunnel

**Sign:** Error handling, validation, or edge cases are the last step ("Step 6: Add error handling")

**Why it's bad:** Error handling shapes architecture. Function signatures change. Retrofitting is expensive.

**Bad:**
```
1. Create endpoint
2. Add database query
3. Return response
4. Add caching
5. Add logging
6. Add error handling
```

**Good:**
```
1. Create endpoint with error wrapper, return 500 on any failure. Verify: throws → 500
2. Add database query with timeout, wrap errors. Verify: timeout → specific error
3. Add caching with fallback to DB on cache miss. Verify: cache miss → DB hit logged
```

**Fix:** Integrate error handling into each step. Ask "what fails here?" at every step.

---

## 3. Pseudo-code Plans

**Sign:** Plan contains 50+ lines of code, variable names, implementation details

**Why it's bad:** It's almost always wrong. Wastes tokens. Biases implementer to copy-paste instead of think.

**Bad:**
```
Step 3: Implement the transform:
```python
def transform(data):
    result = []
    for item in data:
        if item.type == "A":
            result.append(process_a(item))
        elif item.type == "B":
            result.append(process_b(item))
    return result
```
```

**Good:**
```
Step 3: Implement transform function that routes items by type to type-specific processors.
- Input: list of items with .type attribute
- Output: list of processed results
- Pattern: follow existing `batch_process.py` dispatcher pattern
- Verify: test with mixed A/B types returns correct count
```

**Fix:** Describe behavior and boundaries, not syntax. Reference existing patterns.

---

## 4. Refactor Bombs

**Sign:** A step like "Refactor existing X to support Y" embedded in a feature plan

**Why it's bad:** Refactoring is unbounded. Expands to fill all available time. Mixes two concerns.

**Bad:**
```
1. Add new endpoint
2. Refactor auth module to support new token format
3. Wire endpoint to auth
4. Add tests
```

**Good:**
```
# Prerequisite: Refactor auth module (separate plan)
1. Add tests for current auth behavior
2. Extract token parsing to TokenParser class
3. Add new token format to TokenParser
4. Verify all existing tests pass

# Feature: New endpoint (this plan)
1. Add endpoint, use new token format from TokenParser
2. Add integration tests
3. Verify auth flow
```

**Fix:** Refactors are prerequisite plans, not embedded steps.

---

## 5. Invisible Middle

**Sign:** Detailed setup steps, detailed testing steps, hand-waved core logic ("Step 3: Implement the algorithm")

**Why it's bad:** The core logic is where agents fail. Hand-waving it causes hallucination.

**Bad:**
```
1. Create project structure
2. Set up dependencies
3. Implement the transformation algorithm
4. Add unit tests
5. Add integration tests
6. Update documentation
```

**Good:**
```
1. Create project structure with src/, tests/. Verify: pytest runs
2. Parse input CSV with pandas, validate columns exist. Verify: missing column → error
3. Transform: group by customer_id, aggregate totals. Verify: sample data → expected output
4. Transform: apply discount rules from config. Verify: discount applied correctly
5. Output to JSON with schema validation. Verify: output matches schema
6. Add integration test with realistic data. Verify: end-to-end passes
```

**Fix:** Core logic gets MORE detail, not less. Break "implement algorithm" into specific operations.

---

## 6. Skipping Discovery

**Sign:** Planning without reading code. Assuming how things work.

**Why it's bad:** Creates inconsistencies. Misses existing patterns. Reinvents what exists.

**Bad:**
```
1. Create new AuthService class
2. Add login method
3. Add token storage
```

(When the codebase already has an auth pattern using decorators)

**Good:**
```
Discovery notes:
- Auth uses @requires_auth decorator (src/auth/decorators.py)
- Tokens stored in Redis via TokenStore class
- Pattern: services are stateless, state in stores

1. Add new permission check to @requires_auth decorator
2. Extend TokenStore with new token type
3. Add tests using existing auth fixtures
```

**Fix:** Explore before planning. Document what you find. Confirm understanding.

---

## 7. Over-decomposition

**Sign:** 20+ tiny steps. Steps so small they're harder to track than to do.

**Why it's bad:** Loses forest for trees. Tracking overhead exceeds value. Context gets fragmented.

**Bad:**
```
1. Create file src/utils/helper.py
2. Add import statement for os
3. Add import statement for json
4. Define function signature
5. Add docstring
6. Add first line of function
7. Add second line of function
...
```

**Good:**
```
1. Create helper module with load_config function. Verify: import works, returns dict
2. Add validation for required keys. Verify: missing key → ConfigError
3. Add environment variable override. Verify: env var takes precedence
```

**Fix:** 5-7 steps. Each step is a coherent unit of work. If more needed, split into sub-plans.

---

## 8. Implicit Dependencies

**Sign:** Plan assumes things exist without stating them. Secrets, APIs, data, approvals.

**Why it's bad:** Work starts, then blocks. Time wasted on work that can't complete.

**Bad:**
```
1. Add Stripe integration
2. Process payments
3. Store receipts
```

**Good:**
```
Dependencies (verify before starting):
- [ ] Stripe API key in secrets manager
- [ ] Payment webhook URL configured
- [ ] receipts table exists in database

1. Verify Stripe connection. Verify: test mode ping succeeds
2. Implement payment flow. Verify: test payment in Stripe dashboard
3. Store receipt. Verify: record in receipts table
```

**Fix:** List dependencies explicitly. Verify they exist before planning steps that use them.

---

## 9. Layer-by-Layer Planning

**Sign:** All models first, then all controllers, then all views, then "wire together"

**Why it's bad:** Integration problems surface at the end. Can't demo incrementally. "It compiles but doesn't work."

**Bad:**
```
1. Create User model
2. Create Order model
3. Create Product model
4. Create UserController
5. Create OrderController
6. Create ProductController
7. Wire everything together
8. Test
```

**Good:**
```
1. User can view empty order list. Verify: /orders returns []
2. User can create order with one product. Verify: POST /orders, GET shows new order
3. User can add multiple products to order. Verify: order total updates
4. User can checkout. Verify: order status changes
```

**Fix:** Vertical slices. Each step delivers end-to-end functionality.

---

## 10. The Rotting Plan (Context Drift)

**Sign:** Long-running plans where earlier steps change the context for later steps

**Why it's bad:** Step 7 assumes file structure from step 0, but step 3 refactored it.

**Bad:**
Long plan executed over hours/days without updating

**Good:**
```
Plan update after Step 3:
- Note: Moved auth.py to auth/core.py per new structure
- Updated Step 5 file reference accordingly
- Step 7 dependency still valid
```

**Fix:** Update plan after each step. Note what changed. Re-validate remaining steps.
