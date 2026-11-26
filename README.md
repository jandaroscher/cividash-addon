<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/cividash-logo-dark.svg">
    <img src="docs/images/cividash-logo.svg" alt="CiviDash" width="320">
  </picture>
  <br>CIVITAS/CORE Add-on
</h1>

Packages **CiviDash**, the sustainability dashboard (Laravel 12 + Filament +
a Vue 3 SPA), as a **CIVITAS/CORE 2** add-on. This is a **deploy-only**
repository: CIVITAS/CORE component files at the repository root and a local
Helm chart ([`charts/cividash/`](charts/cividash/)), deployed by the
platform's Helmfile like every other component. The application code lives
in the [CiviDash main repository](https://github.com/jandaroscher/cividash)
and ships here as prebuilt container images.

This branch (`v2`, add-on `2.x`) targets CIVITAS/CORE 2. The add-on for
CIVITAS/CORE 1 (Ansible, add-on `1.x`) stays on `main`.

## Quick start

Add the repository as a Git submodule to your deployment and register it as
a component:

```bash
cd deployment/addons/
git submodule add -b v2 https://github.com/jandaroscher/cividash-addon.git cividash
```

The directory name must be `cividash`. Add `cividash` to the `components`
list in `deployment/environments/<env>/global.yaml.gotmpl`, after the core
components:

```yaml
components:
  # ... platform components ...
  - cividash
```

Configure it in an environment file, e.g.
`deployment/environments/<env>/cividash.yaml.gotmpl`, then deploy:

```yaml
cividash:
  cividash:
    subdomain: dashboard         # https://dashboard.<global.domain>
    storage: s3                  # recommended for production, see below
    s3:
      existingSecret: cividash-s3
      endpoint: https://s3.example.org
      bucket: cividash
      publicUrl: ""
```

```bash
helmfile -f deployment/helmfile-instance.yaml.gotmpl apply -e <env> --selector component=cividash
```

With `storage: s3`, create the Secret named in `existingSecret` in the
CiviDash namespace (`<instanceSlug>-cividash`) first, with the keys
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Then assign the Keycloak
client roles `admin` or `editor` of the client `cividash` to the users who
administer the dashboard (see [Authentication](docs/authentication.md)).

## Configuration

The add-on reads `cividash.cividash.*` from the environment. Defaults are in
[`default-environment.yaml.gotmpl`](default-environment.yaml.gotmpl).

| Key (`cividash.cividash.*`) | Default | Notes |
| --- | --- | --- |
| `enabled` | `true` | Deploy the component |
| `namespace` | `<instanceSlug>-cividash` | From `civitas.namespace`, like the core components |
| `subdomain` | `dashboard` | Public host `<subdomain>.<global.domain>`; also the Keycloak client's redirect host |
| `storage` | `volume` | `volume`: a PersistentVolumeClaim shared by all CiviDash pods; with more than one node it needs a ReadWriteMany class (`global.storage.storageClass.rwx`). `s3`: an S3-compatible bucket, recommended for production. See [Media storage](docs/storage.md) |
| `s3.existingSecret` | `""` | **Required** with `storage: s3`: Secret in the CiviDash namespace with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` |
| `s3.endpoint` / `s3.bucket` | `""` | **Required** with `storage: s3` |
| `s3.publicUrl` | `""` | **Required key** with `storage: s3`; empty serves media through the dashboard under `/storage` |
| `s3.region` / `s3.usePathStyle` | `us-east-1` / `true` | Path-style URLs suit MinIO and most self-hosted S3 |
| `rawValues` | — | Chart values merged last, e.g. `seed.*` ([Initial config data](docs/seed.md)), `resources.*` or `ingress.annotations` |

The deployment fails at render time with a clear message when a required
value is missing.

## What it deploys

| File | Effect |
| --- | --- |
| [`keycloak-clients.yaml`](keycloak-clients.yaml) | Confidential client `cividash` for the admin login, roles `admin` and `editor`, mapped to the `groups` claim. CORE generates its secret as Secret `keycloak-client-cividash` |
| [`databases.yaml`](databases.yaml) | Database and role `cividash` in the platform's PostgreSQL (CloudNativePG) |
| [`secrets.yaml`](secrets.yaml) | `cividash-app-key` (Laravel `APP_KEY`) and `db-cividash` (database password, also copied to the postgres namespace) |
| [`networkpolicies.yaml`](networkpolicies.yaml), [`networkpolicies-linkerd.yaml`](networkpolicies-linkerd.yaml) | On top of CORE's default deny: `cividash-web` from anywhere on 8080 (the Ingress controller), `cividash-fpm` only from `cividash-web`, PostgreSQL from the CiviDash pods |
| [`policy-exceptions.yaml`](policy-exceptions.yaml) | The scheduler runs exactly once (no second replica, no rolling update) |
| [`charts/cividash`](charts/cividash/) | The release `cividash-cividash` below |

| Object | Kind | Notes |
| --- | --- | --- |
| `cividash-app-secret`, `cividash-db-secret` | Secret (Helm hook) | App and connection settings without credentials; `pre-install,pre-upgrade`, weight `0` |
| `cividash-migrate` | Job (Helm hook) | `php artisan migrate --force`; `pre-install,pre-upgrade`, weight `5` |
| `cividash-seed` | Job (Helm hook) | Initial config data; `post-install,post-upgrade`, weight `10`, see [Initial config data](docs/seed.md) |
| `cividash-fpm` | Deployment + Service (9000) | php-fpm, the Laravel/Filament app |
| `cividash-web` | Deployment + Service (80 -> 8080) | rootless nginx with the public assets |
| `cividash-queue` | Deployment | `php artisan queue:work` |
| `cividash-scheduler` | Deployment | `php artisan schedule:run` every 60 s, always one replica |
| `cividash-public` | Ingress | `<subdomain>.<global.domain>` -> `cividash-web`, class and cluster issuer from `global.ingress` |
| `cividash-web` | Linkerd `Server` | With Linkerd: lets the Ingress controller reach `cividash-web` (`global.serviceMesh.allowUnauthenticatedIngress`) |
| `cividash-fpm`, `cividash-web` | PodDisruptionBudget | Profile `production` only |
| `cividash-platform-ca` | ConfigMap | With the self-signed platform CA: PHP trusts `custom-ca-cert` next to the system CAs |
| `cividash-public-media` | PersistentVolumeClaim | `storage: volume` only |

CiviDash is reached through its own Ingress only; it registers no APISIX
route (the dashboard is public, the admin area authenticates in the app,
and APISIX's fixed 6-second upstream timeout would cut off imports and
exports). All credentials come from Secrets (`secretKeyRef`), never from Helm
values. All containers run as non-root with a read-only root filesystem,
`seccompProfile: RuntimeDefault`, no privilege escalation and all
capabilities dropped; the paths the app and nginx write to are pod-local
`emptyDir` volumes.

Profile `production` runs `cividash-fpm`, `cividash-web` and
`cividash-queue` with two replicas each and PodDisruptionBudgets; profile
`development` runs one of each.

### Not yet available on CIVITAS/CORE 2

- **Data sync from the platform (NGSI-LD):** CORE 2 has no NGSI-LD broker
  yet, so the sync is off (`civitas.enabled: false`). Dashboards are
  maintained in the admin area or imported. How an add-on's own Keycloak
  client gets access to platform datasets is still open on the CORE side.
- **Admin login through Keycloak:** CORE 2 requires PKCE for confidential
  clients. Keycloak login works once the CiviDash release in
  [`images.yaml`](images.yaml) sends PKCE; until then admins sign in with a
  CiviDash account.

## Versioning and compatibility

The add-on's major and minor version (`charts/cividash/Chart.yaml`) follow the
CORE version it targets: add-on `2.0.x` targets CORE `2.0.x`. The patch digit
is independent. Breaking changes are documented in `CHANGELOG.md`.

| Component | Version |
| --- | --- |
| cividash add-on (this branch/chart) | 2.0.0 |
| CIVITAS/CORE platform | 2.0.x (verified against 2.0.2) |
| CiviDash app images | release tag `1.2.1` ([`images.yaml`](images.yaml)), `linux/amd64` and `linux/arm64` |
| Kubernetes | >= 1.28 |

CI runs CORE's `verify-addon.sh` from the targeted CORE release against this
repository (base and production policies) and additionally renders the
add-on with profile `production` and S3 storage (see
[`.github/workflows/verify.yml`](.github/workflows/verify.yml)). To run the
same check locally with helmfile, helm, yq and the Kyverno CLI installed:

```bash
git clone --depth 1 --branch v2.0.2 https://gitlab.com/civitas-connect/civitas-core/civitas-core-v2/civitas-core-deployment.git /tmp/core
/tmp/core/.ci/policies/verify-addon.sh . --env local
/tmp/core/.ci/policies/verify-addon.sh . --env production
.github/scripts/verify-production-profile.sh /tmp/core .
```

Pass `--env` explicitly: without it, `verify-addon.sh` 2.0.2 reports success
even when the add-on fails to render.

**Migrating from CIVITAS/CORE 1:** CORE 2 has no in-place upgrade. Before the
first deployment, create the Secret `cividash-app-key` (key `app-key`) in the
CiviDash namespace with the `APP_KEY` of the old installation, then restore a
dump of the old database into the new `cividash` database and copy the media
(bucket or volume). Sessions, cache and queue live in the database and move
with it.

**Cutting a release:** tag the `v2` branch `v2.0.x` and publish a GitHub
release for the tag. Publishing runs the `Release SBOM` workflow, which
attaches the image SBOMs of the images pinned in [`images.yaml`](images.yaml).

## Uninstall

```bash
helmfile -f deployment/helmfile-instance.yaml.gotmpl destroy -e <env> --selector component=cividash
```

Then remove `cividash` from the `components` list and the submodule. Left
behind:

- **Hook Secrets** `cividash-app-secret` and `cividash-db-secret`, which are
  not part of the Helm release manifest.
- **Generated Secrets** `cividash-app-key`, `db-cividash` and
  `keycloak-client-cividash`, the Keycloak client `cividash` and the
  database `cividash`, which belong to the platform's secrets, Keycloak and
  postgres components.
- **Media**: the S3 bucket, or the PVC `cividash-public-media`
  (`helm.sh/resource-policy: keep`).

## Documentation

- [Helm chart](docs/helm-chart.md): values, routing, verifying the chart locally, images
- [Authentication](docs/authentication.md): admin login through Keycloak
- [Database](docs/database.md): the platform's PostgreSQL
- [Media storage](docs/storage.md): S3 bucket or volume, backup, switching
- [Initial config data](docs/seed.md): the `cividash-seed` hook Job
- [Troubleshooting](docs/troubleshooting.md)
- [Components](docs/components.md): what a deployment consists of, and the image SBOMs attached to each release
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

Maintainer and contact: Stadt Regensburg, code@regensburg.de.

- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

Licensed under the EUPL-1.2 or later, see [LICENSE](LICENSE) and
[NOTICE](NOTICE).
