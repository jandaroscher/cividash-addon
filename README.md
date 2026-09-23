# CiviDash CIVITAS/CORE Add-on

Packages **CiviDash**, the sustainability dashboard (Laravel 12 + Filament +
a Vue 3 SPA), as a **CIVITAS/CORE** add-on. This is a **deploy-only**
repository: a local Helm chart ([`chart/cividash/`](chart/cividash/))
installed through the central platform Helm task, plus `uri`-based Keycloak /
APISIX Admin-API calls for SSO and gateway registration (outside Helm's
scope). The application code lives in the
[CiviDash main repository](https://gitlab.opencode.de/regensburg_next/cividash)
on openCode and ships here as prebuilt container images.

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
| `enable_ingress` | `true` | Render the `cividash-public` Ingress, register the APISIX route and require `public_host`; `false` skips all three |
| `public_host` / `admin_host` | `dashboard.{{ DOMAIN }}` / `dashboard.{{ DOMAIN }}` | Public hostname(s) |
| `open_http_port` | `true` | Set `false` to disable the ingress-nginx SSL redirect (e.g. TLS terminated upstream) |
| `oidc_client_id` | `cividash` | Keycloak client id |
| `ngsi_ld_roles` | `["dataConsumer", "dataProducer"]` | NGSI-LD client roles granted to the shared `api-access` service account — see [Authentication](docs/authentication.md) |
| `ngsi_ld_scope` | `api:read api:write` | OAuth scope requested for the NGSI-LD machine token — see [Authentication](docs/authentication.md) |
| `m2m_preflight_enabled` | `true` | Deploy-time check that the M2M token works — see [Authentication](docs/authentication.md) |
| `keycloak_base_url_internal` | in-cluster Keycloak service | Override if the SSO token exchange needs a different internal endpoint — see [Troubleshooting](docs/troubleshooting.md) |
| `replicas.{web,fpm}` | `2` / `2` | Deployment replica counts |
| `log_level` / `log_channel` | `info` / `stderr` | Production hardening, override only to loosen for debugging |
| `session_secure_cookie` | `true` | Production hardening |
| `db.host` | — | External PostgreSQL host, **required**, vaulted |
| `db.port` / `db.database` / `db.username` | `5432` / `cividash` / `cividash` | Optional overrides |
| `db.password` | — | **Required**, vaulted |
| `civitas_api_url` | `https://api.{{ DOMAIN }}` | CIVITAS API base URL |
| `s3.{endpoint,bucket,public_url,region}` | see `default_inventory.yml` | S3 media storage |
| `s3.access_key_id` / `s3.secret_access_key` | — | **Required**, vaulted |
| `s3.use_path_style` | `true` | Path-style S3 URLs (`AWS_USE_PATH_STYLE_ENDPOINT`), needed for MinIO and most self-hosted S3 |
| `seed.*` | see [Initial config data](docs/seed.md) | Initial data seeding |
| `gateway_api.{enabled,parentRefs}` | `false` / — | Render a Gateway API `HTTPRoute` alongside the Ingress. `enable_ingress: false` gives `HTTPRoute`-only routing but also skips the APISIX route — see [Helm chart, Routing](docs/helm-chart.md#routing) |
| `image_pull_policy` | `Always` | `imagePullPolicy` for the app and web images |
| `image_pull_secret` | `""` | Name of an existing pull Secret, needed for private registries |
| `helm_values` | — | Recursive override merged on top of the rendered chart values |

The optional controller-side database check in `tasks/database.yml` is
controlled by two top-level variables (not under `inv_addons.cividash`):
`cividash_db_readiness_check` (default `false`) and
`cividash_db_readiness_timeout` (default `60` seconds). See
[Database](docs/database.md).

### Required vaulted keys

The following keys have no default and **must** be supplied via your (vaulted)
platform inventory. The deploy asserts their presence and fails fast otherwise:

- `inv_addons.cividash.db.host` — PostgreSQL hostname, rendered into
  `cividash-db-secret` as `DB_HOST`.
- `inv_addons.cividash.db.password` — PostgreSQL password, rendered into
  `cividash-db-secret` as `DB_PASSWORD`.
- `inv_addons.cividash.s3.access_key_id` — S3 access key, rendered into
  `cividash-app-secret` as `AWS_ACCESS_KEY_ID`.
- `inv_addons.cividash.s3.secret_access_key` — S3 secret key, rendered into
  `cividash-app-secret` as `AWS_SECRET_ACCESS_KEY`.

## What it deploys

Into the namespace `{{ ENVIRONMENT }}-cividash-stack`. The database is **not**
deployed by the add-on — it connects to an externally provisioned PostgreSQL
(see [Database](docs/database.md)).

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
| `cividash-public` | Ingress and/or Gateway API `HTTPRoute` | Ingress when `enable_ingress`, `HTTPRoute` when `gateway_api.enabled` (independent); `public_host` -> `cividash-web` |
| APISIX upstream + route | APISIX Admin API | when `enable_ingress`; open route `public_host` `/*` -> `cividash-web` (see [Authentication](docs/authentication.md)) |

All PHP pods run with a hardened pod-security context (`runAsNonRoot`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`). Media is stored on S3 (`PUBLIC_DISK_DRIVER=s3`);
sessions, cache and queue use the database; logs go to stderr. Images are
built by the CiviDash main repository — see [Helm chart, Images](docs/helm-chart.md#images).

## Versioning and compatibility

The add-on's Helm chart version (`chart/cividash/Chart.yaml`) follows the
CORE platform's minor version — add-on `1.6.x` targets CORE `1.6.x`. The
patch digit is independent. Breaking changes to the inventory structure are
documented in `CHANGELOG.md`.

| Component | Version |
| --- | --- |
| cividash add-on (this repo/chart) | 1.6.1 |
| CIVITAS/CORE platform | 1.6.2 – 1.6.3 |
| CiviDash app image (`cividash_app`/`cividash_web`) | immutable tag `civitas-89f199edfe4e` |
| Helm | >= 3.14 |
| Kubernetes | >= 1.28 |

Kubernetes >= 1.28 is the tested/supported floor (CORE 1.6.x platforms), not
a floor derived from the chart's own API usage — `apps/v1`, `batch/v1` and
`networking.k8s.io/v1 Ingress` only require Kubernetes >= 1.19. With
`inv_addons.cividash.gateway_api.enabled: true` (chart value
`gatewayApi.enabled`) the chart additionally needs Gateway API CRDs
>= v1.0 installed on the cluster, independent of the Kubernetes version.

**Cutting a release:** tag this repo `v1.6.x`. Images are pinned to an
immutable `civitas-<gitsha>` build tag in
[`vars/software_references.yml`](vars/software_references.yml), corresponding
to CiviDash 1.0.0. Never reference the moving `civitas` tag from an add-on
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
- [Database](docs/database.md) — external PostgreSQL, provisioning
- [Initial config data](docs/seed.md) — the `cividash-seed` hook Job
- [Troubleshooting](docs/troubleshooting.md)
- [Conformance with the CORE add-on guideline](docs/core-guideline-conformance.md)
- [`CHANGELOG.md`](CHANGELOG.md)

## Contributing, security and license

The canonical repository is on openCode:
<https://gitlab.opencode.de/regensburg_next/cividash-addon>. A mirror is
published on GitHub: <https://github.com/jandaroscher/cividash-addon>.

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

Licensed under the EUPL-1.2 or later, see [LICENSE](LICENSE) and
[NOTICE](NOTICE).
