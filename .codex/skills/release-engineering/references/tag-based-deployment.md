# Tag-Based Deployment

Complete implementation guide for tag-triggered deployments with environment routing, shadow/slot patterns, and stack-specific examples.

## Table of Contents

1. Tag Format and Environment Routing
2. GitHub Actions Workflow
3. Environment-Specific Deployment
4. Shadow/Slot Deployment Patterns
5. Deployment Test Automation
6. Stack-Specific Examples
7. Troubleshooting

---

## 1. Tag Format and Environment Routing

### Tag Naming Convention

```
v{major}.{minor}.{patch}[-{env}.{iteration}]

Examples:
v1.2.3-dev.1     → Deploy to dev environment
v1.2.3-dev.2     → Re-deploy to dev (after fixes)
v1.2.3-rc.1      → Deploy to staging (release candidate)
v1.2.3-rc.2      → Re-deploy to staging
v1.2.3           → Deploy to production (clean tag)
v1.2.3-rollback.1 → Rollback deployment
```

### Environment Detection Logic

**Bash function:**

```bash
#!/bin/bash

get_environment_from_tag() {
    local tag=$1

    # Remove 'v' prefix
    tag="${tag#v}"

    # Extract suffix after version number
    if [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+-(.+)$ ]]; then
        local suffix="${BASH_REMATCH[1]}"

        # Check environment
        case "$suffix" in
            dev.*)
                echo "dev"
                ;;
            rc.*)
                echo "staging"
                ;;
            rollback.*)
                echo "production"
                ;;
            *)
                echo "unknown"
                ;;
        esac
    else
        # Clean tag (no suffix) = production
        echo "production"
    fi
}

# Usage
TAG="v1.2.3-dev.1"
ENV=$(get_environment_from_tag "$TAG")
echo "Deploying to: $ENV"  # Output: dev
```

**GitHub Actions expression:**

```yaml
env:
  DEPLOY_ENV: ${{ contains(github.ref_name, '-dev.') && 'dev' || contains(github.ref_name, '-rc.') && 'staging' || 'production' }}
```

**Python function:**

```python
import re

def get_environment_from_tag(tag: str) -> str:
    """
    Determine deployment environment from git tag.

    Args:
        tag: Git tag (e.g., 'v1.2.3-dev.1')

    Returns:
        Environment name: 'dev', 'staging', 'production', or 'unknown'
    """
    # Remove 'v' prefix
    tag = tag.lstrip('v')

    # Match version with optional suffix
    match = re.match(r'^\d+\.\d+\.\d+(?:-(.+))?$', tag)

    if not match:
        return 'unknown'

    suffix = match.group(1)

    if not suffix:
        # Clean tag = production
        return 'production'

    if suffix.startswith('dev.'):
        return 'dev'
    elif suffix.startswith('rc.'):
        return 'staging'
    elif suffix.startswith('rollback.'):
        return 'production'
    else:
        return 'unknown'

# Usage
env = get_environment_from_tag('v1.2.3-dev.1')
print(f"Deploying to: {env}")  # Output: dev
```

---

## 2. GitHub Actions Workflow

### Complete Tag-Triggered Workflow

```yaml
# .github/workflows/deploy-on-tag.yml
name: Deploy on Tag

on:
  push:
    tags:
      - 'v*'  # Trigger on all v* tags

jobs:
  determine-environment:
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.parse-tag.outputs.environment }}
      version: ${{ steps.parse-tag.outputs.version }}
      use_shadow: ${{ steps.parse-tag.outputs.use_shadow }}
    steps:
      - name: Parse tag
        id: parse-tag
        run: |
          TAG="${GITHUB_REF_NAME}"
          echo "Tag: $TAG"

          # Remove 'v' prefix for version
          VERSION="${TAG#v}"
          echo "version=$VERSION" >> $GITHUB_OUTPUT

          # Determine environment
          if [[ "$TAG" =~ -dev\. ]]; then
            ENV="dev"
            USE_SHADOW="false"
          elif [[ "$TAG" =~ -rc\. ]]; then
            ENV="staging"
            USE_SHADOW="true"
          elif [[ "$TAG" =~ -rollback\. ]]; then
            ENV="production"
            USE_SHADOW="false"
          else
            # Clean tag = production with shadow
            ENV="production"
            USE_SHADOW="true"
          fi

          echo "environment=$ENV" >> $GITHUB_OUTPUT
          echo "use_shadow=$USE_SHADOW" >> $GITHUB_OUTPUT
          echo "Deploying to: $ENV (shadow: $USE_SHADOW)"

  deploy:
    needs: determine-environment
    runs-on: ubuntu-latest
    environment: ${{ needs.determine-environment.outputs.environment }}
    steps:
      - uses: actions/checkout@v4

      - name: Deploy
        env:
          ENVIRONMENT: ${{ needs.determine-environment.outputs.environment }}
          VERSION: ${{ needs.determine-environment.outputs.version }}
          USE_SHADOW: ${{ needs.determine-environment.outputs.use_shadow }}
        run: |
          echo "Deploying version $VERSION to $ENVIRONMENT (shadow: $USE_SHADOW)"
          ./scripts/deploy.sh "$ENVIRONMENT" "$VERSION" "$USE_SHADOW"

      - name: Run smoke tests
        if: needs.determine-environment.outputs.environment != 'dev'
        run: |
          ./scripts/smoke-tests.sh "${{ needs.determine-environment.outputs.environment }}"

      - name: Notify
        if: always()
        run: |
          # Post deployment notification
          echo "Deployment complete: ${{ needs.determine-environment.outputs.environment }}"
```

### Environment-Specific Configuration

**GitHub Environment Secrets:**

```yaml
# Configure in GitHub: Settings → Environments

# dev environment
Environment: dev
Secrets:
  - DEPLOY_URL: https://dev.example.com
  - API_KEY: dev-api-key-123

# staging environment
Environment: staging
Protection rules:
  - Required reviewers: 1 (optional)
Secrets:
  - DEPLOY_URL: https://staging.example.com
  - SHADOW_URL: https://staging-shadow.example.com
  - API_KEY: staging-api-key-456

# production environment
Environment: production
Protection rules:
  - Required reviewers: 1 (recommended)
Secrets:
  - DEPLOY_URL: https://example.com
  - SHADOW_URL: https://shadow.example.com
  - API_KEY: prod-api-key-789
```

---

## 3. Environment-Specific Deployment

### Deployment Script Template

```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

ENVIRONMENT=$1
VERSION=$2
USE_SHADOW=${3:-false}

echo "=== Deploying version $VERSION to $ENVIRONMENT ==="

case "$ENVIRONMENT" in
  dev)
    echo "Deploying to dev..."
    deploy_to_dev "$VERSION"
    ;;
  staging)
    if [ "$USE_SHADOW" = "true" ]; then
      echo "Deploying to staging shadow slot..."
      deploy_to_staging_shadow "$VERSION"
    else
      echo "Deploying to staging..."
      deploy_to_staging "$VERSION"
    fi
    ;;
  production)
    if [ "$USE_SHADOW" = "true" ]; then
      echo "Deploying to production shadow slot..."
      deploy_to_production_shadow "$VERSION"
    else
      echo "Deploying to production (direct)..."
      deploy_to_production "$VERSION"
    fi
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

echo "=== Deployment complete ==="
```

### Configuration Management

**Environment-specific config files:**

```
config/
  dev.env
  staging.env
  production.env
```

**Load configuration:**

```bash
# In deploy script
load_config() {
    local env=$1
    local config_file="config/${env}.env"

    if [ ! -f "$config_file" ]; then
        echo "Config file not found: $config_file"
        exit 1
    fi

    # Load environment variables
    set -a
    source "$config_file"
    set +a

    echo "Loaded config for $env"
}

# Usage
load_config "$ENVIRONMENT"
```

---

## 4. Shadow/Slot Deployment Patterns

### Azure App Service (Deployment Slots)

**Deploy to shadow slot:**

```bash
deploy_to_staging_shadow() {
    local version=$1

    # Deploy to shadow slot
    az webapp deployment source config-zip \
      --resource-group myapp-staging \
      --name myapp-staging \
      --slot shadow \
      --src "dist/myapp-${version}.zip"

    # Get shadow URL
    SHADOW_URL=$(az webapp show \
      --resource-group myapp-staging \
      --name myapp-staging \
      --slot shadow \
      --query defaultHostName -o tsv)

    echo "Shadow deployment complete: https://${SHADOW_URL}"
}
```

**Swap to production (cutover):**

```bash
swap_to_production() {
    # Swap shadow → production
    az webapp deployment slot swap \
      --resource-group myapp-production \
      --name myapp-production \
      --slot shadow \
      --target-slot production

    echo "Swapped shadow to production"
}
```

### AWS ECS (Blue/Green with Task Definitions)

**Deploy to shadow (green):**

```bash
deploy_to_production_shadow() {
    local version=$1

    # Register new task definition
    TASK_DEF=$(aws ecs register-task-definition \
      --cli-input-json file://task-def-${version}.json \
      --query 'taskDefinition.taskDefinitionArn' \
      --output text)

    # Create green service (shadow)
    aws ecs create-service \
      --cluster myapp-production \
      --service-name myapp-shadow \
      --task-definition "$TASK_DEF" \
      --desired-count 2 \
      --load-balancer targetGroupArn=arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/myapp-shadow,containerName=myapp,containerPort=8000

    echo "Shadow service created: myapp-shadow"
    echo "Shadow URL: https://shadow.example.com"
}
```

**Swap traffic (cutover):**

```bash
swap_to_production() {
    # Update production service to use shadow task definition
    aws ecs update-service \
      --cluster myapp-production \
      --service myapp-production \
      --task-definition "$SHADOW_TASK_DEF"

    echo "Production service updated to shadow task definition"
}
```

### Databricks Apps (App Versions)

**Deploy shadow version:**

```bash
deploy_databricks_app_shadow() {
    local version=$1

    # Update app.yaml with shadow config
    cat > app.yaml << EOF
name: myapp
version: ${version}
env:
  - name: ENVIRONMENT
    value: "production-shadow"
  - name: API_URL
    value: "https://api-shadow.example.com"
EOF

    # Deploy app
    databricks apps deploy \
      --source-dir . \
      --app-name myapp-shadow

    # Get app URL
    APP_URL=$(databricks apps get --app-name myapp-shadow --query url -o tsv)
    echo "Shadow app deployed: $APP_URL"
}
```

**Promote to production:**

```bash
promote_databricks_app() {
    # Promote shadow app to production
    databricks apps promote \
      --app-name myapp-shadow \
      --target-name myapp-production

    echo "App promoted to production"
}
```

---

## 5. Deployment Test Automation

### Smoke Test Script

```bash
#!/bin/bash
# scripts/smoke-tests.sh

set -euo pipefail

ENVIRONMENT=$1

case "$ENVIRONMENT" in
  dev)
    BASE_URL="https://dev.example.com"
    ;;
  staging)
    BASE_URL="https://staging-shadow.example.com"
    ;;
  production)
    BASE_URL="https://shadow.example.com"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

echo "=== Running smoke tests against $BASE_URL ==="

# Test 1: Health check
echo "Test 1: Health check..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health")
if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ Health check failed: HTTP $HTTP_CODE"
  exit 1
fi
echo "✅ Health check passed"

# Test 2: API endpoint
echo "Test 2: API endpoint..."
RESPONSE=$(curl -s "$BASE_URL/api/v1/status")
if ! echo "$RESPONSE" | jq -e '.status == "ok"' > /dev/null; then
  echo "❌ API check failed: $RESPONSE"
  exit 1
fi
echo "✅ API check passed"

# Test 3: Database connection
echo "Test 3: Database connectivity..."
RESPONSE=$(curl -s "$BASE_URL/api/v1/health/db")
if ! echo "$RESPONSE" | jq -e '.database == "connected"' > /dev/null; then
  echo "❌ Database check failed: $RESPONSE"
  exit 1
fi
echo "✅ Database check passed"

# Test 4: Critical feature
echo "Test 4: Critical feature..."
RESPONSE=$(curl -s "$BASE_URL/api/v1/users?limit=1")
if ! echo "$RESPONSE" | jq -e '. | length > 0' > /dev/null; then
  echo "❌ Feature check failed: $RESPONSE"
  exit 1
fi
echo "✅ Feature check passed"

echo "=== All smoke tests passed ✅ ==="
```

### Performance Test

```bash
#!/bin/bash
# scripts/performance-test.sh

SHADOW_URL=$1

echo "=== Running performance tests ==="

# Use Apache Bench for simple load test
ab -n 1000 -c 10 -g results.tsv "$SHADOW_URL/api/v1/users"

# Parse results
P50=$(awk '{sum+=$9; n++} END {if (n>0) print sum/n}' results.tsv)
P95=$(sort -n -k9 results.tsv | awk 'NR==int(0.95*NR)+1 {print $9}')

echo "P50 latency: ${P50}ms"
echo "P95 latency: ${P95}ms"

# Check against thresholds
if (( $(echo "$P95 > 200" | bc -l) )); then
  echo "❌ P95 latency too high: ${P95}ms (threshold: 200ms)"
  exit 1
fi

echo "✅ Performance tests passed"
```

### Automated PR Comment

```yaml
# In GitHub Actions workflow
- name: Comment on release PR
  if: needs.determine-environment.outputs.environment == 'staging'
  uses: actions/github-script@v7
  with:
    script: |
      // Find release PR
      const prs = await github.rest.pulls.list({
        owner: context.repo.owner,
        repo: context.repo.repo,
        state: 'open',
        head: `${context.repo.owner}:release/${context.ref_name}`
      });

      if (prs.data.length === 0) {
        console.log('No release PR found');
        return;
      }

      const pr = prs.data[0];

      // Post test results
      await github.rest.issues.createComment({
        owner: context.repo.owner,
        repo: context.repo.repo,
        issue_number: pr.number,
        body: `## Deployment Tests ✅

### Tag: \`${context.ref_name}\`
### Environment: Staging Shadow

### Automated Tests
- ✅ Health check: 200 OK
- ✅ API smoke tests: All pass
- ✅ Database connectivity: Connected
- ✅ Critical features: Working

### Performance
- P50 latency: 45ms
- P95 latency: 87ms

### Shadow URL
https://staging-shadow.example.com

**Ready to deploy to production.**`
      });
```

---

## 6. Stack-Specific Examples

### React (Vite) Application

**Build and deploy:**

```bash
deploy_react_to_env() {
    local env=$1
    local version=$2

    # Build with environment-specific config
    VITE_API_URL="https://api-${env}.example.com" \
    VITE_VERSION="$version" \
    npm run build

    # Deploy to CDN/static hosting
    aws s3 sync dist/ "s3://myapp-${env}/" --delete

    # Invalidate CloudFront cache
    aws cloudfront create-invalidation \
      --distribution-id "$CLOUDFRONT_DIST_ID" \
      --paths "/*"

    echo "React app deployed to $env"
}
```

**Shadow deployment:**

```bash
deploy_react_shadow() {
    local version=$1

    # Build with shadow API URL
    VITE_API_URL="https://api-shadow.example.com" \
    VITE_VERSION="$version" \
    npm run build

    # Deploy to shadow S3 bucket
    aws s3 sync dist/ "s3://myapp-shadow/" --delete

    echo "React app deployed to shadow"
    echo "Shadow URL: https://shadow.example.com"
}
```

### FastAPI Application

**Docker build and push:**

```bash
deploy_fastapi_to_env() {
    local env=$1
    local version=$1

    # Build Docker image
    docker build \
      --build-arg VERSION="$version" \
      -t "myapp:${version}" \
      -t "myapp:${env}-latest" \
      .

    # Tag for registry
    docker tag "myapp:${version}" "registry.example.com/myapp:${version}"
    docker tag "myapp:${version}" "registry.example.com/myapp:${env}-latest"

    # Push to registry
    docker push "registry.example.com/myapp:${version}"
    docker push "registry.example.com/myapp:${env}-latest"

    # Deploy to environment
    kubectl set image deployment/myapp \
      myapp="registry.example.com/myapp:${version}" \
      --namespace="$env"

    echo "FastAPI app deployed to $env"
}
```

**Shadow deployment:**

```bash
deploy_fastapi_shadow() {
    local version=$1

    # Deploy to shadow namespace
    kubectl set image deployment/myapp-shadow \
      myapp="registry.example.com/myapp:${version}" \
      --namespace=production

    # Get shadow URL
    SHADOW_URL=$(kubectl get ingress myapp-shadow \
      --namespace=production \
      -o jsonpath='{.spec.rules[0].host}')

    echo "FastAPI app deployed to shadow: https://$SHADOW_URL"
}
```

### DLT Pipeline

**Deploy with catalog versioning:**

```bash
deploy_dlt_pipeline() {
    local env=$1
    local version=$1

    # Update pipeline config
    cat > pipeline_config.yaml << EOF
name: my_pipeline
version: ${version}
catalog: mydata_${env}_v${version//./_}
target: ${env}_target
configuration:
  environment: ${env}
EOF

    # Deploy pipeline
    databricks pipelines create \
      --config pipeline_config.yaml \
      --name "my_pipeline_${env}_${version}"

    # Start update
    PIPELINE_ID=$(databricks pipelines get \
      --name "my_pipeline_${env}_${version}" \
      --query pipeline_id -o tsv)

    databricks pipelines update --pipeline-id "$PIPELINE_ID"

    echo "DLT pipeline deployed to $env (catalog: mydata_${env}_v${version//./_})"
}
```

**Blue/green catalog deployment:**

```bash
deploy_dlt_blue_green() {
    local version=$1

    # Deploy to green catalog
    GREEN_CATALOG="mydata_production_v${version//./_}"

    databricks pipelines create \
      --config pipeline_config.yaml \
      --name "my_pipeline_green" \
      --catalog "$GREEN_CATALOG"

    # Run and validate
    databricks pipelines update --pipeline-id "$GREEN_PIPELINE_ID"

    # Swap: Update downstream views to point to green catalog
    databricks sql execute \
      --warehouse-id "$WAREHOUSE_ID" \
      --query "ALTER VIEW production.my_view AS SELECT * FROM ${GREEN_CATALOG}.my_table"

    echo "DLT pipeline deployed to green catalog: $GREEN_CATALOG"
}
```

### Databricks App

**Deploy app with versioning:**

```bash
deploy_databricks_app() {
    local env=$1
    local version=$2

    # Update app.yaml
    cat > app.yaml << EOF
name: myapp
version: ${version}
env:
  - name: ENVIRONMENT
    value: "${env}"
  - name: VERSION
    value: "${version}"
  - name: API_URL
    value: "https://api-${env}.example.com"
EOF

    # Deploy app
    databricks apps deploy \
      --source-dir . \
      --app-name "myapp-${env}"

    # Get app URL
    APP_URL=$(databricks apps get \
      --app-name "myapp-${env}" \
      --query url -o tsv)

    echo "Databricks app deployed to $env: $APP_URL"
}
```

---

## 7. Troubleshooting

### Tag Deployment Not Triggering

**Check workflow filter:**

```yaml
on:
  push:
    tags:
      - 'v*'  # Make sure this matches your tag format
```

**Verify tag was pushed:**

```bash
# List remote tags
git ls-remote --tags origin

# Check if tag exists
git ls-remote --tags origin | grep "v1.2.3"
```

**Re-push tag to trigger:**

```bash
# Delete and re-push tag
git tag -d v1.2.3
git push origin :refs/tags/v1.2.3

git tag v1.2.3
git push origin v1.2.3
```

### Environment Detection Failing

**Debug environment parsing:**

```bash
# Test locally
TAG="v1.2.3-dev.1"
if [[ "$TAG" =~ -dev\. ]]; then
  echo "Detected dev environment"
else
  echo "Did not detect dev environment"
fi
```

**Check GitHub Actions output:**

```yaml
- name: Debug tag parsing
  run: |
    echo "GITHUB_REF: $GITHUB_REF"
    echo "GITHUB_REF_NAME: $GITHUB_REF_NAME"
    echo "GITHUB_REF_TYPE: $GITHUB_REF_TYPE"
```

### Shadow Deployment Issues

**Verify shadow slot exists:**

```bash
# Azure
az webapp deployment slot list \
  --name myapp \
  --resource-group mygroup

# Create shadow slot if missing
az webapp deployment slot create \
  --name myapp \
  --resource-group mygroup \
  --slot shadow
```

**Check shadow URL:**

```bash
# Azure
az webapp show \
  --name myapp \
  --resource-group mygroup \
  --slot shadow \
  --query defaultHostName -o tsv
```

### Smoke Tests Failing

**Test manually:**

```bash
# Health check
curl -v https://staging-shadow.example.com/health

# Check response headers
curl -I https://staging-shadow.example.com/health

# Test with authentication
curl -H "Authorization: Bearer $TOKEN" \
  https://staging-shadow.example.com/api/v1/users
```

**Check logs:**

```bash
# Kubernetes
kubectl logs -l app=myapp --namespace=staging --tail=100

# Databricks Apps
databricks apps logs --app-name myapp-shadow --lines 100
```

### Rollback Not Working

**Verify rollback tag:**

```bash
# Check tag exists
git tag -l 'v1.2.2*'

# Create rollback tag if needed
git tag v1.2.2-rollback.1 v1.2.2
git push origin v1.2.2-rollback.1
```

**Manual rollback:**

```bash
# Azure slot swap
az webapp deployment slot swap \
  --name myapp \
  --resource-group mygroup \
  --slot shadow \
  --target-slot production

# Kubernetes
kubectl rollout undo deployment/myapp --namespace=production
```

---

## Best Practices

### Tag Management
- ✅ Use semantic versioning (major.minor.patch)
- ✅ Always prefix tags with 'v'
- ✅ Use consistent suffix format (-dev.N, -rc.N)
- ✅ Increment iteration number for re-deployments
- ✅ Clean tags (no suffix) for production only

### Shadow Deployments
- ✅ Always deploy to shadow first (except dev)
- ✅ Run smoke tests before cutover
- ✅ Keep old production as shadow for 24h rollback window
- ✅ Monitor metrics after cutover
- ✅ Have rollback plan ready

### Automation
- ✅ Automate smoke tests
- ✅ Comment deployment results on PR
- ✅ Notify team on deployment completion
- ✅ Track deployment metrics
- ✅ Alert on deployment failures

### Testing
- ✅ Test against shadow URL before production
- ✅ Include performance tests
- ✅ Verify database migrations
- ✅ Check error rates
- ✅ Test rollback procedure regularly
