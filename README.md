<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/cividash-logo-dark.svg">
    <img src="docs/images/cividash-logo.svg" alt="CiviDash" width="320">
  </picture>
  <br>CIVITAS/CORE Add-on
</h1>

Packages **CiviDash**, the sustainability dashboard (Laravel 12 + Filament +
a Vue 3 SPA), as a **CIVITAS/CORE** add-on. This is a **deploy-only**
repository: a local Helm chart ([`chart/cividash/`](chart/cividash/))
installed through the central platform Helm task, plus `uri`-based Keycloak /
APISIX Admin-API calls for SSO and gateway registration (outside Helm's
scope). The application code lives in the
[CiviDash main repository](https://github.com/jandaroscher/cividash)
and ships here as prebuilt container images.

## Quick start

Clone (or copy/symlink) this repository into the `addons/` folder of the
`civitas_core` deployment repository as `addons/cividash_addon/`, activate it,
and set the required config:

```yaml
inv_addons:
  import: true
  addons:
    - 'addons/cividash_addon/tasks.yml'
  cividash:
    enable: true
    public_host: "dashboard.{{ DOMAIN }}"
    db:
      host: "cividash-postgres.core-postgres.svc.cluster.local"  # REQUIRED
      # password: "..."  # REQUIRED, supply via vaulted inventory
    s3:
      endpoint: "https://s3.{{ DOMAIN }}"
      bucket: "cividash"
      # access_key_id / secret_access_key: REQUIRED, supply via vaulted inventory
```

Then run the platform deploy. The add-on installs after all other
core-platform tasks. To run only this add-on, use the tags `addons` and
`addon_cividash`.

See [Configuration](#configuration) for the full set of options and
[Required vaulted keys](#required-vaulted-keys) for everything that has no
default and must come from your vaulted inventory.

## Configuration

Defaults come from [`default_inventory.yml`](default_inventory.yml). Keys that
are absent or commented out there fall back to `default()` values in
[`templates/values.yaml.j2`](templates/values.yaml.j2) and
[`tasks/keycloak_sso.yml`](tasks/keycloak_sso.yml).

| Key (`inv_addons.cividash.*`) | Default | Notes |
| --- | --- | --- |
| `enable` | `true` | Enable the add-on |
| `ns_create` / `ns_name` | `true` / `{{ ENVIRONMENT }}-cividash-stack` | Namespace |
| `ns_kubeconfig` | `{{ kubeconfig_file \| default('kubeconfig') }}` | Kubeconfig used for the namespace/Helm tasks |
| `enable_ingress` | `true` | Render the `cividash-public` Ingress. Class from `inv_k8s.ingress_class`, default `traefik` |
| `register_apisix_route` | `true` | Register the open APISIX route, independent of `enable_ingress` and `gateway_api`; `false` disables it |
| `public_host` / `admin_host` | `dashboard.{{ DOMAIN }}` / `dashboard.{{ DOMAIN }}` | Public hostname(s). `public_host` is required when `enable_ingress`, `gateway_api.enabled` or `register_apisix_route` is true |
| `oidc_client_id` | `cividash` | Keycloak client id |
| `ngsi_ld_roles` | `["dataConsumer", "dataProducer"]` | NGSI-LD client roles granted to the shared `api-access` service account — see [Authentication](docs/authentication.md) |
| `ngsi_ld_scope` | `api:read api:write` | OAuth scope requested for the NGSI-LD machine token — see [Authentication](docs/authentication.md) |
| `m2m_preflight_enabled` | `true` | Deploy-time check that the M2M token works — see [Authentication](docs/authentication.md) |
| `keycloak_base_url_internal` | in-cluster Keycloak service | Override if the SSO token exchange needs a different internal endpoint — see [Troubleshooting](docs/troubleshooting.md) |
| `replicas.{web,fpm}` | `2` / `2` | Deployment replica counts |
| `log_level` / `log_channel` | `info` / `stderr` | Production hardening, override only to loosen for debugging |
| `session_secure_cookie` | `true` | Production hardening |
| `db.central` | `false` | `true`: create the database and its role in the central CORE Postgres (`central-db`) and read the credentials from there; `db.host`/`db.password` are then not needed — see [Database](docs/database.md) |
| `db.host` | — | External PostgreSQL host, **required** unless `db.central`, vaulted |
| `db.port` / `db.database` / `db.username` | `5432` / `cividash` / `cividash` | Optional overrides |
| `db.password` | — | **Required** unless `db.central`, vaulted |
| `civitas_api_url` | `https://api.{{ DOMAIN }}` | CIVITAS API base URL |
| `s3.{endpoint,bucket,region}` | see `default_inventory.yml` | S3 media storage. Use a bucket for CiviDash media only; it can stay private |
| `s3.public_url` | `""` | Empty: media is served by the dashboard under `/storage`. A bucket URL makes browsers load media from the bucket directly, which needs anonymous read on it |
| `s3.access_key_id` / `s3.secret_access_key` | — | **Required**, vaulted |
| `s3.use_path_style` | `true` | Path-style S3 URLs (`AWS_USE_PATH_STYLE_ENDPOINT`), needed for MinIO and most self-hosted S3 |
| `seed.*` | see [Initial config data](docs/seed.md) | Initial data seeding |
| `gateway_api.{enabled,parentRefs}` | `false` / — | Render a Gateway API `HTTPRoute` alongside the Ingress. `enable_ingress: false` gives `HTTPRoute`-only routing — see [Helm chart, Routing](docs/helm-chart.md#routing) |
| `images.{app,web}.{registry,repository,tag}` | see `vars/software_references.yml` | Optional per-image override of the default image, e.g. for a mirror or a different tag — see [Helm chart, Images](docs/helm-chart.md#images) |
| `image_pull_policy` | `Always` | `imagePullPolicy` for the app and web images |
| `image_pull_secret` | `""` | Name of an existing pull Secret, needed for private registries |
| `helm_values` | — | Recursive override merged on top of the rendered chart values, e.g. `ingress.annotations` for Ingress annotations such as a Traefik entrypoint or redirect Middleware |

The optional controller-side database check in `tasks/database.yml` is
controlled by two top-level variables (not under `inv_addons.cividash`):
`cividash_db_readiness_check` (default `false`) and
`cividash_db_readiness_timeout` (default `60` seconds). See
[Database](docs/database.md).

### Required vaulted keys

The following keys have no default and **must** be supplied via your (vaulted)
platform inventory. The deploy asserts their presence and fails fast otherwise:

- `inv_addons.cividash.db.host` — PostgreSQL hostname, rendered into
  `cividash-db-secret` as `DB_HOST`. Not needed with `db.central: true`.
- `inv_addons.cividash.db.password` — PostgreSQL password, rendered into
  `cividash-db-secret` as `DB_PASSWORD`. Not needed with `db.central: true`.
- `inv_addons.cividash.s3.access_key_id` — S3 access key, rendered into
  `cividash-app-secret` as `AWS_ACCESS_KEY_ID`.
- `inv_addons.cividash.s3.secret_access_key` — S3 secret key, rendered into
  `cividash-app-secret` as `AWS_SECRET_ACCESS_KEY`.

## What it deploys

Into the namespace `{{ ENVIRONMENT }}-cividash-stack`. The add-on runs no
database server. With `db.central: true` it registers a database in the
central CORE Postgres; otherwise it connects to an externally provisioned
PostgreSQL (see [Database](docs/database.md)).

| Object | Kind | Notes |
| --- | --- | --- |
| `cividash-db-secret` | Secret (Helm hook) | External-Postgres connection; `pre-install,pre-upgrade`, weight `0` |
| `cividash-app-secret` | Secret (Helm hook) | `APP_KEY` (idempotent) + app env; `pre-install,pre-upgrade`, weight `0` |
| `cividash-oidc-secret` | Secret | Keycloak client id + secret, written by the SSO task (not part of the chart — see [Authentication](docs/authentication.md)) |
| `cividash-migrate` | Job (Helm hook) | `php artisan migrate --force`; `pre-install,pre-upgrade`, weight `5` |
| `cividash-seed` | Job (Helm hook) | Initial config data; `post-install,post-upgrade`, weight `10` — see [Initial config data](docs/seed.md) |
| `cividash-fpm` | Deployment + Service (9000) | php-fpm, the full Laravel/Filament app |
| `cividash-web` | Deployment + Service (80 -> 8080) | rootless nginx (uid 101) + baked public assets |
| `cividash-queue` | Deployment | `php artisan queue:work` |
| `cividash-scheduler` | Deployment | loops `php artisan schedule:run` every 60s |
| `cividash-public` | Ingress and/or Gateway API `HTTPRoute` | Ingress when `enable_ingress` (class `traefik` by default), `HTTPRoute` when `gateway_api.enabled` (independent); `public_host` -> `cividash-web` |
| APISIX upstream + route | APISIX Admin API | when `register_apisix_route`; open route `public_host` `/*` -> `cividash-web` (see [Authentication](docs/authentication.md)) |

All PHP pods run with a hardened pod-security context (`runAsNonRoot`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`). Media is stored on S3 (`PUBLIC_DISK_DRIVER=s3`);
sessions, cache and queue use the database; logs go to stderr. Images are
built by the CiviDash main repository — see [Helm chart, Images](docs/helm-chart.md#images).

## Versioning and compatibility

The add-on's major and minor version (`chart/cividash/Chart.yaml`) follow the
highest CORE version it is tested against: add-on `1.8.x` is tested on CORE
`1.8.x` and also supports CORE `1.7.2` and later. The patch digit is
independent. Breaking changes to the inventory structure are
documented in `CHANGELOG.md`.

| Component | Version |
| --- | --- |
| cividash add-on (this repo/chart) | 1.8.2 |
| CIVITAS/CORE platform | 1.7.2 – 1.8.x (tested on 1.8.1) |
| CiviDash app image (`cividash_app`/`cividash_web`) | release tag `1.1.3`, `linux/amd64` and `linux/arm64` |
| Helm | >= 3.14 |
| Kubernetes | >= 1.28 |

Kubernetes >= 1.28 is the supported floor, not
a floor derived from the chart's own API usage — `apps/v1`, `batch/v1` and
`networking.k8s.io/v1 Ingress` only require Kubernetes >= 1.19. With
`inv_addons.cividash.gateway_api.enabled: true` (chart value
`gatewayApi.enabled`) the chart additionally needs Gateway API CRDs
>= v1.0 installed on the cluster, independent of the Kubernetes version.

Installations on CORE 1.6.x stay on add-on `1.6.x`. Before upgrading to
1.8.x, read the Breaking section of the 1.8.0 entry in `CHANGELOG.md`
(Traefik as default ingress class, the separate APISIX route switch,
`open_http_port`) and the operator steps for `api-access` in
[Authentication](docs/authentication.md#operator-prerequisites-m2m--api-access).
During the upgrade from CiviDash 1.0.x to 1.1.0, new `cividash-web` pods can
serve the 1.1.0 frontend while old `cividash-fpm` pods still run 1.0.x, which
has no `/api/v1` routes. Dashboards opened in that window of the rollout may
fail to load data until the page is reloaded; plan the upgrade outside peak
hours.

Media on S3: images up to CiviDash 1.1.2 stored objects under the container path
(`var/www/html/storage/app/public/…`) and needed a bucket with anonymous read.
From CiviDash 1.1.3, objects sit at the bucket root and the dashboard
serves them under `/storage`. When upgrading an installation that already has
uploads, copy (do not move) the objects to the bucket root, stripping that
prefix, before the upgrade, so pods still on 1.1.2 keep finding them during the
rollout. Avoid uploads until all pods run 1.1.3, then delete the prefixed copies,
or upload the media again instead. Re-import theme bundles, and leave
`s3.public_url` empty unless the bucket stays public on purpose.

`cc_cli validate` rejects `inv_addons.cividash` ("Additional properties are not
allowed"), because the CORE inventory schema (`InvAddons` in
`core_platform/inventory_schema.json`, CORE 1.6 to 1.8) only allows `import`
and `addons`. The platform playbook merges and uses the keys as intended;
validate the inventory without the `cividash` block, or skip `cc_cli validate`
for it.

**Cutting a release:** tag this repo `v1.8.x` and publish a GitHub release for
the tag. Publishing runs the `Release SBOM` workflow, which attaches the image
SBOMs; a pushed tag alone does not. If it did not run, start it by hand with
the tag. Images are pinned to an
immutable CiviDash release tag in
[`vars/software_references.yml`](vars/software_references.yml), corresponding
to CiviDash 1.1.3. Never reference the moving `civitas` tag from an add-on
release or an inventory.

## Uninstall

`helm uninstall cividash --namespace <ns>` removes the Deployments, Services,
Ingress/`HTTPRoute` and the Helm hook Jobs — but not everything the add-on
created:

- **Hook Secrets** (`cividash-app-secret`, `cividash-db-secret`) are not part
  of the Helm release manifest and survive `helm uninstall`.
  `cividash-oidc-secret`, written by `tasks/keycloak_sso.yml` rather than by
  Helm, is never removed by Helm either. Delete all three explicitly:
  `kubectl -n <ns> delete secret cividash-app-secret cividash-db-secret cividash-oidc-secret`.
- **Keycloak client** (`cividash`) and its `admin`/`editor` roles, registered
  by `tasks/keycloak_sso.yml`, are outside Helm's scope. Delete them via the
  Keycloak admin console/API.
- **APISIX upstream + route**, registered by `tasks/apisix.yml`, are likewise
  outside Helm's scope. Remove them via the APISIX Admin API.
- **S3 media** (`PUBLIC_DISK_DRIVER=s3`) is untouched by uninstall; the
  bucket and its objects remain and must be cleaned up separately.
- **PVCs:** none — media is on S3 and the database is external, so there is
  nothing chart-owned to reclaim beyond the Secrets/Keycloak/APISIX objects
  above.

## Documentation

- [Helm chart](docs/helm-chart.md) — installation wrapper, values, routing, verifying the chart locally, images
- [Authentication](docs/authentication.md) — admin auth, the NGSI-LD machine token, operator prerequisites
- [Database](docs/database.md) — central CORE Postgres or external PostgreSQL
- [Initial config data](docs/seed.md) — the `cividash-seed` hook Job
- [Troubleshooting](docs/troubleshooting.md)
- [Components](docs/components.md) — what a deployment consists of, and the image SBOMs attached to each release
- [Conformance with the CORE add-on guideline](docs/core-guideline-conformance.md)
- [`CHANGELOG.md`](CHANGELOG.md)

## Contributing, security and license

GitHub is the working and release repository:
<https://github.com/jandaroscher/cividash-addon>. Issues, pull
requests, Renovate dependency updates and release tags live there. The
application images are built from the main repository's releases and
published to GitHub Container Registry at `ghcr.io/jandaroscher`. Watch both GitHub repositories for new releases and
security fixes. The openCode repository
(<https://gitlab.opencode.de/regensburg_next/cividash-addon>) is a mirror;
changes made there are not merged back.

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

Licensed under the EUPL-1.2 or later, see [LICENSE](LICENSE) and
[NOTICE](NOTICE).
