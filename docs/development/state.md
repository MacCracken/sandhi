# sandhi — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable); this file is **state** (volatile). Add release-hook wiring when the repo's release workflow lands.

## Version

**1.5.2** — 2026-06-15. **1.5.x Batch C2 — AGNOS DNS-entropy gap (sit-adoption-driven C1 follow-up; no pin change, stays 6.2.6; no public-surface change).** `_sandhi_resolve_random_u16` (DNS TXID source, anti-Kaminsky) seeded its 2 random bytes from `/dev/urandom` via **bare Linux syscall numbers** (`open`=2 / `read`=0 / `close`=3) — integer literals that *compiled* on AGNOS (so C1 didn't catch it) but meant different syscalls at runtime, and agnos has no `/dev/urandom`, so the TXID silently degraded to the weak clock fallback there (DNS spoofable). Replaced with the stdlib `sys_getrandom(buf, len, 0)` syscall-selector primitive (`syscalls` dep, already declared — **no new dep, no `#ifdef`**): portable across Linux `getrandom(2)` / **AGNOS #45** (agnos 1.45.0) / macOS / Windows (macOS routes through `syscalls_linux_common.cyr`), no fs access, strict upgrade on Linux too. Portable clock-nanos fallback unchanged. **Verified**: agnos `sys_getrandom` resolves on `--agnos`; Linux runtime yields valid distinct TXIDs; every target defines the symbol; **992 assertions green** (440 + 167 + 343 + 42); lint 0/0; `cyrius fmt --check` clean; aarch64 cross-build green; `dist/sandhi.cyr` regenerated at v1.5.2. **C1 + C2 complete the sandhi-side AGNOS transport work**; remaining `--agnos` blockers are upstream-only (`mmap` `CLONE_VM` stub + native `SSL_CTX_*`, Batch A1). (Pre-existing, not C2: `programs/dns-probe.cyr` has a stale include list — references `SANDHI_PROF_PHASE_*` without including `obs/prof.cyr`; noted for cleanup.)

_(1.5.1 — 2026-06-15 — Batch C1: AGNOS socket-backend gap. Wrapped sandhi's raw socket syscalls (`src/http/conn.cyr`, `src/server/mod.cyr`) in `#ifndef CYRIUS_TARGET_AGNOS` so `cyrius build --agnos` compiles; Linux/macOS proven byte-identical. Full detail in CHANGELOG [1.5.1] + the Shipped log.)_

_(1.5.0 — 2026-06-14 — opened the 1.5.x arc: cyrius pin `6.2.1 → 6.2.6` + the aarch64 `bayan` cross-build defect fixed upstream + resolved-issue backlog archived. Full detail in CHANGELOG [1.5.0] + the Shipped log.)_

_Current release only — this file is the live snapshot. Full per-release
history (1.4.11 ← … ← 0.1.0): [`../../CHANGELOG.md`](../../CHANGELOG.md)
and the Shipped log in [`roadmap.md`](roadmap.md)._

## Toolchain

- **Cyrius pin**: `6.2.6` (`cyrius.cyml [package].cyrius`). Bump trail: 5.11.4 → 6.0.1 (1.3.5, cycc/cybs binary rename) → 6.0.55 (1.4.1) → 6.0.82 (1.4.2, native-TLS ALPN/SPKI typed verbs) → 6.0.87 (1.4.3) → 6.1.19 (1.4.5, native-TLS-default switch + the two upstream P1 fixes) → 6.1.20 (1.4.6, folds sandhi 1.4.5 + macho-arm Darwin syscalls) → 6.1.21 (1.4.9, inverts `lib/tls.cyr` to native-no-flag-default + re-folds sandhi 1.4.5→1.4.8) → 6.2.1 (1.4.11, stdlib pin sweep: `json` dropped, `bigint`+`base64` → `bayan`) → 6.2.6 (1.5.0, fixes the aarch64 `bayan` cross-build defect).
- **aarch64 cross-build — RESOLVED (1.5.0 / cyrius 6.2.6, gating again)**: the `cycc_aarch64` `unexpected enum` abort assembling stdlib `bayan` (a 1.4.11–1.4.x best-effort known-issue; an upstream dep-assembly defect reproduced on every toolchain 6.0.21–6.2.1) is fixed in 6.2.6. The `--aarch64` build produces a valid aarch64 ELF with zero sandhi change, so the CI/release step is **gating** again (best-effort warn-skip removed; only-tolerated skip is the toolchain lacking `cycc_aarch64`). [architecture/005](../architecture/005-aarch64-bayan-cross-build.md); [archived issue](../issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md).
- **TLS backend**: **native by default — no flag** as of cyrius 6.1.21 / sandhi 1.4.9. `-D CYRIUS_TLS_LIBSSL` opts out to the deprecated libssl-only build (`sandhi_tls_use_libssl()`); legacy `-D CYRIUS_TLS_NATIVE` is a no-op alias. (1.4.5–1.4.8 used the inverse `-D CYRIUS_TLS_NATIVE` opt-in.) See [architecture/004](../architecture/004-native-tls-default.md).

## Fold-into-stdlib status

**Folded.** Shipped at sandhi **1.0.0** / Cyrius **v5.7.0** (2026-04-25) per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — clean-break, no stdlib-side alias window. Cyrius stdlib vendors `dist/sandhi.cyr` as `lib/sandhi.cyr`; consumers `include "lib/sandhi.cyr"` and drop their `[deps.sandhi]` pins.

Now in **post-fold maintenance**: patches land here first, `dist/sandhi.cyr` is regenerated each release, and a small cyrius-side slot refreshes `lib/sandhi.cyr` from it. The public surface is no longer frozen (ADR 0005's freeze applied only between 0.9.2 and 1.0.0).

## Source

All milestone surfaces are live: M1 server, M2 HTTP client + DNS, M3 RPC dialects, M3.5 SSE / streaming, M4 discovery, M5 TLS policy. ~12k lines across the modules below (720 fns; 432 public `sandhi_*` — 1.4.6 added `sandhi_http_options_tls_policy` / `_get_tls_policy` + internal `_sandhi_policy_pre_open_a` / `_post_open_a`; 1.4.7 added `sandhi_tls_policy_pin_available`; 1.4.9 added `sandhi_server_run_async` + internal `_sandhi_server_async_handler`). **Per-module line counts are approximate** — refreshed at major refactors; per-release detail lives in CHANGELOG.

| Module | Lines | Status |
|--------|-------|--------|
| `src/main.cyr` | 48 | public API declarations — docstring refreshed at 0.7.1; version bumped 0.7.2 |
| `src/http/retry.cyr` | 192 | **0.7.2 new** — retry-with-backoff wrappers for idempotent methods (GET/HEAD/PUT/DELETE). Exponential 2× capped at max_backoff_ms. 0.9.3: AWS-style full-jitter sleep replaces fixed-exponential (thundering-herd guard). 0.9.5: `_sandhi_http_retry` routes through `sandhi_http_request_auto` so retries inherit h2 selection when the pool has an h2 conn for the route. 1.2.1: `_a` variant `_sandhi_http_retry_a` threads allocator through every attempt via `sandhi_http_request_auto_a`. |
| `src/http/h2/dispatch.cyr` | 355 | **0.8.1 new** — `sandhi_http_request_auto` (per-method `_get_auto` / `_head_auto` / `_post_auto` / `_put_auto` / `_patch_auto` / `_delete_auto`). Pool h2-take → 1.1 single-shot fallback. 0.9.5: redirect-following hoisted to this layer — new `_sandhi_http_auto_once` (per-hop dispatch) + `_sandhi_http_auto_follow` (mirrors 1.1 follow's security semantics; each hop re-evaluates h2 selection). 0.9.6: ALPN-driven h2 auto-promotion — `_sandhi_http_try_h2_promote` opens advertising `h2,http/1.1`, runs preface + SETTINGS on h2-pick and caches via `sandhi_http_pool_put_h2`, donates conn to 1.1 pool slot on http/1.1-pick. First release where live h2 fires end-to-end via the auto path. 1.2.1: `_a` variants for the entire family (`_try_h2_promote_a`, `_auto_once_a`, `_auto_follow_a`, `sandhi_http_request_auto_a`) thread allocator through h2 take / promote / 1.1 fallback uniformly. 1.3.2: `sandhi_http_request_auto_a` save+restores the module-level `_sandhi_allow_0rtt` flag from `sandhi_http_options_get_allow_0rtt(opts)` for the duration of the dispatch — the 1.1 fallback's `_do_impl_a` eligibility check reads the flag. h2 path doesn't enable 0-RTT yet (CONNECTION preface vs. early-data ordering pinned for a later milestone). 1.3.3: same save+restore shape extended to `_sandhi_cred_digest` from `_sandhi_compute_cred_digest(user_headers)`, so the conn-finalize sees the right cred-digest for the cache-key isolation. |
| `src/obs/trace.cyr` | 57 | **0.7.2 new** — opt-in sakshi-span wrapper. Default off; `sandhi_trace_enable(1)` turns on emission. Boundary spans: `sandhi.http` / `sandhi.dns.v4` / `sandhi.dns.v6` / `sandhi.rpc`. |
| `src/obs/prof.cyr` | 140 | **1.2.5 new** — per-request per-phase timing instrumentation + recv-buffer cap/used tracking. Default off; runtime toggle via `sandhi_prof_enable(1)`. 5 phase boundaries (URL_PARSE_END / DNS_END / CONN_OPEN_END / REQ_BUILD_END / EXCHANGE_END) captured inside `_sandhi_http_do_impl_a`. 8 public verbs + `SANDHI_PROF_PHASE_*` enum. ~500 ns/request when enabled; zero overhead disabled. |
| `src/error.cyr` | 33 | unified error kinds (PARSE / CONNECT / TLS / TIMEOUT / REMOTE / PROTOCOL / AUTH / DISCOVERY / INTERNAL) |
| `src/http/headers.cyr` | 258 | **M2 done** — key-value store, case-insensitive lookup, wire-format serialize + parse |
| `src/http/url.cyr` | 193 | **M2 done** — http/https parser with CRLF hardening |
| `src/http/conn.cyr` | 877 | **M2 done** — tagged plain/TLS connection abstraction. 0.7.2: `sandhi_conn_open_timed` + SO_RCVTIMEO/SO_SNDTIMEO helpers; EAGAIN surfaced as `0 - _SANDHI_EAGAIN`. 0.7.3: non-blocking connect via `_sandhi_conn_connect_nb` (O_NONBLOCK + poll + SO_ERROR); `sandhi_conn_open_fully_timed`; `sandhi_conn_recv_all_deadline`; module-level `_sandhi_conn_last_err` for failure classification. 1.3.0 Batch: switched `_sandhi_alpn_hook` to v5.10.13's typed `tls_set_alpn` wrapper. 1.3.1: `_sandhi_conn_finalize_a` switched from one-shot `tls_connect_with_ctx_hook` to staged-connect (`tls_connect_alloc` → optional `tls_set_session` → `tls_connect_complete` → capture via `tls_get_session`). 1.3.2: staged-connect finalize gained early-data parameters — `_sandhi_conn_finalize_a` becomes a back-compat wrapper forwarding to `_sandhi_conn_finalize_with_early_data_a` which checks `tls_session_get_max_early_data(cached) >= req_len`, writes via `tls_write_early_data`, captures `tls_get_early_data_status` into new conn-struct slot `SANDHI_CONN_OFF_0RTT_STATUS` (struct grew 32 → 40 bytes). New v4/v6 conn-open variants `_sandhi_conn_open_fully_timed_with_early_data_a` / `_v6_fully_timed_with_early_data_a`. Module-level `_sandhi_allow_0rtt` flag added next to `_sandhi_alpn_advertise_h2`. Public `sandhi_conn_0rtt_status(c)` accessor exposes the latched TLS_EARLY_DATA_* value. 1.3.3: module-level `_sandhi_cred_digest` flag added; finalize reads it for the session-cache key — same flag-pattern precedent as `_sandhi_allow_0rtt` and `_sandhi_alpn_advertise_h2`. **1.5.1**: AGNOS transport seam — every raw socket-syscall site (`SYS_FCNTL`/`SYS_SOCKET`/`SYS_CONNECT`/`SYS_SETSOCKOPT`/`SOL_SOCKET`) wrapped in `#ifndef CYRIUS_TARGET_AGNOS` with an `#ifdef` agnos counterpart (nb-connect → blocking `sock_connect`; SO_*TIMEO → no-op; IPv4-only v6 → fail-closed). Linux/macOS byte-identical. |
| `src/http/response.cyr` | 310 | **M2 done** — Content-Length + chunked + close-delimited body framing. 0.7.1: `err_message` slot added (struct 40→48). |
| `src/net/resolve.cyr` | 557 | **M2 done** — native UDP DNS (RFC 1035). 0.7.2: random TXID; `_sandhi_resolve_name_eq` with compression-pointer following + 32-hop guard; answer-name match against question in the A + AAAA parsers; new `sandhi_resolve_ipv6` + `_sandhi_resolve_build_query_aaaa` + `_sandhi_resolve_parse_response_aaaa`; trace-wrap on both public verbs. Four P1 security items pulled forward from 0.9.x. **1.5.2** (Batch C2): TXID entropy switched from hand-rolled `/dev/urandom` (bare Linux syscall numbers — broke on AGNOS) to the portable stdlib `sys_getrandom` selector primitive (Linux/macOS/Windows/AGNOS #45); no `#ifdef`, no new dep. |
| `src/http/client.cyr` | 1130 | **M2 done** — POST/PUT/DELETE/PATCH/HEAD/GET, redirect following, options struct. 0.7.1: default UA + `Accept-Encoding: identity`; options gained `max_response_bytes`. 0.7.2: options gained `read_ms` / `write_ms`; `SANDHI_ERR_TIMEOUT` now raised; trace-wrap around `_sandhi_http_do`. 0.7.3: options gained `connect_ms` / `total_ms` (struct 40→56); `_sandhi_http_clamp_ms` deadline helper; per-hop budget for redirects. 1.1.2: `_sandhi_client_user_header_is_reserved` filter on `_sandhi_client_build_request_v` — caller-supplied `Host` / `Content-Length` / `Transfer-Encoding` / `Connection` dropped from user_headers (symmetric to `sandhi_headers_smuggle_dup` server-side at 0.9.1). 1.2.0 Batch A: `_a` variants for `_sandhi_http_do` / `_do_impl` / `_dispatch` / `_exchange` / `_exchange_keepalive` + fixed buggy `_sandhi_client_build_request_a` (was dropping `a`); proper `_sandhi_client_build_request_va` variadic threads `a` through `str_builder_*_a`; OOM guard after `str_builder_new_a`. Bare versions stay as back-compat wrappers passing `default_alloc()`. 1.2.1 Batches B+C: `_sandhi_http_follow_a` + `_sandhi_strip_sensitive_headers_a` thread `a` through every redirect hop and the cross-authority cred-strip; `_sandhi_http_dispatch_a`'s 1.2.0 follow-path TODO is now resolved. Internal-cascade orchestrators are fully `_a`-threaded. 1.2.2 Batch D: public-verb `_a` family — `sandhi_http_get_a` / `_post_a` / `_put_a` / `_patch_a` / `_delete_a` / `_head_a` thin wrappers calling `_sandhi_http_dispatch_a`. First consumer-visible end-to-end arena adoption. 1.2.3 Batch E: `_opts` family — `sandhi_http_get_opts_a` / `_post_opts_a`. 1.3.2: TLS 1.3 0-RTT plumbing — added `sandhi_http_options_allow_0rtt(opts, on)` / `_get_allow_0rtt(opts)` (options struct grew 64 → 72 bytes for the new slot), `_sandhi_method_is_replay_safe(method)` classifier (GET/HEAD/OPTIONS, case-sensitive). `_sandhi_http_do_impl_a` restructured to build request bytes BEFORE conn-open so they can be passed as early-data; calls new conn-open `_with_early_data_a` variants on the 0-RTT path. Both exchange paths (`_exchange_a` / `_exchange_keepalive_a`) gained a `sandhi_conn_0rtt_status(conn)` check at entry — ACCEPTED skips request-send, REJECTED/NOT_SENT go through normal send. `_sandhi_http_dispatch_a` save+restores `_sandhi_allow_0rtt` from `sandhi_http_options_get_allow_0rtt(opts)`. 1.3.3: new `_sandhi_fnv1a_mix(h, s)` running-byte-mixer + `_sandhi_compute_cred_digest(headers)` (FNV-1a over Authorization / Cookie / Proxy-Authorization values with per-header marker prefix; returns 0 when no cred-bearing headers). `_sandhi_http_dispatch_a` save+restores `_sandhi_cred_digest = _sandhi_compute_cred_digest(headers)` for the duration of the dispatch — propagates into `_sandhi_conn_finalize_with_early_data_a`'s cache-key calls so different auth contexts don't share a cached session. |
| `src/http/sse.cyr` | 244 | **M3.5 done** — WHATWG SSE event parser |
| `src/http/stream.cyr` | 440 | **M3.5 done** — streaming HTTP + incremental chunked decoder + callback-per-event dispatch. 0.7.1: `sandhi_http_stream_opts` honors `max_response_bytes`. 0.7.2: also honors `read_ms`/`write_ms`; EAGAIN→TIMEOUT in read+body loops. 0.7.3: connect_ms + total_ms threaded via `sandhi_conn_open_fully_timed` + per-recv deadline check in body loop. |
| `src/rpc/json.cyr` | 365 | **M3 done** — nested JSON build + dotted-path extract |
| `src/rpc/dispatch.cyr` | 186 | **M3 done** — JSON-over-HTTP + dialect-aware error envelopes. 0.7.2: trace-wrap on `sandhi_rpc_call` / `_with_headers`. |
| `src/rpc/webdriver.cyr` | 307 | **M3 done** — W3C WebDriver surface (sessions, navigation, elements, exec). 1.2.4 Batch F: 14 public `_a` verbs + 2 internal helper `_a` variants threading allocator through URL build, JSON envelope, and `sandhi_rpc_call_a`. |
| `src/rpc/appium.cyr` | 184 | **M3 done** — Appium extensions (contexts, app lifecycle, mobile exec). 1.2.4 Batch F: 11 public `_a` verbs threading allocator through URL build, JSON envelope, and `sandhi_rpc_call_a`. |
| `src/rpc/mcp.cyr` | 148 | **M3 done** — MCP-over-HTTP transport (JSON-RPC 2.0 envelope). 1.2.4 Batch F: 5 public `_a` verbs (`call`, `call_with_headers`, `result_raw`, `error_message`, `stream`) + internal `_sandhi_mcp_build_request_a`. `sandhi_rpc_mcp_error_code` intentionally NOT paired (no allocation). |
| `src/rpc/mod.cyr` | 17 | dialect-index module |
| `src/discovery/service.cyr` | 75 | **M4 done** — service + resolver type vocabulary |
| `src/discovery/chain.cyr` | 61 | **M4 done** — fallback sequence of resolvers |
| `src/discovery/daimon.cyr` | 116 | **M4 done** — HTTP-backed resolver against daimon registry |
| `src/discovery/local.cyr` | 194 | **M4** — mDNS link-local resolver; unicast (QU-bit) A-record query shipped (0.9.3, works against most responders); multicast membership awaits cyrius `lib/net.cyr` primitives |
| `src/discovery/register.cyr` | 55 | **M4 done** — publish/withdraw via daimon |
| `src/discovery/mod.cyr` | 24 | dialect-index module |
| `src/tls_policy/policy.cyr` | 173 | **M5 done** — policy struct + constructors + combine |
| `src/tls_policy/fingerprint.cyr` | 102 | **M5 done** — SPKI hex normalize / compare / encode helpers |
| `src/tls_policy/apply.cyr` | 259 | **M5 done** — TLS policy enforcement (default / pinned / mTLS / trust-store); 0.9.3 enforcement, 1.3.0 typed ALPN wrapper, 1.4.2 ALPN-read + SPKI-pin onto typed backend-agnostic `tls.cyr` verbs (`tls_get_alpn_selected` / `tls_get_peer_spki_der`). SPKI digest uses sigil `sha256` (deps declared 1.4.3). |
| `src/tls_policy/session_cache.cyr` | ~330 | **1.3.1 new** — process-wide singleton cache for `SSL_SESSION*` keyed by `(sni_host, hook_fp_hex)`. Composes cyrius v5.10.21's `tls_get_session` / `tls_set_session` / `tls_session_free` + capability probe + v5.10.27's staged-connect API. Default-OFF; opt-in via `sandhi_session_cache_enable(1)`. Cache uses `default_alloc()` — sessions outlive any per-request arena. 1.3.3: cache key extended to `(sni_host, hook_fp_hex, cred_digest)`; default `cred_digest=0` preserves the 1.3.1 / 1.3.2 cache-key shape. **1.4.0**: TTL + max-size eviction (`set_max_size` / `set_max_age_ms` defaults 256 / 24h); entry struct `[session, last_used_ms]` (16 B, default_alloc); eviction-on-insert (oldest `last_used_ms`); age-check-on-lookup; touch-on-hit for LRU semantics; `sandhi_session_cache_clear()` to drop all entries; `_evict_count` / `_age_evict_count` counters; `_supported()` capability getter (separated from `enable()`); **`enable()` contract relaxed** (always succeeds modulo OOM — cache initializes regardless of TLS capability). Also fixes the silent 1.3.1 `hashmap_*` (now `map_*`) naming bug + the `_key_a` 1-byte-stack-buffer `strlen` read-past (now uses `str_builder_add_byte`). Bundled three causally-linked fixes per cyrius v5.10.0 "shared cascade" rule. |
| `src/tls_policy/mod.cyr` | 28 | dialect-index module |
| `src/server/mod.cyr` | ~880 | **M1 done** — verbatim lift from `lib/http_server.cyr`. 0.7.2: `sandhi_server_options_*` struct + `_run_opts`; per-connection SO_RCVTIMEO (slowloris guard; 30 s default). 1.2.7 Batch G: 4 server `_send_*` `_a` paint pairs + OOM guards. **1.4.9**: `max_conns` now enforced via the new epoll-cooperative `sandhi_server_run_async` (`lib/async.cyr`; batched accept, per-handler arena buffers); sync `_run`/`_run_opts` unchanged. **1.4.10**: async DoS fix (dropped the infinite `async_await_readable`; floored `idle_ms` > 0) + `async_new()` null-checks. **1.5.1**: listen-fd `O_NONBLOCK` fcntl wrapped in `#ifndef CYRIUS_TARGET_AGNOS` (AGNOS transport seam; `sock_listen` already `Err`s on agnos so the fn bails before the cooperative loop). |

Build outputs:
- `build/sandhi-smoke` — link-proof smoke program.
- `build/dns-probe` — ad-hoc live DNS check (not part of test suite; `cyrius run programs/dns-probe.cyr <host>`).
- `build/http-probe` — ad-hoc live HTTP/HTTPS round-trip (`cyrius run programs/http-probe.cyr <url>`).
- `build/_policy_runtime_probe` — live-network TLS-policy gate (CI step).

`dist/sandhi.cyr` regenerated via `cyrius distlib` each release (~11.9k lines at v1.4.4); CI gates that it stays in sync with `src/`.

## Tests

**992 assertions green** across four suites (CI runs all four; measured on the 6.2.6 pin at 1.5.2):

- `tests/sandhi.tcyr` — **440** — headers / URL / response / client + redirect security (cred-strip cross-authority, https→http refusal, 303→GET) / DNS / discovery / TLS policy + fingerprint / SSE / streaming.
- `tests/h2.tcyr` — **167** — HPACK static + Huffman (RFC 7541 C.4.1) / frame wire format / conn lifecycle / request-encode + roundtrip / response-decode / pool routing.
- `tests/alloc.tcyr` — **343** — per-request-arena round-trips + reset + OOM (`fail_after_n_allocs`) for every `_a` verb; session-cache eviction (1.4.0).
- `tests/rpc.tcyr` — **42** — JSON builder/extractor, RPC dispatch err-envelope, WebDriver URL helpers, MCP envelope.

Beyond unit tests: `programs/_policy_runtime_probe.cyr` is a live-network TLS-policy gate (CI step; skip-cleanly offline). **1.4.5** adds `programs/_https_native_loop_gate.cyr` — the P1 regression gate (N≥4 sequential native `sandhi_http_get` must not crash; built `-D CYRIUS_TLS_NATIVE`; targets 1.1.1.1; skip-cleanly offline) + `programs/_backend_probe.cyr` (backend-selection smoke). Per-program fixup-cap pressure (architecture/001) keeps some coverage in standalone `programs/_*_probe.cyr`.

Backend-agnostic note: the four `.tcyr` suites are unit tests (parsing / headers / wire format) and don't hit live handshakes, so they run on the default backend without `-D` (counts unchanged 1.4.4 → 1.4.5).

## Dependencies

Declared in `cyrius.cyml` (all Cyrius stdlib):

- **Core**: `syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`, `vec`, `args`, `hashmap`, `process`, `thread`, `fnptr`, `async`, `atomic`, `chrono`, `tagged`, `assert`
- **Network primitives** (the layer sandhi composes): `net`, `http`, `tls`, `ws`. `http_server` dropped at M1 (content lives in `src/server/mod.cyr`); stdlib `json` dropped at the 1.4.11 6.2.1 pin (sandhi uses its own `src/rpc/json.cyr`).
- **TLS / libssl-bridge transitive**: `mmap`, `dynlib`, `fdlopen`, `freelist`
- **Crypto** — `sigil` plus its undeclared transitive deps (`ct` / `keccak` / `thread_local` added 1.4.3) and **`bayan`** (the 6.1.25 carve-out replacing standalone `bigint` + `base64`; re-exports `u256_*` / `base64_*` via compat aliases; declared at the 1.4.11 6.2.1 pin, ordered before `sigil`): `bayan`, `sigil`, `ct`, `keccak`, `thread_local`
- **Infrastructure**: `sakshi` (tracing), `regression` (live-network test probe, 1.3.0)

No external git deps — pure stdlib composition. The 1.4.11 sweep closed the old `base64` dep gap — `src/rpc/appium.cyr`'s `base64_*` now resolves through the `bayan` compat aliases.

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
- **No stdlib-side alias** (per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) — done. At the v5.7.0 fold cyrius deleted `lib/http_server.cyr` and added `lib/sandhi.cyr` (vendored from `dist/sandhi.cyr`) in the same release. Cyrius-agent-side change; sandhi repo unaffected.

## Next

The **1.5.x arc is open** (opened at 1.5.0 — toolchain 6.2.6 + aarch64
cross-build restored + resolved-issue backlog archived). The pin is **6.2.6**
(native no-flag default). Remaining work is organized into provisional batches
(ONE item per slot; each opens when its gate clears) — full detail in
[`roadmap.md`](roadmap.md):

- **Batch A — cross-repo-gated repairs** (open when the cyrius primitive lands):
  - **A1 native TLS-policy enforcement** — native `SSL_CTX_*` (trust-store /
    mTLS) in cyrius `lib/tls_native.cyr`; the last libssl coupling. Until then
    native trust/mTLS **fails closed** (1.4.7); SPKI pinning is already
    backend-agnostic. Drops `sandhi_tls_use_libssl()` when it lands.
  - **A2 async server arena-aware repair** — opens when cyrius ships
    `async_new_in(allocator)` (filed `2026-06-09-async-runtime-no-free-task-leak.md`);
    eliminates `sandhi_server_run_async`'s residual ~32 B/conn runtime/task leak.
  - **A3 mDNS multicast primitives** in cyrius `lib/net.cyr` — gates the real
    `discovery/local.cyr` (quality gate; QU-bit unicast works today).
- **Batch B — profile-justified optimization picks** (parked pending prof
  evidence): HPACK Huffman tie-break, `_sandhi_resp_new` collapse, pool LRU.
- **Batch C — sit-adoption reshape** — gate **cleared** (native TLS default
  since 6.1.21). **C1 AGNOS socket-backend gap ✅ 1.5.1** (raw-syscall
  connect/listen machinery in `src/http/conn.cyr` + `src/server/mod.cyr` guarded
  by `#ifndef CYRIUS_TARGET_AGNOS`; Linux/macOS byte-identical) **+ C2 AGNOS
  DNS-entropy ✅ 1.5.2** (`resolve.cyr` TXID switched to the portable
  `sys_getrandom` selector primitive) **together complete the sandhi-side AGNOS
  transport surface.** Further Batch C items fill from what sit surfaces, not
  pre-baked (memory [`project_sit_adoption_drives_roadmap`]). A full `--agnos`
  build still needs the upstream `mmap` `CLONE_VM` stub + native `SSL_CTX_*`
  (Batch A1) — both outside sandhi's scope.
- **Background watches** — `tests/sandhi.tcyr` cap-drift; consumer coordination
  docs (sandhi side shipped; the daimon `serve_async` collapse is sandhi-side ✅
  at 1.4.9, residual daimon-side).
