# Changelog — CiviDash CIVITAS/CORE Add-on

All notable changes to this add-on are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


### Changed

- Installs via Helm (`helm_release_name: cividash`) through the central
  platform Helm task instead of raw `kubernetes.core.k8s` manifests
  See README, "Breaking change" for the required
  one-time migration.
- Image tags pinned to the immutable `civitas-<gitsha>` build tag instead of

### Added

- Helm hook Job `cividash-seed` (`post-install,post-upgrade`) for idempotent
  initial config data (tenant backfill, tenant domain, optional pages/dashboard
  seed), gated by `seed.*` values.
- "Versioning and compatibility" and "Conformance with the CORE add-on
  guideline" sections in the README.
