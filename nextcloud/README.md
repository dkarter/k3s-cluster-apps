# Nextcloud Cloudflare Tunnel

Nextcloud is published at `https://nextcloud.tnnl.me` through a remotely managed
Cloudflare Tunnel. The connector runs in the `nextcloud` namespace and reaches
Nextcloud directly through its cluster-local Service. No inbound router port or
public Kubernetes Service is required.

The tunnel token is stored in the `K3s.Pro` 1Password vault as the
`nextcloud-cloudflare-tunnel` item with a `tunnel_token` field. External Secrets
materializes it as the `cloudflare-tunnel-credentials` Kubernetes Secret. Never
commit the token to this repository.

## Cloudflare Account Configuration

These account-level resources cannot be reconstructed by Argo CD. Their desired
configuration now lives in `terraform/cloudflare`; import the existing
resources before the first Terraform plan. Until Terraform is initialized and
applied, the existing dashboard-managed configuration remains authoritative:

1. Follow `terraform/cloudflare/README.md` to import the existing tunnel, tunnel
   configuration, DNS record, Access application, GitHub identity provider, and
   one-time PIN identity provider. The legacy application-local policies are
   replaced by reusable Terraform-managed policies rather than imported.
2. Review the first plan carefully because a remotely managed tunnel has one
   authoritative ingress configuration shared by all published applications.
3. Keep the generated tunnel token in the 1Password item described above.
   Increment `k3s.pro/tunnel-token-revision` in `values.yml` after rotating the
   token so Argo CD rolls the connector pods onto the new value.
4. Terraform declares `nextcloud.tnnl.me` as a Cloudflare Access self-hosted
   application whose policies allow the configured email sets. It inherits the
   account's required independent MFA configuration. This statement describes
   desired state, not proof that it was applied.
5. Keep the dashboard-managed Cache Rule matching
   `http.host eq "nextcloud.tnnl.me"` with cache eligibility set to
   `Bypass cache`; it is intentionally outside this Terraform root.

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
