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

## Limitations of the h2 path

- ⚠ **A pooled h2 conn stalls after about 64 KiB of responses.** sandhi never sends
  `WINDOW_UPDATE`, so once the responses on one conn add up to the peer's 65,535-byte
  connection window, the peer stops sending. The h2 path sets no read or total timeout
  of its own: only the read timeout of the request that opened the conn bounds the wait,
  and there is none by default. Measured at 1.13.1: two `_auto` GETs of a 56 KB page
  through one pool, and the second never returned. Until roadmap 1.13.x lands, use the
  HTTP/1.1 verbs (`sandhi_http_*`, not `_auto`) with a pool for repeated large
  responses. Setting `sandhi_http_options_read_ms` on the request that opens the conn
  bounds the wait: the stalled request then fails with `SANDHI_ERR_PROTOCOL` after that
  long (measured: 3,000 ms, about 3 s).

Both of these are addressable when a consumer reports a real need. For now, the
h2 path serves single-shot RPC traffic where neither applies.

## When to choose the h2 path

For 0.9.2 — almost never. The 1.1 path with a connection pool covers every
consumer workflow and works today. Keep the h2 path in mind for:

- Future multiplexed RPC (MCP, bote / t-ron) where many parallel requests over
  one conn matters.
- A local test harness where you want to exercise h2-specific behavior.

When the TLS blockers clear, `sandhi_http_request_auto` becomes the default and
the manual path recedes to "for when you want fine-grained control."
