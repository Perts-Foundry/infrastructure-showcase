# Terraform Best Practices

This guide documents Terraform best practices tailored to a Cloudflare Workers + R2 + GitHub Actions stack (Workers with Static Assets, R2 storage, GitHub Actions CI/CD). It synthesizes guidance from HashiCorp's official style guide, provider-specific documentation, and community best practices as of 2026.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Code Style & Naming](#code-style--naming)
3. [State Management](#state-management)
4. [Provider Configuration](#provider-configuration)
5. [Security Best Practices](#security-best-practices)
6. [Cloudflare-Specific Patterns](#cloudflare-specific-patterns)
7. [Checkly Provider Patterns](#checkly-provider-patterns)
8. [GitHub Provider Patterns](#github-provider-patterns)
9. [Module Best Practices](#module-best-practices)
10. [Testing & Validation](#testing--validation)
11. [CI/CD Integration](#cicd-integration)
12. [Latest Terraform Features](#latest-terraform-features)
13. [Common Gotchas](#common-gotchas)
14. [References](#references)

---

## Project Structure

### Recommended File Organization

Organize Terraform files by cloud provider, with shared configuration in dedicated files:

```
infrastructure/
├── providers.tf         # Provider configuration and required_providers
├── variables.tf         # Input variable declarations
├── outputs.tf           # Output declarations
├── locals.tf            # Local values and computed expressions
├── cloudflare.tf        # All Cloudflare resources (DNS, Workers, R2, zone settings)
├── github.tf            # All GitHub resources (repos, secrets, branch protection)
├── checkly.tf           # All Checkly resources (synthetic monitoring, alerts)
├── terraform.tfvars     # Variable values (gitignored if sensitive)
└── .terraform.lock.hcl  # Dependency lock file (commit this)
```

This single-file-per-cloud approach provides:
- Clear ownership boundaries between providers
- Easy navigation when troubleshooting provider-specific issues
- Simplified code review (changes to one cloud are isolated)
- Natural grouping of related resources that share the same provider

For larger deployments with multiple accounts or zones, consider the Cloudflare-recommended pattern of separating by account/zone/product:

```
infrastructure/
├── accounts/
│   └── example-org/
│       ├── zones/
│       │   └── example.com/
│       │       ├── cloudflare.tf
│       │       └── github.tf
│       └── workers/
│           └── website/
└── modules/
```

### What to Commit vs. Gitignore

**Commit these files:**
- All `.tf` files
- `.terraform.lock.hcl` (dependency lock file ensures reproducible builds)
- `*.tfvars.example` (template files without actual values)

**Gitignore these files:**
```gitignore
# Local .terraform directories
**/.terraform/*

# State files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Variable files with actual values
*.tfvars
*.tfvars.json
!*.tfvars.example

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# CLI configuration files
.terraformrc
terraform.rc
```

---

## Code Style & Naming

### Indentation and Formatting

- Use **two-space indentation** (Terraform standard)
- Run `terraform fmt` before every commit
- Configure your editor to format on save

### Naming Conventions

Use **underscores** to separate words in all Terraform identifiers:

```hcl
# Good
resource "cloudflare_dns_record" "proton_mail_mx_primary" {
  # ...
}

# Bad
resource "cloudflare_dns_record" "proton-mail-mx-primary" {
  # ...
}
```

**Avoid type redundancy** in resource names. The resource type already conveys what it is:

```hcl
# Good - the type tells us it's a DNS record
resource "cloudflare_dns_record" "mx_primary" {
  # ...
}

# Bad - redundant "record" in the name
resource "cloudflare_dns_record" "mx_primary_record" {
  # ...
}
```

### Meta-Argument Ordering

Place meta-arguments at the top of resource blocks in this order:

```hcl
resource "cloudflare_dns_record" "mail_txt" {
  # 1. Meta-arguments first
  count      = var.enable_email ? 1 : 0
  for_each   = var.subdomains
  provider   = cloudflare.production
  depends_on = [cloudflare_zone.main]

  # 2. Required arguments
  zone_id = var.zone_id
  name    = "@"
  type    = "TXT"
  content = "v=spf1 include:_spf.protonmail.ch ~all"

  # 3. Optional arguments
  ttl     = 3600
  proxied = false

  # 4. Lifecycle block last
  lifecycle {
    prevent_destroy = true
  }
}
```

### Comments

Use `#` for all comments. Avoid `//` and `/* */`:

```hcl
# Good - single-line comment
# This record is required for Proton Mail verification

/* Bad - block comment style */
// Bad - C-style comment
```

---

## State Management

### Remote State with R2

Cloudflare R2 is S3-compatible and works as a Terraform backend. Configure it with the necessary compatibility flags:

```hcl
terraform {
  backend "s3" {
    bucket = "example-tf-state"
    key    = "infrastructure/terraform.tfstate"
    region = "auto"

    # R2-specific settings
    endpoints = {
      s3 = "https://<account_id>.r2.cloudflarestorage.com"
    }

    # Required for R2 compatibility
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
```

Pass credentials via environment variables in CI/CD:
- `AWS_ACCESS_KEY_ID` - R2 access key
- `AWS_SECRET_ACCESS_KEY` - R2 secret key

### State Locking Strategy

R2 doesn't support DynamoDB-style state locking. For small teams, use **GitHub Actions concurrency control**:

```yaml
concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false
```

For Terraform 1.10+, S3-native locking via conditional writes is available:

```hcl
terraform {
  backend "s3" {
    # ... other config
    use_lockfile = true  # Requires Terraform 1.10+
  }
}
```

### State File Rules

1. **Never commit state files** - They contain sensitive data and resource IDs
2. **Always commit `.terraform.lock.hcl`** - Ensures provider version consistency
3. **Encrypt state at rest** - R2 provides server-side encryption by default
4. **Limit state access** - Scope R2 API tokens to only the state bucket

---

## Provider Configuration

### Required Providers Block

Always pin provider versions explicitly:

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    checkly = {
      source  = "checkly/checkly"
      version = "~> 1.21"
    }
  }
}
```

### Cloudflare Provider v5

The Cloudflare provider v5 is a complete rewrite. Key changes from v4:

- `cloudflare_record` → `cloudflare_dns_record`
- `value` attribute → `content`
- New resource structures and attribute names

Configure with API tokens (not API keys):

```hcl
provider "cloudflare" {
  api_token = var.cloudflare_api_token  # Preferred over API key
}
```

### Ephemeral Credentials (Terraform 1.10+)

For secrets that shouldn't persist in state, use ephemeral variables:

```hcl
variable "cloudflare_api_token" {
  type      = string
  sensitive = true
  ephemeral = true  # Terraform 1.10+
}
```

---

## Security Best Practices

### Sensitive Variable Marking

Always mark sensitive variables:

```hcl
variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with zone and worker permissions"
  sensitive   = true
}

variable "r2_secret_key" {
  type        = string
  description = "R2 S3-compatible secret access key"
  sensitive   = true
}
```

### Static Analysis Tools

Integrate security scanning into CI/CD:

| Tool | Focus | Integration |
|------|-------|-------------|
| **Checkov** | Compliance and security | `checkov -d .` |
| **tfsec** | Terraform-specific security | `tfsec .` |
| **KICS** | Infrastructure-as-code scanning | `kics scan -p .` |
| **Trivy** | Comprehensive scanning | `trivy config .` |

Example GitHub Actions step:

```yaml
- name: Run Checkov
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: .
    framework: terraform
    soft_fail: false
```

### Credential Hygiene

1. **Never hardcode credentials** - Use environment variables or secret managers
2. **Use scoped API tokens** - Minimum permissions necessary for the task
3. **Rotate credentials regularly** - Update tokens periodically
4. **Audit access** - Review who has access to state and credentials

### State File Security

State files contain sensitive data including:
- Resource IDs and attributes
- Values of sensitive variables (marked but not encrypted)
- Provider credentials in some cases

Protect state by:
- Using encrypted remote backends (R2 encrypts at rest)
- Restricting access to the state bucket
- Never storing state in version control

---

## Cloudflare-Specific Patterns

### DNS Record Management

Terraform should be the **single source of truth** for DNS. Import existing records before adding new ones:

```bash
# Using cf-terraforming to generate import commands
cf-terraforming generate --resource-type cloudflare_dns_record \
  --zone <zone_id> --token <api_token>

# Import a specific record (v5 format)
terraform import cloudflare_dns_record.mx_primary <zone_id>/<record_id>
```

After importing, always verify a clean plan before applying changes:

```bash
terraform plan  # Should show "No changes"
```

### Workers Deployment Strategy

**Recommended approach:** Let Wrangler manage Worker script deployments; use Terraform for surrounding infrastructure.

| Terraform Manages | Wrangler Manages |
|-------------------|------------------|
| DNS records | Worker script content |
| Zone settings | Static assets |
| R2 buckets | Deployment versions |
| Custom domain routing | Preview URLs |

This avoids conflicts between the two tools trying to manage the same resource.

### R2 Bucket Management

Create R2 buckets with Terraform:

```hcl
resource "cloudflare_r2_bucket" "assets" {
  account_id = var.cloudflare_account_id
  name       = "example-assets"
  location   = "WNAM"  # Western North America
}
```

**Note:** R2 CORS and lifecycle rules may require the AWS provider due to R2's S3 compatibility layer.

### cf-terraforming for Imports

Use the official `cf-terraforming` tool to import existing Cloudflare resources:

```bash
# Install
go install github.com/cloudflare/cf-terraforming/cmd/cf-terraforming@latest

# Generate resource definitions
cf-terraforming generate \
  --resource-type cloudflare_dns_record \
  --zone <zone_id> \
  --token <api_token>

# Generate import commands
cf-terraforming import \
  --resource-type cloudflare_dns_record \
  --zone <zone_id> \
  --token <api_token>
```

### Environment Separation

For production vs. staging, use **separate Cloudflare accounts** rather than trying to namespace within a single account. This provides:
- Complete isolation of resources
- Separate billing and quotas
- Independent API token scopes

---

## Checkly Provider Patterns

### Authentication

The Checkly provider authenticates via environment variables:

```hcl
provider "checkly" {}
```

Required env vars:
- `CHECKLY_API_KEY`: User-scoped API key from **User Settings > API Keys**. Format is `cu_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`.
- `CHECKLY_ACCOUNT_ID`: UUID from **Account Settings > General**.

The API key is user-scoped (not service-scoped) on the free tier; service-scoped tokens require Enterprise. Rotate the key when the owning user offboards.

### Resource Hierarchy

Checkly resources form a three-layer hierarchy:

```
checkly_alert_channel  (where alerts go: email, Slack, PagerDuty, etc.)
       ▲
       │ subscribed by
checkly_check_group    (shared settings: location, concurrency, alert wiring)
       ▲
       │ group_id
checkly_check          (the actual HTTP probes)
```

Alert subscriptions attach to the **group**, not individual checks. This is because the Checkly provider v1 API limitation (see [checkly/terraform-provider-checkly#332](https://github.com/checkly/terraform-provider-checkly/issues/332)) causes group-level `locations`, `retries`, and alert settings to override per-check values. Configure these on the group as the source of truth.

### Free-Tier Budget

The free tier is 10,000 check runs per month. Exhaustion halts ALL checks in the account until month rollover; there is no throttle mode.

Budget math:
```
runs/month = checks x locations x (730 hours/month / frequency_minutes * 60)
```

Example: 12 checks x 1 location x 60-min frequency = 8,760 base runs/month; retries on failures add ~2-5% (~9,200 total, 92% of tier).

Doubling locations, halving frequency, or adding a few checks can push over the ceiling. Document the budget in a comment next to `check_frequency` so future additions account for it.

### Assertion Strategy

Prefer **structural markers** (DOM IDs, shortcode-generated classes, data attributes) over **editorial content** (body copy, marketing language). Structural markers change only during deliberate template refactors; editorial content drifts with every SEO tweak.

```hcl
# Preferred: structural marker tied to the Hugo template
assertion {
  source     = "TEXT_BODY"
  comparison = "CONTAINS"
  target     = "hero-heading"  # <h1 id="hero-heading">
}

# Acceptable only when no structural marker exists on the page:
assertion {
  source     = "TEXT_BODY"
  comparison = "CONTAINS"
  target     = "privacy policy"
}
```

### Contract-Testing the Error Path

For endpoints protected by gates (CAPTCHA, auth, rate limiting), assert on the expected-failure path to exercise the pipeline without triggering side effects:

```hcl
resource "checkly_check" "contact_form_api" {
  # POST with valid fields but no Turnstile token.
  # Expects 400 + specific error message, proving routing, parsing,
  # field validation, and Turnstile check all reached without side effects.
  request {
    url    = "https://example.com/api/contact"
    method = "POST"
    body   = jsonencode({ ... })

    assertion {
      source     = "STATUS_CODE"
      comparison = "EQUALS"
      target     = "400"
    }

    assertion {
      source     = "TEXT_BODY"
      comparison = "CONTAINS"
      target     = "verification challenge"
    }
  }
}
```

Asserting on specific error text (not just the 400 code) pins down **which** failure path executed, catching regressions where a different guard starts returning 400.

### Muted Groups During Staging

When a site is still gated (behind a Cloudflare Access policy, in pre-launch state, etc.), set `muted = true` on the check group. Checks still run (validating the monitoring config end-to-end) but alert emails are suppressed, avoiding inbox spam from expected failures. Flip to `muted = false` when the site goes public.

---

## GitHub Provider Patterns

### Authentication

Use a Personal Access Token (PAT) or GitHub App for authentication:

```hcl
provider "github" {
  token = var.github_token
  owner = "example-org"  # Organization name
}
```

For fine-grained PATs, required permissions depend on resources managed:
- **Repositories:** Contents, Metadata
- **Actions secrets:** Secrets
- **Branch protection:** Administration

### Repository Management

```hcl
resource "github_repository" "website" {
  name        = "example-website"
  description = "Hugo website"
  visibility  = "private"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  delete_branch_on_merge = true
  allow_squash_merge     = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
}
```

### Actions Secrets

Use `encrypted_value` for secrets when possible to avoid them appearing in plan output:

```hcl
resource "github_actions_secret" "cloudflare_token" {
  repository      = github_repository.website.name
  secret_name     = "CLOUDFLARE_API_TOKEN"
  plaintext_value = var.cloudflare_api_token  # Will appear in state
}
```

**Warning:** GitHub secrets stored via Terraform will have their values in the state file. Use ephemeral values (Terraform 1.10+) to mitigate this.

### Branch Protection

```hcl
resource "github_branch_protection" "main" {
  repository_id = github_repository.website.node_id
  pattern       = "main"

  required_pull_request_reviews {
    required_approving_review_count = 1
    dismiss_stale_reviews           = true
  }

  required_status_checks {
    strict   = true
    contexts = ["build", "test"]
  }

  enforce_admins = false
  allows_force_pushes = false
}
```

### State Sensitivity Warning

The GitHub provider stores sensitive values in state:
- Secret values (plaintext)
- SSH keys
- Deploy keys

Encrypt your state backend and limit access carefully.

---

## Module Best Practices

### When to Use Modules

Create modules for:
- Patterns repeated across multiple environments
- Complex resource groupings with multiple dependencies
- Reusable components shared across projects

Avoid modules for:
- Simple, single-use resources
- Resources that are unlikely to be reused

### Cloudflare Module Caveat

Cloudflare recommends **minimizing module usage** due to potential API sync issues. When Cloudflare's control plane updates, deeply nested modules can cause drift detection problems.

If you do use modules:
- Keep them shallow (avoid nested modules)
- Pin module versions explicitly
- Test thoroughly after provider upgrades

### Module Structure

```
modules/
└── worker_site/
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    └── README.md
```

### Module Versioning

For internal modules, use Git tags:

```hcl
module "worker_site" {
  source = "git::https://github.com/example-org/tf-modules.git//worker_site?ref=v1.2.0"

  worker_name = "example-website"
  zone_id     = var.zone_id
}
```

---

## Testing & Validation

### Built-in Validation

Always run these before committing:

```bash
# Format check (fails if formatting needed)
terraform fmt -check -recursive

# Syntax and reference validation
terraform validate
```

### Native Terraform Test (1.7+)

Create test files with `.tftest.hcl` extension:

```hcl
# tests/dns_records.tftest.hcl
run "verify_mx_records_exist" {
  command = plan

  assert {
    condition     = length(cloudflare_dns_record.mx) > 0
    error_message = "MX records must be defined"
  }
}

run "verify_spf_record" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.spf.content != ""
    error_message = "SPF record must have content"
  }
}
```

Run tests:

```bash
terraform test
```

### Testing Pyramid

Follow the testing pyramid for infrastructure code:

| Level | Percentage | Tools | Speed |
|-------|------------|-------|-------|
| Unit tests | 70% | `terraform validate`, `terraform test`, static analysis | Fast |
| Integration tests | 20% | Terratest, real provider calls | Moderate |
| End-to-end tests | 10% | Full deployment to staging | Slow |

### Terratest for Integration Tests

For complex infrastructure, use Terratest (Go-based):

```go
func TestWorkerDeployment(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../",
        Vars: map[string]interface{}{
            "environment": "test",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    workerUrl := terraform.Output(t, terraformOptions, "worker_url")
    http_helper.HttpGetWithRetry(t, workerUrl, nil, 200, "OK", 30, 5*time.Second)
}
```

---

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: Terraform

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false

jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: ${{ github.ref == 'refs/heads/main' && 'production' || '' }}

    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.10.0"

      - name: Terraform Init
        run: terraform init
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.R2_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.R2_SECRET_ACCESS_KEY }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive

      - name: Terraform Validate
        run: terraform validate

      - name: Terraform Plan
        id: plan
        run: terraform plan -no-color -out=tfplan
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}

      - name: Post Plan to PR
        if: github.event_name == 'pull_request'
        uses: actions/github-script@v7
        with:
          script: |
            const plan = `${{ steps.plan.outputs.stdout }}`;
            github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: '## Terraform Plan\n```\n' + plan + '\n```'
            });

      - name: Terraform Apply
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        run: terraform apply -auto-approve tfplan
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

### Security Scanning in Pipeline

Add security scanning before the plan step:

```yaml
- name: Run tfsec
  uses: aquasecurity/tfsec-action@v1.0.3

- name: Run Checkov
  uses: bridgecrewio/checkov-action@v12
  with:
    directory: .
    framework: terraform
```

---

## Latest Terraform Features

### Provider-Defined Functions (1.8+)

Providers can now expose functions directly:

```hcl
# Example with a hypothetical provider function
output "cidr_netmask" {
  value = provider::aws::cidr_netmask("10.0.0.0/24")
}
```

### Ephemeral Values (1.10+)

Mark values as ephemeral to prevent them from being persisted in state:

```hcl
variable "api_token" {
  type      = string
  sensitive = true
  ephemeral = true
}

ephemeral "random_password" "db" {
  length = 32
}
```

### Write-Only Attributes (1.11+)

Some provider attributes can be marked write-only to prevent them from being read back:

```hcl
resource "example_resource" "this" {
  password = var.password  # Write-only attribute
}
```

### Provider for_each (OpenTofu 1.9+)

Configure multiple instances of the same provider:

```hcl
provider "cloudflare" {
  for_each  = var.accounts
  api_token = each.value.token
  alias     = each.key
}
```

Note: This feature is in OpenTofu; check Terraform version for availability.

---

## Common Gotchas

### DNS Import Risks

Importing DNS records incorrectly can break email. Always:
1. Audit all existing records first
2. Write matching Terraform definitions
3. Import records one by one
4. Verify `terraform plan` shows no changes
5. Test email delivery after any DNS changes

### Cloudflare v5 Provider Breaking Changes

The v5 provider is a complete rewrite. Common migration issues:
- Resource renames (`cloudflare_record` → `cloudflare_dns_record`)
- Attribute renames (`value` → `content`)
- Changed resource schemas
- New required attributes

Always check the [v5 migration guide](https://github.com/cloudflare/terraform-provider-cloudflare/blob/main/docs/guides/version-5-upgrade.md).

### Workers Scripts Not Tracked by Terraform

If using Terraform to create Workers while deploying via Wrangler:
- Terraform may show drift on the script content
- Consider not managing the script resource in Terraform at all
- Or use lifecycle `ignore_changes` for content attributes

### R2 CORS and Lifecycle Rules

R2's CORS and lifecycle configurations use S3-compatible APIs. You may need the AWS provider:

```hcl
resource "aws_s3_bucket_cors_configuration" "r2" {
  provider = aws.r2
  bucket   = cloudflare_r2_bucket.assets.id

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["https://example.com"]
  }
}
```

### Checkly Group Overrides Per-Check Settings

In Checkly provider v1, the `checkly_check_group` resource overrides `locations`, `retries`, and alert settings on any `checkly_check` that references it via `group_id`. Per-check values for these attributes are silently ignored. See [checkly/terraform-provider-checkly#332](https://github.com/checkly/terraform-provider-checkly/issues/332).

Mitigation: configure these attributes on the group resource only, and omit them from individual check resources (or keep them for documentation with an inline comment).

### Checkly Free-Tier Quota Halts All Checks

If the 10K/month free-tier quota is exhausted, Checkly halts ALL checks in the account until month rollover. There is no throttle or soft-fail mode. Budget check frequency and location count carefully; adding a second location or halving frequency can exhaust the ceiling.

### GitHub Secrets Visible in State

When you create `github_actions_secret` resources, the `plaintext_value` is stored in state. Mitigations:
- Use ephemeral variables (Terraform 1.10+)
- Encrypt state storage
- Restrict state access
- Consider creating secrets manually for highly sensitive values

### State Locking Race Conditions

Without DynamoDB-style locking, concurrent Terraform runs can corrupt state. Always:
- Use GitHub Actions concurrency groups
- Or enable S3-native locking with `use_lockfile = true` (Terraform 1.10+)
- Never run Terraform from multiple machines simultaneously

---

## References

### Official Documentation

- [HashiCorp Terraform Style Guide](https://developer.hashicorp.com/terraform/language/style)
- [Cloudflare Terraform Best Practices](https://developers.cloudflare.com/terraform/advanced-topics/best-practices/)
- [Cloudflare Provider v5 Documentation](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Checkly Terraform Provider](https://registry.terraform.io/providers/checkly/checkly/latest/docs)
- [GitHub Terraform Provider](https://registry.terraform.io/providers/integrations/github/latest/docs)

### CI/CD and Automation

- [Automate Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [Terraform GitHub Actions](https://github.com/hashicorp/setup-terraform)

### Security

- [Spacelift Terraform Security Guide](https://spacelift.io/blog/terraform-security)
- [Checkov - Policy as Code](https://www.checkov.io/)
- [tfsec - Security Scanner](https://aquasecurity.github.io/tfsec/)

### New Features

- [Terraform 1.10 Ephemeral Values](https://www.hashicorp.com/blog/terraform-1-10-improves-handling-secrets-in-state-with-ephemeral-values)
- [Terraform 1.8 Provider Functions](https://www.hashicorp.com/blog/terraform-1-8-improves-extensibility-with-provider-defined-functions)
- [Terraform 1.7 Testing](https://developer.hashicorp.com/terraform/language/tests)

### Testing

- [Google Cloud Terraform Testing Best Practices](https://cloud.google.com/docs/terraform/best-practices/testing)
- [Terratest](https://terratest.gruntwork.io/)

---

*Last updated: March 2026*
