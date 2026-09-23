# Helm chart

`tasks/cividash.yml` installs [`chart/cividash/`](../chart/cividash/)
through the central platform task `tasks/templates/k8s-helm.yml` (per
guideline: Helm installs go through the central platform task, with chart
metadata sourced exclusively from `vars/software_references.yml`).
`helm_chart_name`, `helm_release_name` and `helm_chart_version` live in
[`vars/software_references.yml`](../vars/software_references.yml) under
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

## Log hygiene

`tasks/cividash.yml` passes `helm_no_log: true`, but the current
`core_platform/tasks/templates/k8s-helm.yml` does not read that var (no
`no_log` on its `kubernetes.core.helm` task), so running the platform
playbook with `-v`/`-vvv` still prints the rendered chart values — including
`db.password`, `s3.secretAccessKey`, `APP_KEY` — to the log. Do not run the
Helm step with `-v` against shared/persisted logs until CORE adds
`no_log: "{{ helm_no_log | default(false) }}"` to that wrapper task. The
vendored `dev/k8s-helm.yml` used by the local smoke already honours
`helm_no_log`.

## Values

Chart values are rendered by [`templates/values.yaml.j2`](../templates/values.yaml.j2)
from `inv_addons.cividash.*` + `software.addon_cividash.*` (image refs,
honouring the private-registry override) + `inv_k8s.ingress_class` /
`inv_k8s.cert_manager.issuer_name`. Override any chart value directly (values
the inventory has no dedicated key for yet, e.g. per-workload `resources.*`)
via `inv_addons.cividash.helm_values` — it is combined (recursive) on top
of the rendered values (see [`default_inventory.yml`](../default_inventory.yml)).

## `APP_KEY` idempotency

`APP_KEY` idempotency lives in the chart itself, not in Ansible:
`chart/cividash/templates/_helpers.tpl`'s `cividash.appKey` uses
`values.app.key` if set, else a Helm `lookup` of the existing
`cividash-app-secret`'s `APP_KEY` (so re-installs preserve it), else a freshly
generated `base64:`-prefixed key. `helm template` has no cluster to `lookup`
against, so it always generates a fresh key there — expected, and why CI's
`helm lint`/`helm template` runs don't assert a stable key.

## Routing

`ingress.enabled` (`inv_addons.cividash.enable_ingress`, default `true`) renders
the `cividash-public` `Ingress`. Set `gatewayApi.enabled: true`
(`inv_addons.cividash.gateway_api.enabled`) to additionally render a
`gateway.networking.k8s.io/v1 HTTPRoute` named `cividash-public` for the same
host -> `cividash-web:80`; supply `gatewayApi.parentRefs` naming your Gateway.
The two flags are independent — with the add-on's defaults, enabling Gateway
API renders both the `Ingress` and the `HTTPRoute`. For `HTTPRoute`-only
routing, also set `inv_addons.cividash.enable_ingress: false`. That flag also
gates the APISIX route registration and the `public_host` assert in
`tasks/cividash.yml`, so `false` skips the APISIX route as well.

## Verify locally

```bash
helm lint chart/cividash
helm template cividash chart/cividash
helm template cividash chart/cividash -f chart/cividash/ci/smoke-values.yaml
```

## Images

The CiviDash main repository builds and publishes two images to GHCR:

- `cividash_app` -> `ghcr.io/jandaroscher/cividash-app` — php-fpm, the full application.
  Used by `cividash-fpm`, `cividash-queue`, `cividash-scheduler` and the `cividash-migrate`/`cividash-seed` Jobs.
- `cividash_web` -> `ghcr.io/jandaroscher/cividash-web` — nginx with the baked public
  assets, proxying PHP to `cividash-fpm:9000`.

Tags/registries are configured in [`vars/software_references.yml`](../vars/software_references.yml)
under `software.addon_cividash.{cividash_app,cividash_web}.{registry,repository,tag}`.
When `inv_op_stack.private_registry.registry_full_url` is set, it overrides the
per-image registry (platform private-registry support).

The CiviDash main-repo CI also publishes a **moving `civitas` tag**. It is for
**the maintainers' test stack only** and **must not** be used in any inventory: it can move
under a running deployment without any version bump in this repo. Pin
inventories to an immutable `civitas-<gitsha>` tag — see [Versioning and compatibility](../README.md#versioning-and-compatibility).
