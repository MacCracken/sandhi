# 2026-06-03 — HTTP/1.1 `Connection: close` path drains until EOF instead of framing by Content-Length

**Status**: ✅ **Resolved in sandhi 1.4.1** (2026-06-03) — `_sandhi_http_exchange_a`
now reads via `_sandhi_http_recv_framed` (Content-Length/chunked framing, the
same reader the keep-alive path uses) instead of draining until EOF. Verified
live against chromedriver (`/status` → `err_kind=0 status=200`, was TIMEOUT);
normal Content-Length+close server still 200; 979 assertions green. See
CHANGELOG [1.4.1].
**Filed**: yantra side, against sandhi.
**Side**: sandhi-side (`src/http/client.cyr` response read on the non-keep-alive path).
**Severity**: blocked sandhi against chromium-family HTTP servers (chromedriver, Chromium DevTools).
**Observed**: sandhi 1.3.4 (vendored in yantra) and 1.4.0 source. **Fixed**: 1.4.1.

## Summary

The default (`Connection: close`, no-pool) request path reads the entire
response by **draining the socket until EOF** and only *then* parses/frames it.
A server that sends a complete, `Content-Length`-framed response but does **not**
promptly close the socket causes sandhi to block until the deadline and return
`SANDHI_ERR_TIMEOUT` — even though the full, correct response was already in the
buffer. The framed-recv logic that would fix this already exists, but only on
the keep-alive path.

## Evidence

`_sandhi_http_exchange_a` reads the whole response then parses:

```
# src/http/client.cyr:535
var nread = sandhi_conn_recv_all_deadline(conn, rbuf, cap, deadline_ms);
sandhi_conn_close(conn);
...
return sandhi_http_response_parse_a(a, rbuf, nread);
```

`sandhi_conn_recv_all_deadline` stops only on EOF (`n == 0`), `max`, or the
deadline — it never consults `Content-Length` / `Transfer-Encoding`:

```
# src/http/conn.cyr:848
fn sandhi_conn_recv_all_deadline(conn, buf, max, deadline_ms): i64 {
    ...
    while (going == 1 && have < max) {
        ... if (n == 0) { going = 0; } else { have = have + n; } ...
    }
}
```

By contrast `_sandhi_http_exchange_keepalive_a` already does the right thing
(its own header says so): *"does framed recv (Content-Length or chunked
detected from response headers) so the conn stays alive past the response."* So
the capability exists; the close path just doesn't use it.

## Reproduction

A live `chromedriver --port=9515` (W3C WebDriver server):

```cyrius
var o = sandhi_http_options_new();
sandhi_http_options_read_ms(o, 5000);
var r = sandhi_http_get_opts("http://127.0.0.1:9515/status", 0, o);
# sandhi_http_err_kind(r) == 4 (SANDHI_ERR_TIMEOUT), status == 0
# With read_ms unset (bare sandhi_http_get) it blocks indefinitely.
```

Raw exchange (captured): chromedriver replies in full, then leaves the socket open:

```
GET /status HTTP/1.1
Host: 127.0.0.1:9515
Connection: close
...

HTTP/1.1 200 OK
Content-Length:249
Content-Type:application/json; charset=utf-8
Connection:close

{"value":{ ... "ready":true}}              <-- 249 bytes, complete
                                            <-- socket NOT closed; recv blocks
```

`curl` succeeds (it frames by `Content-Length`); sandhi times out (it waits for
an EOF that does not come). Chromium's DevTools HTTP endpoint behaves the same
way (also note: both emit headers with **no space after the colon** —
`Content-Length:249` — so any fix's CL parse must tolerate optional OWS per
RFC 7230 §3.2).

## Should sandhi behave differently? Yes.

Per RFC 7230 §3.3.3, a response with `Content-Length` (or
`Transfer-Encoding: chunked`) is **complete** once that many body bytes (or the
chunked terminator) have arrived. A conformant client must not wait for
connection close to consider such a response done — `Connection: close` governs
connection *reuse*, not message *framing*, and a peer that is slow to close (or
never closes) must not stall the client.

## Proposed fix

Make `_sandhi_http_exchange_a` (the close path) read incrementally and frame
like the keep-alive path already does:

1. recv until the header terminator (`\r\n\r\n`) is seen;
2. parse `Content-Length` / `Transfer-Encoding` from the headers (CL parse must
   accept no-OWS-after-colon);
3. read exactly the framed body (CL bytes, or decode chunks to the terminator),
   then return — do not wait for EOF;
4. fall back to read-until-EOF only when neither CL nor chunked is present
   (HTTP/1.0-style delimited-by-close).

The keep-alive exchange already contains this framed-recv; the close path should
share it.

## Downstream status

yantra's M2 WebDriver backend (`src/protocol/webdriver.cyr`) hit this against
chromedriver and now ships its own minimal `Content-Length`-framed HTTP/1.1
client over `net.cyr` (mirroring what its CDP backend already does for Chromium
discovery — see yantra `docs/architecture/`). yantra will switch the WebDriver
transport back to `sandhi` once the close path frames by Content-Length, since
`sandhi` is otherwise exactly the right HTTP client for the Appium (M3/M4) work.
No sandhi API change is required by this fix — it is read-path behavior only.
