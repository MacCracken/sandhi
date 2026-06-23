# 2026-05-10 — Daimon `serve_async` collapse blocked on `sandhi_server_options_max_conns` enforcement (cross-repo coordination)

**Status:** ✅ **Sandhi-side resolved at 1.4.9** — `sandhi_server_run_async`
ships the epoll-cooperative enforcement (approach (2) below): batched
accept bounded by `max_conns`, a handler task per connection over
`lib/async.cyr`, per-handler recv buffers (no-interleave invariant), and a
reset-per-batch arena. 1.4.10 hardened it (dropped the infinite
`async_await_readable`; floored `idle_ms` > 0). **Residual is daimon-side**:
collapse `serve_async`'s duplicated accept loop + smuggling checks onto
`sandhi_server_run_async`. Sandhi has nothing left to wire — kept here as the
canonical daimon-side coordination record until daimon schedules the collapse.
**Severity:** **Low** — no security impact; pure refactor / dedup blocker on daimon's side
**Reporter:** daimon (AGNOS agent orchestrator, v1.2.0+ — work-loop review during the 1.2.2 ship)
**Sandhi version at time of report:** **1.3.3** (bundled at cyrius 5.10.34 as `lib/sandhi.cyr`)
**Affects:** daimon's `serve_async` → `sandhi_server_run_opts` collapse (1.2.x architectural cleanup); no production consumer behaviour
**Blast radius:** daimon-side only — ~60 LOC of duplicated accept-loop + smuggling-check code stays in `src/main.cyr` instead of collapsing into the shared sandhi path

## What's blocked

`sandhi/src/server/mod.cyr` exposes the public hook:

```cyr
fn sandhi_server_options_max_conns(opts, n) { ... }     # setter (public)
fn sandhi_server_options_get_max_conns(opts) { ... }    # getter (public)
```

…but `sandhi_server_run_opts` (the accept loop in the same module,
mirrored in the bundled `lib/sandhi.cyr:11602-11650` at cyrius 5.10.34)
does not gate `sock_accept` on a connection-count check, does not spawn
a worker per-request, and does not return to accept without finishing
the in-flight request. It remains single-flight regardless of the
configured `max_conns` value.

The bundled `lib/sandhi.cyr:11600` carries the comment:

```
# Opts-aware variant. Applies SO_RCVTIMEO on each accepted connection
# to bound slow/idle peers (slowloris guard). max_conns is accepted
# but not honored today — server stays single-threaded until 0.8.0.
```

The "until 0.8.0" comment predates the 0.8.0 scope shift, which
shipped HTTP/2 + client connection pool (not server multi-conn);
sandhi's 0.9.x P0/P1 sweep also focused on single-server hardening.
So the comment is stale but the underlying state is current — the
enforcement hook is still reserved at 1.3.3.

## Why daimon cares

The 1.1.5 daimon roadmap (later rescoped to 1.2.x) planned:

> **Collapse `serve_async` to `sandhi_server_run_opts`** once a sandhi
> patch enforces `sandhi_server_options_max_conns`. The hook is
> already public — only the enforcement path is reserved. When wired,
> daimon's `serve_async` (epoll loop + per-call buf alloc + inline
> smuggling-check duplication) collapses into one
> `sandhi_server_run_opts(...)` call shared with sync.

What collapses:

- ~40 LOC daimon-owned epoll-cooperative accept loop in
  `serve_async` (`src/main.cyr:4040-4080`)
- daimon's per-call `alloc(MAX_REQUEST_SIZE + 1)` in
  `async_handle_client` (sandhi's `_hsv_req_buf` becomes safe to
  share under a multi-conn server because sandhi would own the
  no-interleave invariant)
- daimon's inline duplication of CL+TE / dup-header smuggling checks
  in `async_handle_client` (sandhi's accept loop already does these
  for the sync path)

Net: ~60 LOC drop + elimination of two parallel code paths that
daimon currently has to keep in sync at every sandhi-stack change.

## What sandhi needs to wire

Either approach unblocks daimon equally:

1. **Worker pool inside `sandhi_server_run_opts`** — accept loop hands
   each request off to a worker thread (or fiber), bounded by
   `max_conns`. The single-flight invariant becomes "per-worker, not
   per-server".
2. **Epoll-cooperative variant** — `sandhi_server_run_opts` integrates
   with `lib/async.cyr` directly (parallel to daimon's current
   approach), reading `max_conns` as the concurrency cap. The accept
   loop spawns into the runtime instead of blocking.

The current `_hsv_req_buf` process-global recv buffer is the main
internal invariant either approach has to address. The bundled
sandhi 1.3.3 comment at `lib/sandhi.cyr:11606` already notes "must
outlive any per-request arena, so always allocate from the global
bump" — so per-worker buffers (or per-fiber buffers) would need to
be the new shape.

## Daimon-side workaround

None needed today. The two-path posture (`serve` sync via sandhi
opts + `serve_async` async via daimon-owned epoll) is correct under
the current upstream state. Daimon's 1.2.2 ship added a per-cfd
`SO_RCVTIMEO` on async accepts (mirroring what
`sandhi_server_run_opts` does internally for sync), so the
security-relevant half of the original 1.1.5 plan is shipped
regardless of whether the collapse lands.

## Severity rationale

**Low** because:

1. No security impact — daimon's 1.2.2 closed the async-path
   slowloris exposure independently via its own
   `set_recv_timeout_ms(cfd, SERVE_IDLE_MS)` call after each accept.
2. No correctness impact — both `serve` and `serve_async` work, pass
   213/213 daimon unit tests, and handle the production HTTP API
   surface (24 endpoints) without divergence.
3. Pure code-cleanup blocker — duplicated smuggling-check logic and
   two parallel accept-loop implementations. Maintenance cost, not
   a functional cost.

Bumps to **Medium** if:

- A new bug shows up in one accept loop and not the other (typical
  failure mode when two parallel paths drift).
- Daimon's WebSocket / streaming roadmap (v1.3.0+) introduces
  a third accept-path shape and the upstream gap forces a third
  parallel implementation.

## Tracking

- This file is the canonical cross-repo coordination doc.
- Re-checked at every cyrius pin bump on daimon's side; if upstream
  has wired enforcement, daimon schedules the collapse as a 1.2.x or
  1.3.x small-slot patch (estimated: <100 LOC delete, ~5 LOC add for
  the opts threading).
- Mirrors the daimon-tagged tracker convention sandhi already uses
  (e.g. `2026-04-24-daimon-registry-endpoints.md`).

## Related

- daimon CHANGELOG 1.2.2 § Known issues — records the gap from the
  consumer side + flags the auto-resolve.
- 1.1.4 daimon sandhi-migration audit, daimon
  `docs/audit/2026-04-27-sandhi-migration.md` § Deferred → 1.1.5
  plan (now this file).
