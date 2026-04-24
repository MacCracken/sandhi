# sandhi — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable); this file is **state** (volatile). Add release-hook wiring when the repo's release workflow lands.

## Version

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

- **Cyrius pin**: `5.6.22` (in `cyrius.cyml [package].cyrius`)

## Fold-into-stdlib status

**Pre-fold, target at Cyrius v5.7.0** as a clean-break fold per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md). Revised from the original "before v5.6.x closeout" target. Follows the sakshi / mabda / sankoch / sigil precedent (sibling crate → fold), but with one twist: no stdlib-side alias window. 5.6.YY emits a deprecation warning on `include "lib/http_server.cyr"`; 5.7.0 deletes it and adds `lib/sandhi.cyr` vendored from `dist/sandhi.cyr`.

M2–M5 must land pre-5.7.0 — the fold freezes the public surface.

## Source

Server module + full HTTP client surface + DNS resolver are live; RPC / discovery / tls_policy still scaffold.

| Module | Lines | Status |
|--------|-------|--------|
| `src/main.cyr` | 48 | public API declarations — docstring refreshed at 0.7.1; version bumped 0.7.2 |
| `src/http/retry.cyr` | 128 | **0.7.2 new** — retry-with-backoff wrappers for idempotent methods (GET/HEAD/PUT/DELETE). Exponential 2× capped at max_backoff_ms. |
| `src/obs/trace.cyr` | 57 | **0.7.2 new** — opt-in sakshi-span wrapper. Default off; `sandhi_trace_enable(1)` turns on emission. Boundary spans: `sandhi.http` / `sandhi.dns.v4` / `sandhi.dns.v6` / `sandhi.rpc`. |
| `src/error.cyr` | 33 | scaffold — error kinds defined |
| `src/http/headers.cyr` | 258 | **M2 done** — key-value store, case-insensitive lookup, wire-format serialize + parse |
| `src/http/url.cyr` | 193 | **M2 done** — http/https parser with CRLF hardening |
| `src/http/conn.cyr` | 193 | **M2 done** — tagged plain/TLS connection abstraction. 0.7.2: `sandhi_conn_open_timed` + SO_RCVTIMEO/SO_SNDTIMEO helpers; EAGAIN surfaced as `0 - _SANDHI_EAGAIN` so callers can distinguish timeout from broken-pipe. |
| `src/http/response.cyr` | 310 | **M2 done** — Content-Length + chunked + close-delimited body framing. 0.7.1: `err_message` slot added (struct 40→48). |
| `src/net/resolve.cyr` | 557 | **M2 done** — native UDP DNS (RFC 1035). 0.7.2: random TXID via `/dev/urandom`; `_sandhi_resolve_name_eq` with compression-pointer following + 32-hop guard; answer-name match against question in the A + AAAA parsers; new `sandhi_resolve_ipv6` + `_sandhi_resolve_build_query_aaaa` + `_sandhi_resolve_parse_response_aaaa`; trace-wrap on both public verbs. Four P1 security items pulled forward from 0.9.x. |
| `src/http/client.cyr` | 426 | **M2 done** — POST/PUT/DELETE/PATCH/HEAD/GET, redirect following, options struct. 0.7.1: default UA + `Accept-Encoding: identity`; options gained `max_response_bytes`. 0.7.2: options gained `read_ms` / `write_ms`; `SANDHI_ERR_TIMEOUT` now raised; trace-wrap around `_sandhi_http_do`. |
| `src/http/sse.cyr` | 244 | **M3.5 done** — WHATWG SSE event parser |
| `src/http/stream.cyr` | 422 | **M3.5 done** — streaming HTTP + incremental chunked decoder + callback-per-event dispatch. 0.7.1: `sandhi_http_stream_opts` variant honors `max_response_bytes`. 0.7.2: opts-variant also honors `read_ms`/`write_ms`; EAGAIN maps to `SANDHI_ERR_TIMEOUT` in the read + body loops. |
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

- `tests/sandhi.tcyr` — **333 assertions green** across 89 test groups: all of the above + **sse (single-event / named-event / multi-line-data / id+retry / comments / multiple-events / CRLF / partial-trailing / no-space-after-colon / empty-data / blank-line-resets) and stream (result-accessors / chunk-parse-size / incomplete / zero-size / chunked-roundtrip)**.
- `tests/integration/` — cross-submodule integration not yet a separate file; loopback client+server round-trip deferred until the HTTPS TLS-init issue resolves.

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
- **0.7.2** ✅ (this patch) — reliability + observability: read/write timeouts, retry wrappers, DNS hardening (incl. 4 P1 security items pulled forward), AAAA resolver, opt-in sakshi spans, server idle-timeout
- **0.7.3** — deferred from 0.7.2: `connect_ms` / `total_ms` (non-blocking connect + monotonic-deadline threading)
- **0.8.0** — HTTP/2 + connection pool (paired; h2 multiplex shares pool checkout shape)
- **0.8.x** — Phase 1 security sweep (P0s: chunked smuggling, CL+TE rejection, redirect cred-strip, pinning fail-closed, chunk-size overflow guard)
- **0.9.x** — Phase 2 P1 sweep (SSE, headers, URL, JSON, TLS-policy — DNS already landed in 0.7.2) + pre-fold closeout (server symbol rename, surface freeze, first `dist/sandhi.cyr`)
- **1.0.0** — fold-into-stdlib event at Cyrius v5.7.0

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
