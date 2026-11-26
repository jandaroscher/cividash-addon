<!--
SPDX-FileCopyrightText: 2025-2026 JANDA+ROSCHER GmbH & Co. KG

SPDX-License-Identifier: EUPL-1.2+
-->

# Media storage

CiviDash stores uploaded public media (logos, tile and page images,
downloads) on its `public` disk. CIVITAS/CORE ships no object storage, so the
add-on offers two places for that disk, chosen with
`cividash.cividash.storage`:

| `storage` | Where media lives | You provide |
|---|---|---|
| `volume` (default) | The PersistentVolumeClaim `cividash-public-media` | A StorageClass in `global.storage.storageClass.rwx`, `ReadWriteMany` on more than one node |
| `s3` (recommended for production) | An S3-compatible bucket | A bucket, its endpoint and a Secret with the access keys |

In both cases browsers load media from the dashboard under `/storage`,
unless `s3.publicUrl` points them at the bucket. Any other value of
`storage` fails the render.

## `storage: s3`

The access keys never go into the environment or the Helm values. Create a
Secret in the CiviDash namespace (`<instanceSlug>-cividash`) with exactly
these two keys before the deployment:

```bash
kubectl -n <instanceSlug>-cividash create secret generic cividash-s3 \
  --from-literal=AWS_ACCESS_KEY_ID=<key> \
  --from-literal=AWS_SECRET_ACCESS_KEY=<secret>
```

```yaml
cividash:
  cividash:
    storage: s3
    s3:
      existingSecret: cividash-s3
      endpoint: https://s3.example.org
      bucket: cividash
      publicUrl: ""        # empty: media are served under /storage
      region: us-east-1    # default
      usePathStyle: true   # default; path-style URLs suit MinIO and most self-hosted S3
```

`existingSecret`, `endpoint` and `bucket` are required; the render fails
with a message naming the missing key. `publicUrl` must be present but may
be empty.

The PHP pods read `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from that
Secret through `secretKeyRef`. If the Secret is missing, the
`cividash-migrate` hook Job stays in `CreateContainerConfigError` and the
deployment fails at the Helm timeout. After rotating the keys in the Secret,
restart the deployments
(`kubectl -n <instanceSlug>-cividash rollout restart deployment`), because
environment variables are read only at pod start.

The bucket's backup, retention and access policy are the operator's
responsibility.

## `storage: volume`

```yaml
cividash:
  cividash:
    storage: volume
```

The `s3.*` keys are ignored. The chart then:

- creates the claim `cividash-public-media` (5Gi, `ReadWriteMany`) on the
  class from `global.storage.storageClass.rwx`, or the cluster's default
  class when that is empty,
- mounts it at `storage/app/public` in `cividash-fpm`, `cividash-queue`,
  `cividash-scheduler` and the `cividash-seed` Job, and read-only in
  `cividash-web`, whose nginx serves `/storage` straight from the volume,
- sets `PUBLIC_DISK_DRIVER=local`.

Size, access mode and class are chart values; change them through
`rawValues`:

```yaml
cividash:
  cividash:
    storage: volume
    rawValues:
      storage:
        volume:
          size: 20Gi
          accessMode: ReadWriteMany
          storageClassName: my-rwx-class
```

### Access mode

Every fpm, queue, scheduler and web pod mounts the same volume. On a cluster
with more than one node the StorageClass must support `ReadWriteMany` (for
example NFS, CephFS or Longhorn RWX). With a class that only supports
`ReadWriteOnce`, pods scheduled on a second node stay in `ContainerCreating`.
If the class does not support `ReadWriteMany` at all, the claim stays
`Pending`, every pod waits for it and the deployment times out. Node-local
classes such as `local-path` (k3d, kind) are such classes.

Set `storage.volume.accessMode: ReadWriteOnce` only on a single node, or with
a node-local class, where every pod is scheduled on the volume's node. All of
CiviDash then runs on that one node and stops if it fails. Local test
clusters with `local-path` need `ReadWriteOnce`.

The claim's class and access mode cannot change once it exists, and its size
can only grow (if the class allows expansion). A later change of class,
access mode or a smaller size makes the deployment fail with "spec is
immutable". To change them, copy the media out, delete the claim and deploy
again, then copy the media back.

### Permissions

The PHP pods write as uid/gid 82 and set `fsGroup: 82`. Whether a CSI driver
applies `fsGroup` depends on its `fsGroupPolicy`
(`kubectl get csidriver <name> -o jsonpath='{.spec.fsGroupPolicy}'`, `File`
applies it) and, on NFS, on the server not squashing root. If it is not
applied, make the volume root writable for gid 82.

On an NFS export with `root_squash` (the NFS default), the kubelet's `chown`
runs as root, the server maps it to `nobody`, and the volume root stays owned
by `65534:65534`. The deployment, the hooks, the readiness probes and `/up`
still succeed, but every upload fails. Fix it once on the NFS server, so that
new volume directories inherit gid 82:

```sh
chown 65534:82 <export-dir>
chmod 2775 <export-dir>
```

For a volume that already exists, run the same on its directory instead:
`chgrp 82 <volume-dir> && chmod 2775 <volume-dir>`. To check, write a file
from the fpm pod:
`kubectl -n <instanceSlug>-cividash exec deploy/cividash-fpm -- php artisan tinker --execute="var_dump(Storage::disk('public')->put('write-test.txt', 'ok'));"`
should print `bool(true)`.

## Backup

The add-on creates no backup schedule. With `storage: s3`, the media are
covered by the bucket's backup. With `storage: volume`, back up the claim
`cividash-public-media` yourself, for example with Velero file-system backup
or snapshots of your storage system. The database is backed up separately
(see [Database](database.md#backup-and-restore)); restore both from the same
point in time, since the database holds the paths of the media.

## Uninstall

The claim carries `helm.sh/resource-policy: keep`, so destroying the release
leaves it and the media in place. Delete it explicitly to drop the media:
`kubectl -n <instanceSlug>-cividash delete pvc cividash-public-media`. With
the usual reclaim policy `Delete`, deleting the claim also deletes the files.
Deleting the namespace deletes the claim regardless of the annotation. Copy
the media out first, or set the volume's reclaim policy to `Retain`
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
3. Check that a few images load under
   `https://<subdomain>.<global.domain>/storage/...`.

From the volume to S3, copy the other way (`rclone copy /data s3:<bucket>`)
before deploying with `storage: s3`. Uploads that land on the volume between
that copy and the end of the deployment are not in the bucket yet, so run the
same copy once more afterwards; `rclone copy` only transfers what is missing.
The claim stays in place until you delete it.

When the cluster enforces the platform's Kyverno policies at admission
(`runtimePolicies.failureAction: Enforce`), a one-off pod in the CiviDash
namespace has to meet them too: non-root, read-only root filesystem,
resources and probes.
