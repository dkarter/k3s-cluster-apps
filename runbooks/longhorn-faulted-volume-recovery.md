# Recover a Faulted Longhorn Volume

Use this when every replica is marked failed but the replica data still exists.
This procedure salvages data in place. It does not recreate or delete storage.

## Safety

- Obtain explicit approval before salvage or temporary setting changes.
- Never delete the PVC, PV, Longhorn volume, replica, snapshot, or replica files.
- If multiple replicas exist, identify the authoritative replica before salvage.
- The volume must be detached. Stop attached workloads through GitOps first.
- Stop if SMART or kernel logs show an active hardware or I/O failure.

## Variables

```bash
export LONGHORN_URL=https://longhorn.k3s.pro/v1
export VOLUME=pvc-b794810f-1a3f-4fb7-96d8-f76d098cff65
export REPLICA=pvc-b794810f-1a3f-4fb7-96d8-f76d098cff65-r-0417bc57
export NODE=k3s6
export DISK_PATH=/mnt/storage03
export DISK_STATUS_KEY=crucial-ssd-500gb-2
```

## Diagnose

Confirm the volume is `detached/faulted` and inspect its replicas:

```bash
kubectl -n longhorn-system get volumes.longhorn.io "$VOLUME" \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

kubectl -n longhorn-system get replicas.longhorn.io \
  -l "longhornvolume=$VOLUME" \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeID,FAILED:.spec.failedAt,STATE:.status.currentState
```

Verify the disk is mounted, has free space, and contains the replica:

```bash
ssh "$NODE" "findmnt $DISK_PATH && df -h $DISK_PATH"
ssh "$NODE" "sudo -n du -sh $DISK_PATH/replicas/$VOLUME-*"
ssh "$NODE" 'sudo -n smartctl -x -d sat /dev/sdb'
ssh "$NODE" "sudo -n journalctl -b -k --no-pager | grep -Ei '(sdb|uas|usb).*(error|fail|reset|disconnect|I/O)'"
```

Check Longhorn disk eligibility:

```bash
kubectl -n longhorn-system get nodes.longhorn.io "$NODE" \
  -o jsonpath="{range .status.diskStatus.$DISK_STATUS_KEY.conditions[*]}{.type}{'='}{.status}{' reason='}{.reason}{'\\n'}{end}"
```

## Salvage

If the disk is `Schedulable=True`, skip to the salvage request.

If the only blocker is `DiskPressure`, save the current threshold and temporarily
lower it below the disk's available percentage. Do not do this on a full or
failing disk.

```bash
ORIGINAL_MIN_AVAILABLE=$(
  curl --fail --silent --show-error \
    "$LONGHORN_URL/settings/storage-minimal-available-percentage" | jq -r '.value'
)

curl --fail --silent --show-error -X PUT \
  "$LONGHORN_URL/settings/storage-minimal-available-percentage" \
  -H 'Content-Type: application/json' \
  --data '{"name":"storage-minimal-available-percentage","value":"5"}' \
  | jq '{value,applied}'
```

Wait until the disk reports `Schedulable=True`, then salvage the selected replica:

```bash
curl --silent --show-error -X POST \
  "$LONGHORN_URL/volumes/$VOLUME?action=salvage" \
  -H 'Content-Type: application/json' \
  --data "{\"names\":[\"$REPLICA\"]}" | jq .
```

The API may return HTTP 500 if attachment races with the response. Check volume
state before retrying. `invalid volume state to salvage: attached` means salvage
already took effect.

Always restore the original threshold:

```bash
curl --fail --silent --show-error -X PUT \
  "$LONGHORN_URL/settings/storage-minimal-available-percentage" \
  -H 'Content-Type: application/json' \
  --data "{\"name\":\"storage-minimal-available-percentage\",\"value\":\"$ORIGINAL_MIN_AVAILABLE\"}" \
  | jq '{value,applied}'
```

## Verify

```bash
curl --fail --silent --show-error "$LONGHORN_URL/volumes/$VOLUME" \
  | jq '{state,robustness,ready,shareState,replicas}'

kubectl -n longhorn-system get pods \
  -l "longhorn.io/share-manager=$VOLUME" -o wide

kubectl -n media get pods -o wide
kubectl -n media exec <pod-name> -- df -h /downloads
kubectl -n media exec <pod-name> -- sh -c 'test -r /downloads && test -x /downloads'
```

Expected result: volume `attached/healthy`, share manager `running`, replica
`running` with an empty `failedAt`, and all application pods Ready.

## Follow Up

- Free space on the replica disk; this incident left `/mnt/storage03` 93% used.
- Review snapshot retention and create a current backup.
- Add replica redundancy after sufficient storage is available.
- Order `k3s-agent.service` after the Longhorn disk mounts. During this incident,
  K3s started before `/mnt/storage02` completed ext4 journal recovery.
