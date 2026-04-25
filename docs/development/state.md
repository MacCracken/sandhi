# sandhi — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable); this file is **state** (volatile). Add release-hook wiring when the repo's release workflow lands.

## Version

**0.9.8** — 2026-04-25. **HPACK Huffman encode.** Wire-size optimization for outgoing h2 header blocks. ADR 0005 freeze respected (no new public verbs; `sandhi_hpack_huffman_encoded_len` + `sandhi_hpack_huffman_encode` are part of the HPACK internals layer that consumers never touch directly). `src/http/h2/huffman.cyr` gains a 257-entry symbol→(code, length) lookup table built at init time alongside the existing decode tree (one alloc, populated from the same hex blob). `_hpack_string_encode` in `hpack.cyr` probes Huffman size first via `sandhi_hpack_huffman_encoded_len` and picks Huffman when strictly shorter than raw — text headers compress 25-30%, short binary tokens stay raw. Encoder validated byte-exact against the RFC 7541 C.4.1 reference vector (`"www.example.com"` → `f1e3c2e5f23a6ba0ab90f4ff`) via the new `test_hpack_huffman_encode_www_example` h2 test. **649 assertions green** (482 sandhi + 167 h2; +14 from the new encode test, two existing literal-encode tests updated to assert Huffman wire-byte counts instead of raw).

**0.9.7** — 2026-04-25. **`TE: trailers` request signaling.** Outgoing-side counterpart to the 0.9.4 response trailer parser. ADR 0005 freeze respected (no new public verbs). (1) `src/http/client.cyr` — `_sandhi_client_build_request_v` auto-injects `TE: trailers\r\n` after `Accept-Encoding: identity\r\n` and before user headers, override-preserving via `sandhi_headers_has(user_headers, "TE")`. (2) `src/http/h2/request.cyr` — `_h2_header_is_forbidden(name)` → `_h2_header_is_forbidden(name, value)`; `te` is allowed iff value is "trailers" (whitespace-tolerant, ci) per RFC 7540 §8.1.2.2 (which is the only TE value h2 permits). New helper `_h2_te_value_is_trailers`. The h2 encoder also auto-emits `te: trailers` when caller didn't set TE, mirroring the 1.1 builder. Five 1.1 builder-test expectations updated to include the new TE line; standalone `programs/_te_trailers_probe.cyr` covers TE-override + h2 te:gzip-drop + h2 te:trailers-allow paths the test suite has no fixup-table room for. **635 assertions green** (482 sandhi + 153 h2; no regression).

**0.9.6** — 2026-04-25. **ALPN-driven h2 auto-promotion.** First release where live h2 fires end-to-end via the auto-dispatcher — no consumer code change. ADR 0005 freeze respected (no new public verbs). `src/http/h2/dispatch.cyr` gains `_sandhi_http_try_h2_promote`: when `_sandhi_http_auto_once` finds no h2 conn in the pool for a TLS route AND the 1.1 slot is also empty for that route (peek via new `_sandhi_pool_has_idle` in `pool.cyr`), it opens a fresh conn with `_sandhi_alpn_advertise_h2 = 1` to advertise `h2,http/1.1`. Post-handshake, `sandhi_conn_alpn_is_h2` decides: h2 → preface + SETTINGS + `sandhi_http_pool_put_h2` cache, dispatch via `sandhi_h2_request`; 1.1 → conn donated to the 1.1 pool slot via `_sandhi_pool_put` so the immediate `_sandhi_http_do` reuses it (no wasted handshake). The has-idle peek prevents repeat-promote bleed when a 1.1-only server is at the other end. Promotion is gated on TLS + pool-attached: plain HTTP has no ALPN, no-pool requests don't amortize h2's preface/SETTINGS overhead. **635 assertions green** (482 sandhi + 153 h2; no regression).

**0.9.5** — 2026-04-25. **h2 redirect-following + retry-through-auto.** Two internal wire-up commits, ADR 0005 freeze respected (no new public verbs). (1) `src/http/h2/dispatch.cyr` — redirect logic hoisted to the auto layer: new `_sandhi_http_auto_once` (per-hop: take h2 from pool, else 1.1 single-shot via `_sandhi_http_do`) + `_sandhi_http_auto_follow` (mirrors `_sandhi_http_follow` semantics — https→http refusal, cred-strip on cross-authority, 303→GET — but each hop re-evaluates h2 selection, so a redirect from authority A to authority B uses h2 if the pool has it for B). Side effect: the 1.1 fallback path used to follow inside `_sandhi_http_dispatch` and stayed on 1.1 across the chain; now redirects ride the auto layer. (2) `src/http/retry.cyr` — `_sandhi_http_retry` calls `sandhi_http_request_auto` instead of `_sandhi_http_dispatch`, so `sandhi_http_get_retry` / `_head_retry` / `_put_retry` / `_delete_retry` inherit h2 selection when the pool has an h2 conn. **635 assertions green** (482 sandhi + 153 h2; no regression). Helpers used by the new code (`_sandhi_is_redirect`, `_sandhi_resolve_location`, `_sandhi_url_same_authority`, `_sandhi_url_is_https_downgrade`, `_sandhi_strip_sensitive_headers`) are already covered by the 0.9.0 P0 redirect tests.

**0.9.4** — 2026-04-25. **Versioning refactor + chunked response trailers.** No new public verbs (ADR 0005 freeze respected). (1) Versioning collapsed to one auto-generated source — new `scripts/version-bump.sh` regenerates `src/version_str.cyr` (auto-generated, committed; the only place `SANDHI_VERSION` is declared); CI re-runs the bump script and `git diff --quiet src/version_str.cyr` for drift detection. Mirrors the cyrius repo's own `scripts/version-bump.sh` + `src/version_str.cyr` pattern. Probe programs and test files updated to `include "src/version_str.cyr"` ahead of `src/error.cyr`. (2) `src/http/response.cyr` — chunked-body decoder parses RFC 7230 §4.1.2 trailers after the terminal 0-chunk and merges allowed fields into the response headers (visible via existing `sandhi_http_headers(r)` accessor — no new public verb). Forbidden trailers (Transfer-Encoding, Content-Length, Host, Authorization, Set-Cookie, Cache-Control, Expect, Max-Forwards, Pragma, Range, TE, Trailer) are filtered as smuggling vectors. **635 assertions green** (482 sandhi + 153 h2). Trailer-parser verification lives in `programs/_trailers_probe.cyr` rather than the test suite — `tests/sandhi.tcyr` is at the per-program fixup cap (architecture/001).

**0.9.3** — 2026-04-25. **TLS runtime wire-up.** Internal-only fill of two surfaces that shipped stubbed in 0.8.x / 0.9.x — no new public verbs (ADR 0005 freeze respected). `tls_policy/apply.cyr` resolves nine libssl/libcrypto symbols via stdlib `tls_dlsym` and runs them through a `tls_connect_with_ctx_hook` callback (ALPN advertise + trust-store override + mTLS cert/key load) plus a post-handshake SPKI extraction (X509_get_pubkey + i2d_PUBKEY → SHA-256 → constant-time hex compare). `tls_policy/alpn.cyr`'s `_selected` / `_is_h2` accessors read a new `SANDHI_CONN_OFF_ALPN_DATA` slot on the conn struct (struct 24 → 32 bytes). `sandhi_http_get("https://example.com/")` returns 200 / 528 bytes. Toolchain pin bumped 5.6.30 → 5.6.41 across the day; libssl-pthread / ALPN-hook / 7-arg-frame-segfault all resolved upstream. **634 assertions green (481 sandhi + 153 h2; two existing tests rewritten to reflect wired-up state).**

**0.9.2** — 2026-04-24. **Pre-fold closeout.** Server symbol rename: every public `http_*` function in `src/server/mod.cyr` renamed to `sandhi_server_*` for consistency with the rest of the sandhi surface. Transitional `http_*` aliases retained through 0.9.x — all 23 affected names get thin tail-call wrappers; aliases drop at 1.0.0 (v5.7.0 fold). First formal `dist/sandhi.cyr` bundle via `cyrius distlib` — 8564 lines / 335 KB / `Version: 0.9.2` header. Surface-freeze policy added to CLAUDE.md as a hard constraint: no new public verbs land between 0.9.2 and 1.0.0; fold ships everything permanently into stdlib. **634 assertions green (481 sandhi + 153 h2; +2 server-rename regression).**

**0.9.1** — 2026-04-24. **Phase 2 security sweep** — 7 P1 hardening fixes from the 0.7.0 audit. (1) URL port digit-count cap (5 max). (2) Header CRLF/NUL validation in `add`/`set`. (3) Strict CL parse — `"10, 20"` rejected, `+10` rejected, comma-or-non-digit fails. (4) SPKI constant-time compare via XOR accumulator. (5) SSE id-with-NUL ignored per WHATWG. (6) Header duplicate detection (Host / CL / TE) on both client and server. (7) SSE re-entrance fix — parser state moved from module-scope globals into a per-call ctx struct (~40 bytes); nested `sandhi_sse_parse` calls are now independent. P2 #21 (JSON escape state) traced and cleared — audit was incorrect, no fix needed. **632 assertions green (479 sandhi + 153 h2; +17 over 0.9.0).**

**0.9.0** — 2026-04-24. **Phase 1 security sweep** — five P0 fixes from the 0.7.0 audit, each with a focused regression test. (1) Chunked decoder requires terminal 0-chunk + `seen_digit` guard, sizes >2^31 rejected. (2) CL+TE coexistence rejected on both client (`SANDHI_ERR_PROTOCOL`) and server (400) per RFC 7230 §3.3.3 — closes CL.TE / TE.CL smuggling. (3) Chunk-size overflow guard caps at `i31`. (4) Redirect cross-origin strips `Authorization` / `Cookie` / `Proxy-Authorization`; https→http downgrades refused outright. (5) TLS-policy fail-closed when policy demands `pinned` / `mtls` / `trust_store` enforcement that isn't actually wired. **Two visible behavior changes** (semver minor): cred-strip on redirects + pinned-without-enforcement now errors instead of silently downgrading. **615 assertions green (462 sandhi + 153 h2; +16 over 0.8.1's 599).**

**0.8.1** — 2026-04-24. Auto-selection wiring. New `sandhi_http_request_auto` (+ per-method `_get_auto` / `_head_auto` / etc.) in `src/http/h2/dispatch.cyr` checks the attached pool for an h2 conn matching the URL's route; if found, dispatches via `sandhi_h2_request`; otherwise falls through to `_sandhi_http_dispatch` (1.1 path with redirects/retry/timeouts). Strictly additive — no existing call-site behavior changes. Filed `docs/issues/2026-04-24-stdlib-tls-alpn-hook.md` for the stdlib upstream-ask: `tls_connect` needs an SSL_CTX hook so sandhi can call `SSL_CTX_set_alpn_protos` to advertise h2. When that lands + libssl-pthread-deadlock clears, auto-selection starts firing without any consumer change. **599 assertions stable (no regression).**

**0.8.0** — 2026-04-24. **HTTP/2 + connection pool** in 8 commit-sized bites (Bite 1 = pool + 1.1 keep-alive; Bites 2+2b = HPACK + Huffman decode; Bite 3 = h2 frames; Bite 4 = ALPN surface; Bites 5a/5b/5c = h2 conn lifecycle / request send / response decode; Bite 6 = pool h2 glue; Bite 7 = public `sandhi_h2_request` verb + version ship). 599 total assertions (446 sandhi + 153 h2; up from 0.7.3's 411). h2 protocol stack functionally complete in synthetic tests; HPACK Huffman correct on RFC C.4.1. **Two known limitations carried as 0.8.1 work**: (a) live h2 talk is gated on the libssl-pthread-deadlock blocker, so `sandhi_http_get` continues to use HTTP/1.1 — consumers wanting h2 today open the conn manually and call `sandhi_h2_request(h2c, ...)` directly; (b) ALPN runtime is stubbed (wire-format encoder ships, OpenSSL hookup pending). Bite 7 + ALPN runtime + Huffman encode all land together in 0.8.1.

**0.7.3** — 2026-04-24. Closes the two timeout deferrals from 0.7.2: `connect_ms` (non-blocking connect via `O_NONBLOCK` + `poll(POLLOUT)` + `getsockopt(SO_ERROR)`) and `total_ms` (monotonic deadline via `clock_now_ms`, threaded through every I/O phase). Local syscall constants for `SYS_POLL=7` / `SYS_GETSOCKOPT=55` defined in `conn.cyr` (Linux x86_64; aarch64 needs a cross-cutting pass when it lands). Module-level `_sandhi_conn_last_err` classifies open failures so callers can distinguish `SANDHI_ERR_TIMEOUT` from `SANDHI_ERR_CONNECT` / `_TLS` precisely. New `sandhi_conn_recv_all_deadline` variant for `total_ms` enforcement on the recv loop. Options struct grew 40→56 bytes. Per-hop `total_ms` semantics (each redirect hop gets its own budget) — documented; end-to-end-across-redirects waits for an actual ask. **411 test assertions green (+16 on 0.7.2)**, including two live-network TEST-NET-1 blackhole tests that verify connect_ms + total_ms fire within a 5 s budget against an unrouted destination.

**0.7.2** — 2026-04-24. Reliability + observability patch. `sandhi_http_options` gained `read_ms` / `write_ms` (via SO_RCVTIMEO / SO_SNDTIMEO through direct `SYS_SETSOCKOPT`; `SANDHI_ERR_TIMEOUT` now actually fires). New `src/http/retry.cyr` — `sandhi_http_get_retry` / `_head_retry` / `_put_retry` / `_delete_retry` for idempotent methods; exponential backoff; retries on CONNECT/TIMEOUT/DISCOVERY/5xx. `src/net/resolve.cyr` hardened — random TXID via `/dev/urandom`, answer-name match via new `_sandhi_resolve_name_eq` (follows compression pointers, case-insensitive, 32-hop guard), P1 security items pulled forward. New `sandhi_resolve_ipv6` AAAA resolver (client-side v6 connect wiring deferred). New `src/obs/trace.cyr` — opt-in sakshi spans at the three boundaries (`sandhi.http`, `sandhi.dns.v4`/`.v6`, `sandhi.rpc`); silent by default. `src/server/mod.cyr` grew options struct + `http_server_run_opts` with per-connection SO_RCVTIMEO (slowloris guard; default 30 s). **395 test assertions green (+61 on 0.7.1)**. Deferred from 0.7.2: `connect_ms`/`total_ms` (need non-blocking connect + deadlines; 0.7.3), connection pool (→ 0.8.0 with HTTP/2), Happy Eyeballs (post-v1), client-side v6 connect (awaits consumer ask).

**0.7.1** — 2026-04-24. Quick-wins patch from the 0.7.0 external security + gaps review. Default `User-Agent: sandhi/<version>` + `Accept-Encoding: identity` request headers (override-preserving). New `sandhi_http_options_max_response_bytes` field caps both the buffered-client scratch and the streaming buffers (via new `sandhi_http_stream_opts` variant). New `err_message` slot on the response struct (reserved for 0.8.x security diagnostics; struct grows 40→48 bytes). CI `workflow_call` trigger added so `release.yml` can reuse `ci.yml`. `src/main.cyr` docstring corrected. All 333 test assertions remain valid (new surface not yet asserted; tests added alongside the 0.8.x security pass). Planning: roadmap rewrites for 0.7.2 medium items, 0.8.0 HTTP/2, 0.8.x P0 sweep, 0.9.x P1 + closeout, 1.0.0 fold, post-v1 defer list.

**0.7.0** — M3.5 closed 2026-04-24. SSE streaming + incremental chunked decode. `sandhi_http_stream(url, method, headers, body, body_len, cb, ctx)` drives a callback per parsed event; WHATWG-compliant SSE parser; MCP-over-SSE via `sandhi_rpc_mcp_stream`. Also carries the stdlib-deps audit (added `mmap`/`dynlib`/`fdlopen`/`bigint`/`freelist`) that unstuck the HTTPS investigation, and the toolchain pin bump to 5.6.30. 333 test assertions green.

**0.6.0** — M5 closed 2026-04-24. TLS-policy surface: policy struct + constructors (`default` / `pinned` / `mtls` / `trust_store`), additive `combine`, SPKI fingerprint format helpers (normalize, compare, encode, byte-length), `sandhi_conn_open_with_policy` integration point. Runtime enforcement stubbed pending the stdlib TLS-init fix — `sandhi_tls_policy_enforcement_available() == 0` surfaces the stub state. 291 test assertions green.

**0.5.0** — M4 closed 2026-04-24. Service discovery: service + resolver types, chain fallback (first-hit wins, no resolver load-bearing), daimon-backed HTTP resolver, mDNS interface (impl-stubbed pending multicast primitives in stdlib net.cyr), register/deregister. 250 test assertions green.

**0.4.0** — M3 closed 2026-04-24. JSON-RPC dialect layer: nested JSON builder + dotted-path extractor, JSON-over-HTTP transport with dialect-aware error envelopes, W3C WebDriver surface (sessions + navigation + element interaction + script execution), Appium extensions (context switching + app lifecycle + mobile exec), MCP-over-HTTP transport (envelope only; protocol semantics stay in bote/t-ron per ADR 0001). 215 test assertions green.

**0.3.0** — M2 closed 2026-04-24. Full HTTP client (POST/PUT/DELETE/PATCH/HEAD/GET), response parser (Content-Length + chunked + close-delimited), opt-in bounded redirect following, native UDP DNS resolver (RFC 1035 A-record queries, `/etc/resolv.conf` + 8.8.8.8 fallback). 173 test assertions green; live `programs/http-probe.cyr http://example.com/` returns 200. HTTPS runtime flagged as known-issue (see `docs/issues/2026-04-24-fdlopen...`).

**0.2.0** — M1 closed 2026-04-24. `lib/http_server.cyr` lift-and-shift into `src/server/mod.cyr` done verbatim (478 lines, no behavior change). sandhi's `cyrius.cyml` dropped `http_server` from `[deps.stdlib]`; smoke exercises the migrated symbols; pure-helper unit tests added (28 assertions green).

**0.1.0** — scaffolded 2026-04-24 via `cyrius init sandhi` + library-shape manifest tuning. Module skeletons + ADR 0001 + compile-link smoke program landed first; no real implementation yet. Named 2026-04-24 after confirming the planned "services" crate in two roadmaps had never received a proper name.

## Toolchain

- **Cyrius pin**: `5.6.41` (in `cyrius.cyml [package].cyrius`)

## Fold-into-stdlib status

**Pre-fold, target at Cyrius v5.7.0** as a clean-break fold per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md). Revised from the original "before v5.6.x closeout" target. Follows the sakshi / mabda / sankoch / sigil precedent (sibling crate → fold), but with one twist: no stdlib-side alias window. 5.6.YY emits a deprecation warning on `include "lib/http_server.cyr"`; 5.7.0 deletes it and adds `lib/sandhi.cyr` vendored from `dist/sandhi.cyr`.

M2–M5 must land pre-5.7.0 — the fold freezes the public surface.

## Source

Server module + full HTTP client surface + DNS resolver are live; RPC / discovery / tls_policy still scaffold.

| Module | Lines | Status |
|--------|-------|--------|
| `src/main.cyr` | 48 | public API declarations — docstring refreshed at 0.7.1; version bumped 0.7.2 |
| `src/http/retry.cyr` | 152 | **0.7.2 new** — retry-with-backoff wrappers for idempotent methods (GET/HEAD/PUT/DELETE). Exponential 2× capped at max_backoff_ms. 0.9.3: AWS-style full-jitter sleep replaces fixed-exponential (thundering-herd guard). 0.9.5: `_sandhi_http_retry` routes through `sandhi_http_request_auto` so retries inherit h2 selection when the pool has an h2 conn for the route. |
| `src/http/h2/dispatch.cyr` | 273 | **0.8.1 new** — `sandhi_http_request_auto` (per-method `_get_auto` / `_head_auto` / `_post_auto` / `_put_auto` / `_patch_auto` / `_delete_auto`). Pool h2-take → 1.1 single-shot fallback. 0.9.5: redirect-following hoisted to this layer — new `_sandhi_http_auto_once` (per-hop dispatch) + `_sandhi_http_auto_follow` (mirrors 1.1 follow's security semantics; each hop re-evaluates h2 selection). 0.9.6: ALPN-driven h2 auto-promotion — `_sandhi_http_try_h2_promote` opens advertising `h2,http/1.1`, runs preface + SETTINGS on h2-pick and caches via `sandhi_http_pool_put_h2`, donates conn to 1.1 pool slot on http/1.1-pick. First release where live h2 fires end-to-end via the auto path. |
| `src/obs/trace.cyr` | 57 | **0.7.2 new** — opt-in sakshi-span wrapper. Default off; `sandhi_trace_enable(1)` turns on emission. Boundary spans: `sandhi.http` / `sandhi.dns.v4` / `sandhi.dns.v6` / `sandhi.rpc`. |
| `src/error.cyr` | 33 | scaffold — error kinds defined |
| `src/http/headers.cyr` | 258 | **M2 done** — key-value store, case-insensitive lookup, wire-format serialize + parse |
| `src/http/url.cyr` | 193 | **M2 done** — http/https parser with CRLF hardening |
| `src/http/conn.cyr` | 338 | **M2 done** — tagged plain/TLS connection abstraction. 0.7.2: `sandhi_conn_open_timed` + SO_RCVTIMEO/SO_SNDTIMEO helpers; EAGAIN surfaced as `0 - _SANDHI_EAGAIN`. 0.7.3: non-blocking connect via `_sandhi_conn_connect_nb` (O_NONBLOCK + poll + SO_ERROR); `sandhi_conn_open_fully_timed`; `sandhi_conn_recv_all_deadline`; module-level `_sandhi_conn_last_err` for failure classification. |
| `src/http/response.cyr` | 310 | **M2 done** — Content-Length + chunked + close-delimited body framing. 0.7.1: `err_message` slot added (struct 40→48). |
| `src/net/resolve.cyr` | 557 | **M2 done** — native UDP DNS (RFC 1035). 0.7.2: random TXID via `/dev/urandom`; `_sandhi_resolve_name_eq` with compression-pointer following + 32-hop guard; answer-name match against question in the A + AAAA parsers; new `sandhi_resolve_ipv6` + `_sandhi_resolve_build_query_aaaa` + `_sandhi_resolve_parse_response_aaaa`; trace-wrap on both public verbs. Four P1 security items pulled forward from 0.9.x. |
| `src/http/client.cyr` | 487 | **M2 done** — POST/PUT/DELETE/PATCH/HEAD/GET, redirect following, options struct. 0.7.1: default UA + `Accept-Encoding: identity`; options gained `max_response_bytes`. 0.7.2: options gained `read_ms` / `write_ms`; `SANDHI_ERR_TIMEOUT` now raised; trace-wrap around `_sandhi_http_do`. 0.7.3: options gained `connect_ms` / `total_ms` (struct 40→56); `_sandhi_http_clamp_ms` deadline helper; per-hop budget for redirects. |
| `src/http/sse.cyr` | 244 | **M3.5 done** — WHATWG SSE event parser |
| `src/http/stream.cyr` | 440 | **M3.5 done** — streaming HTTP + incremental chunked decoder + callback-per-event dispatch. 0.7.1: `sandhi_http_stream_opts` honors `max_response_bytes`. 0.7.2: also honors `read_ms`/`write_ms`; EAGAIN→TIMEOUT in read+body loops. 0.7.3: connect_ms + total_ms threaded via `sandhi_conn_open_fully_timed` + per-recv deadline check in body loop. |
| `src/rpc/json.cyr` | 365 | **M3 done** — nested JSON build + dotted-path extract |
| `src/rpc/dispatch.cyr` | 186 | **M3 done** — JSON-over-HTTP + dialect-aware error envelopes. 0.7.2: trace-wrap on `sandhi_rpc_call` / `_with_headers`. |
| `src/rpc/webdriver.cyr` | 231 | **M3 done** — W3C WebDriver surface (sessions, navigation, elements, exec) |
| `src/rpc/appium.cyr` | 139 | **M3 done** — Appium extensions (contexts, app lifecycle, mobile exec) |
| `src/rpc/mcp.cyr` | 104 | **M3 done** — MCP-over-HTTP transport (JSON-RPC 2.0 envelope) |
| `src/rpc/mod.cyr` | 17 | dialect-index module |
| `src/discovery/service.cyr` | 75 | **M4 done** — service + resolver type vocabulary |
| `src/discovery/chain.cyr` | 61 | **M4 done** — fallback sequence of resolvers |
| `src/discovery/daimon.cyr` | 116 | **M4 done** — HTTP-backed resolver against daimon registry |
| `src/discovery/local.cyr` | 70 | **M4 partial** — interface shipped; lookup stubbed (awaiting net.cyr multicast) |
| `src/discovery/register.cyr` | 55 | **M4 done** — publish/withdraw via daimon |
| `src/discovery/mod.cyr` | 24 | dialect-index module |
| `src/tls_policy/policy.cyr` | 173 | **M5 done** — policy struct + constructors + combine |
| `src/tls_policy/fingerprint.cyr` | 102 | **M5 done** — SPKI hex normalize / compare / encode helpers |
| `src/tls_policy/apply.cyr` | 91 | **M5 partial** — surface shipped; enforcement stubbed (awaiting stdlib TLS-init) |
| `src/tls_policy/mod.cyr` | 28 | dialect-index module |
| `src/server/mod.cyr` | 546 | **M1 done** — verbatim lift from `lib/http_server.cyr`. 0.7.2: `sandhi_server_options_*` struct + `http_server_run_opts` variant; per-connection SO_RCVTIMEO (slowloris guard; 30 s default). `max_conns` option defined but not enforced — concurrent accept model lands 0.8.0. |

Build outputs:
- `build/sandhi-smoke` — link-proof smoke program.
- `build/dns-probe` — ad-hoc live DNS check (not part of test suite; `cyrius run programs/dns-probe.cyr <host>`).
- `build/http-probe` — ad-hoc live HTTP round-trip (`cyrius run programs/http-probe.cyr <url>`). Plain HTTP works end-to-end; HTTPS known-issue (TLS init).

Planned `dist/sandhi.cyr` bundle via `cyrius distlib` — can now be produced any time (M1 complete); first formal bundle pairs with M6 fold prep.

## Tests

- `tests/sandhi.tcyr` — **482 assertions green** across the public surface: headers / URL / response / client / redirect (P0-hardened: cred-strip cross-authority, https→http refusal, 303→GET) / DNS / RPC dialects / discovery / TLS policy + fingerprint / SSE / streaming. File is at the per-program fixup cap (architecture/001) — additional verification lands as `programs/_*_probe.cyr` standalone probes (e.g., `_trailers_probe.cyr` covers RFC 7230 §4.1.2 trailer parsing).
- `tests/h2.tcyr` — **153 assertions green** for HTTP/2: HPACK static table + Huffman (RFC 7541 C.4.1) / frame wire format (SETTINGS / PING / WINDOW_UPDATE / RST_STREAM / GOAWAY / HEADERS) / connection lifecycle / request-encode + roundtrip / response-decode / pool routing.
- **649 total** as of 0.9.8 (`sandhi.tcyr` 482 + `h2.tcyr` 167; the +14 are encoder-side bytes for the RFC 7541 C.4.1 reference vector).

## Dependencies

Declared in `cyrius.cyml` (all Cyrius stdlib):

- **Core**: `syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`, `vec`, `args`, `hashmap`, `process`, `thread`, `fnptr`, `chrono`, `tagged`, `assert`
- **Network primitives** (the things sandhi composes): `net`, `http`, `tls`, `ws`, `json`, `base64` — `http_server` dropped at M1 since the content now lives in `src/server/mod.cyr`.
- **Infrastructure** (already folded into stdlib): `sakshi`, `sigil`

No external git deps. sandhi is pure-stdlib-composition.

## Consumers

> **Note (2026-04-24)**: this list reflects sandhi's *aspiration* per ADR 0001 — which AGNOS crates sandhi was scaffolded to serve. Whether any specific crate has committed to consuming sandhi on its own roadmap isn't inferred from this list; it's tracked in `docs/issues/` coordination files ([index](../issues/README.md)). Each consumer / producer has a paste-ready doc the base-OS modernization pass can drop into its respective repo's roadmap. The in-progress modernization pass is the natural scheduling window.

**Aspirational (sandhi was scaffolded to serve these)**:
- **yantra** — M2+ backends (WebDriver, Appium JSON-RPC) need `sandhi::rpc`. Currently sandhi-less; CDP backend (M1) uses stdlib `ws.cyr` directly and can stay that way. Cross-repo coordination pending.
- **sit** — remote clone/push/pull once the local VCS is done
- **ark** — remote registry ops
- **hoosh** — LLM provider routing
- **ifran** — same shape as hoosh
- **daimon** — MCP-over-HTTP dispatch (consumer side) + registry endpoints (producer side — sandhi's `discovery/daimon.cyr` calls these; contract at [`docs/issues/2026-04-24-daimon-registry-endpoints.md`](../issues/2026-04-24-daimon-registry-endpoints.md))
- **mela** — marketplace API
- **vidya** — any external-knowledge fetch path (future)

**Not consumers** (deliberately):
- daimon's core agent orchestration (daimon owns that)
- bote / t-ron (MCP protocol semantics stay there)
- sigil (sandhi uses sigil for cert fingerprints; does not reimplement crypto)

## Migration status

- `lib/http_server.cyr` — **sandhi-side lift-and-shift complete** (v0.2.0). Canonical implementation now at `src/server/mod.cyr`; sandhi's own build pulls the module directly and no longer depends on stdlib `http_server`.
- **No stdlib-side alias.** Per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md), stdlib keeps `lib/http_server.cyr` unchanged through the 5.6.x window, emits a deprecation warning in 5.6.YY releases, and deletes it outright at v5.7.0 as the `lib/sandhi.cyr` fold lands in the same release. This is a cyrius-agent-side change; sandhi repo is unaffected.

## Next

Release sequence toward v5.7.0 fold (see `roadmap.md` for full detail):

- **0.7.1** ✅ — quick-wins from the 0.7.0 review
- **0.7.2** ✅ — reliability + observability: read/write timeouts, retry wrappers, DNS hardening (incl. 4 P1 security items pulled forward), AAAA resolver, opt-in sakshi spans, server idle-timeout
- **0.7.3** ✅ — `connect_ms` (non-blocking connect via O_NONBLOCK + poll + SO_ERROR) + `total_ms` (monotonic-deadline threading). Full timeout surface complete.
- **0.8.0** ✅ — HTTP/2 + connection pool (8 bites). Pool + 1.1 keep-alive, full HPACK + Huffman decode, h2 frames + lifecycle, ALPN surface (runtime stubbed), public `sandhi_h2_request` verb.
- **0.8.1** ✅ — `sandhi_http_request_auto` + per-method auto verbs. Pool h2-take → 1.1 fallback. ALPN-advertise upstream-ask filed.
- **0.9.0** ✅ — Phase 1 security: 5 P0s from the 0.7.0 audit.
- **0.9.1** ✅ — Phase 2 P1 sweep: 7 hardening fixes.
- **0.9.2** ✅ — Pre-fold closeout: server `http_*` → `sandhi_server_*` rename + transitional aliases, first `dist/sandhi.cyr` via `cyrius distlib`, surface freeze in CLAUDE.md.
- **0.9.3** ✅ — Stub-elimination + CI hardening. All upstream TLS blockers cleared (5.6.39/40/41); ALPN runtime + TLS policy enforcement + mDNS resolver + IPv6 client integration + bracketed IPv6 URLs + retry jitter all wired. Versioning collapsed to `SANDHI_VERSION` literal.
- **0.9.4** ✅ — Versioning refactor (auto-generated `src/version_str.cyr` via `scripts/version-bump.sh`) + chunked response trailers (RFC 7230 §4.1.2; allowed-list filtering against smuggling vectors).
- **0.9.5** ✅ — h2 redirect-following hoisted to the auto layer (re-evaluates h2 per hop) + retry routing through `sandhi_http_request_auto` (retries inherit h2 selection).
- **0.9.6** ✅ — ALPN-driven h2 auto-promotion via `_sandhi_http_try_h2_promote`: open advertising `h2,http/1.1`, branch on `sandhi_conn_alpn_is_h2` (h2 → preface/SETTINGS/cache; 1.1 → donate to pool's 1.1 slot via `_sandhi_pool_has_idle`-gated put). First release where live h2 fires end-to-end via the auto path.
- **0.9.7** ✅ — `TE: trailers` request signaling on both 1.1 and h2 paths; h2 forbidden filter loosened to allow `te: trailers` (the one value RFC 7540 §8.1.2.2 permits) while still dropping other TE values like `te: gzip`.
- **0.9.8** ✅ (this release) — HPACK Huffman encode wired into `_hpack_string_encode`. Encoder picks Huffman over raw when strictly shorter; byte-exact against the RFC 7541 C.4.1 reference vector.
- **0.9.9** — Internal P1 self-audit pass before fold (last chance to fix surface bugs).
- **1.0.0** — fold event @ Cyrius v5.7.0. stdlib gets `lib/sandhi.cyr` vendored from `dist/sandhi.cyr`; stdlib deletes `lib/http_server.cyr` per ADR 0002 clean-break fold.

**Under-v1 milestone back-matter**:

All M2–M5 must land before the Cyrius v5.7.0 fold event (public surface freezes at fold per ADR 0002).

1. ~~**M1 — `lib/http_server.cyr` lift-and-shift.**~~ ✅ landed 2026-04-24 (v0.2.0).
2. ~~**M2 — `sandhi::http::client` real implementation.**~~ ✅ landed 2026-04-24 (v0.3.0). HTTPS runtime still blocked on stdlib TLS-init (see issue doc); compiles clean, runs fine over plain HTTP.
3. ~~**M3 — `sandhi::rpc` WebDriver + Appium + MCP.**~~ ✅ landed 2026-04-24 (v0.4.0).
3.5. ~~**M3.5 — SSE streaming.**~~ ✅ landed 2026-04-24 (v0.7.0). WHATWG SSE parser, incremental chunked decode, callback-per-event dispatch, MCP-over-SSE wrapper. Verified against synthetic byte streams; live-HTTPS SSE waits on the libssl pthread-lock fix like every other HTTPS path.
4. ~~**M4 — `sandhi::discovery` chain resolver + daimon integration.**~~ ✅ landed 2026-04-24 (v0.5.0). Service + resolver vocabulary, chain fallback, daimon HTTP resolver, register/deregister. **Cross-repo**: daimon-side registry endpoints are specified but not yet committed to daimon's roadmap — coordination doc at `docs/issues/2026-04-24-daimon-registry-endpoints.md`. mDNS lookup stubbed — impl awaits multicast primitives in stdlib net.cyr.
5. ~~**M5 — `sandhi::tls_policy` cert pinning + mTLS.**~~ ✅ **surface** landed 2026-04-24 (v0.6.0). Policy constructors, fingerprint helpers, `sandhi_conn_open_with_policy` integration point all shipped + unit-tested. **Enforcement stubbed** pending stdlib TLS-init fix — filling in is a focused ~50-line patch (exact OpenSSL calls enumerated in `src/tls_policy/apply.cyr` TODO list). Native TLS transition at Cyrius v5.9.x is a transport swap beneath this policy surface — no consumer-facing API change.
6. **Fold-into-stdlib at v5.7.0** — one event: stdlib deletes `lib/http_server.cyr`, adds `lib/sandhi.cyr`, consumers migrate their includes in the same release. 5.6.YY releases carry the deprecation warning. Checked at the Cyrius release gate, not in this repo.

Receipts-oriented: sandhi's fold-into-stdlib moment is the anchor for a short-form article ("sandhi folded — the service-boundary layer has a home") in the same micro-article shape as [what-5.5.x-taught-5.6.x.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/what-5.5.x-taught-5.6.x.md) and [micro-work-and-agent-deferment.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md). Outlined at fold time, not before.
