# Cloudflare Terraform

This root manages public DNS, Cloudflare Access, and the remote configuration
for one shared Cloudflare Tunnel. Internal application addresses remain
`<app>.k3s.pro`; only explicit first-level `tnnl.me` records are public.

Terraform does not deploy the connector. The existing `cloudflared` replicas in
the `nextcloud` namespace run the shared remotely managed tunnel using the token
delivered by External Secrets. The token is never an input to Terraform or
stored in Terraform state.

## Architecture

- The root owns one `cloudflare_zero_trust_tunnel_cloudflared` and exactly one
  `cloudflare_zero_trust_tunnel_cloudflared_config`.
- Each app file calls `modules/tunneled-access-app`, which owns an explicit
  proxied CNAME, an Access application, a default reusable allow policy, and any
  app-specific additional policies.
- Modules return ingress data. `tunnel.tf` sorts it by `route_order` and appends
  the required terminal `http_status:404` rule.
- The zone cache-phase ruleset bypasses Cloudflare caching for Nextcloud.
- Every default policy allows the configured administrator email addresses.
  Applications inherit the account's required independent MFA configuration;
  an IdP-based MFA selector would reject GitHub, Google, and one-time PIN users.
  GitHub is the only identity provider enabled for every app.
  Nextcloud additionally enables Google by its existing ID and the managed
  one-time PIN provider, and attaches a separate `Still Love` policy for its
  restricted email set; those identities are not passed to any other module.
  Additional policies use the Cloudflare provider's native rule object shapes.
- `prevent_destroy` protects the shared tunnel. A deliberate tunnel replacement
  requires temporarily removing that guard after review.

## Initial Scope

The repository has 33 real `*.k3s.pro` ingress hostnames (`metallb.k3s.pro` is
an annotation namespace, not an ingress). This foundation initially declares
six browser-oriented applications:

| Internal            | External            | Note                                                                                                |
| ------------------- | ------------------- | --------------------------------------------------------------------------------------------------- |
| `nextcloud.k3s.pro` | `nextcloud.tnnl.me` | Existing application; import before renaming. Browser use only until native clients are tested.     |
| `home.k3s.pro`      | `homepage.tnnl.me`  | Human-facing dashboard.                                                                             |
| `jellyfin.k3s.pro`  | `jellyfin.tnnl.me`  | Explicit media exception. Interactive Access may not work with TV, mobile, or other native clients. |
| `linkding.k3s.pro`  | `linkding.tnnl.me`  | Browser UI; browser extensions may need service-token handling.                                     |
| `memos.k3s.pro`     | `memos.tnnl.me`     | Browser UI; test mobile/API clients separately.                                                     |
| `uptime.k3s.pro`    | `uptime.tnnl.me`    | Protected dashboard only; public status pages need a separate path policy.                          |

The remaining ingresses are intentionally not declared:

| Class                                   | Internal hostnames                                                                                                           | Reason                                                                                                                                   |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Administrative web UIs                  | `argocd`, `blocky-ui`, `grafana`, `livebook`, `longhorn`, `termix`, `wg`                                                     | High-impact administration or remote execution; add only after a separate exposure review. Argo CD CLI and WebSockets also need testing. |
| Native clients, feeds, Git, or webhooks | `forgejo`, `n8n`, `rss`                                                                                                      | Interactive Access can break Git clients, feed readers, and inbound webhooks. Use scoped paths or service tokens where appropriate.      |
| Media and download applications         | `bazarr`, `browsarr`, `deluge`, `flood`, `jellyseerr`, `pinchflat`, `prowlarr`, `qbittorrent`, `radarr`, `sabnzbd`, `sonarr` | Intentionally excluded. Jellyfin is the only media application in the initial public scope.                                              |
| Other compatibility-sensitive apps      | `change`, `paperless`                                                                                                        | Changedetection's browser worker needs testing. Paperless currently derives host/CSRF settings from only `paperless.k3s.pro`.            |
| Internal backends/metrics               | `alertmanager`, `blocky`, `playwright`, `speedtest-exporter`                                                                 | Not user-facing. Keep private.                                                                                                           |

## Prerequisites

Create an HCP Terraform workspace, but do not put its organization or workspace
name in this repository. Configure the CLI-driven workspace with:

```sh
export TF_CLOUD_ORGANIZATION='<organization>'
export TF_WORKSPACE='<existing-workspace>'
terraform login
```

The empty `cloud {}` block consumes those variables. In HCP Terraform, set the
following workspace variables:

| Variable                             | Category    | Sensitive |
| ------------------------------------ | ----------- | --------- |
| `CLOUDFLARE_API_TOKEN`               | Environment | Yes       |
| `TF_VAR_cloudflare_account_id`       | Environment | No        |
| `TF_VAR_cloudflare_zone_id`          | Environment | No        |
| `TF_VAR_admin_access_emails`         | Environment | Yes       |
| `TF_VAR_nextcloud_access_emails`     | Environment | Yes       |
| `TF_VAR_github_access_client_id`     | Environment | Yes       |
| `TF_VAR_github_access_client_secret` | Environment | Yes       |
| `TF_VAR_tunnel_name`                 | Environment | No        |

For a workspace configured for local execution, fnox injects secrets from
1Password without writing a `.tfvars` file. Configure
`CLOUDFLARE_API_TOKEN` in `fnox.toml`; the repository's mise Terraform task
invokes `fnox exec` for operations that contact HCP or Cloudflare. The non-secret
`TF_CLOUD_*` and `TF_VAR_*` values may also come from fnox or the calling shell.
A remotely executing HCP workspace does not inherit the local environment;
configure its workspace variables instead. Do not use commands that print the
resolved environment.

The Cloudflare API token should be scoped to the account and `tnnl.me` zone with
only:

- Account: Cloudflare Tunnel Write (the dashboard may label this Cloudflare One
  Connector/cloudflared Write)
- Account: Access: Apps and Policies Write
- Account: Access: Organizations, Identity Providers, and Groups Write
- Zone `tnnl.me`: DNS Write
- Zone `tnnl.me`: Cache Rules Write
- Account: Account Rulesets Write
- Account: Account Filter Lists Write

Read permissions paired with those write permissions may be required by the
token UI/provider. Do not grant account-wide zone administration.

## Import Existing Nextcloud Resources

Import before the first plan. Obtain IDs from the Cloudflare dashboard or API;
do not paste tokens into commands or shell history. These commands are examples
and must not be run until the HCP workspace and Cloudflare credentials are set:

```sh
task terraform:init

mise run terraform import \
  cloudflare_zero_trust_tunnel_cloudflared.shared \
  '<account_id>/<tunnel_id>'

mise run terraform import \
  cloudflare_zero_trust_tunnel_cloudflared_config.shared \
  '<account_id>/<tunnel_id>'

mise run terraform import \
  module.nextcloud.cloudflare_dns_record.this \
  '<zone_id>/<dns_record_id>'

mise run terraform import \
  module.nextcloud.cloudflare_zero_trust_access_application.this \
  'accounts/<account_id>/<application_id>'

mise run terraform import \
  cloudflare_zero_trust_access_identity_provider.github \
  'accounts/<account_id>/<github_identity_provider_id>'

mise run terraform import \
  cloudflare_zero_trust_access_identity_provider.one_time_pin \
  'accounts/<account_id>/<one_time_pin_identity_provider_id>'
```

Importing the tunnel does not rotate its token. Set `TF_VAR_tunnel_name` to its
current name so the first plan does not rename it. The imported tunnel
configuration is authoritative as a whole: the first plan will propose adding
the five new ordered routes and preserving the imported Nextcloud route, then replacing any
unrepresented dashboard-only ingress rules. Add such rules to Terraform before
applying. The existing `Still Love` and `Admin` Nextcloud policies are
application-local legacy policies, so they cannot be imported into the
provider's reusable policy resource. Terraform will create separate reusable
administrator and `Still Love` policies, then update the
imported application to use them. Other applications receive only their
administrator policy. Inspect that replacement closely.

## Workflow

```sh
task terraform:fmt
task terraform:validate
task terraform:plan
```

Apply only after the imports and a reviewed plan:

```sh
task terraform:apply
```

For ad hoc commands, `mise run terraform <arguments>` is the credentialed
wrapper and passes arguments directly to Terraform without a `--` separator.
Formatting runs Terraform directly. Validation uses the fnox wrapper because
Terraform must initialize the configured HCP workspace even when no provider
API calls are planned.

This repository does not automate apply. HCP state contains sensitive GitHub
OAuth configuration and the email identity allowlists used by Access policies,
so restrict workspace access and state downloads. The Cloudflare API token and
connector token remain absent from Terraform configuration and state.

## Limits and Caveats

The initial root manages about 24 Cloudflare objects: one tunnel, one tunnel
configuration, six DNS records, six Access applications, and six reusable
default policies plus Nextcloud's restricted policy, two identity providers,
and one cache ruleset. It uses six of Cloudflare's
documented 500 Access applications, 500 reusable policies, and 1,000 tunnel
routes, and one of 1,000 tunnels. Its 24
managed resources are below HCP Terraform Free's documented 500-resource limit;
verify current plan terms before expanding the scope.

Terraform CLI is pinned to `1.16.1` through mise and the Cloudflare provider is
pinned to `5.24.0` in both root and module declarations. The provider lock file
was generated by `terraform init`. Resource shapes and import formats follow the
[official provider documentation](https://registry.terraform.io/providers/cloudflare/cloudflare/5.24.0/docs),
and the empty cloud block follows HashiCorp's documented
[`TF_CLOUD_ORGANIZATION` and `TF_WORKSPACE` configuration](https://developer.hashicorp.com/terraform/language/block/terraform#environment-variables-for-the-cloud-block).

Cloudflare proxy request-size limits, Access login redirects, cookies, and MFA
can be incompatible with WebDAV, sync/media/mobile clients, API consumers,
webhooks, Git, feed readers, and public status/share links. Prefer a separate
hostname or narrowly scoped application/policy for machine traffic instead of a
broad bypass. `nextcloud.tnnl.me` retains the existing 100 MB per-request constraint;
`nextcloud.k3s.pro` remains the canonical native-client endpoint.
