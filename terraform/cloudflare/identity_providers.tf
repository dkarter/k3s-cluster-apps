resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = var.cloudflare_account_id
  name       = "GitHub"
  type       = "github"

  config = {
    client_id     = var.github_access_client_id
    client_secret = var.github_access_client_secret
  }
}

resource "cloudflare_zero_trust_access_identity_provider" "one_time_pin" {
  account_id = var.cloudflare_account_id
  name       = ""
  type       = "onetimepin"
  config     = {}
}

locals {
  # Google stays ID-only because its original OAuth client secret is unavailable.
  google_identity_provider_id = "41e301a5-6d0f-43ab-84a8-838dee6c9286"
}
