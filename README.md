# CiviDash CIVITAS/CORE Add-on

Packages the **CIVIDASH** sustainability dashboard (Laravel 12 + Filament + a Vue 3
SPA) as a **CIVITAS/CORE** add-on. This is a **deploy-only** repository: Ansible
plus raw Kubernetes Jinja2 manifests (**no Helm chart**). The application code
lives in the CIVIDASH main repository and ships here as prebuilt container images.

The add-on follows the `airflow_addon` pattern — raw `kubernetes.core.k8s`
manifests and `uri`-based Keycloak / APISIX Admin-API calls — not a Helm chart.

## What it deploys

Into the namespace `{{ ENVIRONMENT }}-cividash-stack`:

| Object | Kind | Notes |
| --- | --- | --- |
| `cividash-db` | StatefulSet + headless Service (3306) | MariaDB 11, PVC `cividash-db-data` (see **R1**) |
| `cividash-db-secret` | Secret | DB name/user/password + root password, generated idempotently |
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
    db: { database: "cividash", username: "cividash", storage: "5Gi" }
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

- `inv_addons.cividash.s3.access_key_id` — S3 access key, rendered into
  `cividash-app-secret` as `AWS_ACCESS_KEY_ID`.
- `inv_addons.cividash.s3.secret_access_key` — S3 secret key, rendered into
  `cividash-app-secret` as `AWS_SECRET_ACCESS_KEY`.

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
2. **Client credentials** — service account for the machine-to-machine NGSI-LD
   token (`CIVITAS_DRIVER=ngsi-ld`).

The client secret is written to `cividash-oidc-secret` and consumed via app env.
APISIX never consumes this client.

> **Note:** If Filament admin access is gated on a Keycloak role/group, the
> first admin must be granted the `cividash:admin` role in Keycloak
> manually. The add-on creates the client roles (`admin`, `editor`) but does
> not assign them to any user.

## R1 — MariaDB is not a CORE-native convention

The dashboard requires **MariaDB**, deployed here as its own `cividash-db`
StatefulSet + PVC. **This is not a documented CORE convention**: CORE is
Postgres-only via the Zalando Postgres operator. This MariaDB is provided as a
**raw StatefulSet + PVC with no operator, no managed backups, and no Velero
integration** — none of that is faked. This is an open policy question to raise
with the CORE team; **Postgres is the documented alternative**.

### Manual MariaDB backup

Because there is no operator-managed backup, take backups manually, e.g.:

```bash
# Dump (adjust namespace/secret as needed)
kubectl -n "$NS" exec statefulset/cividash-db -- \
  sh -c 'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"' \
  > "cividash-$(date +%F).sql"

# Restore
kubectl -n "$NS" exec -i statefulset/cividash-db -- \
  sh -c 'mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"' \
  < cividash-backup.sql
```

Schedule these (CronJob / external backup runner) and store dumps off-cluster.
```
