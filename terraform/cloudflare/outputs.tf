output "tunnel_id" {
  description = "ID of the shared remotely managed tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.shared.id
}

output "application_hostnames" {
  description = "Public hostnames managed by this root."
  value = sort([
    module.nextcloud.hostname,
    module.homepage.hostname,
    module.jellyfin.hostname,
    module.linkding.hostname,
    module.memos.hostname,
    module.uptime_kuma.hostname,
  ])
}
