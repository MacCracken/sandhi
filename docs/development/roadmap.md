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
is currently **cyrius 6.2.7** (the 1.5.x arc — see state.md / CHANGELOG).

**Pacing.** The items below are *provisional groupings*, not committed dated
slots — each opens when its gate clears (a cyrius primitive lands, profile
evidence justifies it, a second consumer asks, or sit surfaces friction). ONE
item per slot. Per [`project_sit_adoption_drives_roadmap`] scope is surfaced from
real signals, not pre-baked; per the no-silent-scope-outs rule every deferral is
a named entry here, not a buried mention.

## Batch A — cross-repo-gated (waiting on a cyrius primitive)

- **A1 — native TLS-policy enforcement (the last libssl coupling).** Native
  trust-store / mTLS currently **fails closed** (since 1.4.7) because the
  enforcing path is libssl-only. Two cyrius-side items unblock it — and let
  `sandhi_tls_use_libssl()` be dropped entirely:
  - **Native `SSL_CTX_*` equivalents** in `lib/tls_native.cyr` (custom trust
    store + client cert/key) so native trust/mTLS *enforces* rather than fails
    closed (mirrors the 1.4.2 ALPN/SPKI rewire). *Re-verified still-open on
    cyrius 6.2.7: the only verify-related public verb is `tls_set_verify`; no
    native trust-store / client-cert / client-key wrapper exists, and native
    CertificateRequest handling is server-side only (an HTTP client gets no
    client-cert path).*
  - **Fix the libssl `tls_get_peer_spki_der` regression** — a single libssl
    pinned open SIGSEGVs in post-handshake SPKI extraction (worked at 1.3.0;
    regressed since). sandhi excludes libssl from `pin_available()` until fixed.
  Tracked at
  [`2026-05-22-cyrius-native-tls-in-6.0.x.md`](../issues/2026-05-22-cyrius-native-tls-in-6.0.x.md).
  (SPKI *pinning* itself is already backend-agnostic + live on native since
  1.4.2 / 1.4.7; only the trust-store/mTLS *enforcement* is gated.)

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
