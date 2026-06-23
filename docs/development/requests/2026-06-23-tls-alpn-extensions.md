# Request: TLS ALPN protocols beyond `http/1.1` + `h2`

**Filed**: 2026-06-23 (consolidated out of the roadmap's wait-for-second-consumer list)
**Touches**: `src/http/conn.cyr` (the ALPN wire buffers + `_sandhi_alpn_*`)
**Gate**: a consumer needing an ALPN protocol beyond `http/1.1` + `h2`

## Ask

Advertise / negotiate ALPN protocol identifiers other than the two sandhi
ships today (`http/1.1` and `h2`) — e.g. a custom application protocol over
TLS, or a future `h3`-adjacent identifier — by extending the per-process
ALPN wire buffers and the advertise toggle in `src/http/conn.cyr`.

## Why it's a request, not roadmap work

Both protocols an AGNOS consumer needs (`http/1.1` for the 1.1 client,
`h2` for the auto-promotion path) already ship and negotiate end-to-end.
Anything beyond them is speculative — the wire-buffer construction is
cheap, but exposing a *configurable* ALPN list is public surface that
should be shaped by a real protocol need, not invented ahead of one.

## When to promote

A consumer that must negotiate a third ALPN protocol over sandhi's TLS
client. Scope the advertise-list surface to what that protocol needs.
