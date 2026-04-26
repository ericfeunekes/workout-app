# Writing Style

Guidelines for clear, scannable documentation.

## Core Principles

1. **Imperative tone** — Commands, not suggestions
2. **Quantitative constraints** — Numbers, not adjectives
3. **Examples over abstractions** — Show, don't just tell
4. **Scannable structure** — Bullets, tables, short paragraphs

---

## Imperative Tone

Write in commands or infinitives. Direct, commanding language.

<tone_examples>
**Bad** (passive, suggestive):
```markdown
You might want to consider using dependency injection.
It would be a good idea to keep functions short.
The team should probably run tests before committing.
```

**Good** (imperative):
```markdown
Use dependency injection for all clients.
Keep functions ≤30 lines.
Run tests before committing.
```
</tone_examples>

---

## Quantitative Constraints

Replace vague qualifiers with measurable constraints.

| Bad (vague) | Good (quantitative) |
|-------------|---------------------|
| Keep it concise | ≤20 words per sentence |
| Functions should be short | Functions ≤30 lines |
| Write a brief summary | 1-2 sentences |
| Don't make pages too long | Pages <300 lines |
| Add some examples | 2-4 examples per key behavior |
| Respond quickly | Response in ≤3 sentences |

<quantitative_examples>
**Bad**:
```markdown
Keep the README brief and focused.
Add enough examples to be clear.
```

**Good**:
```markdown
README: 30-80 lines.
Examples: 2-4 per key behavior, each ≤10 lines.
```
</quantitative_examples>

---

## Sentence Length

Keep sentences ≤20 words. Break longer concepts into bullet lists.

<sentence_examples>
**Bad** (43 words):
```markdown
When you're writing documentation for a repository, you should always
consider the audience and make sure that the content is organized in
a way that makes it easy for readers to find what they're looking for
quickly and efficiently.
```

**Good** (split into bullets):
```markdown
Consider the audience when writing docs.

Key principles:
- Organize for discoverability
- Enable quick scanning
- Front-load important information
```
</sentence_examples>

---

## Lead with Purpose

Start each page/section with purpose and audience. One sentence.

<purpose_examples>
**Bad** (buries the point):
```markdown
# Authentication

Authentication is a critical part of any application. There are many
different approaches to authentication, including OAuth, JWT, and
session-based auth. This document covers our authentication system.
```

**Good** (leads with purpose):
```markdown
# Authentication

How our auth system works. Read this before modifying auth code.

## Overview
...
```
</purpose_examples>

---

## Link Text

Use descriptive link text. Never raw URLs or "click here".

<link_examples>
**Bad**:
```markdown
For more info, click here: https://docs.example.com/auth
See https://github.com/org/repo/blob/main/docs/auth.md
```

**Good**:
```markdown
See the [authentication guide](docs/auth.md) for details.
Load the [rollback playbook](docs/runbooks/rollback.md) before proceeding.
```
</link_examples>

---

## Code Blocks

Use fenced blocks with language hints. Keep snippets focused.

<code_examples>
**Bad** (no language, too long):
```
def fetch_user(id):
    # This function fetches a user from the database
    # It handles various edge cases and errors
    # First we validate the input
    if not id:
        raise ValueError("ID required")
    # Then we connect to the database
    db = get_db_connection()
    # Then we query for the user
    user = db.query(User).filter(User.id == id).first()
    # Then we check if we found anything
    if not user:
        raise NotFoundError("User not found")
    # Finally we return the user
    return user
```

**Good** (language hint, focused):
```python
def fetch_user(user_id: str) -> User:
    """Fetch user by ID. Raises NotFoundError if not found."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise NotFoundError(f"User {user_id} not found")
    return user
```
</code_examples>

---

## Tables

Use tables for comparisons. Keep columns ≤4, rows scannable.

<table_examples>
**Bad** (too many columns, dense):
```markdown
| Name | Type | Required | Default | Description | Example | Notes |
|------|------|----------|---------|-------------|---------|-------|
| id | string | yes | none | The unique identifier | "abc123" | Must be valid UUID |
```

**Good** (focused, scannable):
```markdown
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string | Yes | Unique identifier (UUID) |
| name | string | Yes | Display name |
| email | string | No | Contact email |
```
</table_examples>

---

## Headings

Use headings sequentially (h1 → h2 → h3). Never skip levels.

<heading_examples>
**Bad** (skips levels):
```markdown
# Authentication

### JWT Configuration    <!-- Skipped h2 -->

##### Token Expiry       <!-- Skipped h3, h4 -->
```

**Good** (sequential):
```markdown
# Authentication

## JWT Configuration

### Token Expiry
```
</heading_examples>

---

## Skill Callouts

When readers should load a skill before proceeding, call it out explicitly.

<skill_callouts>
```markdown
## Updating Documentation

Before editing docs, load `skill:documentation-maintenance`.

## Writing AGENTS.md

For AGENTS.md authoring, load `skill:prompting` for best practices.
```
</skill_callouts>

---

## Checklist

Before finalizing documentation:

- [ ] Imperative tone throughout
- [ ] Sentences ≤20 words (or broken into bullets)
- [ ] Vague qualifiers replaced with numbers
- [ ] Pages start with purpose statement
- [ ] Links have descriptive text
- [ ] Code blocks have language hints
- [ ] Tables have ≤4 columns
- [ ] Headings are sequential
- [ ] Skill callouts where applicable
