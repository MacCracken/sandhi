# Connection pool

Without a pool, every `sandhi_http_get` / `_post` / etc. pays a full TCP handshake
(and TLS handshake if HTTPS) per request. For consumers hitting the same host
repeatedly — an RPC loop, a health-check poller, a streaming API client — a small
pool with a generous idle timeout amortizes those handshakes at trivial memory cost.

## When to use it

- A consumer making >1 request to the same host/port in quick succession.
- Any JSON-RPC or RPC-over-HTTP loop (WebDriver, Appium, MCP-over-HTTP).
- Long-running processes where each extra TCP+TLS round-trip adds user-visible latency.

When *not* to use it: truly one-shot fetches, or when you need the connection
definitely-dead between requests (testing, clean state).

## Create a pool

```
var pool = sandhi_http_pool_new(max_per_host, idle_timeout_ms);
```

- `max_per_host` — cap on idle conns **per route** (a "route" is
  `host:port:tls`). Default `8` if you pass `0`.
- `idle_timeout_ms` — how long an idle conn stays pool-eligible before it's
  considered stale and closed. Default `90000` (90 s — matches Go's default) if
  you pass `0`. Tune up for chatty internal services, down for external APIs
  that aggressively drop idle peers.

## Attach to a request

```
var opts = sandhi_http_options_new();
sandhi_http_options_pool(opts, pool);

var r1 = sandhi_http_get_opts("http://api.example.com/ping", 0, opts);
var r2 = sandhi_http_get_opts("http://api.example.com/ping", 0, opts);
# r2 reuses the conn r1 put back.
```

When the pool is attached, sandhi:

1. Emits `Connection: keep-alive` semantics (omits the `Connection: close` header).
2. Tries to take an idle conn for this route before opening a new one.
3. Reads the response using framing-aware recv (`Content-Length` or chunked), so
   the conn can stay alive past the response boundary.
4. Puts the conn back on 2xx/3xx **and** no server `Connection: close` header;
   otherwise closes it.

## Take / evict semantics

- **LIFO take** — freshest conn for the route comes out first. Keeps recent TCP /
  kernel-buffer state hot.
- **Stale skip** — a conn whose `last_used + idle_timeout_ms < now` is closed
  on take (peer likely dropped it) and the next candidate is tried.
- **FIFO eviction when full** — when a put would exceed `max_per_host`, the
  *oldest* idle conn for that route is closed to make room. Bounded memory.

## Per-route isolation

The pool keys on `host:port:tls`. So HTTPS to `api.example.com:443` and
HTTP to `api.example.com:80` are separate routes, and a conn for one never
leaks into the other. TLS-to-TLS-same-host-different-port is also its own route.

## Pool shuts the conn when

- Response had `err_kind != SANDHI_OK` (parse, protocol, timeout, etc.).
- Status is outside `200..=399` (4xx / 5xx / anomalous).
- Server sent `Connection: close` in the response.
- HTTP/1.0 close-delimited body (no framing declared).

In all those cases, the conn is already closed by the time the response struct
hands back to the caller — you don't have to do anything.

## Memory cost

A few KB per active route — an idle_conn struct is 16 bytes, a `sandhi_conn` is
24 bytes, plus the vec overhead. At `max_per_host=8`, a pool with 10 routes
holds ~3 KB idle-state plus whatever the kernel keeps for the open sockets.

## Cleanup

```
sandhi_http_pool_close(pool);
```

Closes every idle conn (fd + TLS context). The pool struct stays allocated and
reusable — you can continue to use it after close; it just has no idle conns.

For pools that hold h2 conns (any `_auto` request on a pooled HTTPS route whose peer
picks h2; see `http2-manual.md`), call
`sandhi_http_pool_close_h2_conns(pool)` **first** to tear down the h2 side
cleanly, *then* `sandhi_http_pool_close(pool)` for the 1.1 side. The h2 map
is not walked by the generic close for build-order reasons.

## Observability

- `sandhi_http_pool_idle_count(pool)` — current number of idle conns across all routes.
- `sandhi_http_pool_max_per_host(pool)` / `sandhi_http_pool_idle_timeout_ms(pool)` —
  configured values.

## Threading

Since 1.13.0 a pool may be **shared across threads**. Each pool owns a mutex
(`lib/sync.cyr`), held only while it updates its route map and idle lists: taking a
connection, returning one, checking for an idle one, and the HTTP/2 helpers
(`sandhi_http_pool_take_h2` / `_put_h2` / `_close_h2_conns`). An HTTP/1.1 connection
is handed to exactly one caller and belongs to that thread until it is put back.
Connections are closed (an evicted one, a stale one, or all of them in
`sandhi_http_pool_close`) after the lock is released, so a slow TLS close never holds up
another thread.

**HTTP/2 works differently.** The pool keeps one HTTP/2 connection per route and hands
the *same* connection to every caller (`sandhi_http_pool_take_h2` does not remove it).
Since 1.13.3 that connection may be used by several threads at once: each h2 connection
owns a mutex, and `sandhi_h2_request_a` (which the `_auto` dispatch uses) holds it for
one request's send and its response. Requests on one h2 connection therefore run one at
a time, not in parallel: threads that need parallel h2 requests to one route give each
thread its own pool. `sandhi_http_pool_close_h2_conns` waits for a request in flight on
each connection, and a thread still holding a closed connection gets
`SANDHI_ERR_PROTOCOL` rather than writing to a reused descriptor. Since 1.13.6 an h2
connection whose exchange fails (a timeout, a protocol error, a GOAWAY) is closed by that
exchange and dropped by the next take, so later requests open a fresh one; see
`http2-manual.md` for the rest of the h2 behaviour.

One pool per thread still works everywhere and avoids any contention, if that suits the
program better.
