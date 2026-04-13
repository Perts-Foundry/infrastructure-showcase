# Infrastructure Showcase

This repository is a Terraform-managed infrastructure showcase for a solo-consultancy website using Cloudflare (Workers, R2, DNS), GitHub, and Checkly providers. Identifiers throughout (domain, organization, repo names) have been replaced with RFC 2606 reserved placeholders (`example.com`, `example-org`, etc.); the architecture and code are real.

## Terraform Best Practices

### File Organization

Organize by cloud provider with one file per provider:

```
cloudflare.tf   # All Cloudflare resources (DNS, Workers, R2, zone settings)
github.tf       # All GitHub resources (repos, secrets, branch protection)
checkly.tf      # All Checkly resources (synthetic monitoring, alerts)
providers.tf    # Provider configuration
version.tf      # Required versions and backend config
variables.tf    # Input variable declarations
outputs.tf      # Output declarations
```

### Code Style

- Two-space indentation
- Underscore naming (`proton_mail_mx`, not `proton-mail-mx`)
- No type redundancy in names (`mx_primary`, not `mx_primary_record`)
- Use `#` for comments only
- Meta-arguments first (count, for_each, provider, depends_on), then required args, then optional, then lifecycle

### State Management

- Remote state in R2 (S3-compatible backend)
- Never commit state files
- Do not commit `.terraform.lock.hcl`
- Use GitHub Actions concurrency groups for state locking

### Security

- Mark sensitive variables with `sensitive = true`
- Use scoped API tokens with minimum required permissions
- Never hardcode credentials
- Always run `terraform fmt -recursive` and `terraform validate` after any Terraform changes before committing

### Provider-Specific Notes

**Cloudflare v5:**
- Resource names changed from v4 (`cloudflare_record` → `cloudflare_dns_record`, `value` → `content`)
- Import existing DNS records before adding new ones to avoid breaking email
- Let Wrangler manage Worker deployments; Terraform manages surrounding infrastructure

**GitHub:**
- Secrets created via Terraform appear in state files
- Use ephemeral variables (Terraform 1.10+) for sensitive values

**Checkly:**
- Group-level settings override check-level for locations, retries, and alerts (provider v1 API limitation, see checkly/terraform-provider-checkly#332); configure these on the check group, not on individual checks
- Free tier is 10,000 check runs/month; exhaustion halts ALL checks in the account until month rollover
- Current budget: 12 checks x 1 location x 60-minute frequency = ~8,760 base runs/month; retries on failures add ~2-5% (~9,200 total, 92% of tier)
- User-scoped API key authenticates as the user that created it; rotate on user offboarding

### Importing Existing Resources

Always use `import` blocks in `.tf` files instead of the `terraform import` CLI command. Import blocks are declarative, reviewable in PRs, and run automatically on apply.

```hcl
import {
  to = cloudflare_dns_record.example
  id = "<zone_id>/<record_id>"
}
```

When importing existing DNS:
1. Audit all existing records first
2. Write matching Terraform definitions with `import` blocks
3. Verify `terraform plan` shows no changes (only imports) before proceeding
4. Remove `import` blocks after successful apply
5. Test email delivery after any DNS changes

## Key Documentation

- `docs/terraform-best-practices.md` - Comprehensive Terraform guide
- `docs/cloudflare-workers-playbook.md` - Workers-specific patterns
- `docs/github-actions-best-practices.md` - GitHub Actions security and workflow patterns
