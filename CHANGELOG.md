# Changelog — CiviDash CIVITAS/CORE Add-on

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Optional inventory keys `inv_addons.cividash.images.{app,web}.{registry,repository,tag}`
  to override the default images. An explicit registry takes precedence over
  `inv_op_stack.private_registry.registry_full_url`.

### Fixed

- Overriding images via `software.addon_cividash.*` in the inventory had no
  effect, because `include_vars` outranks inventory variables. The comment in
  `vars/software_references.yml` now points to the new `images` keys.

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

[1.6.1]: https://gitlab.opencode.de/regensburg_next/cividash-addon/-/tags/v1.6.1
