<!--
SPDX-FileCopyrightText: 2025-2026 JANDA+ROSCHER GmbH & Co. KG

SPDX-License-Identifier: EUPL-1.2+
-->

# Media storage

CiviDash stores uploaded public media (logos, tile and page images,
downloads) on its `public` disk. CIVITAS/CORE ships no object storage, so the
add-on offers two places for that disk, chosen with
`inv_addons.cividash.storage`:

| `storage` | Where media lives | You provide |
|---|---|---|
| `s3` (default) | An S3-compatible bucket | Endpoint, bucket and vaulted credentials under `s3.*` |
| `volume` | The PersistentVolumeClaim `cividash-public-media` | A StorageClass in `inv_k8s.storage_class.rwx` |

In both cases browsers load media from the dashboard under `/storage`,
unless `s3.public_url` points them at the bucket.

## `storage: volume`

```yaml
inv_addons:
  cividash:
    storage: "volume"
    volume:
      size: "5Gi"                  # default
      access_mode: "ReadWriteMany" # default
```

The `s3.*` keys are not needed and are ignored. The chart then:

- creates the claim `cividash-public-media` on the class from
  `inv_k8s.storage_class.rwx`,
- mounts it at `storage/app/public` in `cividash-fpm`, `cividash-queue`,
  `cividash-scheduler` and the `cividash-seed` Job, and read-only in
  `cividash-web`, whose nginx serves `/storage` straight from the volume,
- sets `PUBLIC_DISK_DRIVER=local`.

### Access mode

Every fpm, queue, scheduler and web pod mounts the same volume. On a cluster
with more than one node the StorageClass must support `ReadWriteMany` (for
example NFS, CephFS or Longhorn RWX). With a class that only supports
`ReadWriteOnce`, pods scheduled on a second node stay in `ContainerCreating`.
If the class does not support `ReadWriteMany` at all, the claim stays
`Pending`, every pod waits for it and the Helm install times out. CORE's
example value `standard` and the k3d value `local-path` are such classes.

Set `volume.access_mode: "ReadWriteOnce"` only on a single node, or with a
node-local class such as `local-path`, where every pod is scheduled on the
volume's node. All of CiviDash then runs on that one node and stops if it
fails. CORE's `inventory_loc_k3d.yml` sets all storage classes to
`local-path`, which rejects `ReadWriteMany`, so local test clusters need
`ReadWriteOnce`.

The class always comes from `inv_k8s.storage_class.rwx`. To use another class
for CiviDash only, set it through `helm_values`:

```yaml
inv_addons:
  cividash:
    helm_values:
      storage:
        volume:
          storageClassName: "my-rwx-class"
```

The claim's class and access mode cannot change once it exists, and its size
can only grow (if the class allows expansion). A later change to
`inv_k8s.storage_class.rwx`, `volume.access_mode` or a smaller `volume.size`
makes the deploy fail with "spec is immutable". To change them, copy the
media out, delete the claim and deploy again, then copy the media back.

The PHP pods write as uid/gid 82 and set `fsGroup: 82`. Whether a CSI driver
applies `fsGroup` depends on its `fsGroupPolicy`
(`kubectl get csidriver <name> -o jsonpath='{.spec.fsGroupPolicy}'`, `File`
applies it) and, on NFS, on the server not squashing root. If it is not
applied, make the volume root writable for gid 82.

### Backup

With `storage: volume` the media are no longer covered by the bucket's
backup. When CORE's Velero is enabled (`inv_op_stack.velero.enable`, CORE
1.8.0 or later), the add-on creates the same nightly Velero Schedule for its
namespace that CORE's own components use. It backs up the volume with Velero
file-system backup. On older CORE, or without Velero, back up the volume
yourself.

To get the media back, restore only the volume, for example into a scratch
namespace, and copy the files over:
`velero restore create --from-backup <backup> --namespace-mappings <ns>:<scratch-ns> --include-resources persistentvolumeclaims,persistentvolumes,pods`.
Restoring the whole namespace also brings back a second set of workloads and
routes that point at the same database and host.

### Uninstall

The claim carries `helm.sh/resource-policy: keep`, so `helm uninstall` leaves
it and the media in place. Delete it explicitly to drop the media:
`kubectl -n <ns> delete pvc cividash-public-media`. With the usual reclaim policy
`Delete`, deleting the claim also deletes the files.

CORE's own uninstall (`--tags uninstall`) deletes the whole
`<ENVIRONMENT>-cividash-stack` namespace, and the claim and the media with
it, regardless of the `keep` annotation. Copy the media out first, or set the
volume's reclaim policy to `Retain`
(`kubectl patch pv <pv> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'`).

## Switching between `s3` and `volume`

Switching changes where the app looks for files; it does not move them.
Copy the files first, then deploy with the new `storage` value. Object keys
on the bucket root and paths below `storage/app/public` are the same, so a
plain copy is enough. For example, from S3 to the volume:

1. Deploy once with `storage: volume`, so the claim exists. Media uploaded
   before the copy finishes are missing until step 2 is done.
2. Copy the bucket into the claim with a one-off pod that mounts
   `cividash-public-media` and runs as uid/gid 82, for example with
   `rclone copy s3:<bucket> /data`.
3. Check that a few images load under `https://<public_host>/storage/...`.

From the volume to S3, copy the other way (`rclone copy /data s3:<bucket>`)
before deploying with `storage: s3`. Uploads that land on the volume between
that copy and the end of the deploy are not in the bucket yet, so run the
same copy once more after the deploy; `rclone copy` only transfers what is
missing. The claim stays in place until you delete it.
