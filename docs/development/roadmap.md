# sandhi — Roadmap

> **Open / remaining work only.** Shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md); the live snapshot in
> [`state.md`](state.md); speculative "wait for a real ask" feature surface in
> [`requests/`](requests/README.md); bugs + consumer-coordination in
> [`issues/`](issues/README.md). When an item ships it moves out of this file
> (into the CHANGELOG), so everything here is still to-do. This file was last
> swept clean of completed work on **2026-10-04** (at 1.10.6: the shipped 1.9.13
> repair-queue narrative, the two sections 1.10.6 emptied, and the sigil
> undefined-symbol note that cyrius 6.6.15 resolved were removed; at 1.10.7 the
> whole "P1 follow-ups from the 1.9.12 sweep" section, which 1.10.7 shipped).

## Context (post-fold)

sandhi folded into Cyrius stdlib at **v5.7.0 / sandhi 1.0.0**
([ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) and is in
**post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is
regenerated, and a small cyrius-side slot refreshes `lib/sandhi.cyr`. The public
surface is no longer frozen (ADR 0005's freeze applied only 0.9.2 → 1.0.0). Pin
is currently **cyrius 6.6.15** (since 1.10.5; the full trail is in `state.md`).

**Pacing.** The items below are *provisional groupings*, not committed dated
slots — each opens when its gate clears (a cyrius primitive lands, profile
evidence justifies it, a second consumer asks, or sit surfaces friction). ONE
item per slot. Per [`project_sit_adoption_drives_roadmap`] scope is surfaced from
real signals, not pre-baked; per the no-silent-scope-outs rule every deferral is
a named entry here (or in [`requests/`](requests/README.md)), not a buried mention.
Everything here is gated (profile evidence, a breaking major, a second consumer, a
cyrius primitive, or a measurement first).

## Batch A — libssl retirement (sandhi 2.0 — breaking)

Native enforces pinning, trust-store and mTLS (since 1.6.0), so the deprecated libssl
backend has no remaining functional role. What's left is the breaking removal itself,
held for the **2.0** major (dropping a public verb and a build flag is not a patch):

- **Retire the libssl opt-out (2.0).** Drop `sandhi_tls_use_libssl()` (public
  verb) + the `-D CYRIUS_TLS_LIBSSL` build flag + the libssl branches in
  `src/tls_policy/*` and `src/http/conn.cyr`. Breaking → the 2.0 major, not a
  patch. Nothing blocks it; this is a scheduling decision. See `project_libssl_retirement_at_2_0` (memory).
- **Drop the libssl smoke CI step at 2.0.** The `-D CYRIUS_TLS_LIBSSL` link proof
  (`ci.yml`) was `continue-on-error` from cyrius 6.3.5 through sandhi 1.10.8, while the
  toolchain refused that config (sigil's transitive crypto reachable but unlinked);
  on cyrius 6.7.5 it links and the step gates again (1.10.9;
  [`issues/archive/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md`](issues/archive/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md)).
  It goes with the backend.
- **libssl session cache — moot, drops at 2.0.** The 1.10.7 investigation found two
  quirks. The first is fixed upstream: since cyrius 6.6.16
  `tls_supports_session_resumption` probes `SSL_CTX_ctrl`, so
  `sandhi_session_cache_supported()` reads 1 on OpenSSL 3 under the libssl backend
  (it read 0, because `SSL_CTX_set_session_cache_mode` is a macro). The second, a
  TLS 1.3 session captured right after `SSL_connect`, before the NewSessionTicket
  arrives, was not re-checked. An end-to-end resumption test on the libssl backend
  was offered by cyrius at 6.6.16 and **declined** at 1.10.9: the cache paths it would
  exercise retire with the backend. Native does not resume.
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

No item is open. Items fill only from real-workload friction sit surfaces, never
speculatively ([`project_sit_adoption_drives_roadmap`]).

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
- **`_sandhi_alpn_advertise_h2` is still a process-wide word** (`src/http/conn.cyr`,
  written by the h2 promotion in `src/http/h2/dispatch.cyr`, read by
  `_sandhi_policy_pre_open_a` and the connection finalize). 1.10.7 moved the TLS
  policy hook into the per-call request context; this flag was left, because a
  collision only changes which ALPN list a concurrent open offers (protocol
  negotiation, not enforcement). Lift it into a `SANDHI_REQCTX_*` slot when a
  consumer drives h2 promotion from several threads.
- **Daimon resolver context: auth token + timeouts** (`src/discovery/daimon.cyr`)
  — the daimon resolver ctx reserves a +8 slot (held 0) for a future auth token /
  per-request timeouts; daimon's registry contract defines no auth surface today.
  Wire it when a consumer needs authenticated / timeout-bounded discovery.

## Background watches (not slots)

- **The unguarded-accumulator / unguarded-allocation class is not exhausted.**
  1.9.10, 1.9.12 and 1.9.13 each fixed instances of *"an allocation result or an
  accumulator was stored without its guard"*, and 1.9.13 found a **third** copy of a
  bound two earlier sweeps had each fixed once. Assume a fourth: grep every
  `size = size * ` / `n = n * ` accumulator fed from the wire, and every
  `store64(..., <alloc-returning-call>(...))` that skips its zero check. Write the
  regression test before believing a finding (both 1.9.13 descriptions that came from
  probes were wrong; see that CHANGELOG entry).
- **CI compiles only smoke + the seven live gates — `programs/` rots silently.** At
  1.10.0 nine probes (`dns-probe`, `tls-probe`, `bootstrap-probe`,
  `cpu-features-probe`, five `dynlib-*`) had not compiled since `src/obs/prof.cyr`
  landed (1.2.5); `tls-probe` was even Result-migrated at 1.9.16 without a compile.
  All nine were repaired at 1.10.0. **Provisional:** a compile-only CI step over
  `programs/*.cyr` so the next include-list drift fails loudly. Ask before adding.
- **Whole-surface reachable-undefined proof (provisional CI gate).** `programs/smoke.cyr`
  references one fn, so its link proves little about the rest of the surface. At
  1.10.0 a generated probe taking `&fn` of **all 842** sandhi fns linked under
  `CYRIUS_DCE=1`, with negative controls (adding sigil's `secureboot_sign_module` /
  `_sigil_random_fill`) refused — so no sandhi fn can reach an undefined stub. Worth
  a CI step if a future stdlib/sigil bump makes the question live again.
- **Test-unit include lists are partial by design, and 6.6.6 now says so.**
  `tests/h2.tcyr` includes `h2/dispatch.cyr` but not `client.cyr`, so it compiles
  with unreachable undefined refs — **23** reported on 6.6.15 (21 on 6.6.6, 8 on
  6.6.2: the newer toolchains report them more completely); `sandhi.tcyr` / `rpc.tcyr`
  carry one each. Not a defect (the refusing linker proves them
  unreachable), but the noise can hide a new warning. Complete the lists only if
  it does — watch the per-program fixup cap (architecture/001) when doing so.
- **`tests/sandhi.tcyr` cap-drift** — if a slot pushes sandhi.tcyr against the
  per-program fixup-cap (architecture/001), carve out another `tests/<name>.tcyr`
  in the same slot (mirroring the 1.2.8 sandhi → rpc split). Don't let it block
  the ship. (At 1.10.7 the suite is 889 assertions.)
- **Fuzz-corpus expansion** — the first `fuzz/*.fcyr` round (7 harnesses over url /
  headers / response+chunked / dns / hpack / sse / json) shipped at **1.8.2** and
  gates in CI (`cyrius fuzz`). Add harnesses opportunistically as new parse surfaces
  land or a consumer's traffic motivates one (candidates: Huffman-decode direct, the
  h2 frame header, WebDriver/Appium/MCP envelope extract). Not a committed slot.
- **Native client vs `openssl s_server -tls1_2` on the Ed25519 fixture — unverified.**
  The 1.10.7 session-cache investigation saw the native client fail that handshake
  (`-3`) with the cache off, against OpenSSL's TLS 1.2 server. Not reproduced or
  root-caused; it may be a native TLS 1.2 + Ed25519 interop gap (cyrius-side) or a
  probe artifact. Reproduce ground-first before filing anything upstream.
- **Consumer coordination docs** ([`issues/`](issues/README.md)) — still open:
  ifran (hoosh's half adopted), ark, vidya (fetch), daimon (registry producer);
  yantra / mela / daimon-MCP-client were adopted and archived 2026-08-23. sandhi's
  side is shipped; each opens when its consumer schedules adoption. These stay live in
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

## Recorded by cyrius 6.6.19 (2026-10-06) — for the next cyrius pin move

⛔ **Needs cyrius >= 6.6.19 — do not bump the pin until 6.6.19 is tagged and out.** Docs-only note from the cyrius
6.6.19 lanes; each item is this repo's to adopt when it pins ≥ 6.6.19. Nothing here gates a cyrius release.

- **`_sandhi_server_pool_inline` can test `CHAN_BLOCKING` instead of `CYRIUS_TARGET_LINUX`.** Since cyrius 6.6.19
  (T1) x86 macOS runs real threads (`THREADS_CONCURRENT` = `CHAN_BLOCKING` = 1 on both Mach-O arches), so x86
  macOS pools can run on real threads; test the capability, not the OS (agnos is still serial).
- **The stop-flag idle path can use `async_await_readable_ms(sfd, SANDHI_SERVER_STOP_POLL_MS)` instead of
  `sleep_ms` on every target.** Since 6.6.19 (A1 / A2) the bounded wait exists on macOS (one BSD `poll`),
  Windows (`WSAPoll`, sockets only) and agnos (a readiness stash in the socket adapter), not only Linux, and the
  legacy `async_await_readable` really waits there — the cooperative server's non-blocking accept → EAGAIN →
  `async_await_readable(sfd)` no longer spins at 100 % CPU on macOS, Windows or agnos.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) (naming +
compose-don't-reimplement thesis), [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
(the shipped fold), and [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md)
(surface freeze, lifted post-1.0.0). Shipped history:
[CHANGELOG](../../CHANGELOG.md). Live snapshot: [state.md](state.md). Speculative
feature requests: [requests/](requests/README.md). Bugs + coordination:
[issues/](issues/README.md).
