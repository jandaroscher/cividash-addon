# Local kind smoke (`dev/`)

A throwaway way to validate the add-on's **data-plane** in a real Kubernetes
cluster without a full CIVITAS/CORE control plane. It stands up a throwaway
in-cluster **PostgreSQL** (`cividash-smoke-postgres`, standing in for the operator-
provided external DB), then deploys the four app workloads + the migration Job
using the **real role task files** (`tasks/secrets.yml`, `database.yml`,
`migrate.yml`, `workloads.yml`) and pulls NGSI-LD data from a **local bare
Stellio broker** on the host.

**Skipped** (require a real CORE control plane): `tasks/keycloak_sso.yml`
(replaced by a placeholder `cividash-oidc-secret`), `tasks/apisix.yml`, and the
Ingress (`enable_ingress: false`). So this proves the external-Postgres approach,
the manifests, and the in-cluster NGSI-LD pull — not the APISIX/Keycloak wiring.

## Prerequisites

- `kind`, `kubectl`, `ansible` (with the `kubernetes` python lib), `docker`.
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
