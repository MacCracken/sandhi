# Proposal: CONNECT / proxy tunneling

**Filed**: 2026-06-23 (consolidated out of the roadmap's wait-for-second-consumer list; moved from `docs/development/requests/` at 1.10.11)
**Touches**: `src/http/conn.cyr` (open path) + `src/http/client.cyr`
**Status**: scheduled for **1.15.0** ([roadmap](../roadmap.md#115x--proposals-client-egress), 2026-10-15). Its original gate was "a documented AGNOS egress-proxy need"; the risks below are what the build must settle.

## Ask

Support HTTP `CONNECT`-method tunneling so the client can reach an origin
through a forward proxy (the standard `CONNECT host:port` → 200 → opaque
byte tunnel, then TLS to the origin over the tunnel).

## Why it waited (design risks to settle when building)

No AGNOS consumer egresses through a proxy today, so there is no shape to
build against — proxy auth, `Proxy-Authorization`, no-proxy lists, and TLS
SNI-through-tunnel semantics are all guesswork without a real deployment.
Building it speculatively risks baking in the wrong policy surface (the
same regret the cookie-jar and ALPN-extension requests carry).

## The use it was waiting for

A consumer (or AGNOS deployment) that must reach external services through
a corporate / sidecar egress proxy. At that point this becomes a roadmap
slot scoped to that consumer's actual proxy contract.
