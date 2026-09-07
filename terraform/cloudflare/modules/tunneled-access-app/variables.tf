variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID containing the public hostname."
  type        = string
}

variable "tunnel_id" {
  description = "ID of the shared Cloudflare Tunnel."
  type        = string
}

variable "name" {
  description = "Human-readable Access application name."
  type        = string
}

variable "hostname" {
  description = "Public hostname routed through Cloudflare."
  type        = string
}

variable "service" {
  description = "Cluster-local service URL used by cloudflared."
  type        = string
}

variable "route_order" {
  description = "Unique route order in the shared tunnel configuration."
  type        = number
}

variable "path" {
  description = "Optional path expression for this tunnel route."
  type        = string
  default     = null
}

variable "origin_request" {
  description = "Optional cloudflared origin request overrides."
  type = object({
    connect_timeout          = optional(number)
    disable_chunked_encoding = optional(bool)
    http2_origin             = optional(bool)
    http_host_header         = optional(string)
    keep_alive_connections   = optional(number)
    keep_alive_timeout       = optional(number)
    match_sn_ito_host        = optional(bool)
    no_happy_eyeballs        = optional(bool)
    no_tls_verify            = optional(bool)
    origin_server_name       = optional(string)
    proxy_type               = optional(string)
    tcp_keep_alive           = optional(number)
    tls_timeout              = optional(number)
  })
  default = null
}

variable "access_emails" {
  description = "Email addresses included by the default allow policy."
  type        = set(string)
  sensitive   = true
}

variable "session_duration" {
  description = "Access application and default policy session duration."
  type        = string
  default     = "24h"
}

variable "app_launcher_visible" {
  description = "Show the application in the Cloudflare Access app launcher."
  type        = bool
  default     = true
}

variable "allowed_idps" {
  description = "Optional set of identity provider IDs allowed for this app."
  type        = set(string)
  default     = []
}

variable "allow_authenticate_via_warp" {
  description = "Allow authentication through Cloudflare WARP when explicitly configured."
  type        = bool
  default     = null
}

variable "auto_redirect_to_identity" {
  description = "Automatically redirect to the identity provider when explicitly configured."
  type        = bool
  default     = null
}

variable "enable_binding_cookie" {
  description = "Enable Access binding cookies when explicitly configured."
  type        = bool
  default     = null
}

variable "http_only_cookie_attribute" {
  description = "Set the HttpOnly attribute on Access cookies when explicitly configured."
  type        = bool
  default     = null
}

variable "options_preflight_bypass" {
  description = "Bypass Access for CORS preflight requests when explicitly configured."
  type        = bool
  default     = null
}

variable "additional_policies" {
  description = "Additional reusable Access policies attached after the default policy. Rules use the provider's include/exclude/require object shapes."
  type = map(object({
    name             = string
    decision         = string
    include          = list(any)
    exclude          = optional(list(any), [])
    require          = optional(list(any), [])
    session_duration = optional(string, "24h")
  }))
  default = {}
}

variable "additional_policy_ids" {
  description = "Additional reusable Access policy IDs attached after policies created by this module."
  type        = map(string)
  default     = {}
}
