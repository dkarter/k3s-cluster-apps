variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the tunnel and Access resources."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for tnnl.me."
  type        = string
}

variable "admin_access_emails" {
  description = "Administrator email addresses allowed by every Access application."
  type        = set(string)
  sensitive   = true

  validation {
    condition     = length(var.admin_access_emails) > 0
    error_message = "At least one administrator Access email address is required."
  }
}

variable "nextcloud_access_emails" {
  description = "Additional non-administrator email addresses allowed only by Nextcloud."
  type        = set(string)
  sensitive   = true

  validation {
    condition     = length(var.nextcloud_access_emails) > 0
    error_message = "At least one additional Nextcloud Access email address is required."
  }
}

variable "github_access_client_id" {
  description = "OAuth client ID for the GitHub Access identity provider."
  type        = string
  sensitive   = true
}

variable "github_access_client_secret" {
  description = "OAuth client secret for the GitHub Access identity provider."
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Name of the existing remotely managed Cloudflare Tunnel. Preserve its current name when importing."
  type        = string
}
