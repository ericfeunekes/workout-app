# Release Workflow

Automated versioning, changelog generation, and deployment orchestration.

## Table of Contents

1. Versioning Strategies
2. Tag-Based Workflow (Trunk-Based Development)
3. Changelog Generation
4. Deployment Strategies
5. Rollback Procedures

---

## 1. Versioning Strategies

### Conventional Commits

**Format:** `type(scope): description`

With squash merge, these are enforced on **PR titles**, not individual commits.

```bash
# Breaking change
feat!: remove deprecated API endpoint

# Feature
feat(api): add user export functionality

# Fix
fix(auth): correct timezone handling in reports

# Chore
chore(deps): update FastAPI to 0.110.0
```

**Types and their semver impact:**
- `feat!:` or `BREAKING CHANGE:` → Major version bump (1.0.0 → 2.0.0)
- `feat:` → Minor version bump (1.0.0 → 1.1.0)
- `fix:` → Patch version bump (1.0.0 → 1.0.1)
- `chore:`, `docs:`, `refactor:`, `test:` → No version bump

### Automated Semver

**Fully automated version determination from commits:**

```yaml
# .github/workflows/release.yml
- name: Determine version
  id: version
  uses: paulhatch/semantic-version@v5
  with:
    major_pattern: "(BREAKING CHANGE:|!:)"
    minor_pattern: "feat:"
    patch_pattern: "fix:"
    version_format: "${major}.${minor}.${patch}"

- name: Create release
  uses: actions/create-release@v1
  with:
    tag_name: v${{ steps.version.outputs.version }}
    release_name: v${{ steps.version.outputs.version }}
```

**When to use:**
- Continuous deployment pipelines
- Libraries with strict semver requirements
- Teams comfortable with automated releases

**When NOT to use:**
- Need manual control over version numbers
- Complex release coordination (multiple repos, breaking changes)
- Prefer explicit version decisions

---

## 2. Tag-Based Workflow (Trunk-Based Development)

Alternative to fully automated semver: explicit version control with human approval.

### Prerequisites

1. **Trunk-based development** - Main branch always deployable
2. **Squash merge on PRs** - Clean git history (one commit per feature)
3. **Conventional PR titles** - Enable changelog generation

### The Complete Workflow

**Step 1: Identify changes since last release**

```bash
# Find last release tag
LAST_TAG=$(git describe --tags --abbrev=0)
echo "Last release: $LAST_TAG"

# Review changes
git log $LAST_TAG..HEAD --oneline --no-merges

# Example output:
# a1b2c3d feat(api): add user export endpoint (#145)
# e4f5g6h fix(auth): correct token expiration (#148)
# i7j8k9l chore(deps): update FastAPI to 0.110.0 (#150)
```

**Step 2: Determine new version**

```bash
# Review commit types to decide version bump
git log $LAST_TAG..HEAD --oneline --no-merges | grep -E "^[a-f0-9]+ (feat|fix|BREAKING)"

# Decision:
# - Has BREAKING or feat!: → major bump (1.2.3 → 2.0.0)
# - Has feat: → minor bump (1.2.3 → 1.3.0)
# - Has fix: only → patch bump (1.2.3 → 1.2.4)

NEW_VERSION="1.3.0"
```

**Step 3: Create release branch**

```bash
git checkout main
git pull origin main
git checkout -b release/v$NEW_VERSION
```

**Step 4: Update version in project files**

**Python (pyproject.toml):**
```bash
# Update version
sed -i '' 's/version = ".*"/version = "'$NEW_VERSION'"/' pyproject.toml

# Verify
grep 'version =' pyproject.toml
# Output: version = "1.3.0"
```

**JavaScript (package.json):**
```bash
# Update version
npm version $NEW_VERSION --no-git-tag-version

# Or manually:
sed -i '' 's/"version": ".*"/"version": "'$NEW_VERSION'"/' package.json
```

**Databricks DLT (pipeline_config.yaml):**
```bash
# Update version field
sed -i '' 's/version: .*/version: '$NEW_VERSION'/' pipeline_config.yaml
```

**Step 5: Generate changelog**

**From clean git log (squash merge benefit):**

```bash
# Generate changelog from conventional commits
git log $LAST_TAG..HEAD --oneline --no-merges \
  --pretty=format:"- %s (%h)" \
  | sed 's/#\([0-9]*\)/(#\1)/g' \
  > CHANGELOG_NEW.md

# Example output:
# - feat(api): add user export endpoint (#145) (a1b2c3d)
# - fix(auth): correct token expiration (#148) (e4f5g6h)
# - chore(deps): update FastAPI to 0.110.0 (#150) (i7j8k9l)
```

**Categorize by type:**

```bash
cat > CHANGELOG_NEW.md << EOF
# v$NEW_VERSION ($(date +%Y-%m-%d))

## Features
$(git log $LAST_TAG..HEAD --oneline --no-merges --grep="^feat" --pretty=format:"- %s")

## Fixes
$(git log $LAST_TAG..HEAD --oneline --no-merges --grep="^fix" --pretty=format:"- %s")

## Maintenance
$(git log $LAST_TAG..HEAD --oneline --no-merges --grep="^chore" --pretty=format:"- %s")
EOF
```

**Prepend to existing CHANGELOG.md:**

```bash
cat CHANGELOG_NEW.md CHANGELOG.md > CHANGELOG_TMP.md
mv CHANGELOG_TMP.md CHANGELOG.md
rm CHANGELOG_NEW.md
```

**Step 6: Commit version bump and changelog**

```bash
git add pyproject.toml CHANGELOG.md  # Or package.json, etc.
git commit -m "chore(release): bump version to v$NEW_VERSION

- Update version in pyproject.toml
- Generate changelog from git log
- Prepare for release"

git push -u origin release/v$NEW_VERSION
```

**Step 7: Tag and deploy to dev**

```bash
# Tag for dev environment
git tag v$NEW_VERSION-dev.1
git push origin v$NEW_VERSION-dev.1

# CI/CD detects tag suffix and deploys to dev
# Monitor deployment logs
```

**Step 8: Tag and deploy to staging (RC)**

```bash
# After dev validation, tag for staging
git tag v$NEW_VERSION-rc.1
git push origin v$NEW_VERSION-rc.1

# CI/CD deploys to staging shadow/slot
# Shadow URL: https://staging-shadow.example.com
```

**Step 9: Create PR to main**

```bash
gh pr create \
  --base main \
  --title "chore(release): v$NEW_VERSION" \
  --body "## Release v$NEW_VERSION

### Changes
$(cat CHANGELOG_NEW.md)

### Deployment
- ✅ Deployed to dev: v$NEW_VERSION-dev.1
- ✅ Deployed to staging: v$NEW_VERSION-rc.1
- ⏳ Awaiting deployment tests

### Testing
- [ ] Smoke tests pass on staging
- [ ] Performance acceptable
- [ ] No errors in logs

### Rollback Plan
If issues detected:
1. Do not merge this PR
2. Deploy previous version: v$LAST_TAG
3. Fix issues in separate PR"
```

**Step 10: Run deployment tests**

```bash
# Automated smoke tests against staging shadow
curl https://staging-shadow.example.com/health | jq
curl https://staging-shadow.example.com/api/v1/users | jq

# Performance check
ab -n 1000 -c 10 https://staging-shadow.example.com/api/v1/users

# Manual testing
# - Test critical flows
# - Check error rates in dashboard
# - Review logs for warnings
```

**Step 11: Comment on PR with test results**

```bash
gh pr comment --body "## Deployment Tests ✅

### Automated Tests
- ✅ Health check: 200 OK
- ✅ API smoke tests: All pass
- ✅ Performance: P95 < 100ms

### Manual Testing
- ✅ User export flow
- ✅ Authentication
- ✅ Error handling

### Metrics
- Error rate: 0.02% (baseline: 0.03%)
- P95 latency: 87ms (baseline: 92ms)

**Ready to merge and deploy to production.**"
```

**Step 12: Tag for production deployment**

```bash
# Tag for production (clean tag, no suffix)
git tag v$NEW_VERSION
git push origin v$NEW_VERSION

# CI/CD deploys to production shadow
# Shadow URL: https://prod-shadow.example.com
```

**Step 13: Merge PR (triggers production cutover)**

```bash
# Squash merge via GitHub UI
# Or: gh pr merge --squash

# CI/CD detects PR merge and:
# 1. Runs smoke tests against production shadow
# 2. Swaps production → shadow (cutover)
# 3. Keeps old production as shadow (rollback safety)
```

**Step 14: Monitor production**

```bash
# Monitor for 30 minutes
# - Error rates
# - Latency
# - User reports

# If issues: rollback (see section 5)
# If stable: announce release
```

### Version File Updates (Stack-Specific)

**Python (pyproject.toml):**
```bash
# Update version
sed -i '' 's/version = ".*"/version = "1.3.0"/' pyproject.toml

# Install updated version
uv sync
```

**Python (__init__.py with __version__):**
```bash
# Update __version__
sed -i '' 's/__version__ = ".*"/__version__ = "1.3.0"/' src/mypackage/__init__.py
```

**JavaScript (package.json):**
```bash
# Update version
npm version 1.3.0 --no-git-tag-version

# Install dependencies
npm install
```

**React (public/version.txt for runtime display):**
```bash
echo "1.3.0" > public/version.txt

# Display in UI
# const version = await fetch('/version.txt').then(r => r.text());
```

**Databricks DLT (pipeline_config.yaml):**
```bash
# Update version
sed -i '' 's/version: .*/version: 1.3.0/' pipeline_config.yaml

# Also update in catalog name if versioned
sed -i '' 's/catalog: mydata_v.*/catalog: mydata_v1_3_0/' pipeline_config.yaml
```

**Databricks Apps (app.yaml):**
```bash
# Update version
sed -i '' 's/version: .*/version: 1.3.0/' app.yaml
```

---

## 3. Changelog Generation

### Automated with git-cliff

**Using git-cliff for conventional commits:**

```yaml
# .github/workflows/release.yml
- name: Generate changelog
  uses: orhun/git-cliff-action@v3
  with:
    config: cliff.toml
    args: --latest
```

**cliff.toml configuration:**
```toml
[changelog]
header = """
# Changelog\n
All notable changes to this project will be documented in this file.\n
"""
body = """
{% for group, commits in commits | group_by(attribute="group") %}
    ### {{ group | upper_first }}
    {% for commit in commits %}
        - {{ commit.message | split(pat="\n") | first | trim }}\
          {% if commit.github.pr_number %} ([#{{ commit.github.pr_number }}]({{ commit.github.pr_url }})){% endif %}\
    {% endfor %}
{% endfor %}
"""

[git]
conventional_commits = true
filter_unconventional = false
commit_parsers = [
    { message = "^feat", group = "Features"},
    { message = "^fix", group = "Bug Fixes"},
    { message = "^doc", group = "Documentation"},
    { message = "^perf", group = "Performance"},
    { message = "^refactor", group = "Refactor"},
    { message = "^chore", group = "Miscellaneous"},
]
```

### Manual from git log

**Simple changelog from squashed commits:**

```bash
# Get last tag
LAST_TAG=$(git describe --tags --abbrev=0)

# Generate changelog
cat > CHANGELOG_NEW.md << 'EOF'
# v1.3.0 (2025-01-20)

## Features
EOF

git log $LAST_TAG..HEAD --oneline --no-merges --grep="^feat" \
  --pretty=format:"- %s" >> CHANGELOG_NEW.md

cat >> CHANGELOG_NEW.md << 'EOF'

## Bug Fixes
EOF

git log $LAST_TAG..HEAD --oneline --no-merges --grep="^fix" \
  --pretty=format:"- %s" >> CHANGELOG_NEW.md

# Prepend to existing changelog
cat CHANGELOG_NEW.md CHANGELOG.md > CHANGELOG_TMP.md
mv CHANGELOG_TMP.md CHANGELOG.md
```

**With PR links:**

```bash
git log $LAST_TAG..HEAD --oneline --no-merges --grep="^feat" \
  --pretty=format:"- %s" \
  | sed 's/#\([0-9]*\)/(#\1)/g' \
  | sed 's/(#\([0-9]*\))$/(https:\/\/github.com\/org\/repo\/pull\/\1)/'
```

---

## 4. Deployment Strategies

### Blue/Green

1. Deploy new version alongside old (green)
2. Run smoke tests
3. Switch traffic to new version
4. Keep old version for 24h (easy rollback)
5. Decommission old version

### Canary

1. Deploy to 5% of traffic
2. Monitor metrics for 1 hour
3. Increase to 25% if healthy
4. Increase to 100% if healthy
5. Rollback if error rate >0.1%

### Feature Flags

```python
# Progressive rollout with feature flags
if feature_flags.is_enabled("new_api", user_id):
    return new_api_handler()
return legacy_api_handler()
```

---

## 5. Rollback Procedures

### Automatic Rollback Triggers

- Error rate >5% above baseline
- P95 latency >2x baseline
- Health check failures >10%
- Critical functionality broken

### Tag-Based Rollback

**Re-tag previous version to trigger deployment:**

```bash
# Find previous stable version
git tag -l 'v*' --sort=-version:refname | head -5
# v1.3.0  <- current (broken)
# v1.2.3  <- rollback target
# v1.2.2
# v1.2.1
# v1.2.0

# Tag previous version with rollback suffix
git tag v1.2.3-rollback.1 v1.2.3
git push origin v1.2.3-rollback.1

# CI/CD detects tag and deploys v1.2.3
```

**Or force re-push existing tag:**

```bash
# Push previous tag again (forces redeployment)
git push origin v1.2.3 --force

# Note: Some CI/CD systems ignore duplicate tags
# Use rollback suffix if force push doesn't trigger
```

### Shadow Slot Rollback

**If using shadow/slot deployment (fastest):**

```bash
# Swap production back to previous shadow slot
# Azure App Service
az webapp deployment slot swap \
  --name myapp \
  --resource-group mygroup \
  --slot shadow \
  --target-slot production

# AWS ECS (update service to point to previous task definition)
aws ecs update-service \
  --cluster mycluster \
  --service myservice \
  --task-definition myapp:v1.2.3

# Databricks Apps (promote previous version)
databricks apps promote \
  --app-name myapp \
  --version v1.2.3
```

### Container Rollback

**Kubernetes:**

```bash
# Rollback to previous deployment
kubectl rollout undo deployment/app

# Or specific revision
kubectl rollout undo deployment/app --to-revision=3

# Check rollout status
kubectl rollout status deployment/app
```

**Docker Compose:**

```bash
# Redeploy with previous image tag
docker-compose down
docker-compose up -d --force-recreate
```

### Database Rollback

**If database migration was part of release:**

```bash
# Rollback migration (if reversible)
# Alembic (Python)
alembic downgrade -1

# Flyway (Java)
flyway undo

# Django
python manage.py migrate app 0003_previous_migration
```

**If migration is irreversible:**
- Keep old code compatible with new schema
- Add feature flag to disable new feature
- Schedule data rollback in maintenance window

### Post-Rollback

**After rollback:**
1. Verify application is stable
2. Monitor metrics for 30 minutes
3. Communicate to stakeholders
4. Create incident report
5. Schedule post-mortem
6. Fix issue in new PR
7. Test fix thoroughly before next release
