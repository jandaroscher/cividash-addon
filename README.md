# CiviDash CIVITAS/CORE Add-on

Packages the **CIVIDASH** sustainability dashboard (Laravel 12 + Filament + a Vue 3
SPA) as a **CIVITAS/CORE** add-on. This is a **deploy-only** repository: Ansible
plus raw Kubernetes Jinja2 manifests (**no Helm chart**). The application code
lives in the CIVIDASH main repository and ships here as prebuilt container images.

The add-on follows the `airflow_addon` pattern — raw `kubernetes.core.k8s`
manifests and `uri`-based Keycloak / APISIX Admin-API calls — not a Helm chart.

## What it deploys

Into the namespace `{{ ENVIRONMENT }}-cividash-stack`:

The database is **not** deployed by the add-on: it connects to an **externally
provisioned PostgreSQL** (see **R1**).

| Object | Kind | Notes |
| --- | --- | --- |
| `cividash-db-secret` | Secret | External-Postgres connection (`DB_CONNECTION`/`DB_HOST`/`DB_PORT`/`DB_DATABASE`/`DB_USERNAME`/`DB_PASSWORD`), rendered from the role vars |
| `cividash-app-secret` | Secret | `APP_KEY` (generated idempotently) + app env |
| `cividash-oidc-secret` | Secret | Keycloak client id + secret, written by the SSO task |
| `cividash-migrate` | Job | `php artisan migrate --force`, runs before workloads |
| `cividash-fpm` | Deployment + Service (9000) | php-fpm, the full Laravel/Filament app |
| `cividash-web` | Deployment + Service (80) | nginx + baked public assets, `fastcgi_pass cividash-fpm:9000` |
| `cividash-queue` | Deployment | `php artisan queue:work` |
| `cividash-scheduler` | Deployment | loops `php artisan schedule:run` every 60s |
| Ingress | Ingress | when `enable_ingress`, `public_host` -> `cividash-web` |
| APISIX upstream + route | APISIX Admin API | open route `public_host` `/*` -> `cividash-web` (see **Admin auth**) |

All pods run with a hardened pod-security context (`runAsNonRoot`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`; `cividash_app` runs as uid 82). Per-pod writable paths
are `emptyDir` mounts at `/var/www/html/storage/framework` and
`/var/www/html/bootstrap/cache`. Media is stored on S3
(`PUBLIC_DISK_DRIVER=s3`); sessions, cache and queue use the database; logs go
to stderr.


The CiviDash main repository builds and publishes two images to GHCR:

- `cividash_app` -> `ghcr.io/jandaroscher/cividash-app` — php-fpm, the full application.
  Used by `cividash-fpm`, `cividash-queue`, `cividash-scheduler` and the `cividash-migrate` Job.
- `cividash_web` -> `ghcr.io/jandaroscher/cividash-web` — nginx with the baked public
  assets, proxying PHP to `cividash-fpm:9000`.

Tags/registries are configured in [`vars/software_references.yml`](vars/software_references.yml)
under `software.addon_cividash.{cividash_app,cividash_web}.{registry,repository,tag}`.
When `inv_op_stack.private_registry.registry_full_url` is set, it overrides the
per-image registry (platform private-registry support).

## Installation

Clone (or copy/symlink) this repository into the `addons/` folder of the
`civitas_core` deployment repository as `addons/cividash_addon/`.

Activate it in your inventory:

```yaml
inv_addons:
  import: true
  addons:
    - 'addons/cividash_addon/tasks.yml'
```

## Configuration

Defaults come from [`default_inventory.yml`](default_inventory.yml) and can be
overridden from your platform inventory:

```yaml
inv_addons:
  cividash:
    enable: true
    ns_create: true
    ns_name: "{{ ENVIRONMENT }}-cividash-stack"
    ns_kubeconfig: "{{ kubeconfig_file | default('kubeconfig') }}"
    enable_ingress: true
    public_host: "dashboard.{{ DOMAIN }}"
    admin_host: "dashboard.{{ DOMAIN }}"
    oidc_client_id: "cividash"
    replicas: { web: 2, fpm: 2 }
    # External PostgreSQL connection. host + password are REQUIRED and must come
    # from your VAULTED inventory; database/username/port default in vars/default.yml.
    db:
      host: "cividash-postgres.core-postgres.svc.cluster.local"  # REQUIRED
      port: 5432
      database: "cividash"
      username: "cividash"
      # password: "..."  # REQUIRED, supply via vaulted inventory
    civitas_api_url: "https://api.{{ DOMAIN }}"
    s3:
      endpoint: "https://s3.{{ DOMAIN }}"
      bucket: "cividash"
      public_url: "https://s3.{{ DOMAIN }}/cividash"
      region: "us-east-1"
      # access_key_id / secret_access_key are REQUIRED and must be supplied
      # via your vaulted inventory (see "Required vaulted keys" below).
```

### Required vaulted keys

The following keys have no default and **must** be supplied via your (vaulted)
platform inventory. The deploy asserts their presence and fails fast otherwise:

- `inv_addons.cividash.db.host` — hostname of the externally provisioned
  PostgreSQL, rendered into `cividash-db-secret` as `DB_HOST`.
- `inv_addons.cividash.db.password` — PostgreSQL password, rendered into
  `cividash-db-secret` as `DB_PASSWORD`.
- `inv_addons.cividash.s3.access_key_id` — S3 access key, rendered into
  `cividash-app-secret` as `AWS_ACCESS_KEY_ID`.
- `inv_addons.cividash.s3.secret_access_key` — S3 secret key, rendered into
  `cividash-app-secret` as `AWS_SECRET_ACCESS_KEY`.

`db.port` (default `5432`), `db.database` (default `cividash`) and `db.username`
(default `cividash`) are optional and fall back to the defaults in
[`vars/default.yml`](vars/default.yml).

## Execute

The add-on installs after all other core-platform tasks. To run only this
add-on, use the tags `addons` and `addon_cividash`.

## Admin auth — handled by the APP, NOT by APISIX

The APISIX gateway registration ([`tasks/apisix.yml`](tasks/apisix.yml)) creates
**exactly one OPEN route**: host `public_host`, uri prefix `/*`, forwarding to
the `cividash-web` upstream. There is **deliberately no `openid-connect` / auth
plugin** on this route. It covers `/`, `/api/*`, `/admin`, `/filament` and
`/docs` — and the Laravel/Filament application enforces its own authentication
(Fortify, plus optional Keycloak Socialite SSO for the admin panel).

The add-on still registers a Keycloak client (`cividash`) because the
**app** uses it, not APISIX, for admin SSO: the Socialite standard flow with
redirect `https://{{ admin_host | default(public_host) }}/admin/auth/keycloak/callback`.

The `cividash` client secret is written to `cividash-oidc-secret` (as the
`KEYCLOAK_*` keys) and consumed via app env. APISIX never consumes this client.

### NGSI-LD machine token — shared `api-access` client

The machine-to-machine NGSI-LD token (`CIVITAS_DRIVER=ngsi-ld`,
`CIVITAS_OAUTH_*` in `cividash-oidc-secret`) is **no longer** issued by the
`cividash` client. It is issued by the shared, operator-provided
**`api-access`** IDM client — the same client the CORE data plane (Stellio
behind APISIX) already trusts — mirroring `redpandaconnect_addon`'s FROST
OAuth2 wiring. `tasks/keycloak_sso.yml`:

1. fetches the `api-access` client-secret via the shared platform helper
   `tasks/templates/keycloak_client_secret.yaml` (`client_id: IDM_CLIENT.API_ACCESS`);
2. ensures the purpose-scoped client roles (`dataConsumer` / `dataProducer`,
   overridable via `inv_addons.cividash.ngsi_ld_roles`) that make Keycloak
   mint the `api:read` / `api:write` scopes the CORE APISIX gateway enforces;
3. assigns those roles to the `api-access` service account (idempotent).

The `cividash` client has `serviceAccountsEnabled: false`; it only carries the
auth-code SSO flow and its audience mapper.

> **Platform dependency:** `IDM_CLIENT.API_ACCESS` and the shared task
> `tasks/templates/keycloak_client_secret.yaml` are provided by the CORE
> control plane at run time (not vendored in this add-on), exactly as
> `redpandaconnect_addon` relies on them. Keep the `dataConsumer`/`dataProducer`
> convention in sync with the platform's api:read/api:write scope mapping.

> **Note:** If Filament admin access is gated on a Keycloak role/group, the
> first admin must be granted the `cividash:admin` role in Keycloak
> manually. The add-on creates the client roles (`admin`, `editor`) but does
> not assign them to any user.

## R1 — Database (resolved): external PostgreSQL

**Resolved.** Earlier revisions of this add-on bundled its own **MariaDB**
`cividash-db` StatefulSet + PVC, which was **not** a CORE-native convention (CORE is
Postgres-only via the Zalando Postgres operator) and shipped with no operator,
no managed backups and no Velero integration.

The dashboard application is **database-agnostic** — it reads the standard
Laravel connection env (`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`,
`DB_USERNAME`, `DB_PASSWORD`) and the production image already bundles the
`pdo_pgsql` driver. The add-on therefore now targets **PostgreSQL**, the
CORE-native database, and **no longer runs a database server itself**. It only
renders the connection Secret (`cividash-db-secret`) from the role vars and connects
to an externally provisioned Postgres. This mirrors the main-repo switch to
PostgreSQL and closes the open policy question.

### Provisioning the PostgreSQL (out of scope for the add-on)

The Postgres instance/database is provided by the operator / CORE. The add-on is
agnostic to the topology — any option works as long as the connection details are
supplied. `db.host` and `db.password` are **required** (no default); `db.port`,
`db.database` and `db.username` fall back to the defaults in
[`vars/default.yml`](vars/default.yml):

1. **Dedicated Zalando `postgresql` cluster** in the CORE cluster (operator-managed
   backups, HA). Point `db.host` at its Service.
2. **`preparedDatabases` schema + role in the central CORE Postgres** — a
   database/role carved out of the shared cluster. Point `db.host` at the shared
   endpoint and `db.database`/`db.username` at the prepared database/role.

retention are handled by whichever Postgres the operator provisions, not by this
add-on.
