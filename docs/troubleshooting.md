# Troubleshooting

Commands below assume the default namespace `<instanceSlug>-cividash`.

## Render fails with a `cividash.cividash.*` message

The add-on's values check the environment while rendering. With
`storage: s3`, `s3.existingSecret`, `s3.endpoint` and `s3.bucket` must be
set; `s3.publicUrl` is optional. `storage` must be `s3` or `volume`. The message names the missing or invalid key.

## Hook Job or pods stuck in `CreateContainerConfigError`

A Secret the containers read through `secretKeyRef` is missing. Check the
events of the pod (`kubectl -n <instanceSlug>-cividash describe pod <pod>`):

| Missing Secret | Cause |
| --- | --- |
| The one in `s3.existingSecret` | The operator creates it before the deployment, see [Media storage](storage.md#storage-s3) |
| `cividash-app-key`, `db-cividash` | The secrets component was not applied after adding `cividash` to `components` |
| `keycloak-client-cividash` | Same; the secrets component generates the client secret from `keycloak-clients.yaml` |

Because `cividash-migrate` runs before the workloads, the deployment then
fails at the Helm timeout.

## `cividash-migrate` cannot reach the database

A timeout to `postgres-cluster-rw` usually means the network policy in the
postgres namespace is missing. Apply the networkpolicies component after
adding the add-on; it creates `cividash-postgres` from
[`networkpolicies.yaml`](../networkpolicies.yaml). An authentication error
means the role's password and `db-cividash` differ; see
[Database](database.md).

## Migrate or seed Job fails with `could not find driver`

The image pinned in [`images.yaml`](../images.yaml) includes `pdo_pgsql`. A
custom or mirrored image without it fails `cividash-migrate` and
`cividash-seed` with `could not find driver`. See [Database](database.md).

## `cividash-fpm` or `cividash-web` stuck in `ImagePullBackOff`

For a registry mirror that needs credentials, create an image pull Secret in
the CiviDash namespace and set `images.pullSecret` to its name through
`cividash.cividash.rawValues`. The chart adds it to every pod. See
[Helm chart, Images](helm-chart.md#images).

## Dashboard host answers 404, 502 or times out

- The Ingress class or controller does not match the cluster: check
  `global.ingress.ingressClass` and `global.ingress.controller`.
- The networkpolicies component was not applied, so the default deny blocks
  the ingress controller.
- With Linkerd and an unmeshed ingress controller,
  `global.serviceMesh.allowUnauthenticatedIngress` must be `true`; otherwise
  the `Server` for `cividash-web` rejects plaintext traffic. See
  [Helm chart, Linkerd](helm-chart.md#linkerd).

## Uploads fail with HTTP 413

The nginx ingress controller limits request bodies to 1m by default. The
add-on sets `proxy-body-size: 32m` for `global.ingress.controller: nginx`
only. For other controllers, raise the limit through
`rawValues.ingress.annotations`.

## Keycloak login to the admin area fails

- Keycloak shows an error about a missing code challenge: CORE 2 requires
  PKCE for the client `cividash`, and the pinned CiviDash release does not
  send it yet. Use a local CiviDash account until a release with PKCE is
  pinned; see [Authentication, Known gap: PKCE](authentication.md#known-gap-pkce).
- Keycloak redirects back with an invalid redirect URI: the client's redirect
  host is `dashboard` (`keycloak-clients.yaml`), so a different
  `cividash.cividash.subdomain` does not match.
- The login loops back to `/admin/login`: the server-side token exchange
  fails. With a private CA other than CORE's self-signed one, the PHP pods do
  not trust Keycloak's certificate; set `platformCa.secretName` through
  `rawValues` to a Secret in the CiviDash namespace with that CA (key
  `ca.crt`). See [Helm chart, Platform CA](helm-chart.md#platform-ca).
- Keycloak login succeeds but CiviDash grants no admin access: the user has
  neither client role. Assign `admin` or `editor` of `cividash`; see
  [Authentication, Granting access](authentication.md#granting-access).
