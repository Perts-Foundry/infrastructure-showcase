terraform {
  required_version = ">= 1.10"

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

  # Required environment variables for backend:
  #   AWS_ACCESS_KEY_ID     — R2 S3-compatible access key
  #   AWS_SECRET_ACCESS_KEY — R2 S3-compatible secret key
  #
  # Backend bucket and endpoint supplied via -backend-config:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for required values.
  backend "s3" {
    key                         = "terraform.tfstate"
    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
