# HTTP server

sandhi ships a minimal HTTP/1.1 server: bind + accept + parse the request + call
your handler + close the connection. Single-threaded, one request per connection
(no keep-alive on the server side yet).

## Naming

Canonical symbols are `sandhi_server_*` as of 0.9.2. The earlier `http_*` names
from the lift-and-shift (M1, `lib/http_server.cyr`) still exist as thin
deprecation wrappers and **retire at 1.0.0** (the v5.7.0 fold). New code uses
`sandhi_server_*` exclusively; existing consumers do a search-and-replace before
1.0.0.

## Minimal accept loop

```
fn my_handler(ctx, cfd, req_buf, req_len) {
    sandhi_server_send_response(cfd, 200, "OK",
        "text/plain", "hello\n", 6, 0);
    return 0;
}

fn main() {
    alloc_init();
    sandhi_server_run(INADDR_LOOPBACK(), 8080, &my_handler, 0);
    # never returns on success — loops accepting forever
    return 0;
}
```

- `addr` — network-byte-order IPv4. `INADDR_ANY()` for `0.0.0.0`,
  `INADDR_LOOPBACK()` for `127.0.0.1`. (Both are stdlib net.cyr verbs.)
- `port` — listen port.
- `handler_fp` — function pointer; signature `fn h(ctx, cfd, req_buf, req_len) → 0`.
- `ctx` — opaque pointer passed through to your handler each call.

Return value: `1` if bind / listen fails at startup; otherwise loops forever.

## Handler signature

```
fn handler(ctx, cfd, req_buf, req_len) {
    # ctx:     caller-supplied opaque pointer (your state)
    # cfd:     accepted client fd — write responses here
    # req_buf: buffer containing the full request (headers + body)
    # req_len: number of valid bytes in req_buf
    return 0;
}
```

The server closes `cfd` after your handler returns. Don't close it yourself.

## Parsing the request

```
var method = sandhi_server_get_method(req_buf, req_len);   # "GET" / "POST" / etc.
var path   = sandhi_server_get_path(req_buf, req_len);     # "/foo?x=1"
var host   = sandhi_server_find_header(req_buf, req_len, "Host");
var clen   = sandhi_server_content_length(req_buf, req_len);
```

`sandhi_server_find_header` is case-insensitive, returns a value cstr trimmed of
leading SP and trailing CR (or 0 if absent).

### Reading the request body

```
var body_off = sandhi_server_body_offset(req_buf, req_len);  # or -1 if no \r\n\r\n
if (body_off >= 0) {
    var clen = sandhi_server_content_length(req_buf, req_len);
    # Body bytes live at req_buf + body_off, clen bytes long.
}
```

`sandhi_server_recv_request` (used internally) reads until `Content-Length` is
satisfied or the peer closes, so by the time your handler runs, the body is
already buffered in `req_buf`.

## URL helpers

```
var path_only = sandhi_server_path_only(path);         # "/foo?x=1" → "/foo"
var decoded   = sandhi_server_url_decode("hi%20there"); # "hi there"
var x         = sandhi_server_get_param(path, "x");    # query ?x=... value, decoded
var seg0      = sandhi_server_path_segment(path, 0);   # "/a/b/c" → "a"
```

`sandhi_server_get_param` does percent-decode for you; don't call `url_decode` on
its result.

## Responses

Every response verb returns `0` once all of its bytes are written, and a negative
value otherwise: `-errno` from the write (`-EPIPE` when the client has gone), or
`-1` if building the response ran out of memory. Writes go through `sock_send_all`,
so a short write is completed rather than leaving a response shorter than its own
`Content-Length`. For a one-shot response there is usually nothing left to do on
failure but return; for a stream, see [Chunked / streaming](#chunked--streaming).
(Since 1.10.6; the chunked verbs since 1.10.5. Before that they always returned 0.)

### Simple status-only

```
sandhi_server_send_status(cfd, 404, "Not Found");
sandhi_server_send_status(cfd, 500, "Internal Server Error");
```

Minimal response with `Content-Length: 0` and `Connection: close`. Use for 4xx /
5xx that don't carry a body.

### Full response with body

```
sandhi_server_send_response(cfd,
    200, "OK",
    "application/json",
    body, body_len,
    0);  # extra_headers: 0 or a cstr of CRLF-terminated "Name: Value\r\n" lines
```

`extra_headers` is a pre-baked cstr if you have custom headers:

```
var extra = "X-My-Header: foo\r\nCache-Control: no-store\r\n";
sandhi_server_send_response(cfd, 200, "OK", "application/json", b, bl, extra);
```

### 204 No Content

```
sandhi_server_send_204(cfd, 0);        # minimal 204
sandhi_server_send_204(cfd, my_extra); # 204 with extra headers
```

### Chunked / streaming

For SSE, large bodies, or any long-running response:

```
if (sandhi_server_send_chunked_start(cfd, 200, "text/event-stream", 0) < 0) { return 0; }
if (sandhi_server_send_chunk(cfd, "data: hello\n\n", 13) < 0) { return 0; }
if (sandhi_server_send_chunk(cfd, "data: world\n\n", 13) < 0) { return 0; }
sandhi_server_send_chunked_end(cfd);
```

Each `send_chunk` emits `<hex-len>\r\n<data>\r\n` on the wire.
`send_chunked_end` emits the terminal `0\r\n\r\n`.

All three return `0` once every byte is written, and a negative value otherwise
(see [Responses](#responses)). Check the result and stop streaming on a negative one. A
loop that feeds a stream from a subscription or a long job is otherwise held open,
with its connection, until its own source ends. Writes go through `sock_send_all`,
so a short write is completed rather than breaking the chunk framing (since 1.10.5;
before that all three always returned 0).

Every serve loop ignores SIGPIPE (Linux and macOS; Windows and agnos have no
SIGPIPE), so a write to a client that has gone returns `-EPIPE` instead of
terminating the server. macOS has been covered since 1.10.6.

## Status constants

The server exports the common codes: `HTTP_OK`, `HTTP_NO_CONTENT`,
`HTTP_MOVED_PERMANENTLY`, `HTTP_FOUND`, `HTTP_NOT_MODIFIED`,
`HTTP_BAD_REQUEST`, `HTTP_UNAUTHORIZED`, `HTTP_FORBIDDEN`, `HTTP_NOT_FOUND`,
`HTTP_METHOD_NOT_ALLOWED`, `HTTP_REQUEST_TIMEOUT`, `HTTP_PAYLOAD_TOO_LARGE`,
`HTTP_INTERNAL`, `HTTP_NOT_IMPLEMENTED`, `HTTP_SERVICE_UNAVAILABLE`.

## Slowloris guard

Two bounds, both on by default:

- **Per read — `idle_ms`** (default 30 s, Go's `net/http.Server.IdleTimeout`):
  `SO_RCVTIMEO` on each accepted connection. A peer that stops sending is dropped.
- **Whole request — `request_ms`** (default 60 s, since 1.10.7): from accept to a
  complete request, the TLS handshake included. A peer that keeps sending one byte
  just inside every read timeout never trips `idle_ms`, and through 1.10.6 it held
  a serve loop or a pooled worker indefinitely. Past the budget a plaintext request
  is answered `408 Request Timeout` and closed; a TLS connection is closed (the
  session has failed, so nothing can be written on it). `0` disables it.

```
var opts = sandhi_server_options_new();
sandhi_server_options_idle_ms(opts, 10000);     # 10 s per read
sandhi_server_options_request_ms(opts, 30000);  # 30 s for the whole request
sandhi_server_run_opts(addr, port, handler_fp, ctx, opts);
```

A legitimate client has to deliver its whole request inside `request_ms`, so a
server that raises `max_request` for large uploads over slow links should raise
`request_ms` with it. On agnos, which has no poll, only the TLS half of the budget
applies.

## Built-in smuggling defenses

Before calling your handler, the accept loop refuses requests that carry any of:

- Both `Content-Length` AND `Transfer-Encoding: chunked` (CL.TE smuggling, RFC
  7230 §3.3.3).
- Duplicate `Host` / `Content-Length` / `Transfer-Encoding` headers (CL.CL /
  Host.Host / TE.TE smuggling, RFC 7230 §3.3.2 / §5.4).

On either, the server replies `400 Bad Request` directly and your handler
never runs. No consumer code needed.

## Options

`sandhi_server_options_new()` gives every field its default; the `_run_opts` /
`_run_async` / `_run_pooled` / `_run_tls` / `_run_pooled_tls` loops take the struct.

- `sandhi_server_options_idle_ms(opts, ms)` — per-read timeout (default 30000).
- `sandhi_server_options_request_ms(opts, ms)` — whole-request budget from accept
  (default 60000; 0 disables). 1.10.7.
- `sandhi_server_options_max_request(opts, n)` — largest request buffered, headers
  plus body (default 64 KiB; larger is answered 413). A memory knob: one buffer per
  pooled worker or in-flight async connection.
- `sandhi_server_options_max_conns(opts, n)` — worker threads for `_run_pooled` /
  `_run_pooled_tls`, per-drain cap for `_run_async` (default 128).
- `sandhi_server_options_backlog(opts, n)` — listen backlog and pooled handoff depth
  (default 128).
- `sandhi_server_options_req_arena(opts, n)` — a per-request arena of `n` bytes for
  each pooled worker, plaintext and (since 1.10.7) TLS, rewound before every
  request. The router handlers use it automatically; your own handler reaches it
  through `sandhi_server_request_arena()` and the `_a` helpers. Default 0 (off).
- `sandhi_server_options_tls(opts, cert, cert_len, key, key_len)` — server
  credentials for the `_tls` loops. A **DER** key avoids a per-handshake decode: the
  stdlib decodes a PEM key on every accept and keeps ~120 B of it on the global heap
  each time (filed cyrius-side).
- `sandhi_server_options_stop_flag(opts, &flag)` — a word the loops re-read; non-zero
  stops the server.

