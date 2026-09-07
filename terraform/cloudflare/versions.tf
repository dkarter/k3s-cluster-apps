terraform {
  required_version = "~> 1.16.0"

  cloud {}

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.24.0"
    }
  }
}
