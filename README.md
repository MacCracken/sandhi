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

**0.9.2** (2026-04-24) — pre-fold closeout shipped. **634 test assertions
green** across 481 sandhi + 153 h2 entries. Public surface frozen per
[ADR 0005](docs/adr/0005-public-surface-freeze-at-0-9-2.md).

The next release is **1.0.0** — the fold event at Cyrius v5.7.0. stdlib will
vendor `lib/sandhi.cyr` from this repo's `dist/sandhi.cyr` and delete its
own `lib/http_server.cyr` per the clean-break fold ([ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)).
That's an external gate — checked at the Cyrius release, not here.

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
| `src/discovery/*` | Service discovery: chain composition, daimon-backed resolver, mDNS surface (lookup stubbed pending multicast primitives in stdlib) |
| `src/tls_policy/*` | Cert pinning (SPKI, constant-time compare), mTLS, trust store, ALPN advertise list. Fail-closed on stubbed enforcement (see [issues](docs/issues/)) |
| `src/server/mod.cyr` | HTTP/1.1 server — `sandhi_server_*` canonical names; `http_*` aliases retire at fold |
| `src/net/resolve.cyr` | Native UDP DNS resolver — A + AAAA, randomized TXID + answer-name verification, RFC 1035 |
| `src/obs/trace.cyr` | Opt-in sakshi spans at HTTP / RPC / DNS boundaries |

## Documentation

- **[Getting started](docs/guides/getting-started.md)** — build, smallest GET, response accessors
- **[Timeouts](docs/guides/timeouts.md)** — connect_ms / read_ms / write_ms / total_ms
- **[Connection pool](docs/guides/connection-pool.md)** — keep-alive semantics, route isolation
- **[HTTP/2 (manual)](docs/guides/http2-manual.md)** — opt-in path until libssl-pthread-deadlock clears
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
- **[003 — libssl-pthread stubbing](docs/architecture/003-libssl-pthread-stubbing.md)** — what's stubbed and why

## Consumers

Each AGNOS crate that sandhi serves has a coordination doc in [`docs/issues/`](docs/issues/) — paste-ready roadmap entries for the consumer's modernization pass:

- **yantra** — WebDriver + Appium JSON-RPC backends ([doc](docs/issues/2026-04-24-yantra-sandhi-rpc.md))
- **daimon** — MCP client ([doc](docs/issues/2026-04-24-daimon-sandhi-mcp-client.md)) + producer-side registry ([doc](docs/issues/2026-04-24-daimon-registry-endpoints.md))
- **hoosh / ifran** — LLM-provider HTTP routing ([doc](docs/issues/2026-04-24-hoosh-ifran-sandhi-http.md))
- **sit** — git-over-HTTP for remote clone/push/pull ([doc](docs/issues/2026-04-24-sit-sandhi-git-over-http.md))
- **ark** — remote registry ops ([doc](docs/issues/2026-04-24-ark-sandhi-registry-ops.md))
- **mela** — marketplace API ([doc](docs/issues/2026-04-24-mela-sandhi-marketplace.md))
- **vidya** — external-knowledge fetch ([doc](docs/issues/2026-04-24-vidya-sandhi-fetch.md))

## Known blockers

- [`libssl-pthread-deadlock`](docs/issues/2026-04-24-libssl-pthread-deadlock.md) — `SSL_connect` deadlocks on a futex-wait in static cyrius binaries. Plain HTTP works; live HTTPS gated.
- [`stdlib-tls-alpn-hook`](docs/issues/2026-04-24-stdlib-tls-alpn-hook.md) — stdlib `tls_connect` doesn't expose the SSL_CTX so sandhi can't advertise ALPN. Auto-selection between h2 and 1.1 falls back to 1.1 until both clear.

When both clear, ~80 lines of sandhi-side wiring lights up live HTTPS + ALPN + auto-selection without any consumer change.

## Build

```sh
cyrius deps                                                 # resolve stdlib deps
cyrius build programs/smoke.cyr build/sandhi-smoke         # smoke link proof
cyrius test  tests/sandhi.tcyr                              # core (481 assertions)
cyrius test  tests/h2.tcyr                                  # h2-specific (153 assertions)
cyrius lint  src/*.cyr src/http/*.cyr                       # static checks
CYRIUS_DCE=1 cyrius build programs/smoke.cyr build/sandhi-smoke   # release-parity
cyrius distlib                                              # → dist/sandhi.cyr
```

Toolchain pin: `cyrius.cyml [package].cyrius` is the source of truth; never create a `.cyrius-toolchain` file.

## Why the name

*"services"* was the placeholder in both agnosticos and cyrius roadmaps through 2026-04-24. The name sandhi was assigned that day after confirming the planned crate had never received a proper one. Sandhi fits the AGNOS multilingual naming register (hoosh, sakshi, mabda, sigil, patra, yantra, sit/smriti, kula…) and its linguistic meaning — *rules at the boundary where two units meet* — is structurally identical to the crate's engineering purpose.

## License

GPL-3.0-only.

---

*Part of [AGNOS](https://github.com/MacCracken/agnosticos). Named 2026-04-24.*
