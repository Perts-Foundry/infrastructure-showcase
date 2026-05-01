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

## Sensitive Content

This repository is **public** and is intentionally a sanitized mirror of a
private infrastructure repo. Identifiers throughout (domain, organization,
account/zone IDs, repo names) have been replaced with RFC 2606 reserved
placeholders (`example.com`, `example-org`, `your-cloudflare-account-id`).
The architecture is real; the values are not. Real values must never appear
in the repo, git history, PRs, issues, comments, or release artifacts. The
scope is broad on purpose: git history rewrites are expensive and `gh` API
edits don't scrub everything. The only durable defense is to never let it
land in the first place. CI does NOT run a secret scanner on this repo;
substitution discipline is entirely the author's responsibility.

### What is sensitive

- **Real Cloudflare account ID and zone IDs.** `account_id` appears in
  the R2 backend endpoint (`<account-id>.r2.cloudflarestorage.com`) and
  in every zone resource via `local.account_id`. Zone IDs identify the
  real domains. All of these belong in `terraform.tfvars` (gitignored),
  not in any `.tf` file or example file.
- **Real domain names** owned by the operator. The repo uses
  `example.com`, `example.dev`, `example.net` as stand-ins. Any commit,
  variable description, output description, comment, or commit message
  that names a real domain is a leak — including tab-completed paths,
  log snippets, and screenshots embedded in PR bodies.
- **Real organization, GitHub repo, and user names** beyond the public
  showcase repo itself. The private upstream uses real names; the
  public mirror must not.
- **API tokens and credentials**: Cloudflare API tokens, GitHub PATs /
  fine-grained tokens, Checkly user-scoped API keys, R2 access key IDs
  and secret access keys, ProtonMail / Resend / Google verification
  tokens. None of these belong in `.tf` files, `.tfvars` files (even
  gitignored), `backend.hcl`, workflow YAML, or commit messages. Inject
  via GitHub Actions repo / environment secrets at apply time.
- **Backend state values**: real R2 bucket names, account-bearing
  endpoints, and any access keys for the state backend. `backend.hcl`
  is gitignored; `backend.hcl.example` ships with placeholder values
  only.
- **Real `terraform.tfvars`**. Only `terraform.tfvars.example` ships,
  and only with placeholder values. Any change that adds a new variable
  must land in `.example` with a placeholder, not the real value.
- **Terraform state and plan output**. State files (`*.tfstate`,
  `*.tfstate.backup`, `.terraform/`) and plan binaries (`*.tfplan`)
  carry resolved values for `sensitive = true` variables and must never
  be committed. Plan output rendered into PR comments by the workflow
  must rely on the provider's `sensitive` redaction — do not paste a
  verbose `terraform show -json` decode into a comment.
- **Real Checkly group / check IDs and alert-channel addresses** if
  attached to a real account. Use synthetic addresses
  (`monitoring@example.com`) in any committed file.
- **Local-only filesystem paths**: `~/repos/...`, `/home/<user>/...`,
  internal corp paths. These should not appear in code, comments,
  commit messages, or PR bodies.
- **Cross-references to the private upstream** that name the real
  account or domain. Generic references ("the upstream private repo")
  are fine; references that disclose its name, owner, or contents are
  not.

### What is NOT sensitive (and is fine to commit)

- The RFC 2606 placeholders themselves (`example.com`, `example.dev`,
  `example.net`, `example-org`, `your-*-id`, etc.). These are the
  intended substitutes.
- Provider versions, resource type names, and Terraform syntax — the
  whole point of the showcase is to share the architecture.
- Public Cloudflare-published nameservers, generic Anycast IPs, and
  documented Cloudflare endpoint hostnames (`api.cloudflare.com`,
  `*.r2.cloudflarestorage.com` *without* an account-ID subdomain).
- Documented vendor endpoint hostnames (e.g., `mail.protonmail.ch`).
  Per-tenant tokens and DKIM CNAME delegation IDs are NOT public —
  they belong in tfvars.
- The `backend.hcl.example` and `terraform.tfvars.example` template
  files, as long as they only contain placeholders.
- Generic playbooks under `docs/` written against the showcase
  architecture.

### Pre-push checklist

Before every `git push`, every `gh pr create`, every `gh pr comment`,
and every `gh issue create`:

1. **Diff against the placeholder set.** `git diff main..HEAD` and
   `git log main..HEAD --format=%B`, then grep for: any real domain
   the operator owns, the real Cloudflare account ID prefix, real R2
   bucket name, GitHub org / repo names beyond the showcase, hex-shaped
   tokens (32+ hex chars), and `r2.cloudflarestorage.com` lines that
   contain a non-placeholder subdomain.
2. **Sync-from-upstream guard.** If this push includes content
   cherry-picked or copied from the private upstream, re-run the
   substitution pass before pushing. Verify that no real value sneaked
   through in variable *descriptions*, output descriptions, locals, or
   comments — sanitization is most often missed in prose, not code.
3. **Scan the rendered PR / issue / comment body** for the same
   categories — content typed into `gh pr create --body` does not pass
   through the diff scan.
4. **Confirm `terraform.tfvars`, `backend.hcl`, and `.terraform/`** are
   not staged (gitignored, but verify on every push).
5. If anything sensitive is found:
   - **Pre-push (history not yet on remote)**: rewrite history with
     `git filter-branch --tree-filter` + `--msg-filter` (or
     `git filter-repo` if available). Replace with the appropriate
     placeholder. Re-run all checks before pushing the rewritten
     branch.
   - **Already on remote**: stop. Surface to the user before any
     further action — force-pushing rewritten history to a public
     repo is a visible event that warrants explicit consent. For a
     confirmed token or key, treat it as compromised and rotate it in
     addition to (not instead of) history rewriting. Cloudflare,
     GitHub, and Checkly all support immediate token rotation — do
     that first, then triage history.
6. Adopt a redacted-by-default mindset for **future** commit messages
   and doc entries: describe the resource and the change, not the
   real-world domain or account that prompted it.

### Memory notes

Memory files under `~/.claude/projects/.../memory/` may contain real
domain names, account IDs, or upstream repo paths **for the
assistant's use only**. Never paste memory content into the public
repo; treat memory as a private context store, not a documentation
source.

## Key Documentation

- `docs/terraform-best-practices.md` - Comprehensive Terraform guide
- `docs/cloudflare-workers-playbook.md` - Workers-specific patterns
- `docs/github-actions-best-practices.md` - GitHub Actions security and workflow patterns
