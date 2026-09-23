# Changelog — CiviDash CIVITAS/CORE Add-on

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


### Changed

  docs/migration-from-cividash.md.
- Installs via Helm (`helm_release_name: cividash`) through the central
  platform Helm task instead of raw `kubernetes.core.k8s` manifests
  See docs/migration-from-cividash.md for the required
  one-time migration.
- Image tags pinned to the immutable `civitas-<gitsha>` build tag instead of
- `cividash-web` runs rootless: `nginxinc/nginx-unprivileged`, uid 101, container
  port 8080 behind the unchanged Service port 80. The capability additions for
  the nginx master are gone; every pod now runs `runAsNonRoot` with
  `capabilities.drop: [ALL]`.

### Added

- Helm hook Job `cividash-seed` (`post-install,post-upgrade`) for idempotent
  initial config data (tenant backfill, tenant domain, optional pages/dashboard
  seed), gated by `seed.*` values.
- Secure logging/session defaults: `LOG_LEVEL=info`, `LOG_CHANNEL=stderr`,
  `SESSION_SECURE_COOKIE=true`, configurable via
  `inv_addons.cividash.log_level`/`log_channel`/`session_secure_cookie`.

[1.6.1]: https://gitlab.opencode.de/regensburg_next/cividash-addon/-/tags/v1.6.1
