# AGENTS.md

This file provides guidance to AI Agents when working with code in this repository.

## Architecture Overview

This repository manages a Kubernetes (K3s) cluster running on Raspberry Pi hardware using GitOps principles with ArgoCD. The cluster hosts various self-hosted applications including media services, monitoring, and productivity tools.

### Key Components

- **ArgoCD**: GitOps controller that manages all applications from this repository
- **External Secrets**: Integrates with 1Password Connect for secret management
- **Longhorn**: Distributed block storage for persistent volumes
- **Media Stack**: Complete media management suite (Sonarr, Radarr, Jellyfin, etc.)
- **Monitoring**: Grafana/Prometheus stack for observability

### Repository Structure

- `apps/`: ArgoCD Application manifests that define what gets deployed
- `apps/media/`: Media-related applications organized as sub-applications
- Individual app directories (e.g., `argo-cd/`, `monitoring/`): Contain Helm values and custom templates
- `external-secrets/`: 1Password integration for secret management

## Common Commands

### Task Runner

This project uses [Task](https://taskfile.dev/) for common operations:

```bash
# List all available tasks
task

# Open ArgoCD web interface
task argo:open

# Open Longhorn web interface
task longhorn:open

# Scale down all media services (useful for maintenance)
task media:scale_down

# Scale up all media services
task media:scale_up

# List GitHub PRs
task gh:prs:list

# Auto-merge Renovate PRs
task gh:automerge:renovate
```

### Direct kubectl Commands

```bash
# View ArgoCD applications
kubectl get applications -n argo-cd

# Check application sync status
kubectl describe application <app-name> -n argo-cd

# Scale deployments in media namespace
kubectl scale deployment --all -n media --replicas=0
```

IMPORTANT: Never make any mutative changes to the cluster via kubectl - that
includes apply or patch. We must go through gitops by making a change and
committing and then pushing it - then we can either trigger a refresh in argo cd
or just wait for it to happen automatically. You must confirm with the user if
they want you to make the change before committing and pushing anything.

## Application Patterns

### ArgoCD Applications

Most applications follow this pattern:

- Use `bjw-s/app-template` Helm chart for consistency
  - If you need up-to-date documentation for the app-template use this id with the context7 tool "/bjw-s-labs/helm-charts"
- Multi-source setup: one for values reference, one for the Helm chart
- Automated sync with self-healing enabled
- External secrets integration via templates

### Secret Management

- Secrets are managed via External Secrets Operator
- 1Password Connect provides the backend
- ExternalSecret templates in `<app>/templates/` directories
- Secrets reference vault "K3s.Pro" (vault ID: 1)

### Media Applications

- All media apps deployed to `media` namespace
- Shared storage via Longhorn PVCs
- Common patterns for download/config volume mounts
- Some apps have external secret templates for API keys

## YAML Language Server Annotations

This repo relies heavily on yaml-language-servers to:

- validate correctness of schemas and reduce hallucinations `task validate`
- for auto completion in editors
- whenever adding any new yaml resources/files we should make sure they have the appropriate `yaml-language-server` annotation at the top of the file - search for other files in this repo first to see if we already have one available for that type of resource and use that - otherwise use github codesearch to find one prefer official sources first and foremost, and prefer to have the version match the version we're using if the schema is versioned

## Development Workflow

1. Modify application configs in respective directories
2. ArgoCD automatically syncs changes (automated sync enabled)
3. Use Renovate for dependency updates (runs automatically)
4. Manual sync can be triggered via ArgoCD UI if needed

## Important Notes

- The cluster uses `.k3s.pro` domain for ingress
- Longhorn provides persistent storage - be careful with PVC operations
- External Secrets are required for most applications to function
- Media services can be bulk scaled for maintenance operations
- Git commits are formatted using conventional commits
- **NEVER** use `kubectl patch`, `kubectl annotate`, or similar commands to modify
  Kubernetes resources directly - this breaks GitOps principles. If this is a
  good idea just let the user know and stop
- The only way to make a change to the infrastructure is to commit and push
  changes up via git. After pushing changes you need to be patient and wait. If
  needed, use a sleep command.
- All changes must be made through Git commits to configuration files
- ArgoCD will automatically sync changes from the repository
- **NEVER** delete a persistent volume claim (PVC), or a Kubernetes volume
  without explicitly confirming with the user
- For docker images, never use the `latest` tag - that breaks the ability to control updates - instead find the latest exact version tag from the official online source and use that

## Interaction Guidelines

- If you need a kubectl port-forward - ask the user to run the command instead of running it yourself

## Kubernetes Command Guidelines

- Never use `kubectl patch` commands unless specifically instructed by the user to patch directly - always prefer using gitops via argocd
- IMPORTANT: never amend a commit that's already been pushed and try to force push it. Always prefer adding a new commit.
