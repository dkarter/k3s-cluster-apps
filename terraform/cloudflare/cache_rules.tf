resource "cloudflare_ruleset" "cache" {
  zone_id     = var.cloudflare_zone_id
  name        = "default"
  description = "Terraform-managed cache rules for tunneled applications."
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules = [{
    ref         = "nextcloud_cache_bypass"
    description = "Bypass cache for Nextcloud"
    expression  = "(http.host eq \"nextcloud.tnnl.me\")"
    action      = "set_cache_settings"
    enabled     = true
    action_parameters = {
      cache = false
    }
  }]
}
