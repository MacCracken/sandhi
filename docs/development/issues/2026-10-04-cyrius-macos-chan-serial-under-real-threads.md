# 2026-10-04 — arm64 macOS starts real threads but keeps the serial channel

**Status:** ✅ **Fixed in cyrius 6.6.16** (see *Resolution* at the end; recorded by cyrius 2026-10-05). Open on sandhi's side only until it adopts `CHAN_BLOCKING` — [`2026-10-05-adopt-cyrius-6616.md`](2026-10-05-adopt-cyrius-6616.md) item 4. Was: open — cyrius-side (`lib/thread_macos.cyr`); sandhi works around it (1.10.7).
**Severity:** **P2** — any producer/consumer built on `chan_*` across threads is broken on arm64 macOS, and
on every other target that still uses the serial ring. No error surfaces: the consumer simply sees an
empty channel.
**Reporter:** sandhi, from its first macOS CI run of a pooled-server row (1.10.7, `macos-14`, reproduced on
ecb).
**Toolchain:** cyrius 6.6.15.

## What happens

`lib/thread_macos.cyr` (6.6.15):

- **`thread_create` starts real threads on arm64 macOS.** `THREADS_CONCURRENT = 1` (v6.5.44, via
  `pthread_create` through `__got[5]`); x86 macOS stays serial (`THREADS_CONCURRENT = 0`).
- **The channel below it is the serial ring on both archs:**
  - no lock;
  - `chan_recv` is `chan_try_recv`, which returns **0 when empty** instead of blocking;
  - `chan_send` returns **-1 when full** instead of waiting.

On arm64 that ring is now shared by real threads. A consumer that does `while (1) { v = chan_recv(ch); if (v == 0) break; ... }`,
the standard worker shape and the one `lib/thread.cyr`'s Linux channel supports, sees 0 at once and
exits. A producer's `chan_send` into a channel with no live consumer fails silently once full, and the
ring's head/tail/count are updated without a lock by several threads.

## Consequence in sandhi

`sandhi_server_run_pooled` and `sandhi_server_run_pooled_tls` spawn `max_conns` workers that each loop on
`chan_recv` and treat 0 as "channel closed". On macOS every worker exited immediately, so the servers
bound, listened and accepted but **never served a request**:
- a complete `GET` to a pooled server on ecb went unanswered until the client's 3 s timeout;
- the same happened with the server in a thread, in a forked child, and with or without a stop flag.

The 1.10.7 macOS CI run caught it through `test_server_request_budget_answers_408`, the first macOS test
that needs a pooled server to answer.

## sandhi's workaround (1.10.7)

`_sandhi_server_pool_inline()` answers 1 on every target but Linux with `THREADS_CONCURRENT == 1`. There
the pooled entry points serve each accepted connection on the accept thread, with the same per-request
contract (budget, refusals, arenas). That is correct but unparallelised, the same stance the stdlib's
serial thread backends take. A target test is used because the stdlib exposes no channel capability.

## Proposed fix (cyrius-side)

Either:

- give arm64 macOS a real channel: a mutex + condition variable (or `__ulock_wait` / `__ulock_wake`)
  around the ring, with `chan_recv` blocking until a value arrives or the channel closes, matching
  `lib/thread.cyr`; or
- export a capability (e.g. `CHAN_BLOCKING`) next to `THREADS_CONCURRENT`, so consumers can choose a
  strategy without testing target names (the v6.5.36 / v6.5.44 rule the stdlib already states for
  threads).

Once a real channel lands, sandhi can key `_sandhi_server_pool_inline` on that capability instead of
`CYRIUS_TARGET_LINUX`, and macOS gets a parallel pool.

## Resolution — cyrius 6.6.16 (recorded by cyrius, 2026-10-05)

⛔ Do not push or tag a sandhi that pins cyrius 6.6.16 until cyrius 6.6.16 is out.

**Resolved in cyrius 6.6.16 (bite thr-1), and both proposals shipped.** cyrius copied this filing as its own
`docs/development/issues/2026-10-04-sandhi-macos-chan-serial-under-real-threads.md` and archives it at the
6.6.16 close.

1. arm64 macOS and Windows have a locked channel whose `chan_recv` blocks until a value arrives (0 once closed
   and empty), and whose `chan_send` blocks while full (-1 once closed). That is the Linux contract. The ring
   keeps the same 56-byte header.
2. Every thread peer exports **`CHAN_BLOCKING`** beside `THREADS_CONCURRENT`: 1 on Linux, arm64 macOS and
   Windows; 0 on x86 macOS, agnos and cx. (Separately, cyrius 6.6.16 also makes `THREADS_CONCURRENT` read 1
   on Windows, where `CreateThread` threads were always real.)

**Also fixed — Linux, before 6.6.16:** the pooled server's handoff channel could DEADLOCK on Linux when
saturated. The Linux channel parked senders and receivers on one futex word with wake-one; once the accept
loop blocked in `chan_send` on a full channel (all `backlog` slots queued), a worker's `chan_recv` could wake
another idle worker instead of the accept thread, which then slept for ever with room in the ring. cyrius
measured it with one producer and three consumers on a cap-1 channel (the producer hung on pi). sandhi floors
`backlog` to `workers` and defaults it to 128, so the window is the saturated case only. 6.6.16 fixes it in
the lib — sandhi needs only the pin. If sandhi has an unexplained "pool stopped accepting under load" report
on Linux, this is a candidate.

What sandhi adopts (`_sandhi_server_pool_inline` keyed on `CHAN_BLOCKING`, then the 1.10.7 macOS row re-run
with the pool really taken) is in [`2026-10-05-adopt-cyrius-6616.md`](2026-10-05-adopt-cyrius-6616.md). Move
this file to `archive/` when that lands.
