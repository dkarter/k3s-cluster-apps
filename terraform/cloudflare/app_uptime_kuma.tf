module "uptime_kuma" {
  source = "./modules/tunneled-access-app"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  tunnel_id     = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  access_emails = var.admin_access_emails
  allowed_idps  = [cloudflare_zero_trust_access_identity_provider.github.id]

  name        = "Uptime Kuma"
  hostname    = "uptime.tnnl.me"
  service     = "http://uptime-kuma.uptime.svc.cluster.local:3001"
  route_order = 70
}
