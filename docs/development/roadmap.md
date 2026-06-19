# sandhi — Roadmap

> **Open / remaining work only.** Shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md); the live snapshot in
> [`state.md`](state.md). When an item ships it moves out of this file
> (into the CHANGELOG), so everything here is still to-do.

## Context (post-fold)

sandhi folded into Cyrius stdlib at **v5.7.0 / sandhi 1.0.0**
([ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) and is in
**post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is
regenerated, and a small cyrius-side slot refreshes `lib/sandhi.cyr`. The public
surface is no longer frozen (ADR 0005's freeze applied only 0.9.2 → 1.0.0). Pin
is currently **cyrius 6.2.22** (1.6.4 added the binary streaming download path;
1.6.5 added its live-network gate + the two bugs it caught; 1.6.6 fixed the
yeo-cy-test SIGPIPE server DoS; 1.6.7 added the SecureYeoman-driven server
routing layer + thread-pool serve mode; **1.6.8 added server-side TLS**
(`sandhi_server_run_tls` / `_run_pooled_tls` + the `SandhiConn` transport seam +
conn-aware routing) — sandhi can now SERVE HTTPS on the native TLS stack — plus
the pooled handoff-depth fix (`sandhi_server_options_backlog`) and the pin bump
to 6.2.22 — all pure composition / sandhi-side, see state.md / CHANGELOG).

**Pacing.** The items below are *provisional groupings*, not committed dated
slots — each opens when its gate clears (a cyrius primitive lands, profile
evidence justifies it, a second consumer asks, or sit surfaces friction). ONE
item per slot. Per [`project_sit_adoption_drives_roadmap`] scope is surfaced from
real signals, not pre-baked; per the no-silent-scope-outs rule every deferral is
a named entry here, not a buried mention.

## Batch A — libssl retirement (sandhi 2.0 — breaking)

A1 (native trust-store / mTLS enforcement) **shipped at 1.6.0** over cyrius
6.2.8: native now enforces pinning + trust-store + mTLS via the typed
backend-aware ctx verbs, so the deprecated libssl backend has **no remaining
functional gap**. What's left is the breaking removal itself, held for the
**2.0** major (dropping a public verb + a build flag is not a patch):

- **Retire the libssl opt-out (2.0).** Drop `sandhi_tls_use_libssl()` (public
  verb) + the `-D CYRIUS_TLS_LIBSSL` build flag + the libssl branches in
  `src/tls_policy/*` and `src/http/conn.cyr`. Breaking → the 2.0 major, not a
  1.6.x patch. The prerequisite (A1) is now met; this is a scheduling decision,
  not a blocked item. See `project_libssl_retirement_at_2_0` (memory).
- **libssl `tls_get_peer_spki_der` regression — now moot, low priority.** sandhi
  still excludes libssl from `pin_available()` (a single libssl pinned open
  SIGSEGV'd in post-handshake SPKI extraction). Native covers pinning and libssl
  retires at 2.0, so this gates nothing; only revisit if a libssl build is kept
  alive past 2.0 (unlikely). Tracked at
  [`2026-05-22-cyrius-native-tls-in-6.0.x.md`](../issues/2026-05-22-cyrius-native-tls-in-6.0.x.md).

## Batch B — profile-justified optimization picks (parked; need prof evidence)

The 1.2.5 prof captures (`sandhi_prof_*`) are the gate. No pre-committed
ordering; each ships in its own slot when measurement — not speculation —
justifies it.

- **B1 — HPACK Huffman tie-break for short tokens.** The encoder picks Huffman
  only when *strictly* shorter; a tie-breaker favoring Huffman keeps the dynamic
  table more compact for short cookies / opaque tokens.
- **B2 — `_sandhi_resp_new` allocation collapse.** Fuse the separate header
  storage / body buffer / Str-header allocations into one with internal offset
  slicing — if the call shape measures hot enough.
- **B3 — connection-pool LRU eviction.** The pool evicts on idle-timeout only;
  add an LRU policy behind an option flag (default keeps current semantics until
  profile shows benefit).

## Batch C — sit-adoption reshape (filled by what sit surfaces)

The native-TLS prerequisite sit named has landed (native default since cyrius
6.1.21), and sit's AGNOS adoption drove the C1/C2 transport work already shipped
(see CHANGELOG). Further Batch C items fill from real-workload friction sit
surfaces — NOT speculatively pre-baked ([`project_sit_adoption_drives_roadmap`]).
Currently open:

- **QU mDNS resolver receive correctness (needs a live-network check).** The
  default unicast (QU) resolver in `src/discovery/local.cyr` `sock_connect`s to
  the mDNS group then `sock_recv`s — the same Linux connect()-source-filter shape
  that broke the 1.5.4 QM attempt (an answer arrives from the responder's unicast
  IP, not the group address). Its "works against most responders" claim is
  **unverified** (unit tests use synthetic packets; the smoke only checks a
  no-responder miss). Run a live-network check; if it confirms the resolver never
  receives, apply the 1.5.5 two-socket fix (unconnected RX) to the QU path too.
- **Native custom-trust-store verify-fail proof (needs a CA fixture).** The 1.6.0
  live gate (`_policy_runtime_probe.cyr` `[4]`) proves a *bogus* custom trust
  store is enforced (unreadable CA → open refused with err=TLS, not silently
  ignored). It does **not** yet prove a *loadable-but-wrong* CA causes a handshake
  verify-fail (swap the trust anchor to a CA that doesn't sign the server → must
  reject). That needs a CA PEM fixture + the cyrius `tls_native` CA-bundle
  replace-vs-append semantics. Chain-verify correctness itself is cyrius's (the
  CVE-18 fail-closed `tls_native_connect`); this is sandhi's wiring-proof gap.

## Wait-for-second-consumer-ask

Add only when a *second* consumer needs the same pattern (CLAUDE.md). Each names
the file it would touch.

- **CONNECT / proxy tunneling** — no documented AGNOS egress-proxy need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing APIs; RFC 6265 is a
  regret-magnet, wait for a real ask.
- **JSON Merge Patch (RFC 7396) / JSON-RPC 2.0 batch** — batch is the likelier
  ask (MCP tool-discovery latency); wait for it.
- **TLS ALPN extensions beyond `http/1.1` and `h2`** — both ship today; more
  waits for a consumer ask.
- **h2 spec-completeness** (drained from `src/http/h2/` comments at 1.4.3): (a)
  request-body DATA-frame fragmentation when `body_len > peer_max_frame` (rejects
  with `_SANDHI_H2_ERR_BAD_LENGTH` today — `request.cyr`); (b) flow-control
  `WINDOW_UPDATE` enforcement (silently accepted; the peer's default window keeps
  responses bounded — `response.cyr`); (c) peer-SETTINGS `ENABLE_PUSH` /
  `MAX_HEADER_LIST_SIZE` enforcement (not applied to conn state — `conn.cyr`;
  ENABLE_PUSH is moot client-side, MAX_HEADER_LIST_SIZE advisory); (d)
  caller-overridable HEADERS-frame buffer cap (fixed 8 KB — `request.cyr`). Each
  waits for a consumer whose traffic exercises the limit.
- **Per-hop cred-digest recompute on cross-authority redirect-follow** — the
  1.3.3 session-cache cred-digest is computed once per top-level dispatch, so an
  A→B redirect reuses A's digest for the B handshake. Harmless for the AGNOS
  service-to-service common case; fold the recompute into
  `_sandhi_http_follow_a`'s hop loop when a consumer needs it
  (`src/http/client.cyr`).
- **Daimon resolver context: auth token + timeouts** — the daimon resolver ctx
  reserves a +8 slot (held 0) for a future auth token / per-request timeouts;
  daimon's registry contract defines no auth surface today. Wire it when a
  consumer needs authenticated / timeout-bounded discovery
  (`src/discovery/daimon.cyr`).
- **Client connection-pool thread-safety (per-pool mutex)** — the pool is
  single-threaded; multi-threaded clients would need a per-pool mutex. No
  consumer needs concurrent dispatch yet (`src/http/pool.cyr`).
### From yeo-cy-test (server adoption, 2026-06-17)

yeo-cy-test ported its hand-rolled `httpd.cyr` onto `sandhi_server_*` (recv /
parse / accessors / framing / smuggling rejects), keeping only a route table +
worker pool on top. Adoption verified end to end (13-case CRUD, 250 concurrent
POSTs, smuggling rejects). It surfaced one **security bug** and three rough
edges. Full write-up:
[`secureyeoman/yeo-cy-test/FINDINGS.md`](../../../secureyeoman/yeo-cy-test/FINDINGS.md).

- 🔴 **HIGH — SIGPIPE server DoS — ✅ FIXED 1.6.6** (`src/server/mod.cyr`). Both
  serve loops now install `SIG_IGN` for SIGPIPE at startup
  (`_sandhi_server_ignore_sigpipe`), so a peer that disconnects mid-response can
  no longer crash the process. Linux only today (the **macOS SIGPIPE guard**
  follow-on is open below; macOS needs the BSD `sigaction` ABI / `SO_NOSIGPIPE`).
  See CHANGELOG [1.6.6].
- 🟡 **Document the companion stdlib modules — ✅ DONE 1.6.6.** README gained a
  "Requires (companion stdlib modules)" note (`tls` / `async` / `random` /
  `fdlopen` / `dynlib`, plus the `bayan`-not-`json` rule). Pure documentation.
- 🟡 **macOS server SIGPIPE guard** (`src/server/mod.cyr`) — the 1.6.6 SIGPIPE
  fix is Linux-only (`rt_sigaction`, x86_64 13 / aarch64 134). macOS is a
  documented no-op: the macOS ESYSXLAT whitelist doesn't cover `sigaction`, so a
  raw call would mis-dispatch. Wiring it needs the BSD `sigaction` ABI (or
  per-socket `SO_NOSIGPIPE`) **and a macOS box to verify** (ground-first). macOS
  server support is itself new (1.6.2), so this opens when a consumer actually
  runs a sandhi server on Darwin — or when the stdlib helper below lands (which
  closes it portably in one move). Until then a sandhi server on macOS is still
  SIGPIPE-vulnerable; flagged here so it isn't silently assumed covered.
- **Server-side route table / dispatch — ✅ SHIPPED 1.6.7** (`src/server/mod.cyr`).
  `sandhi_server_route_match` (segment match + `:name` capture, equal-segment-count)
  + param accessors (`_param_int` → `-1` on non-numeric for a clean 400) + a thin
  route table (`sandhi_router_new`/`_add`/`_dispatch`, 405/404 fallback) +
  `sandhi_server_router_handler` (plugs into any serve loop). Lifted from the
  yeo-cy-test reference. SecureYeoman is the driving consumer, so it shipped
  directly (like the takumi download) rather than waiting for a second asker. See
  CHANGELOG [1.6.7].
- **Thread-pool / true-parallel serve mode — ✅ SHIPPED 1.6.7** (`src/server/mod.cyr`).
  `sandhi_server_run_pooled` — a fixed `max_conns`-sized worker-thread pool fed by
  a bounded `chan_*` handoff, so a blocking/CPU-bound handler ties up only its own
  worker (the true parallelism the single-flight `run` / cooperative `run_async`
  can't give). Same handler shape + SIGPIPE/SO_RCVTIMEO/smuggling guards; per-worker
  recv buffer; composes the thread-safe global `alloc`. Verified by the live gate
  `programs/_server_pool_probe.cyr` (rapid burst + slow-client isolation). Pairs
  with the route table above as "the server side a real service needs." See
  CHANGELOG [1.6.7].
- 🔴 **Server-side TLS — ✅ SHIPPED 1.6.8** (`src/server/mod.cyr`). sandhi can now
  SERVE HTTPS: `sandhi_server_run_tls` (single-flight) + `sandhi_server_run_pooled_tls`
  (worker pool) read cert/key from `sandhi_server_options_tls`, do a per-connection
  native handshake, and serve over a `SandhiConn` transport seam (conn-aware send +
  routing — `sandhi_server_send_*_c` / `sandhi_router_dispatch_c` /
  `sandhi_server_router_handler_c`). Ships on the **native** stack; all TLS I/O rides
  the backend-agnostic `tls_write`/`_read`/`_close` contract, only the handshake
  bootstrap composes the native server primitives. Validated end-to-end by the live
  gate `programs/_server_tls_probe.cyr` (real TLS 1.3, cert verify enforced, pool
  isolation). See CHANGELOG [1.6.8]. **Residual is cyrius-side** (filed under
  *Wait-for-stdlib-prerequisite* below): the `lib/tls.cyr` `tls_accept`
  server-handshake wrapper, and an arena-aware native server ctx (so
  per-connection RSS stops growing). *(Native server-side ALPN selection — once a
  gap here — landed at cyrius 6.2.22, so sandhi's `http/1.1` offer is genuinely
  negotiated; h2 over TLS still isn't served, but only because sandhi has no h2
  server, not for an ALPN reason.)*
- 🔵 **`run_pooled` handoff-channel depth = worker count — ✅ SHIPPED 1.6.8**
  (`src/server/mod.cyr`). New `sandhi_server_options_backlog` (default 128) sizes the
  kernel `listen` backlog AND the pooled handoff channel, **decoupled from
  `max_conns`** (the worker count) — a burst beyond the workers now queues up to
  `backlog` accepted conns instead of `chan_new(workers)` shedding to the kernel
  backlog. Applied to `run_pooled` + `run_pooled_tls`. See CHANGELOG [1.6.8].
- 🔵 **Server-only use drags the whole client + h2 + hpack + tls `.bss` — CLOSED
  (won't-fix; not a sandhi item).** A server-only consumer still links ~400 KB of
  static h2/hpack/tls tables (`CYRIUS_DCE=1` NOPs the code but keeps the `.bss`).
  This is a **cyrius issue** — the toolchain's bundled-libs packaging + DCE not
  reclaiming `.bss` — **not** sandhi's: sandhi is one composed library, and which
  symbols a consumer links is the toolchain's lib-packaging concern. There is no
  sandhi-side change that fixes it (splitting sandhi into server-only/client-only
  sub-libs would be sandhi inventing packaging the toolchain owns). Filed against
  cyrius; closed here so the framing doesn't drift back in as a sandhi slot. (See
  also *Not sandhi's slot*, below.)
- 🔵 **Stale `run_async` leak doc comment — ✅ FIXED 1.6.6.** The
  `sandhi_server_run_async` header claimed "leaks ~32 B/connection" via
  `lib/async.cyr` task structs, contradicting the inline 1.5.3 note + the
  `async_new_in(arena)` code that eliminated it. Header rewritten to match (zero
  residual leak, RSS flat). See CHANGELOG [1.6.6].
- **Streaming download to an fd / body-sink — SHIPPED 1.6.4** (`src/http/download.cyr`).
  takumi's source-download ask (takumi `docs/adr/0006-source-download.md`) was
  the trigger — a direct consumer need, so it shipped rather than waiting for a
  *second* asker. `sandhi_http_download(url, fd, opts)` + the general
  `sandhi_http_download_sink(url, cb, ctx, opts)` stream a binary body without
  ever fully buffering it (resident memory bounded; the 128 MiB cap lifts),
  composing the buffered path's redirect-follow + chunked/close decode. The
  **1.6.4 loose end closed at 1.6.5**: `programs/_download_probe.cyr` is now a live
  gate proving a large redirected download round-trips to disk — and it caught two
  real bugs (a spurious 256 KiB cap from inheriting `max_response_bytes`, and a
  split-inter-chunk-CRLF decoder stall in `stream.cyr`), both fixed. See
  CHANGELOG [1.6.4]/[1.6.5].

## Wait-for-stdlib-prerequisite

- **`lib/tls.cyr` server-handshake wrapper (`tls_accept` / `tls_new_server`)** —
  the clean home for 1.6.8's server-TLS handshake bootstrap. The `tls_*` contract
  exposes the client side (`tls_connect_alloc` / `_complete`) but no symmetric
  *server* side, so 1.6.8's `_sandhi_server_tls_handshake` composes the native
  server primitives (`tls_native_new_server` / `_set_alpn` / `_server_load_creds`
  / `_accept`) directly and wraps the result in the standard `lib/tls.cyr` ctx
  shim. When cyrius adds a backend-agnostic `tls_accept` (mirroring the client
  `tls_connect_alloc`/`_complete` that already landed), this one bootstrap
  migrates onto it — exactly as 1.6.1/1.6.2 migrated `conn.cyr`'s raw socket
  syscalls onto `net.cyr` helpers. Cyrius-side; sandhi composes around it today.
  **Filed:** cyrius `docs/development/issues/2026-06-18-lib-tls-cyr-no-server-handshake-wrapper.md`.
- **Arena-aware native server ctx** — `tls_native_new_server` + the per-handshake
  buffers are bump-allocated with no per-connection free (`tls_native_close` sends
  close_notify but doesn't reclaim the ctx), so a sandhi TLS server's RSS grows
  per accepted connection. sandhi can't fix this without forking the primitive
  (forbidden); it needs an arena-parameterized native server ctx (or a server-ctx
  free) upstream. Cyrius-side; until then a long-running sandhi TLS server should
  budget for per-connection growth (same property the proven probe shipped with).
  **Filed:** cyrius `docs/development/issues/2026-06-18-tls-native-server-ctx-not-arena-aware.md`.
- **Portable `signal_ignore` / `sock_send` `MSG_NOSIGNAL`** — the proper home for
  the 1.6.6 SIGPIPE guard. sandhi installs `SIG_IGN(SIGPIPE)` via a raw
  `rt_sigaction` because `net.cyr`'s `sock_send` is a flagsless `sys_write` (can't
  pass `MSG_NOSIGNAL`, and forking it is forbidden) and stdlib exposes no
  signal-disposition helper (SIGPIPE isn't even in the `Signal` enum). A stdlib
  `signal_ignore(signum)` (portable across Linux/macOS/agnos) **or** a
  `MSG_NOSIGNAL`-aware `sock_send` would let sandhi drop the raw syscall — and
  would close the **macOS SIGPIPE guard** gap above in one move. Mirrors how
  1.6.1/1.6.2 migrated `conn.cyr`'s raw socket syscalls onto `net.cyr` helpers
  once they landed. Cyrius-side; revisit when either lands.
- **Fuzzing harness** — the Cyrius toolchain ships no AFL / libFuzzer equivalent
  (re-verified absent on 6.2.7). Revisit when it does.

## Background watches (not slots)

- **`tests/sandhi.tcyr` cap-drift** — if a slot pushes sandhi.tcyr against the
  per-program fixup-cap (architecture/001), carve out another `tests/<name>.tcyr`
  in the same slot (mirroring the 1.2.8 sandhi → rpc split). Don't let it block
  the ship.
- **Consumer coordination docs** ([`docs/issues/`](../issues/README.md)) —
  yantra / hoosh+ifran / ark / mela / vidya / daimon (registry + MCP client).
  sandhi's side is shipped; these open when each consumer schedules adoption. The
  daimon `serve_async` collapse
  ([`2026-05-10-daimon-server-max-conns.md`](../issues/2026-05-10-daimon-server-max-conns.md))
  is sandhi-side done (1.4.9) — residual is daimon-side only.

## Optimization-grade (profile first; deferred, not parked)

- **Arena-per-request adoption (consumer side)** — the 1.1.0 `_a`-variant surface
  + the 1.2.0 hot-path review give consumers the foundation to pass per-request
  arenas end-to-end; whether to evangelize the pattern across AGNOS consumers
  waits on profile evidence from a real workload.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD intrinsics;
  byte-at-a-time is adequate at the SSE / HTTP / HPACK rates observed so far.

## Not sandhi's slot (filed so the framing doesn't drift back in)

- **`tls_connect` native-transport prep audit** — the hook surface
  (`tls_connect`, `tls_connect_with_ctx_hook`, ALPN / SNI / SPKI extraction) is
  owned by stdlib `lib/tls.cyr`. Auditing it for fdlopen-leaning assumptions is a
  cyrius-side issue, not a sandhi slot — sandhi composes the contract; cyrius
  keeps it byte-identical across any transport swap (ADR 0001).

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
[CHANGELOG](../../CHANGELOG.md). Live snapshot: [state.md](state.md).
