---
name: k3s-persistence-safety
description: Use when changing Kubernetes persistence, PVCs, StorageClasses, or bjw-s/app-template persistence entries in this K3s GitOps repo. Prevents accidental data loss from Helm/app-template generated PVC name changes, reclaim policy mistakes, and unsafe storage migrations.
---

# K3s Persistence Safety

Before changing app persistence, prove that the change preserves intended PVC names and reclaim behavior.

## Required Workflow

1. Render the chart before and after the change.
2. Compare rendered `PersistentVolumeClaim` names, Deployment names, and `claimName` references.
3. Compare those names against live cluster resources with read-only `kubectl get pvc,pv -n <namespace>`.
4. If a stateful app would mount a different PVC name, stop unless this is an explicit migration.
5. For existing stateful apps, use `existingClaim` when needed to preserve the live claim name.
6. Never delete PVCs, PVs, or Longhorn volumes without explicit user confirmation.

## app-template Risk

`bjw-s/app-template` can change generated PVC names when adding another persistence item. A single persistence entry may render as the release name, while multiple entries may render as `<release>-<persistence-key>`. This can make an app mount a fresh empty volume while its database still points at existing metadata.

## Retain Policy

Prefer a retained StorageClass for important app data. If a PVC already exists, its storage class cannot be changed in place; changing the live PV reclaim policy requires an explicit, user-approved cluster mutation.
