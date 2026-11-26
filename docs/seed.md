# Initial config data (`cividash-seed`)

[`charts/cividash/templates/cividash-seed.yaml`](../charts/cividash/templates/cividash-seed.yaml)
is a Helm hook Job (`post-install,post-upgrade`, weight `10`). It runs after
`cividash-migrate` and after the workloads of the same release are created,
and it runs again on every upgrade. Configuration that the application only
accepts at runtime is loaded here, in a Job, not in commands executed in a
running pod. It is on by default (`seed.enabled: true`).

Steps, all idempotent; step 3 resets edited pages (see there):

1. `php artisan tenancy:backfill --default-tenant=<seed.defaultTenant>`
   creates the tenant only if it does not exist yet (`Tenant::firstOrCreate`,
   CiviDash main repository `app/Console/Commands/TenancyBackfillCommand.php`).
2. With `seed.setTenantDomain` (default `true`): sets the default tenant's
   `domain` to `app.publicHost` (`<subdomain>.<global.domain>`) through
   `php artisan tinker`, only when the domain differs. There is no dedicated
   artisan command for this.
3. With `seed.pages` (default `false`): `php artisan pages:seed`. `PageSeeder`
   finds or creates each page by its German slug and only updates changed
   fields; `NavigationSeeder` skips once header navigation items exist.
   Changed fields include edits made in the admin area: a page with a seeded
   slug is reset on every run. Turn `seed.pages` off again after the first
   seed.
4. With a non-empty `seed.dashboardJsonUrl` (default empty):
   `php artisan dashboard:seed --url=...`. `CategorySeeder` and `TileSeeder`
   find or create by slug or title and only update changed fields;
   `MetricSeeder` upserts.

## Configuration

The seed settings are chart values. Set them through `rawValues` in the
environment:

```yaml
cividash:
  cividash:
    rawValues:
      seed:
        pages: true
        dashboardJsonUrl: https://example.org/dashboard.json
```

| Chart value | Default |
| --- | --- |
| `seed.enabled` | `true` |
| `seed.defaultTenant` | `default` |
| `seed.setTenantDomain` | `true` |
| `seed.pages` | `false` |
| `seed.dashboardJsonUrl` | `""` |

## `seed.pages` and `seed.dashboardJsonUrl` require `seed.defaultTenant: default`

Both seeders use a hardcoded `default` tenant slug in the CiviDash main
repository (`BelongsToTenant`'s creating hook falls back to
`Tenant::where('slug', 'default')`; the tile branding fallback of
`DashboardSeedCommand` does the same, and its own `--tenant` option is never
read). With another `seed.defaultTenant` and no `default` tenant, the Job
would fail; with one present, content would land in the wrong tenant. The
chart refuses to render this combination.
