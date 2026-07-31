# Serve loops spun a core forever on any persistent accept error

**Filed:** 2026-07-30
**Reporter:** bote 3.2.1
**Affected:** `src/server/mod.cyr` — all five accept sites
**Severity:** High (availability). Not a privilege defect; no data exposure.
**Status:** fixed, `[Unreleased]` (see CHANGELOG)

## What was wrong

Every serve loop was shaped like this, on a **blocking** listen socket:

```
while (1 == 1) { var cr = sock_accept(sfd); if (is_err_result(cr) == 0) { … } }
```

No else branch. On any persistent accept error — EMFILE, ENFILE, EBADF, EINVAL, ENOTSOCK —
that re-issues `accept(2)` immediately, forever: 100% of one core, no backoff, no bound, no
diagnostic.

Under EMFILE it is worse than a plain spin: the pending connection is never dequeued, so the
same connection is re-raced at full speed and the peer is never served. The condition is
self-sustaining — the listen fd stays readable, so nothing in the loop ever blocks.

Measured before and after with `programs/_server_accept_emfile_probe.cyr`:
**1000 ms of CPU burned in a 1000 ms EMFILE window → 0 ms.**

## Why it reached us

Reported by **bote**, whose http / streamable / ws / bridge transports are each a one-line
delegation to `sandhi_server_run` — so all four inherited the defect from one line here. bote
found it while fixing its own hand-rolled copy of the same loop in
`bote/src/transport_unix.cyr` (bote 3.2.1), and its `_unix_accept_action` classifier is the
template this fix generalises.

The realistic trigger is not an attacker — it is ordinary fd exhaustion in a long-running
consumer (audit-chain fds, filesystem tools, outbound client sockets) or a low
`RLIMIT_NOFILE`.

## The five sites

| Function | Loop shape | Was |
|----------|-----------|-----|
| `sandhi_server_run_opts` | blocking (also covers `sandhi_server_run`) | no else branch |
| `sandhi_server_run_pooled` | blocking accept thread → handoff channel | no else branch |
| `sandhi_server_run_tls` | blocking, per-connection handshake | no else branch |
| `sandhi_server_run_pooled_tls` | blocking accept thread → handoff channel | no else branch |
| `sandhi_server_run_async` | non-blocking cooperative drain | **had** an else branch — wrong |

`sandhi_server_run_async` is the one worth reading twice. It folded every errno into "queue
drained". That is right for EAGAIN and wrong for everything else: under EMFILE the pending
connection stays queued, so the listen fd stays readable, so `async_await_readable` returns
instantly and the outer loop spins at 100% CPU exactly like the blocking loops — just one
indirection further out. It looked handled.

## The fix

Three pieces, deliberately split (`src/server/mod.cyr`, "Accept-error policy" block):

- `_sandhi_accept_action(err)` — pure errno → RETRY / BACKOFF / FATAL classifier
- `_sandhi_accept_backoff_next(cur_ms)` — pure delay schedule, 1 ms doubling to 250 ms
- `_sandhi_accept_step(st, err)` — advances caller-owned 16-byte state and **returns** the
  delay; the caller sleeps

The caller doing the sleeping is what makes the 200-step give-up bound unit-testable in
microseconds instead of the ~48 s the real schedule takes.

Classification:

- **Transient → retry now**: EINTR, ECONNABORTED, EPROTO, EAGAIN
- **Resource pressure → capped backoff**: EMFILE, ENFILE, ENOBUFS, ENOMEM
- **Structurally dead listener → return to caller**: EBADF, EINVAL, ENOTSOCK, EOPNOTSUPP
- **Unknown → backoff, never fatal** — a misclassification must not be able to take a working
  server down

Two constraints that shaped it:

1. **EAGAIN must never be slowed.** It is the steady state of the async drain *and* of every
   loop on AGNOS, where `sock_accept` is non-blocking by construction and the server
   poll-loops. Backing off EAGAIN would add latency to every accept on AGNOS.
2. **AGNOS reports both of its error cases as a bare `Err(1)`** (`lib/net.cyr`: fd-isn't-a-
   listener, and conn-table-full). EPERM is unknown to the classifier → backoff → bounded
   give-up, rather than an unbounded spin. This is the unknown-errno rule earning its keep.

Both pooled loops close the handoff channel *before* the listen socket on the way out, so
workers' `chan_recv` returns 0 and they exit instead of parking on a channel nobody will feed.

## Behaviour change

These loops previously never returned once listening. They now return 1 on a structurally dead
listener, and after 200 consecutive resource failures (~48 s once the delay reaches its cap).
That is the point — the alternative is an unbounded spin — but a caller treating
`sandhi_server_run*` as `noreturn` should now check the return value.

## Coverage

- **49 assertions** in `tests/sandhi.tcyr` (`server/accept_policy/*`): every errno in each
  class, the backoff schedule including the 250 ms clamp, streak accounting (RETRY neither
  consumes nor resets the streak), the give-up boundary at exactly 200/201, the null-state
  fail-closed path, and that `sleep_ms` genuinely blocks. Mutation-proven: breaking the
  classifier default, the backoff advance, or the give-up bound each turns the suite red.
- **`programs/_server_accept_emfile_probe.cyr`** (CI-gated) — the unit tests cover the
  classifier and the state machine as pure functions; they cannot cover the **loop wiring**,
  which is the half that actually burned the core. The probe forks a server whose `accept(2)`
  is guaranteed EMFILE (clamped `RLIMIT_NOFILE`, every descriptor but one consumed), parks a
  connection in its backlog, and measures the child's on-CPU nanoseconds over 1 s via
  `/proc/<pid>/schedstat`. Budget 250 ms against a pre-fix 1000 ms. Verified in both
  directions: reverting `sandhi_server_run_opts` to the old shape makes it report 1000 ms and
  fail.

## Downstream

**A fix landing here does not reach consumers.** Consumers include stdlib's vendored
`lib/sandhi.cyr`, so bote's four transports stay affected until a cyrius release re-vendors it
from `dist/sandhi.cyr`. This was filed *by* a consumer — bumping a sandhi pin is not enough.

## Related

- `cyrius/docs/development/issues/2026-07-30-net-cyr-x86-only-socket-syscall-numbers.md` —
  raised in the same report. `lib/net.cyr`'s `sock_accept` issues a bare `SYS_ACCEPT = 43`
  (the x86_64 number, `statfs` on aarch64) with no arch guard, correct there only via the
  backend's ESYSXLAT renumber chain. Out of scope for sandhi — that is a cyrius-repo change.
- bote CHANGELOG 3.2.1 — the originating fix and the `sys_accept4` rationale.
