# sandhi — HTTP client dispatch stashes per-request state in module globals: not thread-safe (blocks concurrent clients)

**Status**: Filed — blocks a downstream consumer from running concurrent HTTP
clients. Not a correctness bug in single-threaded use (the save/restore idiom is
reentrancy-safe); it is a **thread-safety** gap that the code already flags as a
known limitation.
**Date**: 2026-06-23
**From**: thoth (the agentic-coding TUI) — found while designing parallel MCP
tool calls (N concurrent `sandhi_http_post_a` workers over `lib/thread.cyr`).
Reconfirmed against the sandhi bundled in cyrius **6.2.37**.
**Severity**: blocks the feature; degrades safely today because every consumer is
single-threaded. **Acknowledged in-source**: the client-pool header comment
("Single-threaded today. Multi-threaded clients would need a per-pool mutex").
**Affects**: `src/http/conn.cyr`, `src/http/client.cyr` (the `_sandhi_http_dispatch_a`
save/restore site). thoth needs no change once these are per-call.

## Summary

The per-request state that the client dispatch needs during connect/TLS-finalize
is held in **module-level globals**, set on entry to a dispatch and restored on
exit (a save → write → call → restore idiom). That idiom is correct for the
single-threaded *redirect recursion* it was designed for, but it is a **data race
across OS threads**: two concurrent dispatches share one word, so worker B's
write/restore can interleave between worker A's write and A's later read deep in
the connect path.

The globals (declared in `src/http/conn.cyr`):

- **`_sandhi_allow_0rtt`** (`conn.cyr:83`) — written per dispatch, read in connect
  to gate 0-RTT eligibility.
- **`_sandhi_cred_digest`** (`conn.cyr:94`) — **the dangerous one**: a real
  per-request, credential-derived value (from Authorization/Cookie). Written per
  dispatch, read at the TLS session-cache **lookup** (`conn.cyr:454`) and **store**
  (`conn.cyr:492`). Under concurrency, worker A can perform its TLS session
  lookup/store under worker B's credential digest — cross-wiring resumption state
  between two differently-credentialed requests.
- **`_sandhi_tls_policy_pending`** (`conn.cyr:118`) — written per dispatch, read to
  decide pool-bypass and to enforce SPKI pinning / mTLS. A racing worker could see
  another's policy pointer (or 0, skipping its own pin enforcement).
- **`_sandhi_conn_last_err`** (`conn.cyr:251`, read via the accessor at `conn.cyr:261`)
  — written all over the connect path (`conn.cyr:414…618`) and read back to classify
  an open failure (TIMEOUT vs TLS vs CONNECT). Concurrent opens misclassify each
  other's errors.

What is **already correctly per-call** (so this is the *only* blocker): the recv
buffer, request bytes, conn struct, and TLS hook ctx are all allocated from the
caller's arena via the `_a` variants; `sock_send`/`sock_recv` use caller buffers on
a per-conn fd. So once these four globals become per-call, concurrent
`sandhi_http_post_a` with distinct arenas + fresh connections is structurally safe.

## Reproduction (the intended downstream use)

thoth wants to run a round of MCP tool calls concurrently — N workers, each:
`arena_allocator(CAP)` → `daimon_invoke_a(a, req_buf, …)` → `sandhi_http_post_a(a, …)`.
Even with per-call arenas + per-call request buffers + a fresh connection per call
(opts==0), the workers race the four globals above. For the HTTPS path this steers
0-RTT eligibility, the TLS session-cache key (derived from *another* thread's
credentials), SPKI/mTLS enforcement, and connect-error classification.

## Asked of sandhi

Lift this per-request state out of module globals into the **per-call dispatch
context** (the dispatch already threads an Allocator and per-call structs — these
four values can ride the same per-call struct / be passed as parameters to the
connect path instead of stashed in globals). The values are already computed
per-call; they just need a per-call *home*. The `_sandhi_conn_last_err` classifier
can return its error code through the call chain (or a per-call out-param) rather
than a shared global. No API change is required for existing single-threaded
callers if the bare wrappers keep their current behavior.

Once done, a multi-threaded client (thoth's parallel tool calls) lights up with no
further sandhi change. Filed proactively per thoth's "port the floor; never fork
the spine" posture — thoth will not work around this in its own tree.
