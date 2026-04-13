# Cloudflare resources (DNS, Workers, R2, zone settings, redirect rules)

locals {
  account_id  = var.cloudflare_account_id
  zone_id_com = var.zone_id_com
  zone_id_dev = var.zone_id_dev
  zone_id_net = var.zone_id_net
}

# =============================================================================
# Zones
# =============================================================================

resource "cloudflare_zone" "example_com" {
  name                = "example.com"
  paused              = false
  type                = "full"
  vanity_name_servers = []
  account = {
    id = local.account_id
  }
}

resource "cloudflare_zone" "example_dev" {
  name                = "example.dev"
  paused              = false
  type                = "full"
  vanity_name_servers = []
  account = {
    id = local.account_id
  }
}

resource "cloudflare_zone" "example_net" {
  name                = "example.net"
  paused              = false
  type                = "full"
  vanity_name_servers = []
  account = {
    id = local.account_id
  }
}

# =============================================================================
# DNS Records — example.com
# =============================================================================

# Proton Mail MX records

resource "cloudflare_dns_record" "com_mx_primary" {
  comment  = "Proton Mail mx record 1"
  content  = "mail.protonmail.ch"
  name     = "example.com"
  priority = 10
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "MX"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_mx_secondary" {
  comment  = "Proton Mail mx record 2"
  content  = "mailsec.protonmail.ch"
  name     = "example.com"
  priority = 20
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "MX"
  zone_id  = local.zone_id_com
  settings = {}
}

# Proton Mail DKIM records

resource "cloudflare_dns_record" "com_dkim_1" {
  comment = "Proton Mail DKIM 1"
  content = "protonmail.domainkey.${var.protonmail_dkim_cname_target}.domains.proton.ch"
  name    = "protonmail._domainkey.example.com"
  proxied = false
  tags    = []
  ttl     = 300
  type    = "CNAME"
  zone_id = local.zone_id_com
  settings = {
    flatten_cname = false
  }
}

resource "cloudflare_dns_record" "com_dkim_2" {
  comment = "Proton Mail DKIM 2"
  content = "protonmail2.domainkey.${var.protonmail_dkim_cname_target}.domains.proton.ch"
  name    = "protonmail2._domainkey.example.com"
  proxied = false
  tags    = []
  ttl     = 300
  type    = "CNAME"
  zone_id = local.zone_id_com
  settings = {
    flatten_cname = false
  }
}

resource "cloudflare_dns_record" "com_dkim_3" {
  comment = "Proton Mail DKIM 3"
  content = "protonmail3.domainkey.${var.protonmail_dkim_cname_target}.domains.proton.ch"
  name    = "protonmail3._domainkey.example.com"
  proxied = false
  tags    = []
  ttl     = 300
  type    = "CNAME"
  zone_id = local.zone_id_com
  settings = {
    flatten_cname = false
  }
}

# Proton Mail TXT records

resource "cloudflare_dns_record" "com_spf" {
  comment  = "Proton Mail SPF config"
  content  = "\"v=spf1 include:_spf.protonmail.ch ~all\""
  name     = "example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_dmarc" {
  comment  = "Proton Mail DMARC config"
  content  = "\"v=DMARC1; p=quarantine\""
  name     = "_dmarc.example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_protonmail_verification" {
  comment  = "Proton Mail domain registration"
  content  = "\"protonmail-verification=${var.protonmail_verification_token}\""
  name     = "example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_google_search_console" {
  comment  = "Google Search Console domain verification"
  content  = "\"google-site-verification=${var.google_site_verification}\""
  name     = "example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_github_org_verification" {
  comment  = "GitHub organization domain verification"
  content  = "\"${var.github_org_verification}\""
  name     = "_gh-example-org-o.example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

# Resend email sending records (mail.example.com subdomain)

resource "cloudflare_dns_record" "com_dkim_resend" {
  comment  = "Resend DKIM verification for mail.example.com"
  content  = "\"p=${var.resend_dkim_public_key}\""
  name     = "resend._domainkey.mail.example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_mx_resend_bounce" {
  comment  = "Resend MX record for bounce handling"
  content  = "feedback-smtp.us-east-1.amazonses.com"
  name     = "bounce.mail.example.com"
  priority = 10
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "MX"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_spf_resend_bounce" {
  comment  = "Resend SPF record for bounce handling"
  content  = "\"v=spf1 include:amazonses.com ~all\""
  name     = "bounce.mail.example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_dmarc_resend" {
  comment  = "DMARC policy for mail.example.com sending subdomain"
  content  = "\"v=DMARC1; p=quarantine; rua=mailto:${var.dmarc_rua_email}\""
  name     = "_dmarc.mail.example.com"
  proxied  = false
  tags     = []
  ttl      = 300
  type     = "TXT"
  zone_id  = local.zone_id_com
  settings = {}
}

# =============================================================================
# DNS Records — example.dev
# =============================================================================

resource "cloudflare_dns_record" "dev_redirect_root" {
  comment  = "Config for example.com redirect"
  content  = "192.0.2.1"
  name     = "example.dev"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_dev
  settings = {}
}

resource "cloudflare_dns_record" "dev_redirect_www" {
  comment  = "Config for example.com redirect"
  content  = "192.0.2.1"
  name     = "www.example.dev"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_dev
  settings = {}
}

# =============================================================================
# DNS Records — example.net
# =============================================================================

resource "cloudflare_dns_record" "net_redirect_root" {
  comment  = "Config for example.com redirect"
  content  = "192.0.2.1"
  name     = "example.net"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_net
  settings = {}
}

resource "cloudflare_dns_record" "net_redirect_www" {
  comment  = "Config for example.com redirect"
  content  = "192.0.2.1"
  name     = "www.example.net"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_net
  settings = {}
}

# =============================================================================
# Zone Settings — example.com
# =============================================================================

resource "cloudflare_zone_setting" "com_ssl" {
  zone_id    = local.zone_id_com
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "com_always_use_https" {
  zone_id    = local.zone_id_com
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "com_min_tls_version" {
  zone_id    = local.zone_id_com
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "com_tls_1_3" {
  zone_id    = local.zone_id_com
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "com_automatic_https_rewrites" {
  zone_id    = local.zone_id_com
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

# =============================================================================
# Zone Settings — example.dev
# =============================================================================

resource "cloudflare_zone_setting" "dev_ssl" {
  zone_id    = local.zone_id_dev
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "dev_always_use_https" {
  zone_id    = local.zone_id_dev
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "dev_min_tls_version" {
  zone_id    = local.zone_id_dev
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "dev_tls_1_3" {
  zone_id    = local.zone_id_dev
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "dev_automatic_https_rewrites" {
  zone_id    = local.zone_id_dev
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

# =============================================================================
# Zone Settings — example.net
# =============================================================================

resource "cloudflare_zone_setting" "net_ssl" {
  zone_id    = local.zone_id_net
  setting_id = "ssl"
  value      = "strict"
}

resource "cloudflare_zone_setting" "net_always_use_https" {
  zone_id    = local.zone_id_net
  setting_id = "always_use_https"
  value      = "on"
}

resource "cloudflare_zone_setting" "net_min_tls_version" {
  zone_id    = local.zone_id_net
  setting_id = "min_tls_version"
  value      = "1.2"
}

resource "cloudflare_zone_setting" "net_tls_1_3" {
  zone_id    = local.zone_id_net
  setting_id = "tls_1_3"
  value      = "on"
}

resource "cloudflare_zone_setting" "net_automatic_https_rewrites" {
  zone_id    = local.zone_id_net
  setting_id = "automatic_https_rewrites"
  value      = "on"
}

# =============================================================================
# Workers — example-website
# =============================================================================
# Worker script deployed by Wrangler in the example-website repo.
# Terraform manages DNS, routing, and redirect rules.

resource "cloudflare_dns_record" "com_root" {
  comment  = "Workers custom domain — apex"
  content  = "192.0.2.1"
  name     = "example.com"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_dns_record" "com_www" {
  comment  = "www — redirected to apex by redirect rule"
  content  = "192.0.2.1"
  name     = "www.example.com"
  proxied  = true
  tags     = []
  ttl      = 1
  type     = "A"
  zone_id  = local.zone_id_com
  settings = {}
}

resource "cloudflare_workers_route" "com_root" {
  zone_id = local.zone_id_com
  pattern = "example.com/*"
  script  = "example-website"
}

# =============================================================================
# Redirect Rules
# =============================================================================

resource "cloudflare_ruleset" "com_redirects" {
  zone_id = local.zone_id_com
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    action      = "redirect"
    expression  = "(http.host eq \"www.example.com\")"
    description = "Redirect www to apex"
    enabled     = true
    action_parameters = {
      from_value = {
        target_url = {
          expression = "concat(\"https://example.com\", http.request.uri.path)"
        }
        status_code           = 301
        preserve_query_string = true
      }
    }
  }]
}

resource "cloudflare_ruleset" "dev_redirects" {
  zone_id = local.zone_id_dev
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    action      = "redirect"
    expression  = "(http.host eq \"example.dev\") or (http.host eq \"www.example.dev\")"
    description = "Redirect to canonical .com domain"
    enabled     = true
    action_parameters = {
      from_value = {
        target_url = {
          expression = "concat(\"https://example.com\", http.request.uri.path)"
        }
        status_code           = 301
        preserve_query_string = true
      }
    }
  }]
}

resource "cloudflare_ruleset" "net_redirects" {
  zone_id = local.zone_id_net
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    action      = "redirect"
    expression  = "(http.host eq \"example.net\") or (http.host eq \"www.example.net\")"
    description = "Redirect to canonical .com domain"
    enabled     = true
    action_parameters = {
      from_value = {
        target_url = {
          expression = "concat(\"https://example.com\", http.request.uri.path)"
        }
        status_code           = 301
        preserve_query_string = true
      }
    }
  }]
}

# =============================================================================
# Response Header Transform Rules
# =============================================================================

resource "cloudflare_ruleset" "com_response_headers" {
  zone_id = local.zone_id_com
  name    = "default"
  kind    = "zone"
  phase   = "http_response_headers_transform"

  rules = [
    {
      ref         = "security_headers"
      action      = "rewrite"
      expression  = "ssl"
      description = "Add security headers to HTTPS responses (HSTS on HTTP violates RFC 6797 §8.1 and triggers hstspreload.org warnings)"
      enabled     = true
      action_parameters = {
        headers = {
          "X-Content-Type-Options" = {
            operation = "set"
            value     = "nosniff"
          }
          "X-Frame-Options" = {
            operation = "set"
            value     = "DENY"
          }
          "Referrer-Policy" = {
            operation = "set"
            value     = "strict-origin-when-cross-origin"
          }
          "Permissions-Policy" = {
            operation = "set"
            value     = "camera=(), microphone=(), geolocation=()"
          }
          "X-XSS-Protection" = {
            operation = "set"
            value     = "0"
          }
          "Strict-Transport-Security" = {
            operation = "set"
            value     = "max-age=31536000; includeSubDomains; preload"
          }
          # unsafe-inline is required: the site theme uses inline scripts
          # and dynamic style manipulation throughout its templates.
          "Content-Security-Policy" = {
            operation = "set"
            value     = "default-src 'self'; script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-src https://challenges.cloudflare.com; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'; upgrade-insecure-requests"
          }
          "Cross-Origin-Opener-Policy" = {
            operation = "set"
            value     = "same-origin"
          }
        }
      }
    },
    # Rules 1 and 2 compose correctly: rule 1 sets security headers on all
    # responses, rule 2 adds Cache-Control on asset paths. They set disjoint
    # header names, so both apply without conflict on matching requests.
    {
      ref         = "immutable_cache_assets"
      action      = "rewrite"
      expression  = "(starts_with(http.request.uri.path, \"/css/\") or starts_with(http.request.uri.path, \"/js/\") or starts_with(http.request.uri.path, \"/lib/\"))"
      description = "Immutable cache for fingerprinted CSS, JS, and lib assets"
      enabled     = true
      action_parameters = {
        headers = {
          "Cache-Control" = {
            operation = "set"
            value     = "public, max-age=31556952, immutable"
          }
        }
      }
    },
  ]
}

# =============================================================================
# WAF Rate Limiting
# =============================================================================

resource "cloudflare_ruleset" "contact_rate_limit" {
  zone_id     = local.zone_id_com
  name        = "Contact form rate limiting"
  description = "Rate limit /api/contact endpoint"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [{
    action = "block"
    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      requests_per_period = 3
      mitigation_timeout  = 10
    }
    expression  = "(http.request.uri.path eq \"/api/contact\" and http.request.method eq \"POST\")"
    description = "Rate limit contact form submissions"
    enabled     = true
  }]
}

# =============================================================================
# Zero Trust Access — construction gate (remove when site goes live)
# =============================================================================

# Import block removed after initial import. To adopt an existing identity
# provider, use: import { to = ...otp  id = "accounts/<account_id>/<idp_id>" }

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = local.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

resource "cloudflare_zero_trust_access_policy" "construction_gate" {
  account_id = local.account_id
  name       = "Allow owner email"

  # Site is public; policy is left in place as a bypass so re-gating is a
  # one-line revert. To re-gate: change decision back to "allow" and restore
  # the email include below.
  decision = "bypass"
  include = [{
    everyone = {}
  }]

  # decision = "allow"
  # include = [{
  #   email = {
  #     email = var.access_allowed_email
  #   }
  # }]
}

resource "cloudflare_zero_trust_access_application" "example_com" {
  account_id       = local.account_id
  name             = "Example Site - Under Construction"
  type             = "self_hosted"
  domain           = "example.com"
  session_duration = "720h"
  destinations = [
    { uri = "example.com" },
    { uri = "www.example.com" },
  ]

  policies = [{
    id         = cloudflare_zero_trust_access_policy.construction_gate.id
    precedence = 1
  }]
}

