# 2026-09-25 — `sandhi_http_stream` gives the consumer no turn while the upstream is silent (SSE keep-alive unreachable)

**Status:** Resolved in sandhi **1.10.5** (2026-10-04). Reaches hoosh only when a cyrius release re-vendors `lib/sandhi.cyr` from `dist/sandhi.cyr`; there is no sandhi pin to bump.
**Severity:** **P2** — nothing breaks inside sandhi. A proxy between a gateway and its client can drop a
stream that is healthy but quiet, which is common with reasoning models and cold model loads.
**Reporter:** hoosh (AI inference gateway, 2.7.0 — remote provider streaming).
**Sandhi version:** 1.9.17 (bundled at cyrius 6.6.6 as `lib/sandhi.cyr`); re-checked against 1.10.0 source.
**Affects:** any consumer that relays an upstream SSE stream to its own client over `sandhi_http_stream` /
`sandhi_http_stream_opts`, and so needs to write *something* to that client while the upstream is silent.

## Premise check

Checked before filing, because
[`archive/2026-07-03-rpc-mcp-call-no-custom-request-headers.md`](2026-07-03-rpc-mcp-call-no-custom-request-headers.md)
was withdrawn for missing an existing variant:

- `sandhi_http_options_*` has connect, read, write and total timeouts, max bytes, pool, redirects and the
  TLS policy. None of them is a periodic or idle callback.
- The public stream surface is `sandhi_http_stream{,_a,_opts,_opts_a}`, `sandhi_rpc_mcp_stream`,
  `sandhi_stream_{status,events,err,stopped}` and `sandhi_sse_*`. There is no pull-style or
  step-at-a-time stream (no `open` / `next(timeout)` pair).
- `src/http/stream.cyr` `_sandhi_stream_body_loop_a`: `cb(ctx, event)` runs only from
  `_sandhi_stream_dispatch`, i.e. once per parsed SSE event. A `sandhi_conn_recv` that returns
  `-_SANDHI_EAGAIN` (the `read_ms` SO_RCVTIMEO firing) ends the stream with `SANDHI_ERR_TIMEOUT`.

So between two upstream events the consumer gets no control at all. A quiet stretch longer than
`read_ms` kills the stream, and a quiet stretch shorter than `read_ms` gives the consumer no chance to act
during it.

## Why a consumer needs a turn

hoosh relays a provider's SSE stream to an OpenAI-compatible client. The Rust implementation it replaced
sent an SSE comment (`: keep-alive`) after every 15 s of silence. Proxies and load balancers in front of
the gateway close connections after an idle timeout (nginx `proxy_read_timeout` and most cloud LBs:
60 s). A reasoning model that thinks for 90 s before its first token, or a cold model load, therefore
gets its stream cut at the proxy even though the upstream is healthy.

hoosh 2.7.0 restored the keep-alive for **local** backends, where hoosh owns the read loop: SO_RCVTIMEO
is 15 s, each EAGAIN writes a comment, and the silences are summed against the real idle bound. For
**remote** (TLS) backends the loop is sandhi's, and none of that can be done from outside.

The workarounds are poor:

- **A timer thread writing to the client socket.** It races the stream callback's writes to the same fd,
  so SSE frames interleave. That means a per-connection lock that every event write takes, and a thread
  per stream.
- **Hand-rolling the stream** from `sandhi_conn_open_*` + `sandhi_conn_recv` + `sandhi_sse_parse`. That
  re-implements request building and chunked decoding, which are private
  (`_sandhi_client_build_request_a`, `_sandhi_stream_decode_chunked_into`), plus the TLS-policy
  bracketing added in 1.4.6.

## Proposed API

Two options on `sandhi_http_options`, so the positional signature of `sandhi_http_stream_opts` does not
change:

```cyrius
sandhi_http_options_idle_ms(opts, ms);    # 0 = off (today's behavior)
sandhi_http_options_idle_cb(opts, fp);    # fp(ctx, silent_ms) -> nonzero continue, 0 stop
```

`_sandhi_stream_body_loop_a` semantics when `idle_ms > 0`:

- Arm SO_RCVTIMEO at `idle_ms` instead of `read_ms`.
- On `-_SANDHI_EAGAIN`, add `idle_ms` to a silence counter. If the counter reaches `read_ms` (when
  `read_ms > 0`), return `SANDHI_ERR_TIMEOUT` exactly as today. Otherwise call `idle_cb(ctx, silent_ms)`:
  0 stops the stream the way a 0 from `cb` does (`stopped = 1`), nonzero goes back to `recv`.
- Any received byte resets the counter.
- `total_ms` and its deadline check are unchanged.

`read_ms` keeps its meaning, "the longest silence I accept", and `idle_ms` adds "how often I get a turn
during it". The `ctx` is the same one `cb` receives, so the consumer's state (hoosh: the client fd plus
a "headers sent" flag) is already there.

The header-drain loop can stay as it is. A keep-alive only matters once the consumer has started its own
response, which it does after the upstream answers.

## Things to verify on the sandhi side

- **Partial TLS records across EAGAIN.** Today nothing retries after `-_SANDHI_EAGAIN`, because it ends
  the stream, so it has never mattered whether the native TLS reader keeps a partially received record
  across a timed-out read. With a retry it matters. The common idle case (no bytes at all) is safe, but a
  record split across the 15 s boundary must resume, not desync.
- **The libssl bridge.** The same retry on the libssl path (`SSL_read` after `SSL_ERROR_WANT_READ`) is
  standard, but it goes through the bridge that
  [`archive/2026-06-09-https-repeated-request-segfault.md`](2026-06-09-https-repeated-request-segfault.md)
  hardened.
- **h2.** The same option would be useful on h2 streams if and when `sandhi_http_stream` gains an h2
  path.

## Acceptance

A gate program in the style of `programs/_https_policy_threading_gate.cyr`: a local TLS SSE server that
sends one event, stays silent for 40 s, then sends a second event and closes. With `idle_ms = 15000`,
`read_ms = 300000`:

- `idle_cb` runs twice, at about 15 s and about 30 s.
- Both events reach `cb`.
- The result is `SANDHI_OK`.

With `idle_ms = 0` the behavior is byte-identical to today. With `read_ms = 20000`, the stream ends with
`SANDHI_ERR_TIMEOUT` after one `idle_cb`.

## Consumer side (hoosh)

Once shipped and folded into a cyrius release, hoosh sets `idle_ms` / `idle_cb` on its remote stream
options. Its callback writes `: keep-alive\n\n` to the client with the same `http_sse_comment` the local
path uses, and returns 0 when the client is gone. hoosh records the gap as a known non-port in
`docs/development/rust-old-retirement.md`.

## Resolution (sandhi 1.10.5)

Shipped as proposed at the API level: `sandhi_http_options_idle_ms(opts, ms)` and
`sandhi_http_options_idle_cb(opts, fp)`, with `fp(ctx, silent_ms)` (nonzero continues, 0 stops
with `stopped = 1`), plus the getters `sandhi_http_options_get_idle_ms` / `_get_idle_cb`. The
options struct grew 80 → 96 bytes. `read_ms` keeps its meaning (the longest silence accepted),
`total_ms` still bounds the stream, and either option at 0 is the old loop.

**The mechanism differs from the proposal, and the "Things to verify" section is why.** The
proposal armed SO_RCVTIMEO at `idle_ms` and retried after `-EAGAIN`. Against cyrius 6.6.15 that
cannot work on TLS:

- native TLS reports an expired SO_RCVTIMEO as `TLS_ERR_IO`, and every negative read **fails the
  ctx for good** (`lib/tls_native_conn.cyr`, the read-path error table, 6.6.13). The retry would
  read `TLS_ERR_IO` forever;
- a record read cut off mid-record cannot resume (the record reader loops `read(2)` until the
  record is complete);
- `sandhi_conn_recv` collapses every negative `tls_read` to `-1`, so a TLS timeout was never
  `-_SANDHI_EAGAIN` in the first place.

So the body loop instead **waits for readability** with `fd_wait_ready` (cyrius 6.6.13: poll on
Linux and macOS, WSAPoll on Windows) for at most `idle_ms` before each read. A wait consumes
nothing at either layer, so no read is cut short and the TLS ctx is never touched. Plaintext the
TLS layer could hold out of the socket's view never arises: the loop reads 16384 bytes, a whole
maximum-size record. agnos has no poll (`fd_wait_ready` answers -38), so the turn does not come
there and the loop reads exactly as before. The silence is measured on the monotonic clock from the
last received byte. Both "partial TLS record" and "libssl bridge" concerns are therefore moot: no
read is ever retried after a failure.

Acceptance, as specified: `programs/_stream_idle_gate.cyr`, a forked pooled sandhi TLS server on
the Ed25519 fixtures, run in CI at a 100 ms unit and once locally at the literal figures
(`build/_stream_idle_gate 1000`):

- idle 15 s, read 300 s, 40 s silence: `idle_cb` at 15015 ms and 30015 ms, both events, SANDHI_OK;
- read 20 s: SANDHI_ERR_TIMEOUT after one `idle_cb` (15015 ms);
- idle 0: no turn, both events, SANDHI_OK.

The libssl build of the gate does not link at this pin. That is the open cyrius DCE issue
([`../2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md`](../2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md)),
and the readiness wait does not depend on the backend.

**Found on the way, fixed in the same release:** the chunked path of the same loop decoded each pass
into a fresh buffer, so the unterminated tail of an SSE event (which the 1.9.15 parser fix correctly
leaves unconsumed) was thrown away at the next read. An event whose bytes arrived in two reads was
**lost**, the same symptom hoosh reported before 1.9.15, still present on chunked streams. Each pass
also reserved another `max_response_bytes` (256 KiB by default) from an allocator that never frees.
Fixed by keeping one decode buffer for the life of the stream.

h2 is unchanged: `sandhi_http_stream` has no h2 path.

