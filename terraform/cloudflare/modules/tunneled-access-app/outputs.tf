output "hostname" {
  description = "Public hostname of this application."
  value       = var.hostname
}

output "access_application_id" {
  description = "Cloudflare Access application ID."
  value       = cloudflare_zero_trust_access_application.this.id
}

output "default_policy_id" {
  description = "Cloudflare Access default policy ID."
  value       = cloudflare_zero_trust_access_policy.default.id
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID."
  value       = cloudflare_dns_record.this.id
}

output "tunnel_route" {
  description = "Route consumed by the root's single tunnel configuration."
  value = {
    hostname       = var.hostname
    origin_request = var.origin_request
    order          = var.route_order
    path           = var.path
    service        = var.service
  }
}
