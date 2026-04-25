# Timeouts

sandhi's HTTP client has four independent timeout knobs. Attach them to a request via
`sandhi_http_options_new()` and the `_opts`-suffixed verbs.

## The four knobs

| Knob         | Bounds                                              | Default (`0`) |
| ------------ | --------------------------------------------------- | ------------- |
| `connect_ms` | `connect()` syscall (non-blocking + poll)           | blocking      |
| `read_ms`    | each `recv()` via `SO_RCVTIMEO`                     | blocking      |
| `write_ms`   | each `send()` via `SO_SNDTIMEO`                     | blocking      |
| `total_ms`   | monotonic deadline across the whole request/response | no deadline  |

All four are in milliseconds. `0` means "no limit" for that knob.

`connect_ms` engages a non-blocking-connect + `poll()` path when >0. When `0`, the
kernel's default `SYN` retry can take up to ~75 s on a dropped-SYN blackhole — set
`connect_ms` for any network you don't control.

`read_ms` / `write_ms` apply `SO_RCVTIMEO` / `SO_SNDTIMEO` to the socket. On fire
the underlying syscall returns `EAGAIN`; sandhi maps that to `SANDHI_ERR_TIMEOUT`.

`total_ms` is the outer ceiling. Every phase (connect, send, recv) checks the
deadline before its next syscall. Per-phase knobs clamp against it: the effective
`connect_ms` is `min(connect_ms, deadline - now)`; if the deadline has already
passed when a phase is about to start, the request returns `SANDHI_ERR_TIMEOUT`
without issuing the syscall.

## Usage

```
var opts = sandhi_http_options_new();
sandhi_http_options_connect_ms(opts, 2000);   # 2 s to establish TCP
sandhi_http_options_read_ms(opts, 5000);      # 5 s per recv
sandhi_http_options_write_ms(opts, 5000);     # 5 s per send
sandhi_http_options_total_ms(opts, 10000);    # 10 s end-to-end

var resp = sandhi_http_get_opts(url, 0, opts);
```

Setter summary (all take the opts struct + an `ms` value):

- `sandhi_http_options_connect_ms(opts, ms)`
- `sandhi_http_options_read_ms(opts, ms)`
- `sandhi_http_options_write_ms(opts, ms)`
- `sandhi_http_options_total_ms(opts, ms)`

And the `_opts` verbs that honor them:

- `sandhi_http_get_opts(url, user_headers, opts)`
- `sandhi_http_post_opts(url, user_headers, body, body_len, opts)`

For other methods (PUT / PATCH / DELETE / HEAD) today you call the base verb; if
you need `_opts` variants, open an issue — the dispatch layer
(`_sandhi_http_dispatch`) already threads `opts` through and adding a public
wrapper is three lines.

## Checking for timeout

```
var resp = sandhi_http_get_opts(url, 0, opts);
if (sandhi_http_err_kind(resp) == SANDHI_ERR_TIMEOUT) {
    # connect, recv, send, or total_ms fired.
    # status == 0, body == 0, body_len == 0.
}
```

sandhi does not tell you *which* phase tripped — the contract surface is
"TIMEOUT fired" with no further discrimination. (If you need that, enable
tracing via `sandhi_trace_enable(1)`; spans mark each phase.)

## How the knobs interact

1. On entry, if `total_ms > 0` sandhi computes `deadline_ms = clock_now_ms() + total_ms`.
2. Before `connect()`: effective connect = `min(connect_ms, deadline - now)`. If
   `deadline - now <= 0`, return `TIMEOUT` without attempting the syscall.
3. After connect: `SO_RCVTIMEO`/`SO_SNDTIMEO` applied to the fd per `read_ms`/`write_ms`.
4. On each `recv()` in the response loop: check deadline first; if passed,
   return `TIMEOUT`.

Per-hop reset: when redirect following is enabled, each redirect hop gets a **fresh
`total_ms` budget** — the deadline is recomputed per hop. If you want a hard
end-to-end bound across hops, lower `max_hops` or measure externally.

Pool interaction: when a connection is taken from the pool, the connect phase is
skipped entirely (and its timeout doesn't apply). `read_ms` / `write_ms` still
apply normally — they're set on the fd. `total_ms` still bounds the outer loop.

## Typical settings

- **Internal service with reliable network**: `connect_ms=500, read_ms=2000, total_ms=5000`.
- **External API over the internet**: `connect_ms=3000, read_ms=10000, total_ms=30000`.
- **Long-polling / slow response**: set `total_ms` high (or `0`); keep
  `connect_ms` tight so a DNS/SYN black-hole still fails fast.
- **Never-stall server-sent events stream**: use `sandhi_http_stream_opts` with
  the same option shape — `total_ms` bounds the whole stream lifetime, not per-event.
