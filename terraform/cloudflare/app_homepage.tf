module "homepage" {
  source = "./modules/tunneled-access-app"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  tunnel_id     = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  access_emails = var.admin_access_emails
  allowed_idps  = [cloudflare_zero_trust_access_identity_provider.github.id]

  name        = "Homepage"
  hostname    = "homepage.tnnl.me"
  service     = "http://homepage.homepage.svc.cluster.local:3000"
  route_order = 20

  # Homepage currently allows only home.k3s.pro in HOMEPAGE_ALLOWED_HOSTS.
  origin_request = {
    http_host_header = "home.k3s.pro"
  }
}
