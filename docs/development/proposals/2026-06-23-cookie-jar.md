# Proposal: cookie jar

**Filed**: 2026-06-23 (consolidated out of the roadmap's wait-for-second-consumer list; moved from `docs/development/requests/` at 1.10.11)
**Touches**: `src/http/` (new module) + redirect-follow in `src/http/client.cyr`
**Status**: scheduled for **1.15.x**, after CONNECT ([roadmap](../roadmap.md#115x--proposals-client-egress), 2026-10-15). Its original gate was "an AGNOS consumer using cookie-bearing APIs"; the roadmap starts it host-only, per the risks below.

## Ask

A client-side cookie store (RFC 6265): capture `Set-Cookie` from responses,
attach matching `Cookie` headers on subsequent requests to the same
origin/path, honour `Domain` / `Path` / `Secure` / `HttpOnly` / `Max-Age` /
`SameSite`, and thread the jar through redirect-follow.

## Why it waited (design risks to settle when building)

No AGNOS consumer talks to a cookie-bearing API — AGNOS service-to-service
traffic is token/header-authenticated, not cookie-session. RFC 6265 is a
well-known **regret-magnet** (eTLD+1 public-suffix handling, `SameSite`
evolution, jar-scoping edge cases); building it without a real consumer
shape invites a surface that's wrong for whoever eventually needs it.

## The use it was waiting for

A consumer that must drive a cookie-session web API. Scope the jar to that
consumer's actual cookie semantics rather than a full RFC 6265
implementation up front.
