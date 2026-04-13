# Required environment variables:
#   CLOUDFLARE_API_TOKEN — Scoped API token (zone + workers + R2 permissions)

provider "cloudflare" {}

# Required environment variables:
#   GITHUB_TOKEN — Fine-grained PAT with Administration, Environments permissions
#                  (set as GH_PAT_ADMIN secret in GitHub Actions)

provider "github" {
  owner = "example-org"
}

# Required environment variables:
#   CHECKLY_API_KEY    — API key from Checkly account settings
#   CHECKLY_ACCOUNT_ID — Account ID from Checkly account settings

provider "checkly" {}
