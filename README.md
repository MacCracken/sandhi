# sandhi

> Service-boundary layer for AGNOS — HTTP/1.1 + HTTP/2 client, connection pool,
> JSON-RPC, service discovery, TLS policy, HTTP server. Composed on top of
> Cyrius stdlib primitives.

**sandhi** (Sanskrit सन्धि — *junction, connection, joining*) is the layer
that governs rules at the boundary where two services meet. Stdlib carries
the thin network primitives (`http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`,
`net.cyr`); sandhi composes them into the full-featured client + server
surface that AGNOS consumers need.

The linguistic sense of sandhi (rules at the boundary where two morphemes
meet) maps onto the service-mesh sense — same abstract structure at two
scales.

## Status

**Post-fold maintenance.** sandhi folded into Cyrius stdlib as `lib/sandhi.cyr`
at 1.0.0 / Cyrius v5.7.0 ([ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)).
Patches land here first; `dist/sandhi.cyr` is regenerated each release and a
small cyrius slot re-folds it.

Current: **1.5.5**, pinned to **Cyrius 6.2.7**. **1001 test assertions green**
(449 sandhi + 167 h2 + 343 alloc + 42 rpc). Builds clean for x86_64, aarch64,
and the **AGNOS** target.

**TLS backend: native by default, no flag** (since Cyrius 6.1.21). `-D
CYRIUS_TLS_LIBSSL` opts out to the deprecated libssl bridge.

Per-release history: [CHANGELOG.md](CHANGELOG.md). Remaining / open work:
[roadmap](docs/development/roadmap.md).

## Quick start

```sh
cyrius deps
cyrius build programs/smoke.cyr build/sandhi-smoke   # link proof
cyrius test  tests/sandhi.tcyr                        # core tests
cyrius test  tests/h2.tcyr                            # HTTP/2 tests
cyrius distlib                                        # produce dist/sandhi.cyr
```

Smallest useful program (see [`docs/examples/01-simple-get.cyr`](docs/examples/01-simple-get.cyr)):

```cyr
include "src/main.cyr"   # plus the rest of the standard sandhi includes

fn main() {
    alloc_init();
    var r = sandhi_http_get("http://example.com/", 0);
    if (sandhi_http_err_kind(r) != SANDHI_OK) { return 1; }
    fmt_int(sandhi_http_status(r));
    return 0;
}

var exit_code = main();
syscall(60, exit_code);
```

## Module map

| Module | Purpose |
|--------|---------|
| `src/http/client.cyr` | Full HTTP/1.1 client — GET/POST/PUT/DELETE/PATCH/HEAD, custom headers, HTTPS, redirects, timeouts |
| `src/http/pool.cyr` | Connection pool — HTTP/1.1 keep-alive + HTTP/2 multiplex from the same struct |
| `src/http/retry.cyr` | Retry-with-backoff wrappers for idempotent methods |
| `src/http/stream.cyr` | Streaming HTTP + WHATWG SSE parser |
| `src/http/h2/*` | Full HTTP/2 stack: frames (RFC 7540), HPACK + Huffman (RFC 7541), connection lifecycle, request/response, dispatch |
| `src/rpc/*` | JSON-RPC dialects: W3C WebDriver, Appium extensions, MCP-over-HTTP + SSE — transport only per [ADR 0001](docs/adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) |
| `src/discovery/*` | Service discovery: chain composition, daimon-backed resolver, mDNS — QU-bit unicast (default) + opt-in multicast (QM) resolver `sandhi_discovery_local_mc_resolver` (1.5.5, over Cyrius 6.2.7 multicast primitives) |
| `src/tls_policy/*` | Cert pinning (SPKI, constant-time compare), mTLS, trust store, ALPN, backend selection. Enforcement is live + **backend-aware** (1.4.7): trust/mTLS libssl-only, SPKI-pin backend-agnostic; high-level threading via `sandhi_http_options_tls_policy` (1.4.6); fail-closed |
| `src/tls_policy/session_cache.cyr` | TLS 1.3/1.2 client session-resumption cache — TTL + max-size LRU eviction, cred-strip-aware keying (1.3.1–1.4.0) |
| `src/server/mod.cyr` | HTTP/1.1 server — sync `sandhi_server_run` / `_run_opts` + epoll-cooperative `sandhi_server_run_async` (`max_conns`, 1.4.9); built-in CL+TE / dup-header smuggling guards |
| `src/net/resolve.cyr` | Native UDP DNS resolver — A + AAAA, randomized TXID + answer-name verification, RFC 1035 |
| `src/obs/trace.cyr` · `prof.cyr` | Opt-in sakshi spans at HTTP / RPC / DNS boundaries; opt-in per-request per-phase profiling |

## Documentation

- **[Getting started](docs/guides/getting-started.md)** — build, smallest GET, response accessors
- **[Timeouts](docs/guides/timeouts.md)** — connect_ms / read_ms / write_ms / total_ms
- **[Connection pool](docs/guides/connection-pool.md)** — keep-alive semantics, route isolation
- **[HTTP/2 (manual)](docs/guides/http2-manual.md)** — explicit opt-in path; ALPN-driven h2 auto-selection lands via `sandhi_http_request_auto` (0.9.6)
- **[Redirects + security](docs/guides/redirects-and-security.md)** — cross-origin credential strip, https→http refusal
- **[TLS policy](docs/guides/tls-policy.md)** — pinning, mTLS, fail-closed semantics
- **[Server](docs/guides/server.md)** — minimal accept loop, request parsing, smuggling guards

Examples — runnable Cyrius programs in [`docs/examples/`](docs/examples/):
- [`01-simple-get.cyr`](docs/examples/01-simple-get.cyr) · [`02-post-json.cyr`](docs/examples/02-post-json.cyr) · [`03-server.cyr`](docs/examples/03-server.cyr) · [`04-sse-consumer.cyr`](docs/examples/04-sse-consumer.cyr)

## Architecture & decisions

- **[ADR 0001](docs/adr/0001-sandhi-is-a-composer-not-a-reimplementer.md)** — sandhi composes; doesn't reimplement
- **[ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)** — clean-break fold at v5.7.0 (no alias window)
- **[ADR 0003](docs/adr/0003-http2-and-pool-bundled.md)** — HTTP/2 and connection pool bundled together at 0.8.0
- **[ADR 0004](docs/adr/0004-security-first-refusal-model.md)** — refuse-don't-interpret on ambiguous protocol input
- **[ADR 0005](docs/adr/0005-public-surface-freeze-at-0-9-2.md)** — public surface frozen at 0.9.2

Architecture notes (invariants / quirks, not decisions):
- **[001 — HPACK Huffman blob](docs/architecture/001-hpack-huffman-blob.md)** — single string-literal pattern for large lookup tables
- **[002 — forward-reference glue modules](docs/architecture/002-forward-reference-via-glue-modules.md)** — pattern for crossing build-order boundaries
- **[003 — libssl-pthread stubbing](docs/architecture/003-libssl-pthread-stubbing.md)** — *historical*: what was stubbed pre-0.9.3 and the surface-first / runtime-second pattern
- **[004 — native TLS is the default](docs/architecture/004-native-tls-default.md)** — native no-flag default (Cyrius 6.1.21), `-D CYRIUS_TLS_LIBSSL` opt-out
- **[005 — aarch64 cross-build](docs/architecture/005-aarch64-bayan-cross-build.md)** — the `bayan` cross-build defect, resolved upstream at Cyrius 6.2.6; CI step is gating

## Consumers

Each AGNOS crate that sandhi serves has a coordination doc in [`docs/issues/`](docs/issues/) — paste-ready roadmap entries for the consumer's modernization pass:

- **yantra** — WebDriver + Appium JSON-RPC backends ([doc](docs/issues/2026-04-24-yantra-sandhi-rpc.md))
- **daimon** — MCP client ([doc](docs/issues/2026-04-24-daimon-sandhi-mcp-client.md)) + producer-side registry ([doc](docs/issues/2026-04-24-daimon-registry-endpoints.md))
- **hoosh / ifran** — LLM-provider HTTP routing ([doc](docs/issues/2026-04-24-hoosh-ifran-sandhi-http.md))
- **sit** — git-over-HTTP for remote clone/push/pull ([doc](docs/issues/2026-04-24-sit-sandhi-git-over-http.md))
- **ark** — remote registry ops ([doc](docs/issues/2026-04-24-ark-sandhi-registry-ops.md))
- **mela** — marketplace API ([doc](docs/issues/2026-04-24-mela-sandhi-marketplace.md))
- **vidya** — external-knowledge fetch ([doc](docs/issues/2026-04-24-vidya-sandhi-fetch.md))

## Cross-repo dependencies

Live HTTPS works end-to-end on the native backend. One item remains open
cyrius-side (tracked in the [roadmap](docs/development/roadmap.md)):

- **Native TLS-policy enforcement** — SPKI pinning is backend-agnostic and live
  on native; trust-store / mTLS still reach for libssl `SSL_CTX_*`, so they
  **fail closed** on native pending native `SSL_CTX_*` equivalents in cyrius
  `lib/tls_native.cyr`. The last libssl coupling, and the gate for dropping the
  libssl opt-out entirely.

## Build

```sh
cyrius deps                                                 # resolve stdlib deps
cyrius build programs/smoke.cyr build/sandhi-smoke          # smoke link proof (native, no flag)
cyrius test  tests/sandhi.tcyr                              # core (449 assertions)
cyrius test  tests/h2.tcyr                                  # h2-specific (167 assertions)
cyrius test  tests/alloc.tcyr                               # allocator / arena (343 assertions)
cyrius test  tests/rpc.tcyr                                 # RPC dialects (42 assertions)
cyrius lint  src/*.cyr src/**/*.cyr                         # static checks (warn-as-fail in CI)
CYRIUS_DCE=1 cyrius build programs/smoke.cyr build/sandhi-smoke              # release-parity (native)
cyrius build -D CYRIUS_TLS_LIBSSL programs/smoke.cyr build/sandhi-smoke-libssl   # deprecated libssl opt-out
cyrius distlib                                              # → dist/sandhi.cyr
```

Toolchain pin: `cyrius.cyml [package].cyrius` is the source of truth; never create a `.cyrius-toolchain` file.

## Why the name

*"services"* was the placeholder in both agnosticos and cyrius roadmaps through 2026-04-24. The name sandhi was assigned that day after confirming the planned crate had never received a proper one. Sandhi fits the AGNOS multilingual naming register (hoosh, sakshi, mabda, sigil, patra, yantra, sit/smriti, kula…) and its linguistic meaning — *rules at the boundary where two units meet* — is structurally identical to the crate's engineering purpose.

## License

GPL-3.0-only.

---

*Part of [AGNOS](https://github.com/MacCracken/agnosticos). Named 2026-04-24.*
