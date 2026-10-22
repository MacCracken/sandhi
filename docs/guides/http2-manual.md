# HTTP/2 — manual path

HTTP/2 auto-selection is **live** — most consumers get h2 automatically. The
manual path documented here is for fine-grained control.

## When to use the manual path

ALPN-driven h2 auto-selection is wired (since 0.9.6): on a pooled TLS route,
`sandhi_http_request_auto` opens advertising `h2,http/1.1`, and when the peer
negotiates h2 — `sandhi_conn_alpn_is_h2(conn)` returns the real negotiated
protocol off the conn struct — it runs the preface/SETTINGS exchange and caches
an h2 connection in the pool; otherwise it uses HTTP/1.1. So you normally don't
touch the manual path at all.

Reach for it when you've established an h2-speaking connection some other way (an
h2c upgrade, a test harness with pre-negotiated ALPN, a local h2 proxy) and want
to drive frames / HPACK directly. The h2 stack is fully exercised in
`tests/h2.tcyr` (frames, HPACK, preface/SETTINGS, request/response) and fires
end-to-end over live TLS via the auto path.

## Manual h2 path

If you have another way to establish an h2-speaking connection (an h2c
upgrade, a test harness with pre-negotiated ALPN, a local h2 proxy), you can
drive it end-to-end:

```
# 1. Open an underlying sandhi_conn (TCP or TLS-with-ALPN-h2).
var conn = sandhi_conn_open(addr, port, use_tls, sni_host);

# 2. Wrap it in an h2 conn (sets up HPACK tables, stream-id counter).
var h2c = sandhi_h2_conn_new(conn);

# 3. Exchange preface + SETTINGS (RFC 7540 §3.5 + §6.5).
sandhi_h2_conn_send_preface_and_settings(h2c);
sandhi_h2_conn_recv_peer_settings(h2c);

# 4. Send requests through the request verb.
var resp = sandhi_h2_request(h2c, "GET", "http://host/path", 0, 0, 0);
# resp has the same accessors as the 1.1 client:
# sandhi_http_status, _body, _body_len, _headers, _err_kind.
```

You can fire many requests over the same `h2c` — stream-ids are allocated
automatically (odd, monotonically increasing per RFC 7540 §5.1.1).

## Auto-selection — `sandhi_http_request_auto`

Added in 0.8.1. Takes the same args as `_sandhi_http_dispatch`:

```
var resp = sandhi_http_request_auto(method, url, headers, body, body_len, opts);
```

Behavior:

- If the attached pool has an h2 conn for this route → dispatch through
  `sandhi_h2_request`.
- Otherwise → fall back to `_sandhi_http_dispatch` (normal HTTP/1.1 with
  pool + redirect + timeout honoring).

With no h2 conn pooled for the route, a pooled HTTPS request first tries the ALPN
promotion described above, and caches the h2 conn when the peer picks h2. Redirects
are followed per hop on either protocol, and the `_retry` verbs send every attempt
through `sandhi_http_request_auto`.

Convenience verbs: `sandhi_http_get_auto`, `_head_auto`, `_post_auto`, `_put_auto`,
`_patch_auto`, `_delete_auto` — all mirror the 1.1 signatures.

## Sharing one h2 connection between threads

`sandhi_h2_request` / `_request_a` lock the h2 connection for one request's send and
its response read (since 1.13.3), so threads may share one connection: their requests
run one after another. A caller that composes the lower-level verbs itself
(`sandhi_h2_request_send_a`, then `sandhi_h2_response_recv_a`) on a shared connection
must keep the pair together on one thread: the response reader drops frames for other
streams, so a second thread's send between them loses one of the two answers.

## How the h2 path behaves

Since 1.13.6:

- **Flow control.** Response data is returned to the peer with `WINDOW_UPDATE` (for the
  connection and the stream) once half the default window is outstanding, so a pooled
  conn no longer stalls after 64 KiB of responses. Request bodies go out as DATA frames
  of at most the peer's `MAX_FRAME_SIZE`, within its connection and stream windows; the
  sender waits for the peer's `WINDOW_UPDATE` when they are spent. If the peer answers
  before the body is all sent, the sender stops, the answer is read, and the stream is
  closed with `RST_STREAM` (`NO_ERROR`).
- **Headers.** The request side never indexes (every field is a literal without
  indexing), so the conn's encoder table stays empty. A header block longer than the
  peer's `MAX_FRAME_SIZE` goes out as HEADERS + CONTINUATION; there is no fixed cap. A
  header list larger than the peer's `SETTINGS_MAX_HEADER_LIST_SIZE` is refused before
  anything is sent (`SANDHI_ERR_PROTOCOL`, with a message), and the conn carries on.
- **Timeouts.** The `_auto` path applies the request's own `read_ms`, `write_ms` and
  `total_ms` to its exchange; a timeout fails as `SANDHI_ERR_TIMEOUT`. The manual verb
  (`sandhi_h2_request_a`) keeps whatever timeouts the conn's socket has.
- **Failure retires the conn.** An exchange that fails after its request reached the
  wire (a timeout, a protocol error, a GOAWAY) marks the conn dead and closes it; the
  pool's next take drops it. A peer's `RST_STREAM` ends only that stream, and the conn
  stays.
- **Push is off.** The preface's SETTINGS carry `ENABLE_PUSH = 0`, and a `PUSH_PROMISE`
  fails the exchange.

## Limitations of the h2 path

- **GOAWAY fails the exchange in flight,** even when its last-stream-id says the peer
  will still finish it (roadmap 1.14.x).
- **Response caps are fixed:** a header block over 16 KB, or a body over 1 MiB, fails
  as `SANDHI_ERR_PROTOCOL` (roadmap 1.14.x).

The h2 path serves RPC traffic where neither applies.

## When to choose the h2 path

For 0.9.2 — almost never. The 1.1 path with a connection pool covers every
consumer workflow and works today. Keep the h2 path in mind for:

- Future multiplexed RPC (MCP, bote / t-ron) where many parallel requests over
  one conn matters.
- A local test harness where you want to exercise h2-specific behavior.

When the TLS blockers clear, `sandhi_http_request_auto` becomes the default and
the manual path recedes to "for when you want fine-grained control."
