# HTTP/2 — manual path

HTTP/2 in sandhi is **opt-in**, manual, and rarely used today. Here's why, and how
to use it when you have to.

## Why h2 is opt-in today

Two upstream blockers keep h2 from being automatic:

1. **libssl-pthread-deadlock** — the stdlib `tls.cyr` hits a pthread-futex
   deadlock on `SSL_connect`, so live HTTPS doesn't work. See
   `docs/issues/2026-04-24-libssl-pthread-deadlock.md`.
2. **Missing stdlib TLS hook for ALPN** — even with libssl fixed, we can't
   advertise `h2` via ALPN without an `SSL_CTX` customization hook in stdlib.
   See `docs/issues/2026-04-24-stdlib-tls-alpn-hook.md`.

Until those clear, `sandhi_conn_alpn_is_h2(conn)` returns 0 for every live
connection, and auto-selection correctly degrades to HTTP/1.1. The h2 code is
fully exercised in `tests/h2.tcyr` against synthetic byte streams — frames,
HPACK, preface/settings exchange, request/response — so the path is ready to
go live the moment the TLS blockers clear.

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

Today the "if" branch is effectively dead: nothing populates the pool's h2 map
because `sandhi_conn_alpn_is_h2` always returns 0 post-handshake. So
`sandhi_http_request_auto` is `_sandhi_http_dispatch` with a cheap h2-map
lookup in front of it.

Convenience verbs: `sandhi_http_get_auto`, `_head_auto`, `_post_auto`, `_put_auto`,
`_patch_auto`, `_delete_auto` — all mirror the 1.1 signatures.

Consumers can call the `_auto` verbs today and get HTTP/1.1 behavior; when TLS
clears, they get h2 without a code change.

## Limitations of the h2 path

The h2 path does **not** honor:

- **Redirects** — `sandhi_http_options_follow_redirects` is 1.1-only. Redirect
  responses on an h2 stream come back to the caller unhandled. (If you need
  redirect following on h2, the dispatch layer can plumb it through — ask.)
- **Retry with backoff** — `sandhi_http_get_retry` and friends are 1.1-only.
  The h2 path is single-shot for idempotent-method calls.

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
