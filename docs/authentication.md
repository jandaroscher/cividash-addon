# Authentication

## Public area and admin area

The add-on registers no APISIX route. CiviDash is reached only through its
own Ingress (see [Helm chart, Routing](helm-chart.md#routing)), and nothing
in front of it checks tokens. The public dashboard, `/api/*` and `/docs` are
open. The Laravel/Filament application protects the admin area (`/admin`)
itself: with local CiviDash accounts (password login) and, optionally, with
Keycloak single sign-on.

## Keycloak client `cividash`

[`keycloak-clients.yaml`](../keycloak-clients.yaml) declares one confidential
client, which CORE's keycloak component creates in the instance realm:

| Setting | Value |
| --- | --- |
| Client ID | `cividash` |
| Flow | Authorization code (Socialite); direct access grants off, no service account |
| Redirect URI | `https://<subdomain>.<global.domain>/admin/auth/keycloak/callback` |
| Client roles | `admin`, `editor` |
| Protocol mappers | `client-roles-as-groups`: the client roles of `cividash` in the claim `groups` (ID token, access token, userinfo); `cividash-audience`: `cividash` in the access token audience |

The subdomain in `keycloak-clients.yaml` is fixed to `dashboard`. If you
change `cividash.cividash.subdomain`, the redirect URI no longer matches.

CORE generates the client secret and stores it as Secret
`keycloak-client-cividash` (key `client-secret`) in the keycloak namespace
and in the CiviDash namespace. The chart reads it through `secretKeyRef`
(`keycloak.clientSecret`); it never appears in Helm values.

The add-on's values set the other Keycloak settings of the chart:

| Chart value | Source |
| --- | --- |
| `keycloak.enabled` | `true` |
| `keycloak.baseUrl` | `https://<keycloak.app.subdomain>.<global.domain><keycloak.app.pathPrefix>` |
| `keycloak.realm` | `global.instanceSlug` |
| `keycloak.clientId` | `cividash` |
| `keycloak.clientSecret` | Secret `keycloak-client-cividash`, key `client-secret` |
| `keycloak.baseUrlInternal` | Not set. Set it through `cividash.cividash.rawValues` if the app has to exchange the code at another URL than the public one |

With the self-signed platform CA (`global.ingress.clusterIssuer:
selfsigned-ca`), the PHP pods also trust the CA from the Secret
`custom-ca-cert`, so the server-side token exchange with the public Keycloak
URL works (see [Helm chart, Platform CA](helm-chart.md#platform-ca)).

## Granting access

The add-on creates the roles but assigns them to nobody. In the Keycloak
admin console, open the instance realm and assign the client role `admin` or
`editor` of the client `cividash` to each user who administers the dashboard,
directly or through a group. The roles reach the app in the `groups` claim.

| Role | Access |
| --- | --- |
| `admin` | Full access to the CiviDash admin area |
| `editor` | Edits dashboard content in the admin area |

A role change takes effect at the user's next Keycloak login.

## Known gap: PKCE

CORE 2 enables PKCE (`pkce.code.challenge.method: S256`) on every
confidential client, including `cividash`. Keycloak then rejects an
authorization request without a code challenge. The CiviDash release pinned
in [`images.yaml`](../images.yaml) does not send PKCE yet, so Keycloak login
to the admin area fails until a CiviDash release with PKCE support is
pinned. Password login with local CiviDash accounts is not affected.

## NGSI-LD data sync

The chart can sync data from the platform (`civitas.*`). CORE 2 does not
provide NGSI-LD yet, so the add-on's values keep it off
(`civitas.enabled: false`), and the dashboards are maintained in the admin
area or imported. The `cividash` client has no service account and no access
to platform datasets. How an add-on's own client gets read access to
datasets is an open question with CIVITAS/CORE; this page will describe it
once the platform defines it.
