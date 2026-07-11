# sandhi — Roadmap

> **Open / remaining work only.** Shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md); the live snapshot in
> [`state.md`](state.md); speculative "wait for a real ask" feature surface in
> [`requests/`](requests/README.md); bugs + consumer-coordination in
> [`issues/`](issues/README.md). When an item ships it moves out of this file
> (into the CHANGELOG), so everything here is still to-do. This file was last
> swept clean of completed work on **2026-06-29** (after 1.7.0).

## Context (post-fold)

sandhi folded into Cyrius stdlib at **v5.7.0 / sandhi 1.0.0**
([ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) and is in
**post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is
regenerated, and a small cyrius-side slot refreshes `lib/sandhi.cyr`. The public
surface is no longer frozen (ADR 0005's freeze applied only 0.9.2 → 1.0.0). Pin
is currently **cyrius 6.3.5** (1.7.0 parity bump; was 6.2.37 across 1.6.9–1.6.13).
The 1.6.9–1.6.13 + 1.7.0 patches (client dispatch thread-safety, the server-TLS
handshake migration + flat-RSS, the native trust-store verify-fail proof, the QU
mDNS receive fix, the conn-off fd-collision fix, and the two yeo-cy-test fixes)
were all pure sandhi-side (see CHANGELOG).

**Pacing.** The items below are *provisional groupings*, not committed dated
slots — each opens when its gate clears (a cyrius primitive lands, profile
evidence justifies it, a second consumer asks, or sit surfaces friction). ONE
item per slot. Per [`project_sit_adoption_drives_roadmap`] scope is surfaced from
real signals, not pre-baked; per the no-silent-scope-outs rule every deferral is
a named entry here (or in [`requests/`](requests/README.md)), not a buried mention.
The concrete sandhi-capacity patch sequence (1.6.10–1.6.12) shipped; everything
remaining here is gated (profile evidence, a breaking major, a second consumer, or
a cyrius primitive).

## Consumer-filed bugs (yeo-cy-test, 2026-06-28) — SHIPPED at 1.7.0

Both sandhi-side bugs surfaced adopting `sandhi_server_run_pooled_tls` + the h2
client (folded sandhi in cyrius 6.3.x) **shipped at 1.7.0** (see CHANGELOG; issue
docs archived): the **h2-promote IPv6 arity** one-liner (`dispatch.cyr` now passes
the 9th `ctx`=0) and the **misleading pooled-TLS concurrency comment** (corrected +
`max_conns = 1` recommended + the `[4]` concurrent-handshake watch added to
`_server_tls_probe.cyr`). One residual, gated below.

## Wait-for-upstream (sigil) — concurrent-handshake gate — ✅ SHIPPED at 1.8.1

The sigil process-global crypto-scratch race
(`2026-06-28-concurrent-tls-handshake-global-scratch-race`) that made a
multi-worker HTTPS pool unsafe is **fixed** — sigil auto-banks a private
crypto-scratch lane per thread (since 3.9.7; vendored 3.11.1 under the 6.4.49
pin). Verified at 1.8.1 on the new pin: `_server_tls_probe.cyr` `[4]` drives 16
genuinely-simultaneous handshakes against a 4-worker pool and **all 16 survive**
(was 0/16 through 1.7.0 / cyrius 6.3.5). Followed through: `[4]` **promoted to
gating**, and `sandhi_server_run_pooled_tls`'s `max_conns = 1` guidance relaxed
(`max_conns > 1` is now supported for HTTPS). No sandhi-side code change was
needed for the crash — sigil's per-thread lane is assigned automatically.

## Batch A — libssl retirement (sandhi 2.0 — breaking)

A1 (native trust-store / mTLS enforcement) **shipped at 1.6.0** over cyrius
6.2.8: native enforces pinning + trust-store + mTLS via the typed backend-aware
ctx verbs, so the deprecated libssl backend has **no remaining functional gap**.
What's left is the breaking removal itself, held for the **2.0** major (dropping
a public verb + a build flag is not a patch):

- **Retire the libssl opt-out (2.0).** Drop `sandhi_tls_use_libssl()` (public
  verb) + the `-D CYRIUS_TLS_LIBSSL` build flag + the libssl branches in
  `src/tls_policy/*` and `src/http/conn.cyr`. Breaking → the 2.0 major, not a
  1.6.x patch. The prerequisite (A1) is met; this is a scheduling decision, not a
  blocked item. See `project_libssl_retirement_at_2_0` (memory).
- **libssl smoke build is non-gating since cyrius 6.3.5 — drop at 2.0.** The
  `-D CYRIUS_TLS_LIBSSL` CI link-proof (`ci.yml`) is now `continue-on-error`:
  6.3.x's linker refuses reachable-undefined fns, and the libssl config leaves 4
  of sigil's transitive crypto symbols (`thread_local_init/set/get`, `ct_select`)
  reachable-but-unlinked — a cyrius-side DCE artifact of the libssl `#ifdef`, NOT a
  sandhi/sigil source defect (native links them all). Filed cyrius-side:
  [`issues/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md`](issues/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md).
  Delete the CI step entirely as part of the 2.0 libssl removal below; revisit
  sooner only if cyrius fixes the DCE reachability (or plumbs `--allow-undef`
  through `cyrius build`).
- **libssl `tls_get_peer_spki_der` regression — moot, low priority.** sandhi
  still excludes libssl from `pin_available()` (a single libssl pinned open
  SIGSEGV'd in post-handshake SPKI extraction). Native covers pinning and libssl
  retires at 2.0, so this gates nothing; only revisit if a libssl build is kept
  alive past 2.0 (unlikely). Context:
  [`issues/archive/2026-05-22-cyrius-native-tls-in-6.0.x.md`](issues/archive/2026-05-22-cyrius-native-tls-in-6.0.x.md).

## Batch B — profile-justified optimization picks (parked; need prof evidence)

The 1.2.5 prof captures (`sandhi_prof_*`) are the gate. No pre-committed
ordering; each ships in its own slot when measurement — not speculation —
justifies it. **Parked for later review** (the would-be `1.6.13` "opts" arc): the
concrete sandhi-capacity items all shipped at 1.6.10–1.6.12, so the next move here
is to capture prof data on a representative workload first and ship only what it
warrants — revisit when there's a reason to measure.

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

Gate cleared (native default since cyrius 6.1.21); sit's AGNOS adoption drove the
C1/C2 transport work plus the 1.6.11 trust-store-verify-fail proof and the 1.6.12
QU-mDNS receive fix — all shipped (see CHANGELOG). **No Batch C item is open** —
further items fill only from real-workload friction sit surfaces, NOT speculatively
pre-baked ([`project_sit_adoption_drives_roadmap`]).

## Backlog — wait for a second consumer (concrete, sandhi-anchored)

Each names the specific code site it would touch and is a deliberate deferral —
sandhi could build it but is holding until a *second* consumer needs the same
pattern (CLAUDE.md). Speculative feature surface with **no** such code anchor
(CONNECT/proxy, cookie jar, JSON merge-patch / RPC batch, ALPN-beyond-h2) has
moved to [`requests/`](requests/README.md) instead.

- **Client connection-pool thread-safety (per-pool mutex)** (`src/http/pool.cyr`)
  — the connection pool is single-threaded. 1.6.9 made the *buffered dispatch*
  path thread-safe (per-call request context) for fresh-connection concurrency,
  but a multi-threaded client sharing a pooled-connection cache would still need a
  per-pool mutex. No consumer needs concurrent pooled dispatch yet; this is the
  natural next thread-safety slot when one does.
- **h2 spec-completeness** (drained from `src/http/h2/` comments at 1.4.3): (a)
  request-body DATA-frame fragmentation when `body_len > peer_max_frame` (rejects
  with `_SANDHI_H2_ERR_BAD_LENGTH` today — `request.cyr`); (b) flow-control
  `WINDOW_UPDATE` enforcement (silently accepted; the peer's default window keeps
  responses bounded — `response.cyr`); (c) peer-SETTINGS `ENABLE_PUSH` /
  `MAX_HEADER_LIST_SIZE` enforcement (not applied to conn state — `conn.cyr`;
  ENABLE_PUSH is moot client-side, MAX_HEADER_LIST_SIZE advisory); (d)
  caller-overridable HEADERS-frame buffer cap (fixed 8 KB — `request.cyr`). Each
  waits for a consumer whose traffic exercises the limit.
- **Per-hop cred-digest recompute on cross-authority redirect-follow**
  (`src/http/client.cyr`) — the 1.3.3 session-cache cred-digest is computed once
  per top-level dispatch (now stored in the 1.6.9 per-call request context), so an
  A→B redirect reuses A's digest for the B handshake. Harmless for the AGNOS
  service-to-service common case; fold the recompute into `_sandhi_http_follow_a`'s
  hop loop when a consumer sets cred-bearing headers AND follows cross-authority
  redirects.
- **Daimon resolver context: auth token + timeouts** (`src/discovery/daimon.cyr`)
  — the daimon resolver ctx reserves a +8 slot (held 0) for a future auth token /
  per-request timeouts; daimon's registry contract defines no auth surface today.
  Wire it when a consumer needs authenticated / timeout-bounded discovery.

## Wait-for-stdlib-prerequisite

- **Portable `signal_ignore` / `sock_send` `MSG_NOSIGNAL`** — the proper home for
  the 1.6.6 SIGPIPE guard, and the one move that also closes the **macOS server
  SIGPIPE guard** below. sandhi installs `SIG_IGN(SIGPIPE)` via a raw
  `rt_sigaction` because `net.cyr`'s `sock_send` is a flagsless `sys_write` (can't
  pass `MSG_NOSIGNAL`, and forking it is forbidden) and stdlib exposes no
  signal-disposition helper (SIGPIPE isn't even in the `Signal` enum). A stdlib
  `signal_ignore(signum)` (portable across Linux/macOS/agnos) **or** a
  `MSG_NOSIGNAL`-aware `sock_send` would let sandhi drop the raw syscall.
  **Re-verified absent on cyrius 6.2.37** (grep `net.cyr` / `syscalls.cyr`).
  Revisit when either lands.
- **macOS server SIGPIPE guard** (`src/server/mod.cyr`) — the 1.6.6 SIGPIPE fix is
  Linux-only (`rt_sigaction`, x86_64 13 / aarch64 134); macOS is a documented
  no-op (the ESYSXLAT whitelist doesn't cover `sigaction`). Wiring it needs the BSD
  `sigaction` ABI (or per-socket `SO_NOSIGNAL`) **and a macOS box to verify**
  (ground-first) — OR the stdlib `signal_ignore` above, which closes it portably in
  one move. Until then a sandhi server on macOS is still SIGPIPE-vulnerable; flagged
  so it isn't silently assumed covered.
- **Fuzzing harness** — the Cyrius toolchain ships no AFL / libFuzzer equivalent
  (re-verified absent on 6.2.37). Revisit when it does.

## Background watches (not slots)

- **`tests/sandhi.tcyr` cap-drift** — if a slot pushes sandhi.tcyr against the
  per-program fixup-cap (architecture/001), carve out another `tests/<name>.tcyr`
  in the same slot (mirroring the 1.2.8 sandhi → rpc split). Don't let it block
  the ship. (At 1.6.9 the suite is 539 assertions.)
- **Consumer coordination docs** ([`issues/`](issues/README.md)) — yantra /
  hoosh+ifran / ark / mela / vidya / daimon (registry + MCP client). sandhi's side
  is shipped; each opens when its consumer schedules adoption. These stay live in
  `issues/` (sandhi-side-complete handoffs, not closed defects) rather than the
  archive.

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
- **Server-only use drags the whole client + h2 + hpack + tls `.bss`** — a
  server-only consumer still links ~400 KB of static h2/hpack/tls tables
  (`CYRIUS_DCE=1` NOPs the code but keeps the `.bss`). This is a **cyrius**
  toolchain lib-packaging / DCE-`.bss`-reclaim concern, not sandhi's: sandhi is one
  composed library, and splitting it into server-only/client-only sub-libs would be
  sandhi inventing packaging the toolchain owns. Closed won't-fix here so it doesn't
  drift back in as a sandhi slot.

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
[CHANGELOG](../../CHANGELOG.md). Live snapshot: [state.md](state.md). Speculative
feature requests: [requests/](requests/README.md). Bugs + coordination:
[issues/](issues/README.md).
