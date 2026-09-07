resource "cloudflare_dns_record" "this" {
  zone_id = var.zone_id
  name    = var.hostname
  content = "${var.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  ttl     = 1
  proxied = true
  comment = "Managed by Terraform: ${var.name} Cloudflare Tunnel route"
}

resource "cloudflare_zero_trust_access_policy" "default" {
  account_id       = var.account_id
  name             = "${var.name}: allowed emails"
  decision         = "allow"
  session_duration = var.session_duration

  include = [for email in sort(tolist(var.access_emails)) : {
    email = { email = email }
  }]

}

resource "cloudflare_zero_trust_access_policy" "additional" {
  for_each = var.additional_policies

  account_id       = var.account_id
  name             = each.value.name
  decision         = each.value.decision
  include          = each.value.include
  exclude          = each.value.exclude
  require          = each.value.require
  session_duration = each.value.session_duration
}

resource "cloudflare_zero_trust_access_application" "this" {
  account_id                  = var.account_id
  name                        = var.name
  domain                      = var.hostname
  type                        = "self_hosted"
  session_duration            = var.session_duration
  app_launcher_visible        = var.app_launcher_visible
  allowed_idps                = length(var.allowed_idps) > 0 ? var.allowed_idps : null
  allow_authenticate_via_warp = var.allow_authenticate_via_warp
  auto_redirect_to_identity   = var.auto_redirect_to_identity
  enable_binding_cookie       = var.enable_binding_cookie
  http_only_cookie_attribute  = var.http_only_cookie_attribute
  options_preflight_bypass    = var.options_preflight_bypass

  destinations = [{
    type = "public"
    uri  = var.hostname
  }]

  policies = concat(
    [{
      id         = cloudflare_zero_trust_access_policy.default.id
      precedence = 1
    }],
    [for index, key in sort(keys(var.additional_policies)) : {
      id         = cloudflare_zero_trust_access_policy.additional[key].id
      precedence = index + 2
    }],
    [for index, key in sort(keys(var.additional_policy_ids)) : {
      id         = var.additional_policy_ids[key]
      precedence = index + length(var.additional_policies) + 2
    }],
  )
}
