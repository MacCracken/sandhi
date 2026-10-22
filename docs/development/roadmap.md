# sandhi — Roadmap

> **Open / remaining work only, by release line.** Shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md); the live snapshot in
> [`state.md`](state.md); enhancement proposals (each scheduled below) in
> [`proposals/`](proposals/README.md); bugs + consumer-coordination in
> [`issues/`](issues/README.md). When an item ships it moves out of this file
> (into the CHANGELOG), so everything here is still to-do. Last swept clean of
> completed work on **2026-10-22** at 1.13.4: the HPACK / Huffman first-use item shipped
> with the pin → 6.7.16, and nothing new joined the line. The 1.11.x and
> 1.12.x lines are complete and their sections are gone (the 1.12.x traits item was
> re-scoped to the transport seam: CHANGELOG [1.12.3]). History is in the CHANGELOG.

## Context (post-fold)

sandhi folded into Cyrius stdlib at **v5.7.0 / sandhi 1.0.0**
([ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) and is in
**post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is
regenerated, and a small cyrius-side slot refreshes `lib/sandhi.cyr`. The public
surface is no longer frozen (ADR 0005's freeze applied only 0.9.2 → 1.0.0). Pin
is currently **cyrius 6.7.16** (since 1.13.4; the full trail is in `state.md`).

**How the lines work.**
- Each line is a minor release (1.11.0, 1.12.0, …) followed by its patches; items
  within a line ship in the order listed, one item per patch (single focus per
  patch). The lines run in order; a line opens when the previous one has shipped.
- **Maintenance lands on the open line.** Pin bumps and consumer-filed fixes ship
  as patches on whichever line is open (1.13.x since 1.13.0) and do not wait for a
  line of their own.
- A consumer-filed defect or real-workload friction (sit, bote, …) takes the next
  patch on whatever line is open; it does not wait for its "own" line.
- Every new public verb still ships permanently into stdlib's `lib/sandhi.cyr`, so
  each proposal is built to the narrowest shape that serves a known AGNOS use
  (CLAUDE.md, small and earned surface), not the full incumbent feature set.
- Per the no-silent-scope-outs rule, every deferral is a named entry here or in
  [`proposals/`](proposals/README.md), not a buried mention.

## 1.13.x — Client concurrency and HTTP/2 completeness

Shipped so far: 1.13.0, the per-pool mutex (a pool may be shared across threads);
1.13.1, the h2 ALPN offer and the `_auto` dispatch's 0-RTT opt-in and credential
digest in the request context; 1.13.2, pin → cyrius 6.7.15 and the server's framing
reads in place (sit's filing); 1.13.3, one h2 connection shared by threads (a
per-connection lock around one exchange); 1.13.4, pin → cyrius 6.7.16 and the HPACK /
Huffman tables built once under concurrent first use.

- **TLS session cache under concurrent opens** (`src/tls_policy/session_cache.cyr`;
  found at 1.13.1). Once `sandhi_session_cache_enable(1)` is on, every TLS open looks
  up, stores and evicts in one process-wide map with no lock. Only the libssl backend
  stores sessions (native never resumes), so there concurrent opens can corrupt the
  map; on native only the hit/miss counters race. A mutex, as the pool got at 1.13.0.
- **Per-hop cred-digest recompute on cross-authority redirect-follow**
  (`src/http/client.cyr`). The 1.3.3 session-cache cred-digest is computed once per
  top-level dispatch (stored in the 1.6.9 request context), so an A→B redirect
  reuses A's digest for the B handshake. Fold the recompute into
  `_sandhi_http_follow_a`'s hop loop, and `_sandhi_http_auto_follow_a`'s (since
  1.13.1 its hops copy the digest from the dispatch's seed context).
- **h2 spec-completeness**, one patch each (drained from `src/http/h2/` comments at
  1.4.3):
  - (a) request-body DATA-frame fragmentation when `body_len > peer_max_frame`
    (rejected with `_SANDHI_H2_ERR_BAD_LENGTH` today; `request.cyr`);
  - (b) flow control (`response.cyr`, `request.cyr`): sandhi never sends
    `WINDOW_UPDATE` and ignores the peer's. **A pooled h2 conn stalls once its
    responses add up to the peer's 65,535-byte connection window**, and the h2 path has
    no read or total timeout of its own (only the opening request's `read_ms`, 0 by
    default). Measured at 1.13.1 against one.one.one.one: two `_auto` GETs of a 56 KB
    page through one pool, the second never returned; with `read_ms` 3,000 on the
    opener it fails with `SANDHI_ERR_PROTOCOL` after about 3 s. Send `WINDOW_UPDATE` as
    response data is consumed, and apply the request's own timeouts on the h2 path;
    `docs/guides/http2-manual.md` carries the caveat until then;
  - (c) peer-SETTINGS `MAX_HEADER_LIST_SIZE` enforcement (not applied to conn
    state; `conn.cyr`). `ENABLE_PUSH` is moot client-side;
  - (d) a caller-overridable HEADERS-frame buffer cap (fixed 8 KB; `request.cyr`).
- **h2 exchanges grow the global heap, arena or not** (`src/http/h2/request.cyr`,
  `response.cyr`, `hpack.cyr`; measured at 1.13.3). Ten `sandhi_h2_request_a` GETs on a
  per-request arena, reset after each, grew the no-free global heap by 42,992 B: about
  4.3 KB an exchange, for the life of a pooled conn.
  - **Frame I/O:** `sandhi_h2_request_send_a`, `sandhi_h2_response_recv_a` and the
    SETTINGS / PING handlers call the bare `sandhi_h2_conn_send_frame` /
    `_recv_frame`, so every frame header, decoded header struct and payload lands on
    the global heap.
  - **HPACK adds:** the encoder inserts through the bare `sandhi_hpack_table_add`, and
    every add rebuilds both vecs (at least 304 B) and abandons the old ones.
  - **The encoder table holds per-request pointers.** The lowercased name and the
    `:path` / `:authority` values come from the request's arena, so after its reset the
    table's eviction runs `strlen` over reused memory. That only corrupts the encoder's
    size accounting today, because the encoder never references its dynamic entries.
  - Thread `a` through the frame I/O, and give the conn's tables copies on the conn's
    own allocator (or stop indexing on the request side).
- **h2 frame reads write a NUL one byte past their buffer** (`src/http/h2/conn.cyr`;
  found at 1.13.3 by reading). `sandhi_h2_conn_recv_frame_a` allocates exactly 9 bytes
  for the header and exactly `plen` for the payload, and `sandhi_conn_recv_all`
  NUL-terminates at `buf[len]` ("buf must have room for max+1"). Allocations are
  8-aligned, so the byte lands in padding unless the length is a multiple of 8, and then
  on the next byte: free space, except when the allocation ends its arena. Allocate one
  more byte, or read with a non-terminating loop.
- **A failed h2 exchange leaves its conn pooled mid-stream** (`src/http/h2/response.cyr`,
  `pool_glue.cyr`; found at 1.13.3 by reading, not reproduced). After a timeout or
  protocol error, that stream's remaining frames stay in the socket and the conn stays
  in the pool. The next exchange skips them as other-stream frames, including any
  HEADERS whose HPACK block then goes undecoded, so the decode table drifts from the
  peer's and later responses can decode wrong header names. Since 1.13.3 the next
  exchange may be another thread's. Retire a conn whose exchange failed (the GOAWAY
  flag already makes `take_h2` evict it).
- **An h2 conn evicted for GOAWAY is never closed** (`src/http/h2/pool_glue.cyr`; found
  at 1.13.3 by reading). `sandhi_http_pool_take_h2` drops it from the map, and
  `_close_h2_conns` walks only the map, so its descriptor stays open for the life of
  the process. Close it once no exchange holds it (the conn's lock says when).
- **Each h2 frame goes out as two writes** (`src/http/h2/conn.cyr`; measured at 1.13.3).
  `sandhi_h2_conn_send_frame_a` sends the 9-byte header and the payload separately, and
  sandhi sets no `TCP_NODELAY`, so Nagle holds the second write until the delayed ACK of
  the first. Over loopback an exchange took about 80 ms; the 1.13.3 row sets
  `TCP_NODELAY` on its test pair to run at full speed. Over TLS each write is its own
  record, so the same applies. Send each frame as one write, or set `TCP_NODELAY` on
  client conns (`sock_set_nodelay`, cyrius 6.7.9).
- **The older fuzz harnesses draw correlated bytes** (`fuzz/dns`, `headers`, `hpack`,
  `json`, `response`, `sse`, `url`; found at 1.13.2). Each takes `% k` of the raw LCG
  state, whose low bits have short periods. `_fz_fill`'s `s % 256` has period 256, and a
  new seed only rotates the same cycle, so every "random" buffer is a rotation of one
  256-byte sequence (a 4,096-byte buffer is it 16 times). Draw from the high bits, as
  `fuzz/server_request.fcyr` does (and why: its low-bit draft missed a mutation). It
  changes every corpus, so it is its own patch: re-run each harness's parser on the new
  corpus and treat any finding as a finding.

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
  the same patch (as the 1.2.8 sandhi → rpc split did). The suite is 1,066
  assertions on Linux at 1.13.2.
- **Fuzz-corpus expansion.** Add harnesses as new parse surfaces land; each
  proposal above that parses wire input (batch responses, merge-patch documents,
  `Set-Cookie`, the CONNECT response) brings its own `fuzz/*.fcyr`. The server's
  request-header readers got theirs at 1.13.2 (`fuzz/server_request.fcyr`). Other
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
