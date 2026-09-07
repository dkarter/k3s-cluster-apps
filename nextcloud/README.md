# Nextcloud Cloudflare Access

Nextcloud is published at `https://nextcloud.tnnl.me` through a remotely managed
Cloudflare Tunnel. The shared connector runs in the `cloudflare-tunnel` namespace
and reaches Nextcloud directly through its cluster-local Service. No inbound
router port or public Kubernetes Service is required.

The tunnel token is stored in the `K3s.Pro` 1Password vault as the
`nextcloud-cloudflare-tunnel` item with a `tunnel_token` field. External Secrets
materializes it as the `cloudflare-tunnel-credentials` Kubernetes Secret in the
connector namespace. Never commit the token to this repository.

## Cloudflare Account Configuration

The account-level desired configuration lives in `terraform/cloudflare` and
includes the tunnel ingress, DNS record, Access application and policies,
identity providers, and a cache-bypass rule for `nextcloud.tnnl.me`. The Access
application inherits the account's required independent MFA configuration.

Keep the generated tunnel token in the 1Password item described above. Increment
`k3s.pro/tunnel-token-revision` in `cloudflare-tunnel/values.yml` after rotating
the token so Argo CD rolls the connector pods onto the new value.

`https://nextcloud.k3s.pro` remains the canonical local and Tailscale endpoint.
It is served by Traefik and is not routed through the Cloudflare Tunnel. Use it
for desktop, mobile, and WebDAV clients because Cloudflare Access interactive
authentication is generally incompatible with those clients.

Cloudflare Free and Pro limit each upload request to 100 MB. Nextcloud is
configured to advertise 50 MiB chunks so authenticated web and compatible sync
clients can upload larger files. Test each client type before relying on it;
clients that do not support chunking still cannot upload files over Cloudflare's
per-request limit.

Two connector replicas are spread across worker nodes. Each connector maintains
multiple edge connections, so a pod restart or single worker outage does not
take the public route offline.

Cloudflare Access means links under `nextcloud.tnnl.me` are not anonymously public:
recipients must first satisfy the Access policy and then any Nextcloud share
requirements. Public links using the canonical `nextcloud.k3s.pro` hostname are
reachable only from the local network or Tailscale.
