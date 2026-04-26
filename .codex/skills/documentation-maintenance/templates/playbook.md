---
title: "Playbook: <Failure Name>"
last_reviewed: <YYYY-MM-DD>
owner: @username
---

# Playbook: <Failure Name>

Step-by-step mitigation for <specific failure>.

## Scope

**Failure signature**: <What triggers this playbook>

**Affected components**:
- Component 1
- Component 2

**Severity**: P1 | P2 | P3

## Detection

### Alerts

| Alert | Dashboard | Threshold |
|-------|-----------|-----------|
| `alert-name` | [Link](url) | >X for Y minutes |

### Quick Check

```bash
# Command to verify the issue
curl -s https://api.example.com/health | jq '.status'
```

Expected: `"healthy"` | Actual during failure: `"degraded"`

## Triage

1. **Confirm scope**
   ```bash
   # Check affected regions/services
   ```

2. **Identify cause**
   - If X → likely cause A
   - If Y → likely cause B

3. **Escalate if needed**
   - Slack: #incident-channel
   - PagerDuty: escalation-policy

## Mitigation

### Option 1: Restart

```bash
# Restart the affected service
kubectl rollout restart deployment/service-name -n namespace
```

**Expected result**: Pods restart within 2 minutes, alert clears.

### Option 2: Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/service-name -n namespace
```

**Expected result**: Previous version restored, functionality restored.

### Option 3: Feature Flag

```bash
# Disable problematic feature
curl -X POST https://api.example.com/admin/flags \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"flag": "feature-x", "enabled": false}'
```

## Root Cause Hints

| Symptom | Likely Cause | How to Confirm |
|---------|--------------|----------------|
| High latency | DB connection pool exhausted | Check `pg_stat_activity` |
| 500 errors | Upstream service down | Check dependency health |
| Memory spike | Memory leak in v2.3.1 | Check if running v2.3.1 |

## Communications

### Internal (Slack)

```
🔴 [P1] <Service> degraded
- Impact: <user-facing impact>
- Status: Investigating
- Updates: This thread
```

### External (Status Page)

```
We are currently investigating reports of <impact>.
Updates will be posted here.
```

## Exit Checks

- [ ] Alert cleared for 10+ minutes
- [ ] No elevated error rates
- [ ] Spot-check 3 requests manually
- [ ] Post-incident ticket created: JIRA-XXX
- [ ] Schedule post-mortem if P1/P2
