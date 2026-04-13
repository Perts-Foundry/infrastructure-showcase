# GitHub resources (repos, rulesets, Dependabot)
#
# To add a new repo: add an entry to local.repositories, then run
# terraform plan to verify. Shared settings are defined once on each
# resource block; per-repo config lives in the map.

locals {
  repositories = {
    infrastructure = {
      description      = "Infrastructure as Code showcase (Terraform + Cloudflare + GitHub + Checkly)"
      topics           = ["terraform", "cloudflare", "github", "checkly", "infrastructure-as-code"]
      ci_check_context = "plan"
    }
    example_website = {
      name             = "example-website"
      description      = "Hugo static site for a technical consultancy."
      homepage_url     = "https://example.com"
      topics           = ["hugo", "cloudflare-workers", "static-site"]
      ci_check_context = "validate"
    }
    example_portfolio_source = {
      name             = "example-portfolio-source"
      description      = "Second repo managed by this org (illustrative)."
      topics           = ["yaml"]
      ci_check_context = "validate"
    }
    example_resume_tool = {
      name             = "example-resume-tool"
      description      = "Third repo managed by this org (illustrative)."
      homepage_url     = "https://example.com"
      topics           = ["python", "cli"]
      ci_check_context = "validate"
    }
  }
}

# =============================================================================
# Repositories
# =============================================================================

resource "github_repository" "repo" {
  for_each = local.repositories

  name         = try(each.value.name, replace(each.key, "_", "-"))
  description  = each.value.description
  visibility   = "private"
  homepage_url = try(each.value.homepage_url, null)
  topics       = each.value.topics

  has_issues             = false
  has_projects           = false
  has_wiki               = false
  delete_branch_on_merge = true
  allow_update_branch    = true
  allow_squash_merge     = true
  allow_merge_commit     = false
  allow_rebase_merge     = false
  vulnerability_alerts   = true
}

# =============================================================================
# Dependabot Security Updates
# =============================================================================

resource "github_repository_dependabot_security_updates" "repo" {
  for_each   = local.repositories
  repository = github_repository.repo[each.key].name
  enabled    = true
}

# =============================================================================
# Repository Rulesets
# =============================================================================
#
# Rulesets require GitHub Pro for private repos (free tier returns 403).
# Uncomment this block when repos go public or the org upgrades to Pro.
# Each repo gets a main-branch ruleset enforcing status checks, PR review,
# no force-push, and no branch deletion. OrganizationAdmin bypass allows
# the sole maintainer to self-merge.
#
# resource "github_repository_ruleset" "main" {
#   for_each = local.repositories
#
#   name        = "main-protection"
#   repository  = github_repository.repo[each.key].name
#   target      = "branch"
#   enforcement = "active"
#
#   conditions {
#     ref_name {
#       include = ["~DEFAULT_BRANCH"]
#       exclude = []
#     }
#   }
#
#   bypass_actors {
#     actor_id    = 1
#     actor_type  = "OrganizationAdmin"
#     bypass_mode = "always"
#   }
#
#   rules {
#     required_status_checks {
#       required_check {
#         context = each.value.ci_check_context
#       }
#       strict_required_status_checks_policy = true
#     }
#
#     pull_request {
#       required_approving_review_count   = 1
#       dismiss_stale_reviews_on_push     = false
#       require_code_owner_review         = false
#       require_last_push_approval        = false
#       required_review_thread_resolution = true
#     }
#
#     non_fast_forward = true
#     deletion         = true
#   }
#
#   lifecycle {
#     prevent_destroy = true
#   }
# }

