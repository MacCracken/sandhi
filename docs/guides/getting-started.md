# Getting started

Smallest possible HTTP GET with sandhi.

## Build / test

```bash
cyrius deps                                               # resolve stdlib deps
cyrius build programs/smoke.cyr build/sandhi-smoke       # link proof
cyrius test src/test.cyr                                  # unit tests
cyrius lint src/*.cyr                                     # static checks
```

`programs/smoke.cyr` is the build/link proof, not a CLI. sandhi is a library — your
consumer program includes the sandhi module chain (see the `include` block at the
top of `programs/smoke.cyr` for the full list, or mirror `[lib].modules` from
`cyrius.cyml`) and calls into it from `fn main()`.

## Simplest GET

```
include "src/error.cyr"
# ... (full include chain — see programs/smoke.cyr)
include "src/main.cyr"

fn main() {
    alloc_init();

    var resp = sandhi_http_get("http://example.com/", 0);

    if (sandhi_http_err_kind(resp) != SANDHI_OK) {
        # Transport / parse / TLS failure. No status, no body.
        return 1;
    }

    var status = sandhi_http_status(resp);
    var body = sandhi_http_body(resp);
    var blen = sandhi_http_body_len(resp);

    # ... do something with status + body
    return 0;
}

var exit_code = main();
syscall(60, exit_code);
```

`sandhi_http_get(url, user_headers)` — pass `0` for `user_headers` when you have no
custom headers. sandhi auto-emits `Host`, `User-Agent`, `Accept-Encoding: identity`,
and `Connection: close` for you.

## Inspecting the response

Every public verb returns a `sandhi_response*`. The accessors live in
`src/http/response.cyr`:

| Accessor                    | Returns                                         |
| --------------------------- | ----------------------------------------------- |
| `sandhi_http_status(r)`     | HTTP status integer (200 / 404 / 500 / ...)     |
| `sandhi_http_body(r)`       | NUL-terminated body cstr (alloc-owned)          |
| `sandhi_http_body_len(r)`   | Body length in bytes                            |
| `sandhi_http_headers(r)`    | `sandhi_headers*` block (never 0)               |
| `sandhi_http_err_kind(r)`   | `SandhiErrorKind` — `SANDHI_OK` on success      |
| `sandhi_http_err_message(r)`| Optional context cstr, or 0                     |

Always check `sandhi_http_err_kind` first — on a transport failure (`CONNECT`,
`TLS`, `TIMEOUT`, `PARSE`, `DISCOVERY`, `PROTOCOL`) `status` will be 0 and
`body` will be 0. The error kinds are defined in `src/error.cyr`:

```
SANDHI_OK             # 0
SANDHI_ERR_PARSE      # 1 — URL or response framing malformed
SANDHI_ERR_CONNECT    # 2 — socket / TCP failure
SANDHI_ERR_TLS        # 3 — TLS handshake / policy refusal
SANDHI_ERR_TIMEOUT    # 4 — per-op deadline or total_ms fired
SANDHI_ERR_REMOTE     # 5 — reserved for server-reported errors
SANDHI_ERR_PROTOCOL   # 6 — HTTP framing / smuggling refusal
SANDHI_ERR_AUTH       # 7 — reserved
SANDHI_ERR_DISCOVERY  # 8 — DNS / service-lookup miss
SANDHI_ERR_INTERNAL   # 99
```

Call `sandhi_err_kind_name(kind)` to get a printable string ("OK", "CONNECT",
"TIMEOUT", etc.).

## Reading response headers

`sandhi_http_headers(r)` returns a header block you can query directly:

```
var h = sandhi_http_headers(resp);
var ctype = sandhi_headers_get(h, "Content-Type");  # 0 if absent
if (ctype != 0) {
    # ctype is a NUL-terminated cstr; use strlen / streq / etc.
}
```

`sandhi_headers_get` is case-insensitive. For multi-valued headers (Set-Cookie),
iterate with `sandhi_headers_count` + `sandhi_headers_name_at` + `sandhi_headers_value_at`.

## Where to go next

- `timeouts.md` — bounding every phase with `connect_ms`/`read_ms`/`write_ms`/`total_ms`
- `connection-pool.md` — keep-alive reuse when you hit the same host repeatedly
- `redirects-and-security.md` — opt-in redirect following with 0.9.0 security model
- `tls-policy.md` — pinning, mTLS, custom trust stores
- `server.md` — running an HTTP server with `sandhi_server_run`
- `http2-manual.md` — manual h2 path and `sandhi_http_request_auto` behavior

Runnable examples live in `docs/examples/`.
