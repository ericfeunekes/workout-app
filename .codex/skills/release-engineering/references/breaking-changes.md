# Breaking Change Management

Detection, migration patterns, and consumer protection.

## OpenAPI Breaking Change Detection

```yaml
# .github/workflows/contract-check.yml
- name: Check for breaking changes
  uses: oasdiff/oasdiff-action@v0.0.15
  with:
    base: origin/main:contracts/openapi.yaml
    revision: contracts/openapi.yaml
    fail-on-diff: breaking
```

### What's Breaking

**API changes:**
- Required field added to request
- Field removed from response
- Endpoint removed
- Response code changed (200 → 201)
- Type changed (string → number)

**Non-breaking:**
- Optional field added
- New endpoint added
- Response field added

## Database Migration Safety

### Backwards-Compatible DDL

```sql
-- ❌ Breaking: drops column immediately
ALTER TABLE users DROP COLUMN legacy_field;

-- ✅ Safe: multi-phase migration
-- Phase 1: Stop writing to column
-- Phase 2: Deploy code that ignores column
-- Phase 3: Drop column after grace period
ALTER TABLE users DROP COLUMN legacy_field;
```

### Type Change Pattern

```sql
-- Phase 1: Add new column
ALTER TABLE users ADD COLUMN age_int INTEGER;

-- Phase 2: Backfill data
UPDATE users SET age_int = CAST(age_string AS INTEGER);

-- Phase 3: Deploy code using new column
-- Phase 4: Drop old column
ALTER TABLE users DROP COLUMN age_string;
```

## API Versioning

### URL-Based

```
/api/v1/users
/api/v2/users
```

### Header-Based

```
Accept: application/vnd.myapp.v2+json
```

### Deprecation Warnings

```python
@app.get("/api/users")
async def get_users():
    """
    .. deprecated:: 2.0
       Use /api/v2/users instead
    """
    return {"warning": "Deprecated, use /api/v2/users"}
```

## Migration Checklist

- [ ] Breaking changes detected in CI
- [ ] Migration plan documented
- [ ] Backward compatibility tests added
- [ ] Consumers notified (2 week notice minimum)
- [ ] Deprecation warnings deployed
- [ ] New version available
- [ ] Grace period observed
- [ ] Old version removed
- [ ] Documentation updated
