# Request: cookie jar

**Filed**: 2026-06-23 (consolidated out of the roadmap's wait-for-second-consumer list)
**Touches**: `src/http/` (new module) + redirect-follow in `src/http/client.cyr`
**Gate**: an AGNOS consumer using cookie-bearing APIs

## Ask

A client-side cookie store (RFC 6265): capture `Set-Cookie` from responses,
attach matching `Cookie` headers on subsequent requests to the same
origin/path, honour `Domain` / `Path` / `Secure` / `HttpOnly` / `Max-Age` /
`SameSite`, and thread the jar through redirect-follow.

## Why it's a request, not roadmap work

No AGNOS consumer talks to a cookie-bearing API — AGNOS service-to-service
traffic is token/header-authenticated, not cookie-session. RFC 6265 is a
well-known **regret-magnet** (eTLD+1 public-suffix handling, `SameSite`
evolution, jar-scoping edge cases); building it without a real consumer
shape invites a surface that's wrong for whoever eventually needs it.

## When to promote

A consumer that must drive a cookie-session web API. Scope the jar to that
consumer's actual cookie semantics rather than a full RFC 6265
implementation up front.
