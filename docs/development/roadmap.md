# sandhi — Roadmap

> **Open / remaining work only, by release line.** Shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md); the live snapshot in
> [`state.md`](state.md); enhancement proposals (each scheduled below) in
> [`proposals/`](proposals/README.md); bugs + consumer-coordination in
> [`issues/`](issues/README.md). When an item ships it moves out of this file
> (into the CHANGELOG), so everything here is still to-do. Last swept clean of
> completed work on **2026-10-15** at 1.12.4: the 1.12.x line is complete (1.12.0
> the `loop` sweep, 1.12.1 private `const`, 1.12.2 private `bool`, 1.12.3 – 1.12.4
> the server and client transport traits), so its section is gone, as 1.11.x's
> went at 1.12.0. The traits item was re-scoped at 1.12.3 from the resolver /
> handler seams to the transport seam (why: CHANGELOG [1.12.3] and the 2.0 item).
> History is in the CHANGELOG.

## Context (post-fold)

sandhi folded into Cyrius stdlib at **v5.7.0 / sandhi 1.0.0**
([ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) and is in
**post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is
regenerated, and a small cyrius-side slot refreshes `lib/sandhi.cyr`. The public
surface is no longer frozen (ADR 0005's freeze applied only 0.9.2 → 1.0.0). Pin
is currently **cyrius 6.7.12** (since 1.10.10; the full trail is in `state.md`).

**How the lines work.**
- Each line is a minor release (1.11.0, 1.12.0, …) followed by its patches; items
  within a line ship in the order listed, one item per patch (single focus per
  patch). The lines run in order; a line opens when the previous one has shipped.
- **Maintenance lands on the open line.** Pin bumps and consumer-filed fixes ship
  as patches on whichever line is open (1.12.x until 1.13.0 opens 1.13.x) and do
  not wait for a line of their own.
- A consumer-filed defect or real-workload friction (sit, bote, …) takes the next
  patch on whatever line is open; it does not wait for its "own" line.
- Every new public verb still ships permanently into stdlib's `lib/sandhi.cyr`, so
  each proposal is built to the narrowest shape that serves a known AGNOS use
  (CLAUDE.md, small and earned surface), not the full incumbent feature set.
- Per the no-silent-scope-outs rule, every deferral is a named entry here or in
  [`proposals/`](proposals/README.md), not a buried mention.

## 1.13.x — Client concurrency and HTTP/2 completeness

- **1.13.0 — client connection-pool thread-safety (per-pool mutex)**
  (`src/http/pool.cyr`). 1.6.9 made the *buffered dispatch* path thread-safe (a
  per-call request context) for fresh-connection concurrency; a multi-threaded
  client sharing a pooled-connection cache still needs a per-pool mutex.
- **`_sandhi_alpn_advertise_h2` into the request context** (`src/http/conn.cyr`,
  written by the h2 promotion in `src/http/h2/dispatch.cyr`, read by
  `_sandhi_policy_pre_open_a` and the connection finalize). 1.10.7 moved the TLS
  policy hook into the per-call request context and left this process-wide flag,
  because a collision only changes which ALPN list a concurrent open offers
  (negotiation, not enforcement). Lift it into a `SANDHI_REQCTX_*` slot. Pairs with
  the pool mutex; it also clears the ground for the 1.14 ALPN proposal.
- **Per-hop cred-digest recompute on cross-authority redirect-follow**
  (`src/http/client.cyr`). The 1.3.3 session-cache cred-digest is computed once per
  top-level dispatch (stored in the 1.6.9 request context), so an A→B redirect
  reuses A's digest for the B handshake. Fold the recompute into
  `_sandhi_http_follow_a`'s hop loop.
- **h2 spec-completeness**, one patch each (drained from `src/http/h2/` comments at
  1.4.3):
  - (a) request-body DATA-frame fragmentation when `body_len > peer_max_frame`
    (rejected with `_SANDHI_H2_ERR_BAD_LENGTH` today; `request.cyr`);
  - (b) flow-control `WINDOW_UPDATE` enforcement (silently accepted; the peer's
    default window keeps responses bounded; `response.cyr`);
  - (c) peer-SETTINGS `MAX_HEADER_LIST_SIZE` enforcement (not applied to conn
    state; `conn.cyr`). `ENABLE_PUSH` is moot client-side;
  - (d) a caller-overridable HEADERS-frame buffer cap (fixed 8 KB; `request.cyr`).

## 1.14.x — Proposals: RPC and TLS surface

- **1.14.0 — JSON-RPC 2.0 batch** (`src/rpc/dispatch.cyr` + `src/rpc/mcp.cyr`):
  send an array of requests in one POST, demultiplex the responses by `id`. MCP
  tool discovery (many small calls) is the motivating use. Settle partial failure,
  notification-vs-request mixing and ordering in the proposal before coding.
  [Proposal](proposals/2026-06-23-json-merge-patch-and-rpc-batch.md).
- **JSON Merge Patch (RFC 7396)** (`src/rpc/json.cyr`): recursive object merge,
  `null` deletes a member. Same proposal; ships separately.
- **TLS ALPN protocols beyond `http/1.1` + `h2`** (`src/http/conn.cyr` ALPN wire
  buffers + `_sandhi_alpn_*`): a caller-supplied advertise list, per request (it
  builds on the 1.13 request-context slot, not a process-wide list).
  [Proposal](proposals/2026-06-23-tls-alpn-extensions.md).

## 1.15.x — Proposals: client egress

- **1.15.0 — CONNECT / proxy tunneling** (`src/http/conn.cyr` open path +
  `src/http/client.cyr`): `CONNECT host:port` → 200 → opaque tunnel, then TLS to the
  origin over it, with SNI for the origin. Start with an explicit proxy option and
  basic `Proxy-Authorization`; environment variables and no-proxy lists only if a
  deployment needs them.
  [Proposal](proposals/2026-06-23-connect-proxy-tunneling.md).
- **Cookie jar** (new `src/http/` module + redirect-follow in `src/http/client.cyr`):
  capture `Set-Cookie`, attach matching `Cookie` per origin and path, honour
  `Domain` / `Path` / `Secure` / `Max-Age`, and thread the jar through redirects.
  Host-only cookies first: the public-suffix list and `SameSite` policy are the
  regret-magnets the proposal names, and they need a real cookie-session API to
  shape them. [Proposal](proposals/2026-06-23-cookie-jar.md).

## 1.16.x — Performance (measure first)

The 1.2.5 prof captures (`sandhi_prof_*`) are the method. The line opens by
capturing prof data on a representative workload (sit, bote or hoosh traffic),
and ships only what the profile warrants, each in its own patch:

- **B1 — HPACK Huffman tie-break for short tokens.** The encoder picks Huffman
  only when *strictly* shorter; a tie-breaker favouring Huffman keeps the dynamic
  table more compact for short cookies / opaque tokens.
- **B2 — `_sandhi_resp_new` allocation collapse.** Fuse the separate header
  storage / body buffer / Str-header allocations into one with internal offset
  slicing, if the call shape measures hot.
- **B3 — connection-pool LRU eviction.** The pool evicts on idle-timeout only; add
  an LRU policy behind an option flag (the default keeps current semantics).
- **Arena-per-request adoption guidance for consumers.** The 1.1.0 `_a`-variant
  surface and the 1.2.0 hot-path review let consumers pass per-request arenas end
  to end; write it up in `docs/guides/` with the profile numbers that justify it.

## 2.0.0 — the breaking major

Everything that changes a public verb, flag, signature or kind. Post-fold this is
also a **breaking stdlib change**: cyrius vendors `dist/sandhi.cyr` as
`lib/sandhi.cyr`, so consumers break when cyrius re-vendors 2.0, not when they
move a sandhi pin.

- **Coordinate the re-vendor with cyrius first.** An ADR here for the 2.0 surface
  and a cyrius-side issue for the vendoring release (deprecation notes, the
  consumer sweep), filed before 2.0.0 is cut.
- **Retire the libssl opt-out.** Native enforces pinning, trust store and mTLS
  (since 1.6.0), so the deprecated backend has no functional role. Drop
  `sandhi_tls_use_libssl()`, the `-D CYRIUS_TLS_LIBSSL` build flag, and the libssl
  branches in `src/tls_policy/*` and `src/http/conn.cyr`.
  - **The libssl smoke CI step goes with it.** It was `continue-on-error` from
    cyrius 6.3.5 through sandhi 1.10.8 and gates again since 1.10.9
    ([`issues/archive/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md`](issues/archive/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md)).
  - **Two libssl-only quirks drop with the backend, unfixed.** The TLS 1.3 session
    captured before the NewSessionTicket arrives (the 1.10.7 session-cache
    investigation; the libssl resumption test offered by cyrius at 6.6.16 was
    declined at 1.10.9), and the `tls_get_peer_spki_der` SIGSEGV that keeps libssl
    out of `pin_available()`
    ([`issues/archive/2026-05-22-cyrius-native-tls-in-6.0.x.md`](issues/archive/2026-05-22-cyrius-native-tls-in-6.0.x.md)).
- **Public `: bool` predicates.** The public `sandhi_*_is_*` / `_has_*` predicates
  change kind.
- **Public `const`.** `HTTP_OK` / `HTTP_NOT_FOUND` and the other status names share
  their names with `lib/http.cyr`'s vars, and a `const` beside a same-name `var` is
  a hard error, so this needs a cyrius-side plan (likely in the same coordination
  issue).
- **Trait-typed public signatures** for the discovery resolver (`sandhi_resolver_new`
  takes a fn pointer + ctx today) and the server handlers (`fn h(ctx, cfd, buf, blen)`):
  a consumer would declare a struct and an `impl`, and get checked dispatch in return.
  1.12.3 found no internal trait seam there (CHANGELOG [1.12.3]); the transports got
  their traits instead (1.12.3 server, 1.12.4 client).

## 2.0.x — after the major

- **Consumer migration support.** Patch whatever the first consumers hit moving to
  2.0 through the cyrius re-vendor, and update the handoff docs in
  [`issues/`](issues/README.md) to the 2.0 surface.

## Blocked on another repo (no line until it moves)

- **Daimon resolver context: auth token + timeouts** (`src/discovery/daimon.cyr`).
  The resolver ctx reserves a +8 slot (held 0) for an auth token / per-request
  timeouts, but daimon's registry contract defines no auth surface, and its
  `/services/` routes do not exist yet
  ([`issues/2026-04-24-daimon-registry-endpoints.md`](issues/2026-04-24-daimon-registry-endpoints.md)).
  Takes a patch on the open line once daimon publishes the contract.
- **Consumer coordination docs** ([`issues/`](issues/README.md)): ifran (hoosh's
  half adopted), ark, vidya (fetch), daimon (registry producer). sandhi's side is
  shipped; each opens when its consumer schedules adoption.

## Standing watches (process, not releases)

- **The unguarded-accumulator / unguarded-allocation class is not exhausted.**
  1.9.10, 1.9.12 and 1.9.13 each fixed instances of *"an allocation result or an
  accumulator was stored without its guard"*, and 1.9.13 found a **third** copy of a
  bound two earlier sweeps had each fixed once. Assume a fourth: grep every
  `size = size * ` / `n = n * ` accumulator fed from the wire, and every
  `store64(..., <alloc-returning-call>(...))` that skips its zero check. Write the
  regression test before believing a finding (both 1.9.13 descriptions that came from
  probes were wrong; see that CHANGELOG entry).
- **Test-unit include lists are partial by design.** `tests/h2.tcyr` includes
  `h2/dispatch.cyr` but not `client.cyr`, so it compiles with unreachable undefined
  refs (23 reported on 6.6.15); `sandhi.tcyr` / `rpc.tcyr` carry one each. Not a
  defect (the refusing linker proves them unreachable), but the noise can hide a
  new warning. Complete the lists only if it does, watching the per-program fixup
  cap (architecture/001).
- **`tests/sandhi.tcyr` cap-drift.** If a patch pushes `sandhi.tcyr` against the
  per-program fixup cap (architecture/001), carve out another `tests/<name>.tcyr` in
  the same patch (as the 1.2.8 sandhi → rpc split did). The suite is 1,006
  assertions on Linux at 1.12.4.
- **Fuzz-corpus expansion.** Add harnesses as new parse surfaces land; each
  proposal above that parses wire input (batch responses, merge-patch documents,
  `Set-Cookie`, the CONNECT response) brings its own `fuzz/*.fcyr`. Other
  candidates: Huffman-decode direct, the h2 frame header, the WebDriver / Appium /
  MCP envelope extract.
- **Native client vs `openssl s_server -tls1_2` on the Ed25519 fixture —
  unverified.** The 1.10.7 session-cache investigation saw the native client fail
  that handshake (`-3`) with the cache off. Not reproduced or root-caused; it may be
  a native TLS 1.2 + Ed25519 interop gap (cyrius-side) or a probe artifact.
  Reproduce ground-first before filing anything upstream.

## Not sandhi's slot (filed so the framing doesn't drift back in)

- **`tls_connect` native-transport prep audit** — the hook surface
  (`tls_connect`, `tls_connect_with_ctx_hook`, ALPN / SNI / SPKI extraction) is
  owned by stdlib `lib/tls.cyr`. Auditing it for fdlopen-leaning assumptions is a
  cyrius-side issue, not a sandhi slot — sandhi composes the contract; cyrius
  keeps it byte-identical across any transport swap (ADR 0001).
- **Server-only use drags the whole client + h2 + hpack + tls `.bss`** — a
  server-only consumer still links ~400 KB of static h2/hpack/tls tables
  (`CYRIUS_DCE=1` NOPs the code but keeps the `.bss`). This is a **cyrius**
  toolchain lib-packaging / DCE-`.bss`-reclaim concern, not sandhi's: sandhi is one
  composed library, and splitting it into server-only/client-only sub-libs would be
  sandhi inventing packaging the toolchain owns. Closed won't-fix here so it doesn't
  drift back in as a sandhi slot.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD intrinsics, and
  byte-at-a-time is adequate at the SSE / HTTP / HPACK rates observed so far. A
  cyrius feature first, if ever.

## Won't ship without strong cause

- **OCSP stapling / CT log check / HSTS preload** — operational footguns (HPKP
  retirement lessons). Pin + custom trust store covers AGNOS's actual threat
  model.
- **gRPC-Web / GraphQL-over-HTTP** — explicit non-goals.

## Non-goals (durable; preserved from pre-fold)

- **Reimplement network primitives** — those stay in stdlib.
- **Ship its own config parser** — stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics** — bote + t-ron own protocol; `sandhi::rpc::mcp`
  is transport only.
- **Be a generic "service framework"** — keep the surface small and specific to
  what AGNOS consumers actually need; if something more general is called for,
  it's the caller's to own.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively**
  — add only when a second consumer needs the same pattern.

---

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) (naming +
compose-don't-reimplement thesis), [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
(the shipped fold), and [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md)
(surface freeze, lifted post-1.0.0). Shipped history:
[CHANGELOG](../../CHANGELOG.md). Live snapshot: [state.md](state.md). Enhancement
proposals: [proposals/](proposals/README.md). Bugs + coordination:
[issues/](issues/README.md).
