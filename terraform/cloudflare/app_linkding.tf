module "linkding" {
  source = "./modules/tunneled-access-app"

  account_id    = var.cloudflare_account_id
  zone_id       = var.cloudflare_zone_id
  tunnel_id     = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  access_emails = var.admin_access_emails
  allowed_idps  = [cloudflare_zero_trust_access_identity_provider.github.id]

  name        = "Linkding"
  hostname    = "linkding.tnnl.me"
  service     = "http://linkding.linkding.svc.cluster.local:9090"
  route_order = 40
}
