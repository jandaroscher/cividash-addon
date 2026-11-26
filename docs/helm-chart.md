# Helm chart

The add-on deploys one part, `cividash` ([`civitas-component.yaml`](../civitas-component.yaml)),
as the Helm release `cividash-cividash` in the namespace
`cividash.cividash.namespace` (default `<instanceSlug>-cividash`). The chart is
local: [`charts.yaml`](../charts.yaml) points at
[`charts/cividash`](../charts/cividash/), with no repository and no version.
CORE's Helmfile includes [`helmfile.yaml.gotmpl`](../helmfile.yaml.gotmpl) as
a sub-Helmfile, like every other component.

## Values

Helmfile passes three value layers to the chart, later ones win:

1. [`values/cividash/base-values.yaml.gotmpl`](../values/cividash/base-values.yaml.gotmpl):
   everything derived from the platform and from `cividash.cividash.*`.
2. `values/cividash/<global.profile>-values.yaml.gotmpl`:
   [`development`](../values/cividash/development-values.yaml.gotmpl) or
   [`production`](../values/cividash/production-values.yaml.gotmpl).
3. `cividash.cividash.rawValues` from the environment.

Operators set only the keys in
[`default-environment.yaml.gotmpl`](../default-environment.yaml.gotmpl)
(`enabled`, `namespace`, `subdomain`, `storage`, `s3.*`, see the README).
Any other chart value, as listed in
[`charts/cividash/values.yaml`](../charts/cividash/values.yaml), can be
overridden through `rawValues`:

```yaml
cividash:
  cividash:
    rawValues:
      resources:
        fpm:
          limits: { cpu: "2", memory: 1Gi }
      ingress:
        annotations:
          traefik.ingress.kubernetes.io/router.entrypoints: websecure
```

Values the add-on sets from the platform:

| Chart value | Source |
| --- | --- |
| `images.app`, `images.web` | [`images.yaml`](../images.yaml), see [Images](#images) |
| `app.publicHost` | `<subdomain>.<global.domain>` |
| `app.keySecret` | Secret `cividash-app-key`, key `app-key`, see [APP_KEY](#app_key) |
| `app.s3.*` | `cividash.cividash.s3.*`, with `storage: s3` only, see [Media storage](storage.md) |
| `storage.type`, `storage.volume.storageClassName` | `cividash.cividash.storage`, `global.storage.storageClass.rwx` |
| `db.*` | [`databases.yaml`](../databases.yaml), see [Database](database.md) |
| `keycloak.*` | [`keycloak-clients.yaml`](../keycloak-clients.yaml) and the keycloak component, see [Authentication](authentication.md) |
| `civitas.enabled` | `false`, see [Authentication, NGSI-LD data sync](authentication.md#ngsi-ld-data-sync) |
| `platformCa.secretName` | `custom-ca-cert` when `global.ingress.clusterIssuer` is `selfsigned-ca`, otherwise empty |
| `ingress.*` | `global.ingress`, see [Routing](#routing) |
| `linkerd.*` | `global.serviceMesh`, see [Linkerd](#linkerd) |
| `networkPolicy.enabled` | `false`: the policies come from [`networkpolicies.yaml`](../networkpolicies.yaml) |
| `replicas.*`, `podDisruptionBudget.enabled` | Profile: `development` 1 replica each and no PDB, `production` 2 replicas of fpm, web and queue and PDBs for fpm and web |

The values files carry the CORE deployment requirement checklist as
comments; see [Conformance](core-guideline-conformance.md).

## Credentials

The chart takes no credentials as values. Every container reads them from
existing Secrets through `secretKeyRef`:

| Variable | Secret (key) | Created by |
| --- | --- | --- |
| `APP_KEY` | `cividash-app-key` (`app-key`) | CORE secrets component, from [`secrets.yaml`](../secrets.yaml) |
| `DB_PASSWORD` | `db-cividash` (`password`) | CORE secrets component, from `secrets.yaml` |
| `KEYCLOAK_CLIENT_SECRET` | `keycloak-client-cividash` (`client-secret`) | CORE secrets component, from `keycloak-clients.yaml` |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `s3.existingSecret` (same keys) | The operator, with `storage: s3` only |

The other settings go into two Secrets the chart renders as
`pre-install,pre-upgrade` hooks (weight `0`), before the `cividash-migrate`
Job (weight `5`): `cividash-app-secret` (Laravel environment: `APP_URL`, log
settings, session, cache and queue drivers, storage, Keycloak and sync
settings) and `cividash-db-secret` (host, port, database, user). Hook
resources are not part of the release manifest, so destroying the release
leaves them behind; delete them by hand when decommissioning.

## APP_KEY

Laravel encrypts sessions and encrypted columns with `APP_KEY`. The secrets
component generates it once as Secret `cividash-app-key` (key `app-key`, 32
characters, a raw key Laravel accepts) in the CiviDash namespace and keeps an
existing value on later runs.

When migrating an existing installation, create the Secret with the old key
before the first deployment, so the generator keeps it. The secrets
component manages the Secret with its own Helm release
`secrets-cividash-app-key` in the CiviDash namespace, so give it that
release's ownership metadata; otherwise Helm refuses to take over a Secret
it did not create:

```bash
kubectl create namespace <instanceSlug>-cividash   # if it does not exist yet
kubectl -n <instanceSlug>-cividash create secret generic cividash-app-key \
  --from-literal=app-key='<old APP_KEY>'
kubectl -n <instanceSlug>-cividash label secret cividash-app-key \
  app.kubernetes.io/managed-by=Helm
kubectl -n <instanceSlug>-cividash annotate secret cividash-app-key \
  meta.helm.sh/release-name=secrets-cividash-app-key \
  meta.helm.sh/release-namespace=<instanceSlug>-cividash
```

Laravel accepts a 32-character raw key or `base64:` followed by 32 encoded
bytes, so an old key in either form works unchanged.

## Routing

CiviDash is reached only through its own Ingress `cividash-public`:
`<subdomain>.<global.domain>` to the Service `cividash-web` (port 80, container
port 8080), with TLS. The add-on registers no APISIX route. The dashboard is
public, the admin area authenticates in the app, and APISIX's fixed
6-second upstream timeout would cut off imports and exports.

The Ingress takes its settings from `global.ingress`:

| Chart value | Source |
| --- | --- |
| `ingress.className` | `global.ingress.ingressClass` |
| `ingress.clusterIssuer` | `global.ingress.clusterIssuer`; the chart adds `cert-manager.io/cluster-issuer` and `kubernetes.io/tls-acme`, TLS Secret `<host>-tls` |
| `ingress.annotations` | By `global.ingress.controller`: `nginx` sets `nginx.ingress.kubernetes.io/proxy-body-size: 32m` (the upload limit of `cividash-web`), `traefik` sets `traefik.ingress.kubernetes.io/router.tls: "true"`, `haproxy` sets `haproxy.org/ssl-redirect: "true"` and port 443 |

Further annotations can be added through `rawValues` under
`ingress.annotations`; Helm merges them with the ones above.

[`networkpolicies.yaml`](../networkpolicies.yaml) opens `cividash-web` on 8080
to any source, since the ingress controller runs in a cluster-specific
namespace. `cividash-fpm` (9000) only accepts `cividash-web`.

### Gateway API

The chart can also render an `HTTPRoute` named `cividash-public` for the same
host to `cividash-web:80`. CORE 2 provides no Gateway settings, so the add-on
does not use it; an operator who runs a Gateway can enable it through
`rawValues`:

```yaml
cividash:
  cividash:
    rawValues:
      ingress:
        enabled: false
      gatewayApi:
        enabled: true
        parentRefs:
          - name: my-gateway
            namespace: gateway-system
```

`SESSION_SECURE_COOKIE` stays `true`, so the Gateway needs an HTTPS listener
for this host.

### Linkerd

With `global.serviceMesh.enable` and `global.serviceMesh.type: linkerd`, the
chart renders a Linkerd `Server` named `cividash-web` for the `http` port.
Its access policy follows `global.serviceMesh.allowUnauthenticatedIngress`:
`true` accepts plaintext from an unmeshed ingress controller
(`all-unauthenticated`), `false` requires a meshed one
(`all-authenticated`). Meshed traffic arrives on the proxy port 4143, which
[`networkpolicies-linkerd.yaml`](../networkpolicies-linkerd.yaml) opens for
the same peers as `networkpolicies.yaml`.

## Platform CA

With the self-signed platform CA (`global.ingress.clusterIssuer:
selfsigned-ca`), `platformCa.secretName` is `custom-ca-cert`, the Secret the
prepare component distributes. An init container `ca-bundle` then joins the
image's system CAs and that CA (key `ca.crt`) into one bundle, and the
ConfigMap `cividash-platform-ca` points PHP's curl and openssl at it. Outbound
HTTPS calls, such as the Keycloak token exchange, then trust the platform's
certificates. With any other issuer the pods use the image's system CAs only.

The bundle is built at pod start. After the platform CA rotates, restart the
deployments (`kubectl -n <instanceSlug>-cividash rollout restart deployment`)
so they pick up the new CA.

## Workloads

| Object | Image | Notes |
| --- | --- | --- |
| `cividash-fpm` | `cividash-app` | php-fpm, port `fastcgi` 9000, rolling update `maxUnavailable: 0`, `maxSurge: 1` |
| `cividash-web` | `cividash-web` | nginx (unprivileged, uid 101), port `http` 8080, serves the public assets and passes PHP to `cividash-fpm:9000`; the Service name `cividash-fpm` is baked into the image |
| `cividash-queue` | `cividash-app` | `php artisan queue:work --tries=3 --max-time=3600`, rolling update |
| `cividash-scheduler` | `cividash-app` | `php artisan schedule:run` every 60 seconds, always one replica with the `Recreate` strategy |
| `cividash-migrate` | `cividash-app` | Hook Job, `php artisan migrate --force` |
| `cividash-seed` | `cividash-app` | Hook Job, see [Initial config data](seed.md) |

The PHP containers run as uid/gid 82 with a read-only root filesystem. They
write to `storage/`, `bootstrap/cache` and `/tmp`, each a pod-local `emptyDir`
that the init container `writable-dirs` fills from the image. `cividash-web`
writes to `/tmp` and `/etc/nginx/conf.d`, which the init container
`nginx-conf` fills from the image. No pod mounts a service account token.

## Images

The CiviDash main repository publishes two images to GHCR:

- `ghcr.io/jandaroscher/cividash-app`: php-fpm with the full application,
  used by fpm, queue, scheduler and the migrate and seed Jobs.
- `ghcr.io/jandaroscher/cividash-web`: nginx with the built public assets.

Both are pinned to a CiviDash release tag in [`images.yaml`](../images.yaml).
The add-on's values split each `repository` at the first `/` into the chart's
`images.<name>.registry` and `images.<name>.repository`, and set
`pullPolicy: IfNotPresent`.

To pull from a mirror, override the image per environment, like for every
CORE component:

```yaml
images:
  cividash:
    app:
      repository: registry.example.org/mirror/cividash-app
    web:
      repository: registry.example.org/mirror/cividash-web
```

If the mirror needs credentials, create an image pull Secret in the CiviDash
namespace and name it in `rawValues` as `images.pullSecret`; the chart adds
it to every pod.

The CiviDash main repository also publishes a moving `civitas` tag, which is
also the chart's own default in `values.yaml` for linting. It is for the
maintainers' test stack only: it can change under a running deployment
without a version change here. Always deploy an immutable release tag such as
`1.2.1`, see
[Versioning and compatibility](../README.md#versioning-and-compatibility).

## Verify locally

Lint and render the chart alone:

```bash
helm lint --strict charts/cividash -f charts/cividash/ci/smoke-values.yaml
helm template cividash charts/cividash -f charts/cividash/ci/smoke-values.yaml
```

The chart's own defaults do not render: `app.keySecret.name`,
`db.host`, `db.passwordSecret.name` and the S3 settings are required, which
the smoke values provide. To check the add-on as CORE renders it, against
the CORE policies, run the commands in
[Versioning and compatibility](../README.md#versioning-and-compatibility);
CI runs the same in [`.github/workflows/verify.yml`](../.github/workflows/verify.yml).

## Security headers

The chart sets no HTTP security headers. The `cividash-web` image sends
`X-Content-Type-Options`, `X-Frame-Options` (left out on the tile embed
routes) and `Referrer-Policy`. `Strict-Transport-Security`,
`Content-Security-Policy` and `Permissions-Policy` belong at the
TLS-terminating ingress controller; add them through
`rawValues.ingress.annotations` in the form your controller expects. The main
repository's
[security header guide](https://github.com/jandaroscher/cividash/blob/main/docs/deployment/security-headers.md)
has recommended values, including a tested Content-Security-Policy and the
exception that keeps tile embeds working.
