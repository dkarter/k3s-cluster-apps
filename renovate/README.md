# Self-hosted Renovate

ArgoCD deploys an hourly CronJob in the `renovate` namespace. It starts **suspended**
and in **full dry-run mode**, so merging this setup does not start a second bot.
The existing hosted Renovate safety-review identity remains the default.

The official image is pinned to `44.176.2` and supports ARM64. Renovate reads the
existing root `renovate.json`. The runner creates a fresh GitHub App installation
token for each job using Node built-ins; no extra authentication image or npm
package is needed. Tokens are restricted to `k3s-cluster-apps`, kept in memory,
and passed to Renovate through its environment, never command-line arguments.

## 1. Create a GitHub App

Create an App in [GitHub developer settings](https://github.com/settings/apps).
Choose an available name, for example `dkarter-k3s-renovate`. Record its exact
bot login (`<app-slug>[bot]`), numeric App ID, and installation ID.

- Homepage: this repository's URL.
- Disable webhooks. This deployment polls on a schedule and needs no public endpoint.
- Install only on `dkarter/k3s-cluster-apps`.
- Repository permissions recommended by Renovate:
  - Read/write: Checks, Commit statuses, Contents, Issues, Pull requests, Workflows.
  - Read-only: Administration, Dependabot alerts, Metadata.
  - Organization Members: read-only if installing on an organization; not applicable
    to this personal-account repository.
- Generate a private key and store it directly in 1Password. Do not commit it or
  paste it into chat. The installation ID appears in the App installation's URL.
- Do not grant branch-protection or ruleset bypass permissions.

`RENOVATE_PLATFORM_COMMIT=enabled` requests GitHub-signed API commits. Do not
disable signing to work around an authentication or repository-rule failure.

## 2. Configure 1Password

Create an item named `renovate` in the `K3s.Pro` vault with these exact fields:

| Field             | Value                                         |
| ----------------- | --------------------------------------------- |
| `app-id`          | Numeric GitHub App ID                         |
| `installation-id` | Numeric installation ID                       |
| `private-key`     | Complete PEM private key, preserving newlines |

The ExternalSecret maps only these fields into `renovate-app`. The private key
is mounted read-only rather than placed in the process environment. No Kubernetes
API service-account token is mounted. Missing credentials block job startup.

## 3. Deploy and dry-run through GitOps

After review and approval, commit and push the setup. Wait for ArgoCD to sync and
for the `renovate-app` ExternalSecret to report Ready. Check status without reading
the generated Secret or credential values:

```sh
kubectl get applications -n argo-cd renovate
kubectl get externalsecret -n renovate renovate-app
kubectl get cronjob -n renovate renovate
```

Change `spec.suspend` to `false` in `templates/cronjob.yml`, leaving
`RENOVATE_DRY_RUN=full`. Commit and push after approval, then wait for a scheduled
run. Do not use `kubectl create job`, `patch`, or `apply` to bypass GitOps.

```sh
kubectl get jobs -n renovate
kubectl logs -n renovate job/<job-name>
```

Check authentication, repository detection, dependency lookups, and completion.
Full dry-run mode prevents Renovate's repository changes; it still contacts GitHub
and registries and mints an installation token. Do not enable debug/trace logging
or publish raw logs without checking them for sensitive information.

## 4. Cut over

1. Suspend the CronJob again through a reviewed Git change. Let any job finish.
2. Disable the hosted Renovate App for **this repository only**.
3. Finish or close existing hosted-bot PRs. Do not assume a new bot will adopt them.
4. Set the GitHub repository Actions variable `RENOVATE_BOT_LOGIN` to the new
   App's exact login, including `[bot]`. This is a non-secret variable. Discovery,
   review instructions, and the finishing gate use this same exact identity.
   The old hosted identity is no longer trusted once the variable is set.
5. Remove the `RENOVATE_DRY_RUN` environment entry and set `spec.suspend: false`.
   Commit and push after approval. Wait for ArgoCD and the next hourly run.
6. Confirm the first PR has the expected bot author and verified commits, and
   passes CI. Manually dispatch `Renovate safety review` for that PR to verify
   the identity migration; its normal Friday review schedule is unchanged.

This does not enable Renovate's own automerge. The existing independent review
and CI gate remains responsible for automatic merges. The legacy
`task gh:automerge:renovate` command still targets the hosted bot; do not use it
as part of this rollout.

## Operations and limits

- Schedule: hourly at minute 17, UTC; no overlapping jobs or automatic retries.
- Initial resource budget: 250m CPU / 512Mi requested, 2 CPU / 2Gi maximum.
  These are starting values, not measured capacity requirements.
- Work/cache: a disposable 4Gi `emptyDir`, cleared after each job. No PVCs or
  existing volumes are changed. Repeated scans may be slower without shared cache.
- Renovate is killed after 45 minutes; Kubernetes ends the job after 50 minutes,
  before the one-hour installation token expires. For larger repositories,
  redesign token refresh rather than simply extending these timeouts.
- Package scripts and plugins are disabled. No ingress or persistent service.
- Changing the repository allowlist requires updating both the CronJob environment
  and the explicit token scope/allowlist in `runner.cjs`, plus the App installation.
- To pause or roll back: suspend via Git first and wait for active jobs to finish.
  Restore `RENOVATE_BOT_LOGIN` to `renovate[bot]` (or unset it) before re-enabling
  hosted Renovate. Never run both bots in write mode on the same repository.

## Local verification

```sh
kubectl kustomize renovate
task test:renovate
```

`kubectl kustomize` only renders local manifests; it does not contact or modify
the cluster. Tests use ephemeral test keys and mocked HTTP/process calls, never
real credentials. The runner tests also work with
`node --test test/renovate_runner.test.cjs`.

References:

- [Renovate self-hosting examples](https://docs.renovatebot.com/examples/self-hosting/)
- [Running as a GitHub App](https://docs.renovatebot.com/modules/platform/github/#running-as-a-github-app)
- [Self-hosted configuration](https://docs.renovatebot.com/self-hosted-configuration/)
