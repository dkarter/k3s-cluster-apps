resource "cloudflare_zero_trust_access_policy" "nextcloud_only" {
  account_id       = var.cloudflare_account_id
  name             = "Nextcloud: Still Love"
  decision         = "allow"
  session_duration = "24h"

  include = [for email in sort(tolist(var.nextcloud_access_emails)) : {
    email = { email = email }
  }]

}

module "nextcloud" {
  source = "./modules/tunneled-access-app"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  tunnel_id     = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  access_emails = var.admin_access_emails

  additional_policy_ids = {
    still_love = cloudflare_zero_trust_access_policy.nextcloud_only.id
  }

  name        = "Nextcloud"
  hostname    = "nextcloud.tnnl.me"
  service     = "http://nextcloud.nextcloud.svc.cluster.local:80"
  route_order = 10

  allowed_idps = [
    cloudflare_zero_trust_access_identity_provider.github.id,
    cloudflare_zero_trust_access_identity_provider.one_time_pin.id,
    local.google_identity_provider_id,
  ]
  allow_authenticate_via_warp = true
  auto_redirect_to_identity   = false
  enable_binding_cookie       = false
  http_only_cookie_attribute  = false
  options_preflight_bypass    = false
}
