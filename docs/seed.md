# Initial config data (`cividash-seed`)

`chart/cividash/templates/cividash-seed.yaml` is a Helm hook Job
(`post-install,post-upgrade`, weight `10`, after `cividash-migrate` and the
workloads created by the same `helm upgrade --install`), per guideline:
"initial loading of configuration data" via an add-on-local step after
deployment. A Job, not an init script. Gated by `seed.enabled`
(default `true`, `inv_addons.cividash.seed.enabled`). Steps, all
idempotent and safe to re-run on every install/upgrade:

1. `php artisan tenancy:backfill --default-tenant={{ seed.defaultTenant }}` —
   creates the tenant only if it doesn't exist yet (`Tenant::firstOrCreate`,
   CiviDash main repo `app/Console/Commands/TenancyBackfillCommand.php`).
2. When `seed.setTenantDomain` (default `true`): sets the default tenant's
   `domain` to `app.publicHost` via `php artisan tinker`, only when it
   differs — there is no dedicated artisan command for this.
3. When `seed.pages` (default `false`): `php artisan pages:seed`. Idempotent:
   `PageSeeder` finds-or-creates per DE
   slug and only updates changed fields, `NavigationSeeder` skips once header
   navigation items exist.
4. When `seed.dashboardJsonUrl` is non-empty (default empty): `php artisan
   dashboard:seed --url=...`. Idempotent:
   `CategorySeeder`/`TileSeeder` find-or-create per slug/title and only
   update changed fields; `MetricSeeder` documents idempotent upserts.

Values: `inv_addons.cividash.seed.{enabled,default_tenant,set_tenant_domain,pages,dashboard_json_url}`
(see [`default_inventory.yml`](../default_inventory.yml)).

**`seed.pages` / `seed.dashboardJsonUrl` require `seed.defaultTenant: default`.**
Both seeders operate on a hardcoded `"default"` tenant slug elsewhere in the
CiviDash main repo (`BelongsToTenant`'s creating-hook falls back to
`Tenant::where('slug', 'default')`; `DashboardSeedCommand`'s tile-branding
fallback chain does the same, and its own `--tenant` option is never read).
With a different `seed.defaultTenant` and no `default` tenant, the Job would
fail; with one present, content would land in the wrong tenant. The chart
enforces this with a `fail` guard at render time.
