# Infrastructure Showcase

Terraform-managed infrastructure showcase for a solo-consultancy website. Manages Cloudflare (DNS, Workers, R2), GitHub, and Checkly resources with remote state stored in Cloudflare R2.

Domain names, organization, and repository identifiers in this repo have been replaced with [RFC 2606](https://datatracker.ietf.org/doc/html/rfc2606) reserved examples (`example.com`, `example.dev`, `example.net`, `example-org`). The architecture and code are authentic; `terraform apply` will not run cleanly without substituting your own identifiers.

## Prerequisites

- [Terraform](https://www.terraform.io/) >= 1.10
- [direnv](https://direnv.net/) (optional, for loading environment variables)

## Providers

| Provider | Version | Purpose |
|----------|---------|---------|
| [cloudflare/cloudflare](https://registry.terraform.io/providers/cloudflare/cloudflare/latest) | ~> 5.0 | DNS, Workers, R2, zone settings |
| [integrations/github](https://registry.terraform.io/providers/integrations/github/latest) | ~> 6.0 | Repos, secrets, branch protection |
| [checkly/checkly](https://registry.terraform.io/providers/checkly/checkly/latest) | ~> 1.21 | Synthetic uptime monitoring, alerts |

## Environment Variables

Set these before running Terraform:

```sh
# Provider authentication
CLOUDFLARE_API_TOKEN    # Scoped API token (zone + workers + R2 permissions)
GITHUB_TOKEN            # Fine-grained PAT with Administration, Environments permissions
CHECKLY_API_KEY         # User-scoped API key (User Settings > API Keys)
CHECKLY_ACCOUNT_ID      # Account ID (Account Settings > General)

# Remote state backend (Cloudflare R2, S3-compatible)
AWS_ACCESS_KEY_ID       # R2 access key
AWS_SECRET_ACCESS_KEY   # R2 secret key
```

All infrastructure-specific values (account IDs, zone IDs, verification tokens, DKIM keys) are supplied via Terraform variables. See [`terraform.tfvars.example`](terraform.tfvars.example) for the full list. In CI, these are injected as `TF_VAR_*` environment variables from GitHub secrets.

## Usage

```sh
# Copy and fill in backend config and variable values
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## CI/CD

Infrastructure changes are managed through pull requests with GitHub Actions workflows:

1. **Open a PR** — automatically runs `terraform fmt -check`, `terraform validate`, and `terraform plan`, then posts results as a PR comment
2. **Comment `plan`** — re-runs the plan on the current PR head (useful after pushing new commits)
3. **Comment `plan -target='type.name'`** — runs a targeted plan for specific resources (multiple `-target` flags allowed, up to 10)
4. **Comment `apply`** — applies the saved plan and posts the output. Auto-merges only after a full (non-targeted) plan.
5. **Comment `apply -target='type.name'`** — runs a fresh targeted plan and apply without merging

Target addresses must be wrapped in single quotes. This supports all Terraform address forms:

```
plan -target='cloudflare_dns_record.com_root'
plan -target='module.cdn.cloudflare_dns_record.example'
plan -target='cloudflare_dns_record.example["us-east-1"]'
plan -target='cloudflare_dns_record.example[0]'
```

Commands must be the first word in the comment (case-sensitive, lowercase). For example, `plan -target='cloudflare_dns_record.com_root'` works, but `run the plan` does not.

Targeted applies are an operational escape hatch for situations like applying a single urgent fix while other resources have known plan deltas. They are not a substitute for full plan+apply. After any targeted apply, run a full `plan` to reconcile remaining changes, then `apply` to merge. For targeted operations, `plan -target='X'` followed by `apply` is the safer workflow because it lets you review the plan before applying.

The workflow uses a concurrency group to prevent concurrent state modifications. Plan artifacts are SHA-verified to ensure the applied plan matches the current PR head.

Only repository owners, members, and collaborators can trigger `plan` and `apply`.

## File Structure

```
cloudflare.tf    # Cloudflare resources (DNS, Workers, R2, zone settings)
github.tf        # GitHub resources (repos, secrets, branch protection)
checkly.tf       # Checkly resources (synthetic monitoring, alerts)
providers.tf     # Provider configuration
version.tf       # Required versions and backend config
variables.tf     # Input variable declarations
outputs.tf       # Output declarations
```

## Documentation

- [`docs/terraform-best-practices.md`](docs/terraform-best-practices.md) — Comprehensive Terraform guide
- [`docs/cloudflare-workers-playbook.md`](docs/cloudflare-workers-playbook.md) — Workers-specific patterns
- [`docs/github-actions-best-practices.md`](docs/github-actions-best-practices.md) — GitHub Actions security and workflow patterns
- [`docs/building-a-credible-website.md`](docs/building-a-credible-website.md) — Content strategy notes for solo-consultancy sites
