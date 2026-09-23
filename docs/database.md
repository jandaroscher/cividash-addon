# Database

## External PostgreSQL

The add-on does not deploy a database; it connects to an operator-provisioned
PostgreSQL (CORE-native, Zalando Postgres operator).

The dashboard application is **database-agnostic** — it reads the standard
Laravel connection env (`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`,
`DB_USERNAME`, `DB_PASSWORD`). The image pinned in `vars/software_references.yml` includes `pdo_pgsql`; a
custom or mirrored image without it fails `cividash-migrate` with `could not
find driver` (see
[Troubleshooting](troubleshooting.md)). The add-on targets **PostgreSQL**,
the CORE-native database, and does not run a database server itself. It only
renders the connection Secret (`cividash-db-secret`) from the chart values and
connects to an externally provisioned Postgres. This matches the main
repository, which runs on PostgreSQL.

## Provisioning the PostgreSQL (out of scope for the add-on)

The Postgres instance/database is provided by the operator / CORE. The add-on is
agnostic to the topology — any option works as long as the connection details are
supplied. `db.host` and `db.password` are **required** (no default); `db.port`,
`db.database` and `db.username` fall back to the defaults in
[`templates/values.yaml.j2`](../templates/values.yaml.j2):

1. **Dedicated Zalando `postgresql` cluster** in the CORE cluster (operator-managed
   backups, HA). Point `db.host` at its Service.
2. **`preparedDatabases` schema + role in the central CORE Postgres** — a
   database/role carved out of the shared cluster. Point `db.host` at the shared
   endpoint and `db.database`/`db.username` at the prepared database/role.

Choose the topology with your platform operator. Backups, HA and
retention are handled by whichever Postgres the operator provisions, not by this
add-on.
