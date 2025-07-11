# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

## Application Patterns

### ArgoCD Applications

Most applications follow this pattern:

- Use `bjw-s/app-template` Helm chart for consistency
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

## Interaction Guidelines

- If you need a kubectl port-forward - ask the user to run the command instead of running it yourself

## Kubernetes Command Guidelines

- Never use `kubectl patch` commands unless specifically instructed by the user to patch directly - always prefer using gitops via argocd