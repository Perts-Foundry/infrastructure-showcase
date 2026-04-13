# Checkly resources (uptime monitoring, synthetic checks)

locals {
  base_url                  = "https://example.com"
  synthetic_email           = var.checkly_alert_email
  check_frequency           = 60 # minutes. 12 checks x 1 location x 730h = 8,760 base runs/mo; retries add ~2-5% on failures (~9,200 total, 92% of 10K free tier)
  degraded_response_time_ms = 2000
  max_response_time_ms      = 3000
  check_location            = "us-east-1"
  check_tags                = ["website", "production"]

  # Page availability checks. Each check asserts on STATUS_CODE==200 plus every
  # marker in `markers` (AND-combined). Structural markers (DOM IDs, shortcode
  # classes) are validated by the upstream website CI smoke tests, so they
  # change only during deliberate refactors.
  #
  # services_listing, case_studies_listing, and blog_listing all render from
  # list.html and share `data-reveal-stagger`; a second per-page marker (the
  # meta description) disambiguates each match.
  #
  # Privacy, accessibility, and blog_post pages use layouts with no unique
  # structural markers, so they assert on stable editorial text.
  page_checks = {
    homepage = {
      name    = "Homepage"
      path    = "/"
      markers = ["hero-heading"]
    }
    contact_page = {
      name    = "Contact Page"
      path    = "/contact/"
      markers = ["contact-form"]
    }
    services_listing = {
      name    = "Services Listing"
      path    = "/services/"
      markers = ["data-reveal-stagger", "services listing marker"]
    }
    service_page = {
      name    = "Service Page"
      path    = "/services/cloud-infrastructure/"
      markers = ["numbered-steps-wrapper"]
    }
    case_studies_listing = {
      name    = "Case Studies Listing"
      path    = "/case-studies/"
      markers = ["data-reveal-stagger", "case studies listing marker"]
    }
    case_study_page = {
      name    = "Case Study Page"
      path    = "/case-studies/example-case-study/"
      markers = ["tech-tags"]
    }
    about = {
      name    = "About"
      path    = "/about/"
      markers = ["certification-badges"]
    }
    privacy = {
      name    = "Privacy"
      path    = "/privacy/"
      markers = ["privacy policy"]
    }
    accessibility = {
      name    = "Accessibility"
      path    = "/accessibility/"
      markers = ["WCAG 2.1 Level AA"]
    }
    blog_listing = {
      name    = "Blog Listing"
      path    = "/blog/"
      markers = ["data-reveal-stagger", "blog listing marker"]
    }
    blog_post = {
      name    = "Blog Post"
      path    = "/blog/example-post/"
      markers = ["Example blog post opening sentence that is stable across edits"]
    }
  }
}

# =============================================================================
# Alert Channels
# =============================================================================

resource "checkly_alert_channel" "email" {
  email {
    address = local.synthetic_email
  }

  send_recovery = true
  send_failure  = true
  send_degraded = false

  # Foundation resource for all alert delivery; guard against accidental
  # destroy during refactors.
  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Check Groups
# =============================================================================

# Group-level settings override check-level for locations, retries, and alerts.
# This is a Checkly provider v1 API limitation.
# See: github.com/checkly/terraform-provider-checkly/issues/332
#
# concurrency=1 serializes check execution within the group. With 12 checks at
# 60-minute frequency, Checkly spaces them out over the hour, avoiding a burst
# at the top of each hour and bounding alert-email volume during incidents.
#
# If the 10K free-tier quota is exhausted mid-month, Checkly halts ALL checks
# in the account until month rollover. Base usage is 8,760/month; retries on
# failures add ~2-5% (~9,200 total). Adding a second location or dropping
# frequency to 30 minutes would blow the ceiling.
resource "checkly_check_group" "website" {
  name        = "Example Website"
  activated   = true
  muted       = false
  concurrency = 1
  tags        = local.check_tags
  locations   = [local.check_location]

  retry_strategy {
    type                 = "FIXED"
    base_backoff_seconds = 60
    max_retries          = 1
    same_region          = true
  }

  alert_channel_subscription {
    channel_id = checkly_alert_channel.email.id
    activated  = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Page Availability Checks (GET)
# =============================================================================

resource "checkly_check" "page" {
  for_each = local.page_checks

  name                   = each.value.name
  type                   = "API"
  activated              = true
  frequency              = local.check_frequency
  degraded_response_time = local.degraded_response_time_ms
  max_response_time      = local.max_response_time_ms
  group_id               = checkly_check_group.website.id
  tags                   = local.check_tags

  request {
    url = "${local.base_url}${each.value.path}"

    assertion {
      source     = "STATUS_CODE"
      comparison = "EQUALS"
      target     = "200"
    }

    dynamic "assertion" {
      for_each = each.value.markers
      content {
        source     = "TEXT_BODY"
        comparison = "CONTAINS"
        target     = assertion.value
      }
    }
  }
}

# =============================================================================
# API Health Checks (POST)
# =============================================================================

# POST with valid fields but no Turnstile token.
# Expected: 400 + "Please complete the verification challenge."
# This proves: Worker routing, JSON parsing, field validation, and Turnstile
# check all reached without side effects. No emails are sent, no external
# API calls are made. Each execution consumes 1 of 5 in-memory rate-limit
# slots per Checkly source IP per hour (negligible at 60-min intervals).
#
# Use a plus-addressed sender (e.g. monitoring+checkly@yourdomain) via
# var.checkly_alert_email so any log line or audit trail containing this
# address reads unambiguously as synthetic traffic, not a real submission.
resource "checkly_check" "contact_form_api" {
  name                   = "Contact Form API"
  type                   = "API"
  activated              = true
  should_fail            = true # 400 is the expected response; without this, Checkly treats any non-2xx as a check failure regardless of assertions
  frequency              = local.check_frequency
  degraded_response_time = local.degraded_response_time_ms
  max_response_time      = local.max_response_time_ms
  group_id               = checkly_check_group.website.id
  tags                   = local.check_tags

  request {
    url       = "${local.base_url}/api/contact"
    method    = "POST"
    body_type = "JSON"
    body = jsonencode({
      name    = "Checkly Synthetic"
      email   = local.synthetic_email
      message = "Synthetic health check"
    })

    headers = {
      Content-Type = "application/json"
    }

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
