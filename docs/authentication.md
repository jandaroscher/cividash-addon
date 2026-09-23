# Authentication

## Admin authentication is handled by the application, not APISIX

The APISIX gateway registration ([`tasks/apisix.yml`](../tasks/apisix.yml)) creates
**exactly one open route**: host `public_host`, uri prefix `/*`, forwarding to
the `cividash-web` upstream. There is **deliberately no `openid-connect` / auth
plugin** on this route. It covers `/`, `/api/*`, `/admin`, `/filament` and
`/docs` — the Laravel/Filament application enforces its own authentication
(Fortify, plus optional Keycloak Socialite SSO for the admin panel).

The add-on still registers a Keycloak client (`cividash`) because the
**app** uses it, not APISIX, for admin SSO: the Socialite standard flow with
redirect `https://{{ admin_host | default(public_host) }}/admin/auth/keycloak/callback`.

The `cividash` client secret is written to `cividash-oidc-secret` (as the
`KEYCLOAK_*` keys) and consumed via app env. APISIX never consumes this client.

## NGSI-LD machine token — shared `api-access` client

The machine-to-machine NGSI-LD token (`CIVITAS_DRIVER=ngsi-ld`,
`CIVITAS_OAUTH_*` in `cividash-oidc-secret`) is **not** issued by the
`cividash` client. It is issued by the shared, operator-provided
**`api-access`** IDM client — the same client the CORE data plane (Stellio
behind APISIX) already trusts — mirroring `redpandaconnect_addon`'s FROST
OAuth2 wiring. `tasks/keycloak_sso.yml`:

1. fetches the `api-access` client-secret via the shared platform helper
   `tasks/templates/keycloak_client_secret.yaml` (`client_id: IDM_CLIENT.API_ACCESS`);
2. ensures the purpose-scoped client roles (`dataConsumer` / `dataProducer`,
   overridable via `inv_addons.cividash.ngsi_ld_roles`) that make Keycloak
   mint the `api:read` / `api:write` scopes the CORE APISIX gateway enforces;
3. assigns those roles to the `api-access` service account (idempotent).

The `cividash` client has `serviceAccountsEnabled: false`; it only carries the
auth-code SSO flow and its audience mapper.

> **Platform dependency:** `IDM_CLIENT.API_ACCESS` and the shared task
> `tasks/templates/keycloak_client_secret.yaml` are provided by the CORE
> control plane at run time (not vendored in this add-on), exactly as
> `redpandaconnect_addon` relies on them. Keep the `dataConsumer`/`dataProducer`
> convention in sync with the platform's api:read/api:write scope mapping.

> **Note:** If Filament admin access is gated on a Keycloak role/group, the
> first admin must be granted the `cividash:admin` role in Keycloak
> manually. The add-on creates the client roles (`admin`, `editor`) but does
> not assign them to any user.

## Operator prerequisites (M2M / `api-access`)

The NGSI-LD machine token rides on the shared `api-access` client, which the
**operator** owns and provisions — the add-on does not create it and, mirroring
`redpandaconnect_addon`, deliberately does **not** enable service accounts or
edit group membership on it. For the M2M flow to actually work, `api-access`
must be provisioned so that:

1. **`serviceAccountsEnabled = true`** — otherwise Keycloak mints **no**
   client-credentials token at all (`401 unauthorized_client`).
2. The **`api:read` / `api:write`** scopes are requestable by the client (these
   are the scopes the CORE APISIX gateway enforces in front of Stellio). The
   add-on requests them via `CIVITAS_OAUTH_SCOPE` (default `api:read api:write`,
   override with `inv_addons.cividash.ngsi_ld_scope`).
3. The **`api-access` service account is a member of the tenant group** (e.g.
   `ds_open_data`) with the SPI-read attributes, so the issued token carries a
   non-empty **`tenants`** claim. With an empty claim Stellio refuses every
   request (`no access to tenant ds_open_data`) even though a token was minted.

**Deploy-time preflight.** [`tasks/preflight_m2m.yml`](../tasks/preflight_m2m.yml)
runs right after `keycloak_sso.yml` and verifies (1)–(3) against the live realm
before any workloads are deployed: it requests a client-credentials token for
the api-access client and asserts both that a token is issued and that its
`tenants` claim is non-empty. On failure it stops the deploy with a message
naming the missing operator step above, instead of shipping a dashboard that
cannot reach Stellio. Skip the check consciously with
`inv_addons.cividash.m2m_preflight_enabled: false`.

The pure decode/assert logic ([`tasks/preflight_m2m_assert.yml`](../tasks/preflight_m2m_assert.yml))
is proved in isolation against mocked token payloads by
[`dev/preflight-assert.test.yml`](../dev/preflight-assert.test.yml).
