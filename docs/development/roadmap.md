# sandhi — Roadmap

> Forward-looking sequencing post-fold. State lives in
> [`state.md`](state.md); shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md). This file is the
> remaining work.

## Guiding objective (post-fold)

**Fold landed at Cyrius v5.7.0 (sandhi 1.0.0)** per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).
Cyrius stdlib vendors `dist/sandhi.cyr` as `lib/sandhi.cyr`;
consumers `include "lib/sandhi.cyr"` and drop their
`[deps.sandhi]` pins.

This repo is now in **post-fold maintenance**. Patches still
land here first — `dist/sandhi.cyr` is regenerated and the
cyrius-side `lib/sandhi.cyr` refresh is a small cyrius slot
that picks up the change. The public surface is no longer
frozen (ADR 0005's freeze applied "between 0.9.2 and 1.0.0";
post-fold patches are explicitly allowed per the 1.1.0 ship).

## Shipped (M0 through 1.1.0)

Compressed log — one line per release. CHANGELOG carries the
details, state.md the current snapshot.

- **M0 — 0.1.0** — scaffold + library-shape manifest + ADR 0001
- **M1 — 0.2.0** — `lib/http_server.cyr` lift-and-shift to `src/server/mod.cyr`
- **M2 — 0.3.0** — full HTTP client (POST/PUT/DELETE/PATCH/HEAD/GET, redirects, native UDP DNS)
- **M3 — 0.4.0** — JSON-RPC dialects (WebDriver, Appium, MCP) + dialect-aware error envelopes
- **M4 — 0.5.0** — service discovery (chain resolver, daimon HTTP backend, mDNS interface)
- **M5 — 0.6.0** — TLS-policy surface (default / pinned / mTLS / trust-store + combine)
- **M3.5 — 0.7.0** — SSE streaming + incremental chunked decode + MCP-over-SSE
- **0.7.1** — quick-wins from external review (default UA / AE, max-response-bytes, err_message slot)
- **0.7.2** — read/write timeouts, retry wrappers, DNS hardening, AAAA resolver, sakshi tracing, server idle-timeout
- **0.7.3** — connect_ms + total_ms (non-blocking connect + monotonic deadline threading)
- **0.8.0** — HTTP/2 + connection pool (pool, HPACK, frames, ALPN surface, h2 lifecycle, public `sandhi_h2_request`)
- **0.8.1** — `sandhi_http_request_auto` + per-method auto verbs (pool h2-take → 1.1 fallback)
- **0.9.0** — Phase 1 security: 5 P0s from the 0.7.0 audit
- **0.9.1** — Phase 2 P1 sweep: 7 hardening fixes
- **0.9.2** — pre-fold closeout: server symbol rename + `dist/sandhi.cyr` + ADR 0005 surface freeze
- **0.9.3** — stub-elimination + CI hardening (TLS enforcement / ALPN / mDNS / IPv6 client / retry jitter)
- **0.9.4** — versioning refactor (auto-generated `src/version_str.cyr`) + chunked response trailers
- **0.9.5** — h2 redirect-following hoisted to auto layer + retry-through-auto routing
- **0.9.6** — ALPN-driven h2 auto-promotion (first release where live h2 fires end-to-end via the auto path)
- **0.9.7** — `TE: trailers` request signaling on both 1.1 and h2; te-conditional h2 forbidden filter
- **0.9.8** — HPACK Huffman encode wired into `_hpack_string_encode`; byte-exact RFC 7541 C.4.1 reference
- **0.9.9** — internal P1 self-audit: trailer forbidden list expanded; ALPN/Huffman/redirect/h2 filter audited sound
- **0.9.10** — pool stale-skip hardening: `_sandhi_pool_has_idle` peek now ignores conns past `idle_timeout_ms` so ALPN promotion fires deterministically
- **1.0.0** — fold-ready release. Transitional `http_*` aliases dropped; final `dist/sandhi.cyr` regenerated; vendored into Cyrius stdlib at v5.7.0
- **1.1.0** — allocator-as-first-arg migration. 6 commit-sized bites; ~150 new `_a` public verbs alongside back-compat wrappers. Toolchain pin 5.6.41 → 5.8.36. 792 assertions green (482 sandhi + 167 h2 + 143 alloc)
- **1.1.1** — `Proxy-Authenticate` trailer-forbidden (rounds out 0.9.9 proxy-auth pair); toolchain pin 5.8.36 → 5.10.0 (mechanical, profile-instrumentation only)

## What's next

### 1.1.x — post-fold patch window (deferred-from-audit + small fixups)

*Small, well-scoped patches that don't fit the optimization-
pass shape of 1.2.0. Each ships independently when ready.
The 1.0.x window's per-program-fixup-cap deferrals re-baseline
post-fold (consumers' tests no longer re-concatenate sandhi's
`src/`), so both items below land cleanly here.*

- ~~**1.1.1 — `Proxy-Authenticate` trailer-forbidden**~~
  ✅ landed 2026-05-08 (also bumped toolchain pin 5.8.36
  → 5.10.0).
- **1.1.2 — Request-builder dup-prevention** —
  caller-supplied `Host` / `Content-Length` /
  `Transfer-Encoding` / `Connection` in `user_headers`
  currently emit alongside the auto-injected versions,
  creating dup-header smuggling vectors on the wire.
  Server-side counterpart (`sandhi_headers_smuggle_dup`)
  landed at 0.9.1; this is the symmetric client-side
  filter applied at build time. Implementation prototyped
  at 0.9.9 but tipped the per-program fixup cap. Cap re-
  baselines post-fold.

Either of these can absorb additional small patches when a
consumer files something — the 1.1.x window is intentionally
a "small fixes" lane separate from 1.2.0's optimization pass.

### 1.2.0 — true TLS + optimization pass

**Theme**: take TLS from "wired up over fdlopen-libssl" to
"production-grade across the policy surface", paired with a
profile-driven optimization pass on the hot paths. This is
the natural sandhi-side companion to the Cyrius v5.9.x →
v5.10.x native-TLS work.

**True TLS work**:

- **Session-resumption cache in `tls_policy`** — long-pinned
  ("right moment is the v5.9.x native-TLS transition" per
  the M5 closeout note). Sandhi-side cache holds session
  tickets (TLS 1.3) / session IDs (TLS 1.2) keyed by
  `(host, port, alpn)`; hands them to `tls_connect` on
  reuse. Closes a meaningful TTFB gap on repeated requests
  to the same authority. Keying must respect the 0.9.0
  cred-strip rules (no resumption across different
  authentication contexts).
- **Live-network TLS-policy gate** — exercise the four
  policy modes (`default` / `pinned` / `mtls` /
  `trust_store`) end-to-end against real endpoints, not
  synthetic fixtures. The `pinned` and `trust_store`
  modes shipped at 0.6.0 with surface tests; `mtls` is
  unverified post-stub-fill (0.9.3). Add a probe-style
  test (mirroring the cyrius `_tls_live_gate` shape) so
  regressions in the policy-enforcement path don't sneak
  past unit tests.
- **TLS 1.3 0-RTT (early data) — opt-in** — only for
  GET / HEAD / OPTIONS where the request is replay-safe
  per RFC 8446 §8. Behind an explicit options flag
  (`sandhi_http_options_allow_0rtt`) — the replay-attack
  surface means default-off is the only safe default.
  Pairs with session-resumption since 0-RTT requires a
  cached session.
- **`tls_connect` native-transport prep** — when Cyrius
  ships native TLS (v5.10.x or later — currently
  fdlopen-libssl), the `tls_connect_with_ctx_hook` /
  ALPN / SNI / SPKI surfaces need to keep working
  byte-identical. Audit the hook surface for any
  fdlopen-leaning assumptions; document the ones that
  must hold across the transport swap. No code change
  in this slot if the hook surface is already
  abstraction-clean — but the audit itself is a real
  deliverable.

**Optimization pass** (each item: profile first, justify
with numbers):

- **Hot-path allocator review** — the 1.1.0 `_a`-variant
  surface lets consumers pass arena allocators; sandhi's
  internal helpers default to `default_alloc()` for
  process-wide singletons (HPACK static / Huffman tree /
  ALPN literals) but per-request data should ride the
  caller's arena. Walk `src/http/` + `src/rpc/` looking
  for cases where back-compat wrappers (calling
  `default_alloc()`) leak into per-request paths.
- **HPACK Huffman tie-break for short tokens** — current
  encoder picks Huffman over raw when *strictly* shorter;
  ties go to raw. Some short cookies / opaque tokens
  benefit from a tie-breaker that favors Huffman to keep
  dynamic-table state more compact. Profile-gated.
- **`_sandhi_resp_new` allocation collapse** — the
  central response-builder allocates header storage,
  body buffer, and Str header separately. If the call
  shape is hot enough, fuse into a single allocation
  with internal offset slicing.
- **Connection-pool LRU eviction** — current pool evicts
  on idle-timeout only; under sustained pressure the
  oldest-but-recently-touched entries can hold slots
  that newer routes would benefit from. LRU policy
  behind an option flag; default keeps current
  semantics until profiling shows benefit.
- **`_sandhi_conn_connect_nb` factoring candidate
  (Cyrius v5.9.42)** — Cyrius v5.9.42 carved out
  `lib/regression.cyr` and exposes
  `regression_network_probe(addr_ipv4, port,
  timeout_ms)` — same non-blocking-connect + poll +
  SO_ERROR-readback mechanics as sandhi's
  `_sandhi_conn_connect_nb` in
  [`src/http/conn.cyr`](https://github.com/MacCracken/sandhi/blob/main/src/http/conn.cyr).
  Two reasonable directions, decide at slot entry:
  (a) factor sandhi's helper into a stdlib-shaped
      `net_connect_nb(fd, addr, port, timeout_ms)`
      primitive in `lib/net.cyr` (or a new
      `lib/net_extra.cyr`), then `regression_network_probe`
      compose-uses it for its socket+probe shape.
      Cleaner, but a stdlib API addition that needs
      its own slot in the cyrius cycle.
  (b) leave sandhi's helper as is; just document the
      shape duplication so future readers know both
      exist. No code change.
  Default to (b) unless profiling surfaces a hot-path
  reason to extract (which it likely won't —
  connect-nb runs once per conn-open, not per
  request). Either way, document the choice in the
  slot's CHANGELOG so the parallel evolution is
  intentional rather than accidental.

**Acceptance criteria for 1.2.0**:
- Session resumption cache hits documented via the
  existing `sakshi.tracing` boundaries (no new public
  span verbs).
- Live-network TLS policy gate runs in CI with the
  same skip-cleanly cascade as the cyrius
  `_tls_live_gate` (cc5 / dlopen-helper / network /
  upstream cert reachable).
- 0-RTT path verified against a known TLS 1.3 endpoint;
  default-off behavior unchanged from 1.1.x.
- At least one optimization-pass item lands with a
  measured improvement; the others can defer to
  1.2.1+ or stay parked under "profile-grade".

### Post-1.2.0 — wait-for-trigger

*Same shape as before — items grouped by what unblocks
them, not by version pin.*

**Wait-for-second-consumer-ask**:

- **CONNECT / proxy tunneling** — no documented AGNOS egress-proxy need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing APIs. RFC 6265 is a regret-magnet; wait for a real ask.
- **JSON Merge Patch (RFC 7396)** / **JSON-RPC 2.0 batch** — batch is the likelier ask (MCP tool-discovery latency); wait for it.
- **TLS ALPN extensions beyond `http/1.1` and `h2`** — both ship today; anything beyond that waits for a consumer ask.

**Wait-for-stdlib-prerequisite**:

- **mDNS lookup + publishing** — blocked on stdlib `net.cyr` multicast primitives (`IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` / `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`). Request as a targeted stdlib patch when multicast becomes a priority for any consumer. The 0.9.3 unicast-response (QU bit) implementation works against most responders without multicast support.
- **Fuzzing harness** — Cyrius toolchain doesn't ship AFL/libFuzzer equivalent yet. Revisit when it does.

**Optimization-grade, profile first**:

- **Arena-per-request allocator** — the 1.1.0 `_a`-variant surface enables this; consumer-side opt-in. Profile the alloc traffic on a real workload before evangelizing.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD intrinsics; byte-at-a-time is perfectly adequate at SSE / HTTP / HPACK parsing rates observed so far.

**Won't ship without strong cause**:

- **OCSP stapling / CT log check / HSTS preload** — operational footguns (HPKP retirement lessons). Pin + custom trust store covers AGNOS's actual threat model.
- **gRPC-Web / GraphQL-over-HTTP** — explicit non-goals.

## What sandhi does NOT plan to do

Explicit non-goals (preserved from pre-fold; still hold):

- **Reimplement network primitives.** Those stay in stdlib.
- **Ship its own config parser.** Stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics.** bote + t-ron own protocol; sandhi::rpc::mcp is transport only.
- **Be a generic "service framework."** Keep the surface small and specific to what AGNOS consumers actually need. If something more general is called for, it's a case for the caller to own, not sandhi.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively.** Add only when a second consumer needs the same pattern.

## Why this roadmap exists

Pre-fold, this file documented the path to v5.7.0. Post-fold,
its job is keeping the post-v1 patch window honest:
1.1.x catches small deferrals from the freeze period; 1.2.0
is the first real new-work release (true TLS + optimization);
beyond that, items wait for their unblock signal rather than
landing speculatively.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md)
for the naming + thesis, [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
for the (now-shipped) clean-break fold decision, [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md)
for the surface freeze (now lifted post-1.0.0), and
[`state.md`](state.md) for live progress.
