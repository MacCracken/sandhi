# sandhi — Roadmap

> Forward-looking sequencing toward fold-into-Cyrius-stdlib. State
> lives in [`state.md`](state.md); shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md). This file is the
> remaining work.

## Guiding objective

**Fold into Cyrius stdlib at v5.7.0** via a clean-break fold (see
[ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) —
revised from the original "before v5.6.x closeout" target. At
v5.7.0 stdlib deletes `lib/http_server.cyr` and gains
`lib/sandhi.cyr` in one event; 5.6.YY releases emit a deprecation
warning on any include of `lib/http_server.cyr`. The public surface
is frozen at 0.9.2 per [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md):
between 0.9.2 and 1.0.0 no new public verbs land, since every name
becomes a permanent stdlib API at fold time.

## Shipped (M0 through 0.9.9)

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

## What's left

### M6 — Fold into Cyrius stdlib (v1.0.0) — clean-break at v5.7.0

*Per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md): one event at the Cyrius v5.7.0 release gate, not a separate sandhi milestone. The 5.6.YY window is the notice period; 5.7.0 is the cutover.*

**Pre-fold (this repo)**:
- Documentation pass — confirm CLAUDE.md / state.md / roadmap.md / CHANGELOG / ADRs all reflect 0.9.9 final state
- Public-surface freeze confirmation — re-walk every `sandhi_*` name against the 0.9.2 surface; nothing leaked in 0.9.3-0.9.9
- Final `dist/sandhi.cyr` regeneration via `cyrius distlib` — this is the bundle stdlib vendors
- Consumer pin uplift coordination via `docs/issues/` paste-ready docs (yantra, daimon, hoosh, ifran, sit, ark, mela, vidya)

**v5.7.0 (the fold event, on the cyrius-side)**:
- Cyrius stdlib adds `lib/sandhi.cyr` vendored from `dist/sandhi.cyr`
- Cyrius stdlib deletes `lib/http_server.cyr` — no alias, no passthrough, no empty stub
- Downstream consumers' 5.7.0-compatible tags switch `include "lib/http_server.cyr"` → `include "lib/sandhi.cyr"`, and any `[deps.sandhi]` pin is dropped
- sandhi repo enters maintenance mode; subsequent patches land via the Cyrius release cycle

**Acceptance** (checked at the 5.7.0 release gate, not in this repo):
- Consumer repos (yantra, hoosh, ifran, daimon, mela, vidya, sit-remote, ark-remote) build against 5.7.0 stdlib without `[deps.sandhi]` pins
- `dist/sandhi.cyr` is byte-identical to `lib/sandhi.cyr` at the fold commit
- No include of `lib/http_server.cyr` survives anywhere in AGNOS

### Post-v1 (1.0.x stdlib-patch window)

*The fold freezes the public surface, so anything below lands via
the Cyrius release cycle, not sandhi's. Items grouped by trigger.*

**Deferred from the 0.9.9 audit** — both prototyped, both ran into
`tests/sandhi.tcyr`'s per-program fixup cap (architecture/001).
Once sandhi is folded into `lib/sandhi.cyr`, the per-program cap
re-baselines (consumers' tests no longer re-concatenate all of
sandhi's src), so both land cleanly as 1.0.x patches.

- **Trailer-forbidden list — `Proxy-Authenticate`** — would round
  out the proxy-auth pair landed at 0.9.9 (`Proxy-Authorization`).
  Single string-literal addition; lower priority than the three
  landed names since it's a response challenge to the client, not
  an injectable credential vector.
- **Request-builder dup-prevention** — caller-supplied `Host` /
  `Content-Length` / `Transfer-Encoding` / `Connection` in
  `user_headers` currently emit alongside the auto-injected
  versions, creating dup-header smuggling vectors on the wire. The
  server-side counterpart (`sandhi_headers_smuggle_dup`) landed at
  0.9.1; this is the symmetric client-side filter applied at build
  time. Implementation prototyped in 0.9.9 as a hand-rolled byte
  compare in `_sandhi_client_name_is_reserved` (no string literals)
  but the per-character bit ops still tipped the cap. Caller
  currently owns the contract — don't pass these in `user_headers`.

**Wait-for-second-consumer-ask**:

- **CONNECT / proxy tunneling** — no documented AGNOS egress-proxy need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing APIs. RFC 6265 is a regret-magnet; wait for a real ask.
- **JSON Merge Patch (RFC 7396)** / **JSON-RPC 2.0 batch** — batch is the likelier ask (MCP tool-discovery latency); wait for it.
- **TLS ALPN extensions beyond `http/1.1` and `h2`** — both ship today; anything beyond that waits for a consumer ask.

**Wait-for-stdlib-prerequisite**:

- **mDNS lookup + publishing** — blocked on stdlib `net.cyr` multicast primitives (`IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` / `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`). Request as a targeted stdlib patch when multicast becomes a priority for any consumer. The 0.9.3 unicast-response (QU bit) implementation works against most responders without multicast support.
- **Session-resumption cache in tls_policy** — right moment is the v5.9.x native-TLS transition.
- **Fuzzing harness** — Cyrius toolchain doesn't ship AFL/libFuzzer equivalent yet. Revisit when it does.

**Optimization-grade, profile first**:

- **HPACK Huffman encode for short binary tokens** — current encoder picks Huffman over raw when strictly shorter; ties go to raw. Some short cookies / opaque tokens could benefit from a tie-breaker that favors Huffman to keep dynamic-table state more compact. Wait for evidence.
- **Arena-per-request allocator** — profile first; stdlib `alloc` may already be a bump allocator under the hood.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD intrinsics; byte-at-a-time is perfectly adequate at SSE / HTTP / HPACK parsing rates observed so far.

**Won't ship without strong cause**:

- **OCSP stapling / CT log check / HSTS preload** — operational footguns (HPKP retirement lessons). Pin + custom trust store covers AGNOS's actual threat model.
- **gRPC-Web / GraphQL-over-HTTP** — explicit non-goals.

## What sandhi does NOT plan to do

Explicit non-goals (to survive the fold-into-stdlib filter):

- **Reimplement network primitives.** Those stay in stdlib.
- **Ship its own config parser.** Stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics.** bote + t-ron own protocol; sandhi::rpc::mcp is transport only.
- **Be a generic "service framework."** Keep the surface small and specific to what AGNOS consumers actually need. If something more general is called for, it's a case for the caller to own, not sandhi.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively.** Add only when a second consumer needs the same pattern.

## Why this roadmap exists

The fold-into-stdlib target is aggressive — sandhi's sibling-crate phase is the 5.6.x window, with the fold happening in one event at the v5.7.0 release gate. That constraint forced scope discipline through the 0.x sequence: minimum viable + what existing consumers actually need + nothing speculative. M6's acceptance criteria are checked at the 5.7.0 release gate by existing repos continuing to build, not by new features landing in this repo.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) for the naming + thesis, [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) for the clean-break fold decision, [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md) for the surface freeze, and [`state.md`](state.md) for live progress.
