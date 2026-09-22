# CiviDash CIVITAS/CORE Add-on

Packages **CiviDash**, the sustainability dashboard (Laravel 12 + Filament +
a Vue 3 SPA), as a **CIVITAS/CORE** add-on. This is a **deploy-only**
repository: a local Helm chart ([`chart/cividash/`](chart/cividash/))
installed through the central platform Helm task, plus `uri`-based Keycloak /
APISIX Admin-API calls for SSO and gateway registration (outside Helm's
scope). The application code lives in the
on openCode at

> **Breaking change:** the add-on now installs via Helm
> (`helm_release_name: cividash`) instead of raw `kubernetes.core.k8s`
> manifests. Existing deployments must be migrated once: `helm install` does
> not adopt resources it didn't create, and the chart's Deployment selectors
> now include `app.kubernetes.io/instance` (Kubernetes selectors are
> immutable), so in-place adoption of the Deployments is not possible. Before
> the first Helm run, delete only the non-Secret objects:
> `kubectl -n <ns> delete --ignore-not-found=true deploy cividash-fpm cividash-web
> cividash-queue cividash-scheduler svc cividash-fpm cividash-web ingress cividash-public
> job cividash-migrate` (`--ignore-not-found` covers the Ingress when
> `enable_ingress` was false and the migrate Job when it already finished).
> Do **not** delete `cividash-app-secret` / `cividash-db-secret`: they are Helm hook
> resources (`before-hook-creation`), so Helm deletes and recreates them
> itself on the first run, and the chart's `lookup` preserves the existing
> `APP_KEY` from `cividash-app-secret`. `cividash_db_*` role-var names were dropped in
> favor of `inv_addons.cividash.db.*` read directly by the chart values
> (no inventory change needed if you were already using `db.*`).
>
> Hook Secrets are also not part of the Helm release manifest: `helm
> uninstall cividash --namespace <ns>` leaves `cividash-app-secret` and
> `cividash-db-secret` behind, and `cividash-oidc-secret` (written by the SSO task)
> is never removed by Helm either. Delete all three explicitly when
> decommissioning:
> `kubectl -n <ns> delete secret cividash-app-secret cividash-db-secret cividash-oidc-secret`.

## What it deploys

Into the namespace `{{ ENVIRONMENT }}-cividash-stack`:

The database is **not** deployed by the add-on: it connects to an **externally
provisioned PostgreSQL** (see **R1**).

| Object | Kind | Notes |
| --- | --- | --- |
| `cividash-db-secret` | Secret (Helm hook) | External-Postgres connection (`DB_CONNECTION`/`DB_HOST`/`DB_PORT`/`DB_DATABASE`/`DB_USERNAME`/`DB_PASSWORD`); `pre-install,pre-upgrade`, weight `0` |
| `cividash-app-secret` | Secret (Helm hook) | `APP_KEY` (idempotent) + app env; `pre-install,pre-upgrade`, weight `0` |
| `cividash-oidc-secret` | Secret | Keycloak client id + secret, written by the SSO task (NOT part of the chart — see **Helm chart** below) |
| `cividash-migrate` | Job (Helm hook) | `php artisan migrate --force`; `pre-install,pre-upgrade`, weight `5` (after the two secrets above) |
| `cividash-seed` | Job (Helm hook) | initial config data (tenant backfill/domain, optional pages/dashboard seed); `post-install,post-upgrade`, weight `10` — see "Initial config data" below |
| `cividash-fpm` | Deployment + Service (9000) | php-fpm, the full Laravel/Filament app |
| `cividash-web` | Deployment + Service (80 -> 8080) | rootless nginx (uid 101) + baked public assets, `fastcgi_pass cividash-fpm:9000` |
| `cividash-queue` | Deployment | `php artisan queue:work` |
| `cividash-scheduler` | Deployment | loops `php artisan schedule:run` every 60s |
| `cividash-public` | Ingress and/or Gateway API `HTTPRoute` | Ingress when `enable_ingress`, `HTTPRoute` when `gateway_api.enabled` (independent); `public_host` -> `cividash-web` |
| APISIX upstream + route | APISIX Admin API | open route `public_host` `/*` -> `cividash-web` (see **Admin auth**) |

All PHP pods (`cividash-fpm`, `cividash-queue`, `cividash-scheduler`, `cividash-migrate`,
`cividash-seed`) run with a hardened pod-security context (`runAsNonRoot`,
`seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation: false`,
`capabilities.drop: [ALL]`; `cividash_app` runs as uid 82, `cividash-web` as the
nginx user uid 101 on `nginxinc/nginx-unprivileged`, listening on 8080 behind
the Service port 80). Media is stored on S3
(`PUBLIC_DISK_DRIVER=s3`); sessions, cache and queue use the database; logs go
to stderr.


The CiviDash main repository builds and publishes two images to GHCR:

- `cividash_app` -> `ghcr.io/jandaroscher/cividash-app` — php-fpm, the full application.
  Used by `cividash-fpm`, `cividash-queue`, `cividash-scheduler` and the `cividash-migrate`/`cividash-seed` Jobs.
- `cividash_web` -> `ghcr.io/jandaroscher/cividash-web` — nginx with the baked public
  assets, proxying PHP to `cividash-fpm:9000`.

Tags/registries are configured in [`vars/software_references.yml`](vars/software_references.yml)
under `software.addon_cividash.{cividash_app,cividash_web}.{registry,repository,tag}`.
When `inv_op_stack.private_registry.registry_full_url` is set, it overrides the
per-image registry (platform private-registry support).

**maintainer test stack only** and **must not** be used in any inventory: it can move
under a running deployment without any version bump in this repo. Pin
inventories to an immutable `civitas-<gitsha>` tag (or, once available, a

## Versioning and compatibility

**Scheme:** the add-on's Helm chart version (`chart/cividash/Chart.yaml`)
follows the CORE platform's minor version — add-on `1.6.x` targets CORE
`1.6.x`. The patch digit is independent: the add-on may release `1.6.1`,
`1.6.2`, ... without a matching CORE patch, and vice versa. Breaking changes
to the inventory structure are documented in this README (see "Breaking
change" notes above) and in `CHANGELOG.md`.

| Component | Version |
| --- | --- |
| cividash add-on (this repo/chart) | 1.6.1 |
| CIVITAS/CORE platform | 1.6.2 – 1.6.3 |
| Helm | >= 3.14 |
| Kubernetes | >= 1.28 |

Kubernetes >= 1.28 is the tested/supported floor (CORE 1.6.x platforms), not
a floor derived from the chart's own API usage: `apps/v1`, `batch/v1` and
`networking.k8s.io/v1` `Ingress` only require Kubernetes >= 1.19. With
`inv_addons.cividash.gateway_api.enabled: true` (chart value
`gatewayApi.enabled`) the chart additionally needs Gateway API CRDs
>= v1.0 installed on the cluster (`gateway.networking.k8s.io/v1 HTTPRoute`),
independent of the Kubernetes version.

**Cutting a release:** tag this repo `v1.6.x` (git tag on the add-on repo; not
releases yet — until the main repo starts cutting a release tag, the
immutable `civitas-<gitsha>` tags in `vars/software_references.yml` are the
reference to pin against. Never reference the moving `civitas` tag from an
add-on release or an inventory.

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
    # Production hardening (defaults shown; override only to loosen for debugging).
    log_level: info
    log_channel: stderr
    session_secure_cookie: true
    # External PostgreSQL connection. host + password are REQUIRED and must come
    # from your VAULTED inventory; database/username/port default in the chart values.
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
[`templates/values.yaml.j2`](templates/values.yaml.j2) / the chart's
[`values.yaml`](chart/cividash/values.yaml).

## Helm chart

`tasks/cividash.yml` installs [`chart/cividash/`](chart/cividash/)
through the central platform task `tasks/templates/k8s-helm.yml` (per
guideline: Helm installs go through the central platform task, with chart
metadata sourced exclusively from `vars/software_references.yml`).
`helm_chart_name`, `helm_release_name` and `helm_chart_version` live in
[`vars/software_references.yml`](vars/software_references.yml) under
`software.addon_cividash`; no `helm_repo_name`/`helm_repo_url` is set, so
the wrapper takes its **local chart** branch (`chart_ref` is a filesystem
path, `chart/cividash`, not a repo/chart pair — `helm_chart_version` is
therefore metadata only and NOT forwarded to the wrapper's `helm_chart_version`
var). `helm_chart_reference` is anchored at `playbook_dir` (`{{ playbook_dir }}/{{
addon_dir }}chart/cividash`): `kubernetes.core.helm`'s `chart_ref` only
expands `~`, it does not resolve relative to the playbook, and the local
connection plugin shells out from the `ansible-playbook` process's own cwd —
so a bare `addon_dir`-relative path breaks when the playbook is run from a
different working directory (e.g. the CORE repo root).

**Log hygiene:** `tasks/cividash.yml` passes `helm_no_log: true`, but the
current `core_platform/tasks/templates/k8s-helm.yml` does not read that var
(no `no_log` on its `kubernetes.core.helm` task), so running the platform
playbook with `-v`/`-vvv` still prints the rendered chart values — including
`db.password`, `s3.secretAccessKey`, `APP_KEY` — to the log. Do not run the
Helm step with `-v` against shared/persisted logs until CORE adds
`no_log: "{{ helm_no_log | default(false) }}"` to that wrapper task. The
vendored `dev/k8s-helm.yml` used by the local smoke already honours
`helm_no_log`.

Chart values are rendered by [`templates/values.yaml.j2`](templates/values.yaml.j2)
from `inv_addons.cividash.*` + `software.addon_cividash.*` (image refs,
honouring the private-registry override) + `inv_k8s.ingress_class` /
`inv_k8s.cert_manager.issuer_name`. Override any chart value directly (values
the inventory has no dedicated key for yet, e.g. per-workload `resources.*`)
via `inv_addons.cividash.helm_values` — it is combined (recursive) on top
of the rendered values (see `default_inventory.yml`).

**APP_KEY idempotency** moved from an Ansible `k8s_info` dance into the chart
itself: `chart/cividash/templates/_helpers.tpl`'s `cividash.appKey`
uses `values.app.key` if set, else a Helm `lookup` of the existing
`cividash-app-secret`'s `APP_KEY` (so re-installs preserve it), else a freshly
generated `base64:`-prefixed key. `helm template` has no cluster to `lookup`
against, so it always generates a fresh key there — expected, and why CI's
`helm lint`/`helm template` runs don't assert a stable key.

**Routing:** `ingress.enabled` (default `true`) renders the `cividash-public`
`Ingress`. Set `gatewayApi.enabled: true` (`inv_addons.cividash.gateway_api.enabled`)
to additionally (or instead) render a `gateway.networking.k8s.io/v1 HTTPRoute`
named `cividash-public` for the same host -> `cividash-web:80`; supply
`gatewayApi.parentRefs` naming your Gateway.

Verify locally:

```bash
helm lint chart/cividash
helm template cividash chart/cividash
helm template cividash chart/cividash -f chart/cividash/ci/smoke-values.yaml
```

## Initial config data (`cividash-seed`)

`chart/cividash/templates/cividash-seed.yaml` is a Helm hook Job
(`post-install,post-upgrade`, weight `10`, after `cividash-migrate` and the
workloads created by the same `helm upgrade --install`), per guideline:
"initial loading of configuration data" via an add-on-local step after
deployment. A Job, not an init script, per request. Gated by `seed.enabled`
(default `true`, `inv_addons.cividash.seed.enabled`). Steps, all
idempotent and safe to re-run on every install/upgrade:

1. `php artisan tenancy:backfill --default-tenant={{ seed.defaultTenant }}` —
   creates the tenant only if it doesn't exist yet (`Tenant::firstOrCreate`,
   CiviDash main repo `app/Console/Commands/TenancyBackfillCommand.php`).
2. When `seed.setTenantDomain` (default `true`): sets the default tenant's
   `domain` to `app.publicHost` via `php artisan tinker`, only when it
   differs — there is no dedicated artisan command for this.
3. When `seed.pages` (default `false`): `php artisan pages:seed`. Idempotent:
   slug and only updates changed fields, `NavigationSeeder` skips once header
   navigation items exist.
4. When `seed.dashboardJsonUrl` is non-empty (default empty): `php artisan
   `CategorySeeder`/`TileSeeder` find-or-create per slug/title and only
   update changed fields; `MetricSeeder` documents idempotent upserts.

Values: `inv_addons.cividash.seed.{enabled,default_tenant,set_tenant_domain,pages,dashboard_json_url}`
(see `default_inventory.yml`).

**`seed.pages` / `seed.dashboardJsonUrl` require `seed.defaultTenant: default`.**
Both seeders operate on a hardcoded `"default"` tenant slug elsewhere in the
CiviDash main repo (`BelongsToTenant`'s creating-hook falls back to
`Tenant::where('slug', 'default')`; `DashboardSeedCommand`'s tile-branding
fallback chain does the same, and its own `--tenant` option is never read).
With a different `seed.defaultTenant` and no `default` tenant, the Job would
fail; with one present, content would land in the wrong tenant. The chart
enforces this with a `fail` guard at render time.

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

### Operator prerequisites (M2M / api-access)

The NGSI-LD machine token rides on the shared `api-access` client, which the
**operator** owns and provisions — the add-on does not create it and, mirroring
`redpandaconnect_addon`, deliberately does **not** enable service accounts or
edit group membership on it. For the M2M flow to actually work, `api-access`
must be provisioned so that:

1. **`serviceAccountsEnabled = true`** — otherwise Keycloak mints **no**
   client-credentials token at all (`401 unauthorized_client`).
2. The **`api:read` / `api:write`** scopes are requestable by the client (these
   are the scopes the CORE APISIX gateway enforces in front of Stellio). The
   add-on requests them via `CIVITAS_OAUTH_SCOPE` (default `api:read api:write`,
   override with `inv_addons.cividash.ngsi_ld_scope`).
3. The **`api-access` service account is a member of the tenant group** (e.g.
   `ds_open_data`) with the SPI-read attributes, so the issued token carries a
   non-empty **`tenants`** claim. With an empty claim Stellio refuses every
   request (`no access to tenant ds_open_data`) even though a token was minted.

**Deploy-time preflight.** [`tasks/preflight_m2m.yml`](tasks/preflight_m2m.yml)
runs right after `keycloak_sso.yml` and verifies (1)–(3) against the live realm
before any workloads are deployed: it requests a client-credentials token for
the api-access client and asserts both that a token is issued and that its
`tenants` claim is non-empty. On failure it stops the deploy with a message
naming the missing operator step above, instead of shipping a dashboard that
cannot reach Stellio. Skip the check consciously with
`inv_addons.cividash.m2m_preflight_enabled: false`.

The pure decode/assert logic ([`tasks/preflight_m2m_assert.yml`](tasks/preflight_m2m_assert.yml))
is proved in isolation against mocked token payloads by
[`dev/preflight-assert.test.yml`](dev/preflight-assert.test.yml).

## R1 — Database (resolved): external PostgreSQL

**Resolved.** Earlier revisions of this add-on bundled its own **MariaDB**
`cividash-db` StatefulSet + PVC, which was **not** a CORE-native convention (CORE is
Postgres-only via the Zalando Postgres operator) and shipped with no operator,
no managed backups and no Velero integration.

The dashboard application is **database-agnostic** — it reads the standard
Laravel connection env (`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`,
`DB_USERNAME`, `DB_PASSWORD`). The `cividash_app` image used here **must** bundle
the `pdo_pgsql` driver (the `:dev` tag checked on 2026-09-09 did not — the
migrate Job then fails with `could not find driver`; that is an image-build
CORE-native database, and **no longer runs a database server itself**. It only
renders the connection Secret (`cividash-db-secret`) from the chart values and connects
to an externally provisioned Postgres. This mirrors the main-repo switch to
PostgreSQL and closes the open policy question.

### Provisioning the PostgreSQL (out of scope for the add-on)

The Postgres instance/database is provided by the operator / CORE. The add-on is
agnostic to the topology — any option works as long as the connection details are
supplied. `db.host` and `db.password` are **required** (no default); `db.port`,
`db.database` and `db.username` fall back to the defaults in
[`templates/values.yaml.j2`](templates/values.yaml.j2):

1. **Dedicated Zalando `postgresql` cluster** in the CORE cluster (operator-managed
   backups, HA). Point `db.host` at its Service.
2. **`preparedDatabases` schema + role in the central CORE Postgres** — a
   database/role carved out of the shared cluster. Point `db.host` at the shared
   endpoint and `db.database`/`db.username` at the prepared database/role.

retention are handled by whichever Postgres the operator provisions, not by this
add-on.

## Conformance with the CORE add-on guideline (v1, 2026-09-02)

| Guideline item | Status | Where |
| --- | --- | --- |
| Own repo + Copier template | done | This repo; `.copier-answers.yml` |
| `tasks.yml` entry point + `addons`/`addon_<name>` tags | done | [`tasks.yml`](tasks.yml) |
| Own Kubernetes namespace | done | `inv_addons.cividash.ns_create`/`ns_name`, see [`default_inventory.yml`](default_inventory.yml) |
| Helm via central platform task, metadata in `software_references.yml` | done | [`tasks/cividash.yml`](tasks/cividash.yml), [`vars/software_references.yml`](vars/software_references.yml) — see "Helm chart" above |
| Execution after core platform tasks | done | Platform-controlled; not a parameter this add-on exposes (per guideline) |
| No root | done | All workloads using the `cividash-app` image (`cividash-fpm`, `cividash-queue`, `cividash-scheduler`, `cividash-migrate`, `cividash-seed`) run as uid 82, `cividash-web` as uid 101 (`nginxinc/nginx-unprivileged`, port 8080); all pods `runAsNonRoot: true`, `capabilities.drop: [ALL]` without additions |
| Routing: APISIX or Ingress (+ Gateway API) | done | APISIX open route ([`tasks/apisix.yml`](tasks/apisix.yml)) plus `Ingress`/`HTTPRoute` (`ingress.enabled`/`gatewayApi.enabled`) — see "Helm chart" (Routing) above |
| Keycloak 6-step pattern | done | [`tasks/keycloak_sso.yml`](tasks/keycloak_sso.yml) — see "Admin auth" above |
| Dedicated Postgres | done | External, operator-provisioned — see "R1 — Database" above |
| Initial config data | done | `cividash-seed` Helm hook Job — see "Initial config data" above |
| Versioning (add-on minor follows CORE minor, patch free) | done | See "Versioning and compatibility" above |
| Breaking changes documented in README | done | "Breaking change" note above |
| Hardened production defaults (log level/channel, debug off, secure session cookie) | done | `app.logLevel`/`app.logChannel`/`app.sessionSecureCookie` in [`values.yaml`](chart/cividash/values.yaml), templated from `inv_addons.cividash.log_level`/`log_channel`/`session_secure_cookie` — see [`default_inventory.yml`](default_inventory.yml) |
| `readOnlyRootFilesystem` | partial | Not set. `cividash-fpm`/`cividash-queue`/`cividash-scheduler`/`cividash-migrate`/`cividash-seed` write to `storage/`, `bootstrap/cache`, and PHP's `/tmp`; `cividash-web` (nginx-unprivileged) writes its cache/pid dirs — none of these paths are backed by `emptyDir` volumes in the current templates, so a read-only root would break every workload. Add `emptyDir` mounts for those paths first, then flip this on. |
