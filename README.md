# Keycloak on Render, for an OAuth 2.0 token-exchange demo

A Keycloak image with a realm baked in, deployable on [Render](https://render.com) from a
blueprint. It gives a demo a stable, public, HTTPS identity provider in a few minutes.

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

1. **Render > New > Blueprint**, pointing at this public repository. Render asks for the values
   marked `sync: false`:

   | Variable | Value |
   | --- | --- |
   | `KC_BOOTSTRAP_ADMIN_PASSWORD` | A real password. The admin console is on the public internet here |
   | `KC_GATEWAY_CLIENT_SECRET` | The secret of the client that requests the exchange. Whatever you choose, your client has to send the same |
   | `KC_TEST_USER_PASSWORD` | Shared by the three test users |

2. Wait for the first deploy. The health check points at the discovery document, so a
   deploy that goes live is also proof the realm imported.

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
