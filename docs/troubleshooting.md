# Troubleshooting

## Migrate/seed Job fails with `could not find driver`

[Database](database.md).

## `cividash-fpm`/`cividash-web` stuck in `ImagePullBackOff`


## Deploy stops at the M2M preflight

[`tasks/preflight_m2m.yml`](../tasks/preflight_m2m.yml) stops the deploy before any
workloads are created if the shared `api-access` Keycloak client cannot mint a
client-credentials token, or the token's `tenants` claim is empty — see
[Operator prerequisites (M2M / api-access)](authentication.md#operator-prerequisites-m2m--api-access)
for the three operator-side prerequisites it checks. Only skip it with
`inv_addons.cividash.m2m_preflight_enabled: false` if NGSI-LD sync not
working is acceptable for your deployment.

## Keycloak SSO login loops back to `/admin/login`

If Keycloak SSO redirects back to `/admin/login` instead of reaching the
Filament panel, the app's server-side token exchange is likely failing against
the public HTTPS Keycloak endpoint (a self-signed platform CA yields cURL error
60). Set `inv_addons.cividash.keycloak_base_url_internal` to the in-cluster
Keycloak service (see the commented-out default in
[`default_inventory.yml`](../default_inventory.yml)) so the exchange happens
over the internal `http` endpoint instead.
