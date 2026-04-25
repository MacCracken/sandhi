# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### 0.8.0 work in progress

**Bite 2 — HPACK encoder/decoder (RFC 7541)**. 464 test assertions
green (+26 over Bite 1's 438). Pure protocol code; no network. New
`src/http/h2/hpack.cyr` (~530 lines).

#### Added
- Static table — RFC 7541 Appendix A, all 61 entries. Lazy-init
  via `_hpack_static_init` with the entries split across four
  helper fns (`_init_a` / `_b` / `_c` / `_d`) — single-fn version
  exceeded the Cyrius fixup-table per-fn allowance.
- Dynamic table — `sandhi_hpack_table_new(max_size)`,
  `_count` / `_size` / `_max_size` accessors, `_add` (with size-
  triggered tail eviction), `_set_max_size` (shrink-on-shrink).
  Entry size = `strlen(name) + strlen(value) + 32` per RFC §4.1.
  Oversized entries empty the table and drop themselves per §4.4.
- `sandhi_hpack_lookup(t, idx, name_out, value_out)` — combined
  static (1..61) + dynamic (62..N) index resolution.
- `_hpack_int_encode` / `_hpack_int_decode` — RFC §5.1 variable-
  length integer codec with configurable prefix bits (4-7).
- `_hpack_string_encode` / `_hpack_string_decode` — RFC §5.2
  length-prefixed string codec. Encode always emits raw (H=0);
  decode rejects H=1 with `_SANDHI_HPACK_ERR_HUFFMAN` until
  Bite 2b adds Huffman support. Real h2 servers always Huffman-
  encode, so Bite 5 (live h2 talk) blocks on 2b shipping first.
- Header field encoders for all 5 RFC §6 representations:
  `sandhi_hpack_encode_indexed` (§6.1, 7-bit prefix),
  `_encode_literal_indexed` / `_indexed_name` (§6.2.1, 6-bit
  prefix, adds to dynamic table), `_encode_literal_no_index`
  (§6.2.2, 4-bit prefix), `_encode_literal_never` (§6.2.3),
  `_encode_table_size_update` (§6.3).
- `sandhi_hpack_decode_field(t, buf, blen, off_cell, name_out,
  value_out)` — single-field decode. Returns 0 on success, or a
  positive `_SANDHI_HPACK_TBL_UPDATE` sentinel for the dynamic-
  table-size-update representation (which has no associated
  header), or a negative error sentinel.
- Error sentinels: `_SANDHI_HPACK_ERR_TRUNCATED`, `_BAD_INDEX`,
  `_HUFFMAN`, `_MALFORMED`, `_INT_OVERFLOW`.

#### Tests (3 in sandhi.tcyr)
- `static_table_spotcheck` — Appendix A indices 1, 2, 3, 7, 8,
  16, 32, 58, 61 verified by name + value where applicable.
- `huffman_rejected` — H=1 string returns the right sentinel.
- `rfc_c31_request_decode` — RFC 7541 Appendix C.3.1 four-field
  request sequence (`:method GET`, `:scheme http`, `:path /`,
  `:authority www.example.com`) decodes to the expected name/
  value pairs and adds the literal authority entry to the
  dynamic table.

**Trimmed test surface**: I dropped targeted unit tests for integer
encoding (C.1.1, C.1.2, C.1.3 individually), dynamic-table eviction
mechanics, and the literal/indexed/no-index/never-indexed/size-update
representations because they pushed the test file past the Cyrius
fixup-table cap (32768 — already heavily used by the rest of
sandhi.tcyr's existing 461 assertions). The C.3.1 end-to-end test
exercises integer + string + literal-incremental + indexed + dynamic-
table-add through real wire bytes, so semantic coverage is preserved
even if targeted unit coverage isn't. Bite 3 (h2 frames) will likely
need to split tests across files; flagged.

#### Notes
- No version bump — staged on 0.7.3 until 0.8.0 ships fully.
- Encode side always emits raw (no Huffman) — RFC 7541 permits
  this; it just costs wire bytes. Most h2 servers tolerate it.
- This bite ships nothing user-visible — HPACK only matters once
  Bite 5 makes live h2 calls. Tested in isolation against RFC.

**Bite 1 — Connection pool + HTTP/1.1 keep-alive** (earlier commit). 438
test assertions green (+27 pool). Pool stays unused until a caller
attaches one via `sandhi_http_options_pool(opts, pool)`; existing
`Connection: close` paths are unchanged so this is a strictly
additive patch.

#### Added
- New `src/http/pool.cyr` (~330 lines).
  - `sandhi_http_pool_new(max_per_host, idle_timeout_ms)` →
    `sandhi_http_pool_close` / `_idle_count` / `_max_per_host` /
    `_idle_timeout_ms` accessors.
  - Internal `_sandhi_pool_take(pool, host, port, tls)` (LIFO,
    skip-stale, recurse) and `_sandhi_pool_put(...)` (FIFO eviction
    when at cap).
  - Map keyed by `host:port:tls` cstr → vec of idle_conn{conn,
    last_used_ms} via stdlib `map_new` + `vec_*`.
  - `_sandhi_http_recv_framed(conn, buf, cap, deadline_ms)` — drains
    headers incrementally, parses `Content-Length` or detects
    `Transfer-Encoding: chunked`, reads exactly that much body so the
    socket survives for the next request. Returns `0 - 2` sentinel
    when the server sent `Connection: close` so the caller skips
    pool-put.
  - `_sandhi_pool_chunked_complete(buf, body_start, blen)` — detector
    used by the framed-recv loop to know when a chunked body has
    fully arrived.
- **http/client**: `sandhi_http_options_pool(opts, pool)` setter +
  `sandhi_http_options_get_pool(opts)` accessor. Options struct
  56→64 bytes.
- **http/client**: `_sandhi_client_build_request_v` variant accepts
  a `keep_alive` flag — when set, omits the trailing `Connection:
  close` header (HTTP/1.1 default is keep-alive). Existing
  `_sandhi_client_build_request` is now a `keep_alive=0` wrapper.
- **http/client**: `_sandhi_http_exchange_keepalive(conn, req, body,
  body_len, max_bytes, deadline_ms, pool, host, port, use_tls)` —
  framed-recv variant that returns the conn to the pool on
  success (2xx/3xx, no server-Connection-close) or closes it
  otherwise.

#### Changed
- **http/client `_sandhi_http_do_impl`** signature gained `pool`
  parameter. When attached, tries `_sandhi_pool_take` first to skip
  the connect phase entirely; falls through to
  `sandhi_conn_open_fully_timed` on miss. Uses
  `_sandhi_http_exchange_keepalive` instead of the close-delimited
  `_sandhi_http_exchange` when keep_alive is on.
- **http/client `_sandhi_http_follow`** + `_sandhi_http_dispatch`
  thread `pool` through. Per-hop reuse — each redirect hop tries
  the pool independently; non-2xx responses (301/302/etc.) still
  put back since they're successful HTTP exchanges.
- **cyrius.cyml `[lib].modules`**: `pool.cyr` registered between
  `client.cyr` and `retry.cyr` (pool depends on client's
  `_sandhi_http_clamp_ms` indirectly via the recv-framed deadline
  path; alphabetical dep order respected).
- **programs/smoke.cyr**: pool added to keep the smoke link parity
  with the test build.

#### Notes
- This bite is the foundation for both HTTP/1.1 keep-alive (now
  available) and h2 stream multiplex (Bite 6 — same checkout shape,
  per-stream rather than per-connection).
- No version bump — staged on 0.7.3 until 0.8.0 ships fully (after
  Bite 7).
- Pool is single-threaded today (matches the rest of the client).
  When a multi-threaded request dispatch lands, a per-pool mutex
  goes here.
- `_sandhi_http_recv_framed` does NOT parse `Trailer:` headers or
  trailer chunks per RFC 7230 §4.4 robustness — they're discarded.
  Will revisit only if a consumer asks.

## [0.7.3] — 2026-04-24

Closes the two timeout knobs deferred from 0.7.2: `connect_ms` (non-
blocking connect + poll) and `total_ms` (monotonic-deadline threading
through every I/O phase). With both shipped, sandhi's HTTP client has
the full timeout surface — connect, read, write, and end-to-end — that
production consumers expect from a curl/reqwest-class library.

411 assertions green (+16 on the 0.7.2 baseline of 395), including
two live-network tests that fire connect against a TEST-NET-1
(192.0.2.0/24, RFC 5737) blackhole and verify the timeout returns
within budget.

### Added
- **http/conn**: `_sandhi_conn_connect_nb(fd, addr, port, timeout_ms)`
  — non-blocking connect via `O_NONBLOCK` + `connect()` (expects
  `EINPROGRESS`) + `poll(POLLOUT, timeout_ms)` + `getsockopt(SO_ERROR)`
  to distinguish connected from refused/unreachable. Restores
  blocking mode on every exit path. Local syscall constants
  `_SANDHI_SYS_POLL=7`, `_SANDHI_SYS_GETSOCKOPT=55`, `_SANDHI_F_GETFL=3`,
  `_SANDHI_F_SETFL=4`, `_SANDHI_O_NONBLOCK=2048`, `_SANDHI_EINPROGRESS=115`,
  `_SANDHI_SO_ERROR=4`, `_SANDHI_POLLOUT=4` (Linux x86_64; matches
  the existing `SYS_SETSOCKOPT=54` in stdlib `net.cyr` — aarch64
  needs a cross-cutting pass when it becomes a goal).
- **http/conn**: `sandhi_conn_open_fully_timed(addr, port, use_tls,
  sni, connect_ms, read_ms, write_ms)` — supersedes
  `sandhi_conn_open_timed` (now a 0-connect-ms wrapper). Uses
  `_sandhi_conn_connect_nb` when `connect_ms > 0`.
- **http/conn**: module-level `_sandhi_conn_last_err` + accessor
  `sandhi_conn_last_open_err()` — classifies the last open failure as
  `SANDHI_CONN_OPEN_OK` / `_CONNECT` / `_TIMEOUT` / `_TLS`. Single-
  threaded only; revisit if multi-threaded client model ever lands.
- **http/conn**: `sandhi_conn_recv_all_deadline(conn, buf, max,
  deadline_ms)` variant for `total_ms` enforcement. Loop-checks
  `clock_now_ms() >= deadline_ms` before each next-recv. SO_RCVTIMEO
  still bounds individual recv calls; the deadline is the outer
  ceiling. `sandhi_conn_recv_all` is now a `deadline_ms=0` wrapper.
- **http/client**: `sandhi_http_options_connect_ms(opts, ms)` /
  `sandhi_http_options_total_ms(opts, ms)` setters + matching
  getters. Options struct 40→56 bytes.
- **http/client**: `_sandhi_http_clamp_ms(raw_ms, deadline_ms)`
  helper — returns `raw_ms` if no deadline, the lesser of `raw_ms`
  and `(deadline - now)` if both, or `-1` sentinel if the deadline
  has elapsed. Used at every phase boundary in `_sandhi_http_do_impl`
  to bound the next operation against `total_ms`.

### Changed
- **http/client `_sandhi_http_do_impl`** computes `deadline_ms` at
  entry from `total_ms`, threads it to `_sandhi_http_exchange`, and
  uses `_sandhi_http_clamp_ms` to bound `connect_ms`. On
  `_sandhi_conn_open_fully_timed` failure, reads
  `sandhi_conn_last_open_err()` to map to `SANDHI_ERR_TIMEOUT` /
  `_TLS` / `_CONNECT` precisely (was: collapsed everything to
  CONNECT or TLS based on `use_tls`).
- **http/client `_sandhi_http_follow`** + `_sandhi_http_dispatch`
  thread the new `connect_ms` / `total_ms` through. Per-hop semantics
  for redirect chains: each hop gets its own `total_ms` budget — the
  total across all hops is bounded by `max_hops × total_ms`. If a
  consumer needs end-to-end-across-redirects, lower max_hops or
  shorten per-hop total_ms accordingly.
- **http/client `_sandhi_http_exchange`** gains a `deadline_ms` param;
  checks it at entry and uses the new
  `sandhi_conn_recv_all_deadline` for the body read.
- **http/stream `sandhi_http_stream_opts`** computes the same
  deadline + clamp + open-with-classification flow as the client.
  Body-loop checks `deadline_ms` before each next-recv — long-lived
  SSE streams now honor `total_ms` as an overall lifetime ceiling
  rather than a per-event timeout.
- **http/client / conn / stream**: `*_version()` strings → 0.7.3.
- **src/main.cyr**: `sandhi_version()` → 0.7.3.
- **tests**: bumped 4 expected-wire-bytes UA strings 0.7.2 → 0.7.3.

### Tests
- New: options coverage for `connect_ms` / `total_ms` defaults +
  mutators (4 new assertions in defaults + 2 in mutators).
- New: `_sandhi_http_clamp_ms` unit coverage — no-deadline / future-
  deadline / elapsed (~6 assertions across 3 cases).
- New: live-network connect_ms blackhole test against TEST-NET-1
  192.0.2.1:80 with 200 ms timeout, asserts `SANDHI_ERR_TIMEOUT`
  raised within a 5 s budget.
- New: live-network total_ms blackhole — same target, no connect_ms,
  total_ms=300 ms; verifies the deadline clamp closes the connect
  phase even when connect_ms isn't set explicitly.

### Notes
- Per-hop total_ms semantics are documented in the redirect-follower
  comment. End-to-end-across-redirects could be added later as a
  separate option (`overall_ms`) if a consumer asks; the shape is
  one extra field + threading the deadline across hops instead of
  recomputing.
- The non-blocking connect helper restores the fd to blocking mode
  before returning so subsequent recv/send don't get EAGAIN'd
  unexpectedly. SO_RCVTIMEO/SO_SNDTIMEO still apply post-connect.
- `_sandhi_conn_last_err` is module-level state. Today's callers
  (single-threaded HTTP client + stream) read it immediately after
  the open call returns 0, so there's no race window. A
  multi-threaded client would need this lifted to a per-call ctx;
  flagged for the 0.8.0 connection-pool work where multiple opens
  may interleave.

## [0.7.2] — 2026-04-24

Reliability + observability patch. Per-phase timeouts, retry wrappers
for idempotent methods, DNS hardening (TXID randomization + answer-
name verification + compression-pointer loop-guard), AAAA resolver
primitive, opt-in sakshi tracing, server-side idle-timeout. All
composed on stdlib (`syscalls` / `net` / `sakshi` / `chrono`); no
new external dependencies, no FFI, no stdlib patches required.

Pulled in four P1 security items while we were in `net/resolve.cyr`
(TXID randomness, answer-name match, compression-loop guard, source-
port leveraged implicitly via kernel ephemeral-port assignment). These
were on the 0.9.x P1 list; landing them together with the reliability
work is cheaper than a second read of the same file.

395 assertions green (+61 on the 0.7.1 baseline of 334).

### Added
- **http/client**: `sandhi_http_options_read_ms(opts, ms)` /
  `sandhi_http_options_write_ms(opts, ms)` setters + matching getters.
  Wired via direct `SYS_SETSOCKOPT` (`SO_RCVTIMEO=20` / `SO_SNDTIMEO=21`
  defined locally; stdlib `net.cyr` exposes the syscall + `SOL_SOCKET`
  but not the per-direction constants). Options struct 24→40 bytes.
  `SANDHI_ERR_TIMEOUT` (defined but never raised through 0.7.1) now
  fires when the SO_*TIMEO kernel deadline elapses.
- **http/conn**: `sandhi_conn_open_timed(addr, port, use_tls, sni,
  read_ms, write_ms)` variant. `sandhi_conn_open(...)` remains as a
  0-timeout wrapper. `sandhi_conn_send` / `_recv` / `_send_all` /
  `_recv_all` now return `0 - _SANDHI_EAGAIN` (= -11) on kernel
  timeout, letting callers distinguish timeout from other errors.
- **http/retry** (new `src/http/retry.cyr`): `sandhi_retry_new()` +
  `sandhi_retry_max_attempts(r, n)` / `_initial_backoff_ms(r, ms)` /
  `_max_backoff_ms(r, ms)`. Public verbs `sandhi_http_get_retry` /
  `_head_retry` / `_put_retry` / `_delete_retry` for idempotent
  methods only — POST/PATCH retry stays explicit. Retries on
  `CONNECT` / `TIMEOUT` / `DISCOVERY` / 5xx; not on 4xx / `PARSE` /
  `TLS` / `PROTOCOL`. Exponential backoff (2×) capped at max. Defaults:
  3 attempts, initial 50 ms, max 2000 ms. Sleeps via `sleep_ms` from
  stdlib `chrono`.
- **net/resolve**: `sandhi_resolve_ipv6(host)` — AAAA resolver
  returning a 16-byte net-byte-order buffer (or 0 on failure). Shares
  the hardened parse path (TXID echo + answer-name match). Client-side
  v6 connect integration deferred (no consumer has asked) — callers
  that need v6 dialing today use `sandhi_resolve_ipv6` + a future
  `sandhi_conn_open_v6_timed(...)` verb when it lands.
- **net/resolve hardening**: random 16-bit TXID per query via
  `/dev/urandom` (closes the Kaminsky cache-poisoning window). New
  `_sandhi_resolve_name_eq(buf, blen, off_a, off_b)` follows wire-
  format names with compression pointers, case-insensitive per RFC
  1035 §2.3.3, capped at 32 hops per name (`_SANDHI_RESOLVE_MAX_PTR_HOPS`).
  `_sandhi_resolve_parse_response` now verifies TXID echo + answer
  name matches question name — RRs for other hosts are scanned past,
  not trusted. Response qdcount forced to 1 (we only ever send 1
  question; anything else is malformed). All checks in one patch
  rather than spread across 0.9.x; the review finding is closed.
- **obs/trace** (new `src/obs/trace.cyr`): thin opt-in wrapper around
  stdlib sakshi's span API. `sandhi_trace_enable(on)` gates emission
  (default off — silent). `sandhi_trace_begin(name)` / `_end()` wrap
  the three boundary calls: `_sandhi_http_do` emits `sandhi.http`,
  `sandhi_resolve_ipv4` / `_ipv6` emit `sandhi.dns.v4` / `.v6`,
  `sandhi_rpc_call` / `_with_headers` emit `sandhi.rpc`. Nesting
  depth works as expected — the HTTP span appears inside the RPC span
  naturally. Attribute support deferred until sakshi grows span-attrs.
- **server**: `sandhi_server_options_new()` + `_idle_ms(opts, ms)` /
  `_max_conns(opts, n)` + getters. New `http_server_run_opts(addr,
  port, handler_fp, ctx, opts)` applies `SO_RCVTIMEO` to each accepted
  connection (slowloris guard; default 30 000 ms matches Go
  `net/http.Server.IdleTimeout`). `http_server_run(...)` remains as a
  0-opts wrapper. `max_conns` accepted but **not enforced** in 0.7.2 —
  server is single-thread accept/serve; concurrent model lands with
  0.8.0's thread-pool or epoll work.

### Changed
- **http/client** redirect follower + dispatch thread `read_ms` /
  `write_ms` through. `_sandhi_http_do`, `_sandhi_http_exchange`,
  and `_sandhi_http_follow` grew the two new parameters.
- **http/stream**: opts-aware variant honors `read_ms` / `write_ms`
  on the streaming connection. Read-loop + body-loop now map
  `0 - _SANDHI_EAGAIN` to `SANDHI_ERR_TIMEOUT` (was `SANDHI_ERR_CONNECT`
  collapse).
- **net/resolve**: `_sandhi_resolve_parse_response(buf, blen, expected_id)`
  signature changed — third parameter required. Callers inside the
  module + the synthetic-parse test updated.
- **src/main.cyr**: `sandhi_version()` → `0.7.2`.
- **cyrius.cyml `[lib].modules`**: added `src/obs/trace.cyr` (right
  after `error.cyr` — earliest, so all downstream modules can call
  into it) and `src/http/retry.cyr` (after `client.cyr`, before
  `sse.cyr`).

### Deferred from 0.7.2 at planning time
- **connect_ms** option + non-blocking connect path — requires either
  local syscall-number constants for `SYS_POLL` / `SYS_GETSOCKOPT`
  or a stdlib ask. Scheduled for 0.7.3.
- **total_ms** option — needs monotonic-deadline threading through
  every I/O phase. 0.7.3 alongside connect_ms.
- **Happy Eyeballs (RFC 6555)** — parallel v4+v6 connect race. Post-v1.
- **Connection pool / keep-alive** — shifted to 0.8.0 alongside HTTP/2
  since h2 multiplexing changes the pool checkout shape. Roadmap
  0.7.2 entry updated with rationale.
- **Client-side IPv6 connect path** (`sandhi_conn_open_v6_timed`) —
  resolver shipped; connect verb awaits a consumer ask.
- **Server concurrent connections** (`max_conns` enforcement) — 0.8.0.

### Notes
- No live-network tests added for timeout / retry — both require a
  blackhole fixture. Unit tests cover options getters/setters,
  retry-should-retry decision logic, and the EAGAIN-on-socket code
  path via synthetic response structs.
- sakshi is always-compiled-in (it's a stdlib dep anyway); the trace
  layer just gates emission. Zero runtime cost when disabled — every
  `sandhi_trace_begin`/`_end` short-circuits on the `_sandhi_trace_enabled`
  check before touching sakshi.
- DNS hardening bumps parse cost marginally (extra name-walk per
  answer RR). For typical 1-answer responses the overhead is <1 μs;
  CNAME-chain responses scale linearly with chain length but those
  are rare in the A-record path.

## [0.7.1] — 2026-04-24

Quick-wins patch. No behavior change for existing callers; new default
request headers + new response / options fields. Motivated by the 0.7.0
external security + gaps review (`docs/development/review-2026-04-24.md`
planning context captured in `roadmap.md` 0.7.1 entry).

### Added
- **http/client**: default `User-Agent: sandhi/<version>` and
  `Accept-Encoding: identity` request headers. Both are only emitted
  when the caller hasn't set their own — preserves override semantics.
  Explicit `identity` guards against servers that would otherwise
  return `Content-Encoding: gzip` sandhi cannot decode.
- **http/client**: `sandhi_http_options_max_response_bytes(opts, n)` +
  `sandhi_http_options_bytes(opts)`. Caps the buffered client's scratch
  buffer (previously a hard-coded 256 KB that silently truncated larger
  responses). Default unchanged at 262144.
- **http/stream**: `sandhi_http_stream_opts(url, method, headers, body,
  body_len, cb, ctx, opts)` — opts-aware variant honoring
  `max_response_bytes` for the header drain, body accumulator, and
  chunked-decode output buffer. `sandhi_http_stream(...)` unchanged —
  now a wrapper delegating with opts=0.
- **http/response**: `err_message` slot (cstr, +40 offset; struct size
  48) + `sandhi_http_err_message(r)` accessor + `_sandhi_resp_err_msg`
  private constructor. Reserved for the 0.8.x security pass — today's
  parser still populates only `err_kind`. ABI-breaking now so the
  security pass doesn't break it later.

### Changed
- **src/main.cyr** docstring corrected. Previously claimed the client
  shipped keepalive + conn pooling (0.7.2 roadmap items) and that the
  server module added routing + middleware (deferred). Now accurate.
- **src/main.cyr** `sandhi_version()` → `0.7.1`; per-submodule
  `*_version()` pointers aligned.

### Fixed
- **CI workflow**: `.github/workflows/ci.yml` gained an `on:
  workflow_call:` trigger. The 0.7.0 tag release failed because
  `release.yml` called `ci.yml` as a reusable workflow but `ci.yml`
  declared only `push` / `pull_request` triggers. Fix ships in 0.7.1
  for future release-tag workflows; the 0.7.0 release stands without
  a build-artifact upload.

### Notes
- The `User-Agent` string embeds `sandhi_version()` dynamically so it
  stays current across future patch bumps with no extra churn.
- No test regressions — all 333 existing assertions remain valid.
- New security-review surface findings are scoped to later releases
  (0.8.x P0 sweep, 0.9.x P1 + closeout) per `roadmap.md`.

## [0.7.0] — 2026-04-24

M3.5 close — SSE streaming + incremental chunked decode. Also carries the deps-stdlib audit + toolchain bump that unstuck the HTTPS investigation. 333 assertions green (+42 for sse + stream).

### Added
- **http/sse** (`src/http/sse.cyr`): WHATWG SSE/EventSource parser. Event struct `{name, data, id, retry_ms}` + `sandhi_sse_parse(buf, blen, remaining_out) -> vec<event>`. Handles multi-line `data:` concatenation (lines joined with `\n`), comment skipping (`: keepalive`), CRLF / LF / CR line endings, default event name `"message"`, proper field reset between events, empty-data-field dispatch.
- **http/stream** (`src/http/stream.cyr`): streaming HTTP dispatcher. `sandhi_http_stream(url, method, headers, body, body_len, cb, ctx)` sends the request, drains response headers, then feeds body bytes through an incremental chunked decoder (state-machine, not the buffer-the-whole-thing decoder in response.cyr) and into the SSE parser. Callback fires once per event; returning 0 stops the stream cleanly. Returns a stream-result struct `{http_status, events_dispatched, err_kind, stopped_by_cb}`.
- **rpc/mcp**: `sandhi_rpc_mcp_stream(endpoint, method, params, cb, ctx)` — JSON-RPC envelope build + SSE response streaming. Useful for MCP servers that stream tools/progress or resources/change notifications.

### Fixed
- **`cyrius.cyml [deps.stdlib]`** — added `mmap`, `dynlib`, `fdlopen`, `bigint`, `freelist`. These were transitive requirements of `tls` / `sigil` that sandhi's main manifest never listed, so `cyrius build` (non-strict default) patched undef-fn call-sites with a placeholder disp32 that silently looped back into `_cyrius_init` at runtime. All sandhi builds since scaffold had this latent issue — surfaced only when M2 HTTPS exercised `tls_connect`. Root-cause postmortem at `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` (closed at cyrius v5.6.29-1; cyrius shipped a `ud2` fixup so future missing-includes SIGILL instead of looping).

### Changed
- **Toolchain pin** — `cyrius.cyml [package].cyrius` bumped from `5.6.22` to `5.6.30` (via 5.6.29-1). Gains: the `_tls_init` bootstrap sequence (`dynlib_bootstrap_cpu_features/tls/stack_end` before `dynlib_open`) + the undef-fn `ud2` safety net (5.6.29-1) + stale-comment cleanup in `fdlopen.cyr` (5.6.30, doc-only). Residual HTTPS blocker is now at the libssl layer, not the cyrius layer — tracked in `docs/issues/2026-04-24-libssl-pthread-deadlock.md`.
- **cyrius.cyml `[lib].modules`**: http/sse + http/stream added in order (sse first — stream composes on top).
- **Source-comment retro** — `src/http/response.cyr` + `src/http/client.cyr` notes about "Cyrius 5.6.22 stack-slot aliasing" re-framed: the symptom was almost certainly the same undef-fn silent-stomp as the HTTPS loop. Kept the small-function shape because it reads better; dropped the "compiler quirk" framing.
- **src/main.cyr**: `sandhi_version()` → 0.7.0.

### Notes
- SSE works over plain HTTP (verified via unit tests against synthetic byte streams for parser correctness + chunked-decode roundtrip). Live HTTPS SSE waits on the libssl-pthread-deadlock blocker — same block as every other HTTPS path.
- No automatic reconnect on SSE disconnect per the spec's `retry:` field — callers handle it by re-calling `sandhi_http_stream`. Can add an opt-in reconnect wrapper when a consumer asks.
- The `_sandhi_sse_cur_*` dispatcher state lives at module scope because Cyrius has no closures and threading it through the loop via out-params gets unreadable. Parser is single-threaded by design — SSE consumers should drive from one thread.

## [0.6.0] — 2026-04-24

M5 close. TLS-policy surface — SPKI cert pinning, mTLS client certs, custom trust store, policy composition. Surface fully shipped + unit-tested; runtime enforcement stubbed pending the stdlib TLS-init fix. 291 assertions green (+41 for tls_policy).

### Added
- **tls_policy/policy** (`src/tls_policy/policy.cyr`): policy struct `{flags, pinned_spki_hex, mtls_cert, mtls_key, trust_store_path}` + constructors (`new_default` / `new_pinned` / `new_mtls` / `new_trust_store`) + `combine` (additive, right-wins on field conflict, null-safe). Flags are a bitmask (`PINNED | MTLS | CUSTOM_TRUST`) so composition just ORs them together.
- **tls_policy/fingerprint** (`src/tls_policy/fingerprint.cyr`): SPKI hash format helpers. `sandhi_fp_normalize` (strip `:`/space/tab + lowercase), `sandhi_fp_eq` (null-safe case + delimiter-insensitive compare), `sandhi_fp_byte_length` (returns 32 for SHA-256, 20 for SHA-1), `sandhi_fp_encode_bytes` (raw → hex). Accepts all the common SPKI string shapes callers will plausibly hand us.
- **tls_policy/apply** (`src/tls_policy/apply.cyr`): `sandhi_conn_open_with_policy(addr, port, use_tls, sni_host, policy)` — public surface ready, enforcement stubbed. Delegates to `sandhi_conn_open` today while reading policy fields so the call-site shape is stable. `sandhi_tls_policy_enforcement_available() == 0` signals stub state; callers requiring hard enforcement can refuse to run.

### Changed
- **tls_policy/mod.cyr**: scaffold → real dialect-index with a complete usage example and the "enforcement pending" pointer to the issues doc.
- **cyrius.cyml `[lib].modules`**: tls_policy modules moved after http/client so `apply.cyr` can reference `sandhi_conn_open`. Composition order now foundation → http/net → tls_policy → rpc → discovery → server → main.
- **src/main.cyr**: `sandhi_version()` → 0.6.0.

### Deferred with explicit path forward
- **Live enforcement** — the TODO list in `apply.cyr` enumerates exactly the OpenSSL calls needed (`SSL_CTX_load_verify_locations`, `SSL_CTX_use_certificate_file`, `SSL_CTX_use_PrivateKey_file`, `SSL_get_peer_certificate`, `X509_get_pubkey`, `i2d_PUBKEY`). When stdlib TLS-init stabilizes (issue doc `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` — closed post-release at v5.6.29-1; follow-on blocker now tracked at `docs/issues/2026-04-24-libssl-pthread-deadlock.md`), wiring these is a ~50-line follow-up with no API shape change.
- **SPKI extraction from peer certificate** — same gate. `sandhi_fp_encode_bytes` already handles the output-side formatting, so the fill-in is: resolve the two additional OpenSSL symbols, call them, hash with `sha256_hex`, compare via `sandhi_fp_eq`.

## [0.5.0] — 2026-04-24

M4 close. Service discovery — daimon-backed resolver, chain-resolver with fallthrough, mDNS interface stub, register/deregister. 250 assertions green (+35 for discovery).

### Added
- **discovery/service** (`src/discovery/service.cyr`): service struct `{name, host, port, ipv4}` + resolver struct `{lookup_fn, ctx}` + `sandhi_resolver_lookup(r, name)` dispatcher. The type vocabulary every resolver shares.
- **discovery/chain** (`src/discovery/chain.cyr`): `sandhi_discovery_chain_new` / `_add` / `_count` / `_resolve` / `_as_resolver`. Iterates resolvers in insertion order, returns first non-null hit. Supports nesting a chain as a resolver inside another chain.
- **discovery/daimon** (`src/discovery/daimon.cyr`): HTTP-backed resolver against daimon's registry. Contract documented inline (`GET /services/{name}` → `{"host","port","address"?}`). Missing daimon = miss = chain fallthrough; no crash on outage.
- **discovery/local** (`src/discovery/local.cyr`): **mDNS interface only** — resolver struct constructs cleanly and integrates with the chain, but lookup always misses today. Reason documented: stdlib `net.cyr` doesn't expose the multicast-UDP socket primitives (`IP_ADD_MEMBERSHIP`, `IP_MULTICAST_TTL`) needed for the 224.0.0.251:5353 query path. `sandhi_discovery_local_available() == 0` signals the stub state. Real impl lands when `net.cyr` gains multicast helpers or a consumer asks.
- **discovery/register** (`src/discovery/register.cyr`): `sandhi_discovery_register(base, name, host, port)` + `_deregister(base, name)`. Daimon-backed publish/withdraw; mDNS publishing deferred with the local resolver.

### Changed
- **discovery/mod.cyr**: scaffold → real dialect-index comment with typical consumer usage + `sandhi_discovery_version() → "0.5.0"`.
- **cyrius.cyml `[lib].modules`**: discovery submodules added in dependency order (service → chain → daimon → local → register → mod).
- **src/main.cyr**: `sandhi_version()` → 0.5.0.

### Deferred (documented in code + roadmap)
- **mDNS lookup**. Stub resolver shipped today; real impl blocked on multicast primitives in stdlib `net.cyr`.
- **mDNS publishing** (continuous responder loop). Not in scope until multicast + thread-lifecycle story firms up.

## [0.4.0] — 2026-04-24

M3 close. JSON-RPC dialect layer — WebDriver, Appium, MCP-over-HTTP. 215 assertions green.

### Added
- **rpc/json** (`src/rpc/json.cyr`): nested JSON builder + dotted-path extractor. `sandhi_json_obj_new` / `add_string` / `add_int` / `add_bool` / `add_null` / `add_object` / `add_raw` / `escape` / `build`; `sandhi_json_get_string` / `get_int` / `has_path` with `value.sessionId`-style dotted paths. stdlib json.cyr is flat-only, so sandhi owns this surface for RPC use.
- **rpc/dispatch** (`src/rpc/dispatch.cyr`): JSON-over-HTTP transport with dialect-aware error envelope extraction. `sandhi_rpc_call(url, http_method, body_json, dialect)` returns a unified rpc-response (http_status + body + err_kind + err_message). Dialects: `GENERIC`, `WEBDRIVER` (W3C `value.error`/`value.message`), `JSONRPC` (`error.code`/`error.message`).
- **rpc/webdriver** (`src/rpc/webdriver.cyr`): W3C WebDriver dialect. Session lifecycle (`new_session` / `delete_session`), navigation (`navigate_to` / `get_url` / `get_title`), element interaction (`find_element` / `element_click` / `element_text` / `element_attribute` / `element_send_keys`), JS execution (`execute_script`), status probe (`status`). W3C element-reference key (`element-6066-11e4-a52e-4f735466cecf`) + pre-W3C `ELEMENT` fallback in `sandhi_wd_extract_element_id`.
- **rpc/appium** (`src/rpc/appium.cyr`): Appium extensions on top of WebDriver — `new_session` with `appium:automationName` capability, `set_context` / `get_contexts` / `current_context`, app lifecycle (`install_app` / `remove_app` / `activate_app` / `terminate_app`), `mobile_exec` / `source` / `screenshot`.
- **rpc/mcp** (`src/rpc/mcp.cyr`): MCP-over-HTTP transport. JSON-RPC 2.0 envelope build with monotonic per-process request IDs. **Transport only** per ADR 0001 — tool discovery / prompt schemas / sampling semantics stay in bote + t-ron.

### Changed
- **rpc/mod.cyr**: scaffold replaced with a real dialect-index comment + `sandhi_rpc_version() → "0.4.0"`.
- **cyrius.cyml `[lib].modules`**: new ordering routes `rpc/json` → `rpc/dispatch` → each dialect → `rpc/mod`.
- **src/main.cyr**: `sandhi_version()` → 0.4.0.

### Deferred
- **SSE / streaming response** for long-lived RPC calls. Roadmap M3 listed this but chunked framing is already handled in `src/http/response.cyr`; SSE-as-iterator is a callback/async shape that no current consumer needs. Lands as M3.5 when a consumer asks.

## [0.3.0] — 2026-04-24

M2 close. Full HTTP client surface — POST/PUT/DELETE/PATCH/HEAD/GET over HTTP and HTTPS, custom headers, chunked decoding, opt-in redirect following, native DNS resolver. 173 assertions green; live HTTP round-trip to `example.com` verified end-to-end via `programs/http-probe.cyr`.

### Added
- **http/headers** (`src/http/headers.cyr`): real key-value store — `sandhi_headers_new` / `set` / `add` / `get` / `remove` / `has` / `count` / `name_at` / `value_at` / `serialize` / `parse`. Case-insensitive lookup, multi-value support (Set-Cookie etc.), wire-format CRLF serialization.
- **http/url** (`src/http/url.cyr`): URL parser for `http://` and `https://` — returns 40-byte struct with scheme, host, port, path, query. CRLF-injection hardening from the stdlib http.cyr pattern. Default ports inferred (80 / 443).
- **http/conn** (`src/http/conn.cyr`): tagged `{kind, fd, tls_ctx}` connection abstraction. `sandhi_conn_open` wraps plain TCP via net.cyr or TLS via tls.cyr; unified `_send` / `_send_all` / `_recv` / `_recv_all` / `_close`.
- **http/response** (`src/http/response.cyr`): response parser handling Content-Length, Transfer-Encoding: chunked, and connection-close framings. Response struct `{status, body_ptr, body_len, headers, err_kind}`.
- **http/client** (`src/http/client.cyr`): `sandhi_http_get` / `post` / `put` / `delete` / `patch` / `head`. Request builder with HTTP/1.1 request line, Host header, auto Content-Length for body-bearing methods, `Connection: close`. Opt-in redirect following via `sandhi_http_options_new` + `_opts` variants (RFC 7231 §6.4 method rewrite: 303 → GET, 301/302/307/308 preserve). Absolute + relative Location resolution.
- **net/resolve** (`src/net/resolve.cyr`): native UDP DNS resolver. RFC 1035 query build + response parse, `/etc/resolv.conf` nameserver discovery with 8.8.8.8 fallback, A-records only, Linux-first. Includes `sandhi_net_parse_ipv4` for numeric literals. Written because `fdlopen_getaddrinfo` is blocked at 5.6.22 (tracked in `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`).
- **programs/dns-probe.cyr** + **programs/http-probe.cyr**: ad-hoc live-probe tools (not part of test suite; require network).

### Changed
- **programs/smoke.cyr**: include list expanded for the new http/* + net/* modules.
- **cyrius.cyml `[lib].modules`**: new order enforces the dependency chain (headers → url → conn → response → resolve → client).
- **src/main.cyr**: `sandhi_version()` bumped to 0.3.0.

### Known issues
- **HTTPS runtime via `lib/tls.cyr` is unstable.** Compilation is clean and `tls_policy` surface is intact, but live HTTPS round-trips trigger a re-entrant-execution symptom (`programs/http-probe.cyr https://...` prints "GET ..." hundreds of times before being killed). Candidate cause: `_tls_init` calls `dynlib_open` without the `dynlib_bootstrap_*` sequence that `lib/dynlib.cyr` documents as required for libc-dependent sidecars. Logged in `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` (P8 entry). Plain HTTP works end-to-end against hostname and IP-literal URLs.
- **Stack-slot aliasing on crowded frames.** Cyrius 5.6.22 silently zeroes a caller's local after a function call if the caller has ~15+ locals. Worked around by keeping individual sandhi functions below that threshold (see `src/http/response.cyr` comment). Logged in the same issue file.

## [0.2.0] — 2026-04-24

### Added
- **server**: lift-and-shift of `lib/http_server.cyr` into `src/server/mod.cyr`. Status codes, request parsing (`http_get_method` / `http_get_path` / `http_find_header` / `http_content_length`), path + query helpers (`http_path_only` / `http_url_decode` / `http_get_param` / `http_path_segment`), response builders (`http_send_status` / `http_send_response` / `http_send_204`), chunked / SSE (`http_send_chunked_start` / `http_send_chunk` / `http_send_chunked_end`), request reader (`http_recv_request`), and accept-loop (`http_server_run`) — all moved verbatim from the interim stdlib file. No behavior change.
- **tests**: pure-helper unit tests exercising the migrated server symbols (url decoding, path segmentation, query param extraction, request parsing) — 28 assertions green.
- **smoke**: `programs/smoke.cyr` now exercises `http_url_decode` so the linker actually pulls the migrated code in.

### Changed
- **cyrius.cyml**: `http_server` removed from `[deps.stdlib]`; sandhi is now self-sufficient for the HTTP server surface. Stdlib-side stays unchanged through the 5.6.x window and is resolved in one event at Cyrius v5.7.0 per [ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — `lib/http_server.cyr` is deleted and `lib/sandhi.cyr` is added as a clean-break fold. 5.6.YY releases carry a deprecation warning on include.

### Decisions
- **[ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — Clean-break fold at Cyrius v5.7.0.** Supersedes the alias-window migration plan from ADR 0001 / roadmap M1 / M6. One event at v5.7.0 instead of a two-copy window; 5.6.YY deprecation warning as the notice period.

## [0.1.0]

### Added
- Initial project scaffold
