module "memos" {
  source = "./modules/tunneled-access-app"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  tunnel_id     = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  access_emails = var.admin_access_emails
  allowed_idps  = [cloudflare_zero_trust_access_identity_provider.github.id]

  name        = "Memos"
  hostname    = "memos.tnnl.me"
  service     = "http://memos-service.memos.svc.cluster.local:5230"
  route_order = 50
}
