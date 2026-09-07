resource "cloudflare_zero_trust_tunnel_cloudflared" "shared" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  tunnel_routes = {
    for route in [
      module.nextcloud.tunnel_route,
      module.homepage.tunnel_route,
      module.jellyfin.tunnel_route,
      module.linkding.tunnel_route,
      module.memos.tunnel_route,
      module.uptime_kuma.tunnel_route,
    ] : format("%05d-%s", route.order, route.hostname) => route
  }
}

# A remotely managed tunnel has exactly one configuration. App modules only
# contribute route data so they cannot create competing configuration resources.
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "shared" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.shared.id
  source     = "cloudflare"

  config = {
    ingress = concat(
      [for route in values(local.tunnel_routes) : {
        hostname       = route.hostname
        path           = route.path
        service        = route.service
        origin_request = route.origin_request
      }],
      [{
        hostname       = null
        path           = null
        service        = "http_status:404"
        origin_request = null
      }],
    )
  }
}
