# Conformance with the CORE add-on guideline (v1, 2026-09-02)

| Guideline item | Status | Where |
| --- | --- | --- |
| Own repo + Copier template | done | This repo; `.copier-answers.yml` |
| `tasks.yml` entry point + `addons`/`addon_<name>` tags | done | [`tasks.yml`](../tasks.yml) |
| Own Kubernetes namespace | done | `inv_addons.cividash.ns_create`/`ns_name`, see [`default_inventory.yml`](../default_inventory.yml) |
| Helm via central platform task, metadata in `software_references.yml` | done | [`tasks/cividash.yml`](../tasks/cividash.yml), [`vars/software_references.yml`](../vars/software_references.yml) — see [Helm chart](helm-chart.md) |
| Execution after core platform tasks | done | Platform-controlled; not a parameter this add-on exposes (per guideline) |
| No root | done | All workloads using the `cividash-app` image (`cividash-fpm`, `cividash-queue`, `cividash-scheduler`, `cividash-migrate`, `cividash-seed`) run as uid 82, `cividash-web` as uid 101 (`nginxinc/nginx-unprivileged`, port 8080); all pods `runAsNonRoot: true`, `capabilities.drop: [ALL]` without additions |
| Routing: APISIX or Ingress (+ Gateway API) | done | APISIX open route ([`tasks/apisix.yml`](../tasks/apisix.yml)) plus `Ingress`/`HTTPRoute` (`ingress.enabled`/`gatewayApi.enabled`) — see [Helm chart, Routing](helm-chart.md#routing) |
| Keycloak 6-step pattern | done | [`tasks/keycloak_sso.yml`](../tasks/keycloak_sso.yml) — see [Authentication](authentication.md) |
| Dedicated Postgres | done | External, operator-provisioned — see [Database](database.md) |
| Initial config data | done | `cividash-seed` Helm hook Job — see [Initial config data](seed.md) |
| Versioning (add-on minor follows CORE minor, patch free) | done | See README, "Versioning and compatibility" |
| Breaking changes documented | done | See [`CHANGELOG.md`](../CHANGELOG.md) |
| Hardened production defaults (log level/channel, debug off, secure session cookie) | done | `app.logLevel`/`app.logChannel`/`app.sessionSecureCookie` in [`values.yaml`](../chart/cividash/values.yaml), templated from `inv_addons.cividash.log_level`/`log_channel`/`session_secure_cookie` — see [`default_inventory.yml`](../default_inventory.yml) |
| `readOnlyRootFilesystem` | partial | Not set. `cividash-fpm`/`cividash-queue`/`cividash-scheduler`/`cividash-migrate`/`cividash-seed` write to `storage/`, `bootstrap/cache`, and PHP's `/tmp`; `cividash-web` (nginx-unprivileged) writes its cache/pid dirs — none of these paths are backed by `emptyDir` volumes in the current templates, so a read-only root would break every workload. Add `emptyDir` mounts for those paths first, then flip this on. |
