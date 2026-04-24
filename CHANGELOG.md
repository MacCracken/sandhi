# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.3.0] — 2026-04-24

M2 close. Full HTTP client surface — POST/PUT/DELETE/PATCH/HEAD/GET over HTTP and HTTPS, custom headers, chunked decoding, opt-in redirect following, native DNS resolver. 173 assertions green; live HTTP round-trip to `example.com` verified end-to-end via `programs/http-probe.cyr`.

### Added
- **http/headers** (`src/http/headers.cyr`): real key-value store — `sandhi_headers_new` / `set` / `add` / `get` / `remove` / `has` / `count` / `name_at` / `value_at` / `serialize` / `parse`. Case-insensitive lookup, multi-value support (Set-Cookie etc.), wire-format CRLF serialization.
- **http/url** (`src/http/url.cyr`): URL parser for `http://` and `https://` — returns 40-byte struct with scheme, host, port, path, query. CRLF-injection hardening from the stdlib http.cyr pattern. Default ports inferred (80 / 443).
- **http/conn** (`src/http/conn.cyr`): tagged `{kind, fd, tls_ctx}` connection abstraction. `sandhi_conn_open` wraps plain TCP via net.cyr or TLS via tls.cyr; unified `_send` / `_send_all` / `_recv` / `_recv_all` / `_close`.
- **http/response** (`src/http/response.cyr`): response parser handling Content-Length, Transfer-Encoding: chunked, and connection-close framings. Response struct `{status, body_ptr, body_len, headers, err_kind}`.
- **http/client** (`src/http/client.cyr`): `sandhi_http_get` / `post` / `put` / `delete` / `patch` / `head`. Request builder with HTTP/1.1 request line, Host header, auto Content-Length for body-bearing methods, `Connection: close`. Opt-in redirect following via `sandhi_http_options_new` + `_opts` variants (RFC 7231 §6.4 method rewrite: 303 → GET, 301/302/307/308 preserve). Absolute + relative Location resolution.
- **net/resolve** (`src/net/resolve.cyr`): native UDP DNS resolver. RFC 1035 query build + response parse, `/etc/resolv.conf` nameserver discovery with 8.8.8.8 fallback, A-records only, Linux-first. Includes `sandhi_net_parse_ipv4` for numeric literals. Written because `fdlopen_getaddrinfo` is blocked at 5.6.22 (tracked in `docs/issues/2026-04-24-fdlopen-getaddrinfo-blocked.md`).
- **programs/dns-probe.cyr** + **programs/http-probe.cyr**: ad-hoc live-probe tools (not part of test suite; require network).

### Changed
- **programs/smoke.cyr**: include list expanded for the new http/* + net/* modules.
- **cyrius.cyml `[lib].modules`**: new order enforces the dependency chain (headers → url → conn → response → resolve → client).
- **src/main.cyr**: `sandhi_version()` bumped to 0.3.0.

### Known issues
- **HTTPS runtime via `lib/tls.cyr` is unstable.** Compilation is clean and `tls_policy` surface is intact, but live HTTPS round-trips trigger a re-entrant-execution symptom (`programs/http-probe.cyr https://...` prints "GET ..." hundreds of times before being killed). Candidate cause: `_tls_init` calls `dynlib_open` without the `dynlib_bootstrap_*` sequence that `lib/dynlib.cyr` documents as required for libc-dependent sidecars. Logged in `docs/issues/2026-04-24-fdlopen-getaddrinfo-blocked.md` (P8 entry). Plain HTTP works end-to-end against hostname and IP-literal URLs.
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
