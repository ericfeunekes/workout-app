# Quality Metrics & Observability

Track build health, test performance, and quality trends over time.

## Build Metrics

**Track in CI/CD:**
- Test suite duration (detect slowdowns)
- Flake rate by test file
- Coverage trends (overall + diff)
- Build success rate by branch
- Time from commit to deploy

**Alerts:**
- Test suite >2x slower than baseline
- Flake rate >5%
- Coverage drops >5%
- Build failure rate >20%

## Quality Metrics

**Code quality:**
- Mutation score for critical modules (target 80%+)
- Contract coverage (API endpoints × test scenarios)
- Security vulnerabilities (block on high/critical)
- Technical debt ratio (track over time)

**Release metrics:**
- Lead time (commit → production)
- Deployment frequency
- Mean time to recovery (MTTR)
- Rollback rate

## Dashboard Setup

```yaml
# Export metrics to GitHub
- name: Export test metrics
  run: |
    pytest --json-report --json-report-file=test-report.json

- name: Comment PR with metrics
  uses: peter-evans/create-or-update-comment@v4
  with:
    issue-number: ${{ github.event.pull_request.number }}
    body: |
      ## Test Results
      - Duration: ${{ steps.test.outputs.duration }}
      - Coverage: ${{ steps.coverage.outputs.percentage }}%
      - Flakes: ${{ steps.flakes.outputs.count }}
```

## Tracking Flake Rate

```bash
# Log flaky tests to file
pytest --json-report | jq '.tests[] | select(.outcome == "flaky")' >> flakes.jsonl

# Analyze trends
cat flakes.jsonl | jq -r '.nodeid' | sort | uniq -c | sort -rn
```
