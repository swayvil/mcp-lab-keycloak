# Keycloak on Render, for an OAuth 2.0 token-exchange demo

A Keycloak image with a realm baked in, deployable on [Render](https://render.com) from a
blueprint. It gives a demo a stable, public, HTTPS identity provider in a few minutes,
without a database and without a tunnel.

The realm demonstrates [RFC 8693](https://datatracker.ietf.org/doc/html/rfc8693) token
exchange: a first token obtained by a user, then exchanged for one whose audience is
narrowed to a single downstream API. Authorization can then be expressed per audience and
per role, which is what an API gateway in front of those APIs enforces.

| File | Role |
| --- | --- |
| `render.yaml` | The blueprint. One free web service, health-checked on the realm's discovery document |
| `Dockerfile` | Keycloak 26.2, built in a first stage and run with `start --optimized --import-realm`, listening on port 10000 behind the platform's TLS |
| `keycloak-realm.json` | The realm: clients, audience mappers, roles and test users |

## Deploy

1. **Render > New > Blueprint**, pointing at this repository. Render asks for the values
   marked `sync: false`:

   | Variable | Value |
   | --- | --- |
   | `KC_BOOTSTRAP_ADMIN_PASSWORD` | A real password. The admin console is on the public internet here |
   | `KC_GATEWAY_CLIENT_SECRET` | The secret of the client that requests the exchange. Whatever you choose, your client has to send the same |
   | `KC_TEST_USER_PASSWORD` | Shared by the three test users |

2. Wait for the first deploy. The health check points at the discovery document, so a
   deploy that goes live is also proof the realm imported.
Keycloak derives the issuer from the `Host` header, so the service is usable as it stands.
To pin the issuer instead — worth doing before putting a custom domain in front — add
`KC_HOSTNAME` in *Settings > Environment*, set to the service URL, and redeploy. Add it
afterwards rather than declaring it in the blueprint: a blueprint variable whose prompt you
skip is filled with a generated value, and Keycloak would then advertise a host that does
not exist.

Every push redeploys the service, and the realm follows with it.

## The realm

`poc-mcp`, holding four clients:

| Client | Role in the flow |
| --- | --- |
| `mcp-client` | Public client. Obtains the user's first token, whose audience is the gateway |
| `omni-gateway` | Confidential client. Requests the exchange, and is the audience the gateway validates on the way in |
| `flights-api`, `bookings-api` | Audiences only. They exist so a token can be narrowed to one API and refused by the other |

Two audience mappers on `omni-gateway` make both API audiences available to the exchange.
The `audience` parameter of the exchange then *filters* them, so a single requested
audience comes back alone in the `aud` claim — which is what lets the downstream policies
be written per API.

Three realm roles, `flights-reader`, `flights-writer` and `booking-agent`, are carried by
three users: `alice` (reader), `bob` (reader and writer) and `carol` (reader and booking
agent). `carol` is deliberately orthogonal: holding every right on one API grants none on
the other. Note that the exchanged token carries no `roles` claim, so role-based rules can
only be enforced on the first one.

## Credentials

None are in this repository. The client secret and the test users' password are
`${...}` placeholders in the realm file, substituted from environment variables at import
time — a documented Keycloak feature. The instance is reachable from the internet, so
anything trusting its tokens would otherwise trust whoever read those values out of git.

There is no database. The realm is re-imported on every boot and its signing keys are
regenerated, so tokens minted before a restart stop verifying. The URL survives, which is
the point.

## What to know before a demo

| | |
| --- | --- |
| **Cold starts** | A free instance spins down after 15 minutes without traffic and takes about a minute to come back. Callers see that as a JWKS timeout, so the first request after a pause fails. Warm it up beforehand, or take the paid plan, which does not spin down. |
| **Memory** | It fits in 512 MB, but only because the image is built for the options it runs with. Keycloak otherwise augments itself on first start, and that peak got the container killed before a port was ever opened — a failed deploy whose only clue was `Out of memory (used over 512Mi)` after the line about installing custom providers. A builder stage runs that step instead, `start --optimized` skips it, and the heap is capped in absolute terms because what the platform kills for is resident memory, not heap. The first paid tier has the same 512 MB, so it buys availability, not headroom. |
| **Clustering** | Running in prod mode to skip the augmentation brings the clustered cache with it, and that cache looks for peers. With none to find, JGroups connected to the instance's own address and retried until the container was killed — the same `Out of memory` line, from an entirely different cause. `KC_CACHE=local` turns it off; `start-dev` set that implicitly, which is why the problem only appeared after the move to prod mode. |
| **Boot time** | About four minutes from a push to a healthy service, most of it the platform's build and rollout rather than Keycloak, which now starts without augmenting. |
