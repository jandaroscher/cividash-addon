# Database

## PostgreSQL

The add-on does not deploy a database server. It either registers a database
in the central CORE Postgres or connects to an operator-provisioned
PostgreSQL.

The dashboard application is **database-agnostic** — it reads the standard
Laravel connection env (`DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`,
`DB_USERNAME`, `DB_PASSWORD`). The image pinned in `vars/software_references.yml` includes `pdo_pgsql`; a
custom or mirrored image without it fails `cividash-migrate` with `could not
find driver` (see
[Troubleshooting](troubleshooting.md)). The add-on targets **PostgreSQL**,
the CORE-native database, and does not run a database server itself. It
renders the connection Secret (`cividash-db-secret`) from the resolved
connection. This matches the main
repository, which runs on PostgreSQL.

## Central CORE Postgres (`db.central: true`)

CORE runs one shared Zalando Postgres cluster, `central-db` in the namespace
`inv_central_db.ns_name`, and gives each component its own database in it
(Keycloak, Frost, Stellio, geodata). With

```yaml
inv_addons:
  cividash:
    db:
      central: true
      # database: "cividash"  # optional, default cividash
```

the add-on does the same for CiviDash (`tasks/database.yml`):

1. It checks that `inv_central_db.enable` is true and that `central-db`
   exists. It never creates the cluster.
2. It adds one entry to `spec.preparedDatabases` of `central-db`
   (`defaultUsers: true`, schema `public`) by merge patch. The CORE-managed
   entries stay as they are, and a later CORE deploy of `central-db` keeps
   the CiviDash entry.
3. The operator creates the database, the login role `<database>_owner_user`
   and its Secret `<database>-owner-user.central-db.credentials.postgresql.acid.zalan.do`
   in the central DB namespace. The add-on waits for the Secret (up to
   `cividash_db_central_retries` × 10 s, default 30 tries) and renders host
   `central-db.<ns>.svc.cluster.local`, username and password into
   `cividash-db-secret`.

`db.host`, `db.username` and `db.password` are ignored in this mode, so no
database credentials go into the inventory. The database is not removed on
uninstall; delete the `preparedDatabases` entry and the database by hand if
you need to.

## External PostgreSQL (default)

Without `db.central`, the Postgres instance and database are provided by the
operator, and the add-on only connects. `db.host` and `db.password` are
**required** (no default); `db.port`, `db.database` and `db.username` fall back
to `5432`, `cividash` and `cividash` (see [`tasks/database.yml`](../tasks/database.yml)).
Any topology works, for example a dedicated Zalando `postgresql` cluster in the
CORE cluster or a managed Postgres outside it.

Backups, HA and retention are handled by whichever Postgres hosts the
database, not by this add-on.
