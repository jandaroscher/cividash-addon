# Changelog — CiviDash CIVITAS/CORE Add-on

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Optional inventory keys `inv_addons.cividash.images.{app,web}.{registry,repository,tag}`
  to override the default images. An explicit registry takes precedence over
  `inv_op_stack.private_registry.registry_full_url`.
- `inv_addons.cividash.db.central: true` creates the CiviDash database and its
  role in the central CORE Postgres (`central-db`, `preparedDatabases`) and
  reads the credentials from the operator-created Secret, the same way CORE
  provisions its own components. `db.host` and `db.password` are then not
  needed. The default stays the external Postgres. See
  [docs/database.md](docs/database.md).
- `inv_addons.cividash.register_apisix_route` (default `true`) controls the
  APISIX route registration on its own. It no longer depends on
  `enable_ingress`, so `enable_ingress: false` with `gateway_api.enabled: true`
  renders the `HTTPRoute` and registers the APISIX route.
- Chart value `ingress.annotations` (default `{}`): free-form annotations
  rendered unchanged on the `cividash-public` Ingress, e.g. via
  `inv_addons.cividash.helm_values`.

### Breaking

- Inventories with `enable_ingress: false` now run the `public_host` assert and
  register an open APISIX route for `public_host` by default, which makes the
  dashboard publicly reachable. Set `register_apisix_route: false` if the
  deployment must stay internal or has no APISIX.
- `open_http_port: false` now fails the play (see Removed).
- Inventories without `inv_k8s.ingress_class` now get
  `ingressClassName: traefik` instead of the cluster's default IngressClass. Set
  `inv_k8s.ingress_class` explicitly to keep another controller.

### Changed

- `public_host` is asserted whenever `enable_ingress`, `gateway_api.enabled` or
  `register_apisix_route` is true.
- The default ingress controller is Traefik: `ingress.className` defaults to
  `traefik` (`inv_k8s.ingress_class` still overrides it). The HTTP -> HTTPS
  redirect for Traefik is documented in
  [docs/helm-chart.md](docs/helm-chart.md#routing).

### Removed

- The hard-coded `nginx.ingress.kubernetes.io/ssl-redirect` annotation, the
  chart value `ingress.sslRedirect` and the inventory key `open_http_port`.
  A leftover `open_http_port: true` is ignored, `open_http_port: false` fails
  the play. On ingress-nginx, set `helm_values.ingress.annotations` with
  `nginx.ingress.kubernetes.io/ssl-redirect: "false"` instead.

### Fixed

- Overriding images via `software.addon_cividash.*` in the inventory had no
  effect, because `include_vars` outranks inventory variables. The comment in
  `vars/software_references.yml` now points to the new `images` keys.
- An empty `inv_op_stack.private_registry.registry_full_url` no longer renders
  an image reference without a registry; it falls back to the default.
- Docs and comments no longer say images are pinned to a `civitas-<gitsha>`
  build tag; they are pinned to the CiviDash release tag.
- A run with `--tags addons` or `--tags addon_cividash` skipped the database,
  Keycloak SSO, M2M preflight and APISIX tasks, because `include_tasks` does
  not pass its tags to the included tasks.

## [1.6.1] - 2026-09-23

First public release.

### Added

- Ansible role plus local Helm chart (`chart/cividash/`), installed as release
  `cividash` through the central CORE platform Helm task.
- Images pinned to the CiviDash release tag `1.0.0` of
  `ghcr.io/jandaroscher/cividash-app` / `cividash-web`. The moving `civitas`
  tag is for the maintainers' test stack only.
- `cividash-web` runs rootless on `nginxinc/nginx-unprivileged` (uid 101,
  container port 8080 behind Service port 80); every pod runs `runAsNonRoot`
  with `capabilities.drop: [ALL]`.
- Helm hook Job `cividash-seed` (`post-install,post-upgrade`) for idempotent
  initial config data (tenant backfill, tenant domain, optional pages/dashboard
  seed), gated by `seed.*` values.
- Secure logging/session defaults: `LOG_LEVEL=info`, `LOG_CHANNEL=stderr`,
  `SESSION_SECURE_COOKIE=true`, configurable via
  `inv_addons.cividash.log_level`/`log_channel`/`session_secure_cookie`.
  `readOnlyRootFilesystem` is not set, see
  [docs/core-guideline-conformance.md](docs/core-guideline-conformance.md).

[Unreleased]: https://gitlab.opencode.de/regensburg_next/cividash-addon/-/compare/v1.6.1...main
[1.6.1]: https://gitlab.opencode.de/regensburg_next/cividash-addon/-/tags/v1.6.1
