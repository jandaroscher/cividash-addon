# Local kind smoke (`dev/`)

A throwaway way to validate the add-on's **data-plane** in a real Kubernetes
cluster without a full CIVITAS/CORE control plane. It stands up a throwaway
in-cluster **PostgreSQL** (`cividash-smoke-postgres`, standing in for the operator-
provided external DB), then installs the **real Helm chart**
(`chart/cividash/`) via `dev/k8s-helm.yml` — the same install path
production uses (`tasks/cividash.yml` -> the CORE
`tasks/templates/k8s-helm.yml` wrapper) — and pulls NGSI-LD data from a
**local bare Stellio broker** on the host.

`dev/k8s-helm.yml` is a **vendored copy** of the CORE wrapper's "local chart"
branch (no `helm_chart_version` / `helm_repo_name`), not a symlink or a
`playbook_dir` pointed at the CORE checkout: the smoke must run standalone
without assuming a CORE checkout is present at a fixed path, and the local-
chart branch is a handful of lines that rarely changes. Keep it in sync with
`core_platform/tasks/templates/k8s-helm.yml` if that branch changes.

**Skipped** (require a real CORE control plane): `tasks/keycloak_sso.yml`
(replaced by a placeholder `cividash-oidc-secret`), `tasks/apisix.yml`, and the
Ingress (`enable_ingress: false` in `smoke-vars.yml`). So this proves the
external-Postgres approach, the chart, and the in-cluster NGSI-LD pull — not
the APISIX/Keycloak wiring.

## Prerequisites

- `kind`, `kubectl`, `ansible` (with the `kubernetes` python lib), `docker`.
- **Helm v3.** `run-smoke.sh` prepends `$HOME/.local/bin` (override with
  `helm` binary is found there — a system-installed Helm v4 breaks
  `kubernetes.core.helm`'s `helm list --all` call.
- Locally built images `cividash-app:dev` and `cividash-web:dev` (from the CiviDash
  main repo production Dockerfile).
- The local Stellio broker running on host port `8090`
  (`docker/civitas/v1.6.2` stack in the CiviDash repo).

## Run

```bash
dev/run-smoke.sh            # create cluster, load images, deploy, verify
dev/run-smoke.sh teardown   # delete the kind cluster
```

Expected: all pods `Running`, `cividash-migrate` `Complete`, `/up` → 200, and the
NGSI-LD sync reports `created N` then an idempotent re-run `skipped N`, with the
rows persisted into the in-cluster PostgreSQL.

## Notes

- `dev/smoke-vars.yml` stubs the CORE platform inventory (`inv_k8s`,
  `inv_op_stack`, `software`, `inv_addons.cividash`).
- The app-secret appends the **CORE** NGSI-LD path `/context/ngsi-ld`; the local
  bare broker serves `/ngsi-ld/v1`, so `run-smoke.sh` overrides `CIVITAS_API_URL`
  for the sync test only.
- `image_pull_policy: IfNotPresent` (smoke) keeps kind from trying to pull the
  locally-loaded images.
