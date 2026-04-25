# 0003 — HTTP/2 and the connection pool shipped together

**Status**: Accepted
**Date**: 2026-04-24

> **Thesis**: HTTP/2's stream multiplex and HTTP/1.1's keep-alive want
> different checkout shapes from a connection pool. Designing the pool
> against 1.1-only and then bolting h2 on later would have forced a
> mid-0.8.x refactor of the pool's API. Bundling them let one pool
> serve both protocols from day one.

## Context

0.7.2's roadmap originally listed "connection pool / keep-alive" as a
standalone 0.7.2 item. It slipped — the CHANGELOG 0.7.2 "Deferred"
section says so explicitly:

> **Connection pool / keep-alive** — shifted to 0.8.0 alongside HTTP/2
> since h2 multiplexing changes the pool checkout shape. Roadmap
> 0.7.2 entry updated with rationale.

Two checkout shapes were in play:

- **HTTP/1.1 keep-alive**: one conn carries one in-flight request.
  Pool checkout is **exclusive** — caller takes the conn, runs the
  request, returns the conn. LIFO stack per route, FIFO eviction at
  the per-route cap. Matches Go's `net/http.Transport`.
- **HTTP/2 multiplex**: one conn carries N concurrent streams bounded
  by peer `SETTINGS_MAX_CONCURRENT_STREAMS`. Pool checkout is
  **non-exclusive** — caller "takes" the conn without removing it
  from the pool, allocates a stream id, fires the request, and
  streams N and N+1 can overlap freely on the same socket. Stream
  accounting is per-conn state, not pool state.

Both protocols hit the pool struct at the same choke point — the
per-route keyed lookup — but they diverge immediately after that. A
single map keyed by `host:port:tls` needs two value types living next
to each other: a vec of `idle_conn` wrappers for 1.1 and a shared
`sandhi_h2_conn` ptr for h2.

## Decision

Ship the pool and h2 in one release. 0.8.0 lands as eight
commit-sized "bites" that sequence pool → HPACK → h2 frames → ALPN
surface → h2 connection lifecycle → pool h2 glue → public dispatch
verb, all in one minor bump:

- **Bite 1** — `src/http/pool.cyr`. 1.1 keep-alive checkout (LIFO
  take, FIFO evict, 8 conns/route, 90s idle timeout). Pool struct
  layout reserves `SANDHI_POOL_OFF_H2_MAP = 32` up front for Bite 6
  even though Bite 1 doesn't use it — avoids a struct-size churn.
- **Bite 2 / 2b** — HPACK static + dynamic tables; Huffman decode.
- **Bite 3** — h2 frame layer (header struct + all six frame-type
  codecs).
- **Bite 4** — ALPN wire-format encoder + selection accessor (stubbed
  pending libssl).
- **Bite 5a / 5b / 5c** — h2 conn struct + handshake; HEADERS
  encoding + send; response decode loop.
- **Bite 6** — `src/http/h2/pool_glue.cyr` fills in
  `sandhi_http_pool_take_h2` / `_put_h2` / `_close_h2_conns` against
  the `h2_map` slot Bite 1 reserved. See [architecture/002](../architecture/002-forward-reference-via-glue-modules.md)
  for why this is a separate module.
- **Bite 7** — public `sandhi_h2_request` dispatch verb.

The pool's h2 and 1.1 entries coexist without touching each other's
data structures — `idle_conn` wrappers stay in the vec under the
per-route key; `sandhi_h2_conn` ptrs live in a separate per-route
map at `SANDHI_POOL_OFF_H2_MAP = 32`.

## Consequences

- **Positive**
  - One pool API, two protocols. The public surface
    (`sandhi_http_pool_new` / `_close` / opts attachment) is identical
    whether the pool backs 1.1-only or mixed 1.1+h2 traffic.
  - The h2 stream-multiplex tests in `tests/h2.tcyr` exercise the
    same pool data structure that 1.1 keep-alive does. One set of
    per-route-key / LIFO-vec / eviction bugs to catch, not two.
  - Pool struct layout froze once at Bite 1 with the h2_map slot
    reserved. No struct-offset churn mid-0.8.x; Bite 6 just stored
    into a slot that was already there.
  - 0.8.1's `sandhi_http_request_auto` had a single pool to consult
    (check h2_map first, fall through to the idle_conn vec for 1.1)
    instead of a two-pool dispatch shape.
- **Negative**
  - 0.8.0 was a big release — eight bites, ~2500 lines of new code,
    +188 assertions. Bigger than any prior release; bigger than any
    planned future release given the surface freeze at 0.9.2.
  - Test-file split (`sandhi.tcyr` / `h2.tcyr`) became necessary
    mid-Bite-2 when HPACK pushed the per-program fixup cap. Fine
    outcome, but an unexpected mid-release detour — see
    [docs/proposals/2026-04-24-cyrius-fixup-table-cap.md](../proposals/2026-04-24-cyrius-fixup-table-cap.md).
  - Live h2 talk was gated on the libssl-pthread-deadlock blocker.
    The protocol stack shipped fully tested against synthetic byte
    streams but couldn't exercise against a real peer. The 0.8.0
    CHANGELOG called that out; 0.8.1's `_auto` wiring made it a
    seamless upgrade when the blocker clears.
- **Neutral**
  - Sets the pattern for future protocol additions: ship the
    transport module and its pool integration in the same release.
    Should h3 (QUIC) ever arrive, the lesson applies — a QUIC
    "conn" is a stream multiplex just like h2, so the checkout
    shape would fit the existing non-exclusive path.

## Alternatives considered

- **Ship pool in 0.7.2, h2 in 0.8.0.** The original plan. Rejected
  when the 0.7.2 design work surfaced the checkout-shape divergence
  — a pool API frozen against 1.1 semantics would have required
  breaking changes in 0.8.x to accommodate multiplex, and 0.8.x
  is the wrong place for API breaks this close to the v5.7.0 fold.
- **Ship h2 without pool integration; consumers open h2 conns
  directly.** Rejected — the whole point of a pool is that consumers
  don't manage conn lifecycle. An h2 client that can only run one
  request per conn (because the consumer has to close and reopen
  each time) defeats the protocol's primary win. And once
  `sandhi_http_request_auto` is the recommended entry point,
  h2-outside-the-pool has no call-site story.
- **Two separate pools — `sandhi_http_pool` for 1.1,
  `sandhi_h2_pool` for h2 — composed at the http options layer.**
  Considered. Rejected for the consumer-side verbosity (two pool
  attachments, two close calls) and because
  `sandhi_http_request_auto` would need to dispatch across both
  structures anyway — the "single keyed lookup with two value
  types" shape is exactly what the unified pool gives, cheaper.
- **Delay h2 to 0.9.x.** Would have freed 0.8.0 to be a smaller
  release. Rejected because 0.9.x was already spoken for by the
  security sweep (0.9.0 P0 + 0.9.1 P1), and pushing h2 to 1.0.x
  would put it on the far side of the v5.7.0 fold — h2 would then
  ship in stdlib, not sandhi, and we'd have no sibling-crate
  window to shake out protocol bugs.
