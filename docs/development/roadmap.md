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
is currently **cyrius 6.2.9** (1.6.1 ported the v4 nb-connect + per-op timeout to
Darwin by composing stdlib — see state.md / CHANGELOG).

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
- **IPv6 nb-connect + server listen socket not Darwin-ported (follow-on to the
  1.6.1 macOS connect fix).** 1.6.1 ported the IPv4 nb-connect + per-op timeout to
  Darwin by composing stdlib (`net_connect_nb` / `sock_set_*_timeout`). Two raw-
  syscall sites in `src/http/conn.cyr` / `src/server/mod.cyr` still build the
  fcntl/poll/getsockopt dance against Linux-only flag/opt VALUES
  (`_SANDHI_O_NONBLOCK=0x800`, `_SANDHI_EINPROGRESS=115`, `_SANDHI_SO_ERROR=4`):
  (1) `_sandhi_conn_connect_sa_nb_a` (the internal IPv6 sockaddr nb-connect), and
  (2) the server accept-loop's non-blocking listen socket. On macOS the SYSXLAT
  backend translates the syscall numbers but NOT these values, so both misbehave
  on Darwin — and the v6 path additionally needs the Darwin `AF_INET6=30` +
  `sin6_len` sockaddr_in6 shape, which stdlib's own `SockDomain`/sockaddr_in6
  isn't ported to either. The v6 fallout is masked today (v6 connect fails → the
  client falls back to v4); the server listen path is the sharper gap.
  **Blocked on cyrius** — sandhi can't compose a Darwin-correct v6 nb-connect
  (or a non-blocking listen socket) because stdlib exposes no Darwin v6 surface to
  compose; that's a `lib/net.cyr` v6-on-Darwin pass, filed upstream as
  [`2026-06-15-cyrius-net-v6-darwin.md`](../issues/2026-06-15-cyrius-net-v6-darwin.md).
  When those primitives land, sandhi adopts them (retire `_sandhi_conn_connect_sa_nb_a`
  / `_sandhi_conn_sockaddr_in6_a` + the server `O_NONBLOCK` fcntl) the same way
  1.6.1 retired the v4 dance. Surfaced by the 1.6.1 fix; see also
  [`2026-06-06-macos-nonblocking-connect.md`](../issues/2026-06-06-macos-nonblocking-connect.md).
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

## Wait-for-stdlib-prerequisite

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
