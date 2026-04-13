# Input variable declarations

variable "cloudflare_account_id" {
  description = "Cloudflare account identifier"
  type        = string
  sensitive   = true
}

variable "zone_id_com" {
  description = "Zone ID for the primary .com domain"
  type        = string
  sensitive   = true
}

variable "zone_id_dev" {
  description = "Zone ID for the .dev domain"
  type        = string
  sensitive   = true
}

variable "zone_id_net" {
  description = "Zone ID for the .net domain"
  type        = string
  sensitive   = true
}

variable "access_allowed_email" {
  description = "Email address allowed through the construction gate"
  type        = string
  sensitive   = true
}

variable "protonmail_dkim_cname_target" {
  description = "Proton Mail DKIM CNAME delegation identifier (shared across 3 DKIM records)"
  type        = string
  sensitive   = true
}

variable "protonmail_verification_token" {
  description = "Proton Mail domain ownership verification token"
  type        = string
  sensitive   = true
}

variable "google_site_verification" {
  description = "Google Search Console domain verification token"
  type        = string
  sensitive   = true
}

variable "github_org_verification" {
  description = "GitHub organization domain verification code"
  type        = string
  sensitive   = true
}

variable "resend_dkim_public_key" {
  description = "Resend DKIM public key for the mail sending subdomain"
  type        = string
  sensitive   = true
}

variable "dmarc_rua_email" {
  description = "Email address for DMARC aggregate reports"
  type        = string
  sensitive   = true
}

variable "checkly_alert_email" {
  description = "Email address for Checkly synthetic monitoring alerts"
  type        = string
  sensitive   = true
}
