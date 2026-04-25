# sandhi — Roadmap

> Milestone plan toward fold-into-Cyrius-stdlib. State lives in [`state.md`](state.md); this file is the sequencing.

## Guiding objective

**Fold into Cyrius stdlib at v5.7.0** via a clean-break fold (see [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) — revised from the original "before v5.6.x closeout" target. At v5.7.0 stdlib deletes `lib/http_server.cyr` and gains `lib/sandhi.cyr` in one event; 5.6.YY releases emit a deprecation warning on any include of `lib/http_server.cyr`. Every M-level decision is made against *"is this what stdlib wants to carry long-term?"* — speculative surface area doesn't survive that filter, and with a clean-break fold it also can't land post-5.7.0 without a stdlib release.

## Milestones

### M0 — Scaffold (v0.1.0) — ✅ shipped 2026-04-24

- `cyrius init sandhi` + library-shape manifest (`[lib] modules`, `programs/smoke.cyr`, no top-level `main()`)
- Submodule skeletons across `http/`, `rpc/`, `discovery/`, `tls_policy/`, `server/`
- ADR 0001 captures naming + compose-don't-reimplement thesis
- Docs scaffolded per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)
- Registration with agnosticos shared-crates awaits greenlight per current discipline (tag-time bumps only)

### M1 — `lib/http_server.cyr` lift-and-shift (v0.2.0) — ✅ shipped 2026-04-24

*The migration item from the cyrius roadmap. Does the structural move before the feature work. No stdlib-side alias — stdlib keeps its own copy unchanged through 5.6.x and deletes it in the v5.7.0 clean-break fold per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).*

- Copy `lib/http_server.cyr` contents verbatim into `src/server/mod.cyr` ✅
- `cyrius.cyml` drops `http_server` from `[deps.stdlib]`; sandhi's build pulls the local copy ✅
- Smoke program references a migrated symbol so DCE doesn't elide the module ✅
- Pure-helper unit tests exercising the lifted surface ✅
- `dist/sandhi.cyr` producible by `cyrius distlib` (first formal bundle pairs with M6 fold prep)

**Acceptance**: sandhi's smoke program exercises the migrated symbols; `cyrius test tests/sandhi.tcyr` green (28 assertions); stdlib `lib/http_server.cyr` remains untouched through the 5.6.x window. Coordination for the 5.6.YY deprecation warning and the 5.7.0 delete is on the cyrius agent's side, not sandhi's.

### M2 — `sandhi::http::client` real implementation (v0.3.0) — ✅ shipped 2026-04-24

*Absorbed the v5.7.x `lib/http.cyr depth` roadmap item. sandhi's GET is first-party (not delegated back to stdlib `http.cyr`) since the stdlib version is HTTP/1.0-only and doesn't do HTTPS.*

- Full method surface: GET, POST, PUT, DELETE, PATCH, HEAD ✅
- Custom headers via `sandhi::http::headers` (real key-value store) ✅
- HTTPS via `lib/tls.cyr` wrap — compiles clean; runtime blocked on a libssl-side pthread deadlock in `SSL_connect` (see `docs/issues/2026-04-24-libssl-pthread-deadlock.md`)
- Redirect following — opt-in via `sandhi_http_options_new()`, bounded (default max 5 hops), RFC 7231 §6.4 semantics (303 → GET, 301/302/307/308 preserve method) ✅
- Chunked transfer encoding decode ✅
- HTTP/1.1 request line with explicit `Connection: close` (behavior-equivalent to stdlib HTTP/1.0; standards-current) ✅
- **Plus**: native UDP DNS resolver (`src/net/resolve.cyr`) added to unblock hostname URLs without waiting for stdlib `fdlopen_getaddrinfo`.

**Acceptance**: live `http://example.com/` round-trip returns 200 end-to-end (`cyrius run programs/http-probe.cyr`). 173 tcyr unit assertions green across headers / URL / response / client / redirect / DNS groups. `sandhi_http_post("https://...")` pending stdlib TLS-init fix; the same code works clean over plain HTTP so the surface is validated, just not the specific TLS transport.

### M3 — `sandhi::rpc` WebDriver + Appium + MCP (v0.4.0) — ✅ shipped 2026-04-24

*Unblocks yantra M2 (Firefox + WebKit WebDriver + Android UiAutomator2 + iOS XCUITest backends) and daimon MCP-over-HTTP dispatch.*

- `sandhi::rpc::call(url, http_method, body_json, dialect)` generic dispatch ✅
- `sandhi::rpc::webdriver` — W3C WebDriver wire format ✅ (session lifecycle, navigation, element interaction, `execute/sync`)
- `sandhi::rpc::appium` — Appium extensions ✅ (context switching, app lifecycle, `mobile_exec`, screenshot, source)
- `sandhi::rpc::mcp` — MCP-over-HTTP (transport only — protocol semantics stay in bote / t-ron per ADR 0001) ✅
- **Dialect-aware error envelopes** — WebDriver `value.error` / `value.message`; JSON-RPC `error.code` / `error.message`; generic no-envelope passthrough ✅
- **rpc/json** — nested JSON builder + dotted-path extractor ✅ (stdlib json.cyr is flat-only; sandhi owns this for RPC)
- **Streaming (SSE / chunked)** — deferred to M3.5. Chunked framing is solved in `src/http/response.cyr`; SSE-as-iterator awaits a consumer ask.

**Acceptance**: all four dialect modules compile clean and unit tests verify URL shape + envelope shape + error extraction. Live `yantra_web_open("firefox")` needs yantra M2 work + a running geckodriver — sandhi side is complete, consumer-side integration happens in the yantra repo.

### M4 — `sandhi::discovery` (v0.5.0) — ✅ shipped 2026-04-24

*The genuinely new surface.*

- `sandhi::discovery::service` + `resolver` — shared type vocabulary (service struct, fn-ptr-based resolvers) ✅
- `sandhi::discovery::chain` — fallback sequence, first-hit wins, nesting supported ✅
- `sandhi::discovery::daimon` — HTTP-backed resolver against daimon registry (GET /services/{name}) ✅
- `sandhi::discovery::register` / `deregister` — publish/withdraw via daimon ✅
- `sandhi::discovery::local` — **interface only** for M4. mDNS multicast impl deferred because stdlib `net.cyr` doesn't expose `IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` yet. Stub resolver integrates with the chain today and starts resolving the day the real impl lands — no API churn.
- Design: pluggable, no single resolver load-bearing; `chain_as_resolver` lets a chain act as one backend within another chain ✅

**Acceptance**: chain resolver falls through gracefully when the first resolver misses or is unreachable (verified via unit tests with stub resolvers); daimon HTTP contract is the reference doc + unit-tested against synthetic response bodies. Live daimon round-trip acceptance waits for daimon itself to implement the registry endpoints — sandhi side is complete.

### M5 — `sandhi::tls_policy` (v0.6.0) — ✅ surface shipped 2026-04-24 (enforcement stubbed)

- `sandhi_tls_policy_new_default` — standard trust store, cert verification on ✅
- `sandhi_tls_policy_new_pinned(fp)` — SPKI fingerprint pinning ✅ (constructor + fingerprint helpers)
- `sandhi_tls_policy_new_mtls(cert, key)` — mTLS client certificates ✅ (constructor)
- `sandhi_tls_policy_new_trust_store(bundle)` — custom CA bundle ✅ (constructor)
- `sandhi_tls_policy_combine` — additive, right-wins, null-safe ✅
- `sandhi_conn_open_with_policy` — integration point ✅ (delegates to `sandhi_conn_open` until stdlib TLS-init stabilizes; API is stable, enforcement is the only part that fills in later)
- Wraps `lib/tls.cyr` FFI today; transitions to native TLS when Cyrius v5.9.x ships (no sandhi-side change needed — same policy surface, different underlying TLS impl)

**Acceptance** (surface): policy constructors + combine + fingerprint normalization unit-tested (41 assertions covering every constructor, composition semantics, fingerprint format tolerance, byte-length decoding, encoding).

**Acceptance (live enforcement) — pending**: the pinned-cert-rejects test and mTLS-authenticates test both need live HTTPS to work, which is blocked on the libssl-pthread-deadlock issue (`docs/issues/2026-04-24-libssl-pthread-deadlock.md`). The TODO list at the top of `src/tls_policy/apply.cyr` enumerates the exact OpenSSL calls to fill in — ~50 lines once `SSL_connect` round-trips, no API change.

### 0.7.1 — Quick-wins patch — ✅ shipped 2026-04-24

*Hours-scale items from the 0.7.0 external security + gaps review. No
behavior change for existing callers; targeted correctness + ergonomics.*

- Default `User-Agent: sandhi/<version>` + `Accept-Encoding: identity`
  request headers (override-preserving)
- `sandhi_http_options_max_response_bytes` — caps the buffered client
  scratch (previously a 256 KB silent-truncation)
- `sandhi_http_stream_opts` — opts-aware streaming variant honoring
  the same cap across header drain + body accumulator + chunked-decode
  output buffer
- `err_message` slot on the response struct (reserved for 0.8.x security
  diagnostics; ABI-breaking now so it doesn't break later)
- CI `workflow_call:` trigger added so `release.yml` can reuse it
- `src/main.cyr` docstring corrected — previously claimed surface that
  didn't exist (keepalive / pooling / routing)

### 0.7.2 — Medium items (ergonomics + reliability)

*Days-scale items from the same review. Targeted at reliability and
consumer ergonomics before the HTTP/2 feature push. No new dialects,
no new security surface — that's 0.8.x.*

- **Phase-2 timeouts** ✅ shipped 0.7.2 — `read_ms` / `write_ms`
  via `SO_RCVTIMEO` / `SO_SNDTIMEO`. `SANDHI_ERR_TIMEOUT` now raised.
  **`connect_ms` + `total_ms`** ✅ shipped 0.7.3 — non-blocking
  connect via `O_NONBLOCK` + `poll(POLLOUT)` + `getsockopt(SO_ERROR)`;
  monotonic deadline via `clock_now_ms` threaded through every I/O
  phase. Local syscall constants for `SYS_POLL` / `SYS_GETSOCKOPT`
  defined in `conn.cyr` (Linux x86_64). No stdlib ask needed.
- **AAAA (IPv6) DNS** in `src/net/resolve.cyr`. A-only today. Ship
  the resolver first; Happy Eyeballs (RFC 6555) can wait. Adds a
  local `sockaddr_in6()` builder + `sock_connect6()` wrapper since
  stdlib exposes `AF_INET6=10` but no v6-specific verbs.
- **DNS hardening** — TXID randomness (via `/dev/urandom` as `sigil`
  does) + ephemeral source-port rotation + answer-name match against
  question + compression-pointer loop-detection. The last two were
  originally on the 0.9.x P1 list; pulled forward here because
  they're touching the same file as the TXID work, and landing them
  together is strictly cheaper than returning for them later. EDNS0
  + 0x20 case randomization stay deferred.
- **sakshi tracing hooks** — one span each at `_sandhi_http_do`,
  `sandhi_rpc_call`, `sandhi_resolve_ipv4`. ~50 lines in a new
  `src/obs/trace.cyr` wrapping `sakshi_span_enter(name, len)` /
  `_exit()` from stdlib `lib/sakshi.cyr`.
- **Server caps** in `src/server/mod.cyr` — `max_concurrent_connections`,
  `per_connection_idle_ms` (30000 default). Go `net/http.Server`
  defaults as the reference.
- **Retry-with-backoff** wrapper verbs for idempotent methods only —
  `sandhi_http_get_retry` / `_head_retry` / `_put_retry` / `_delete_retry`.
  Exponential 50 → 100 → 200 ms capped via `clock_now_ms()`. POST
  retry stays explicit.

**Deferred from 0.7.2 at planning time**:

### 0.7.3 — Connect/total timeouts — ✅ shipped 2026-04-24

*Closes the two deferrals from 0.7.2's timeout work. With this patch,
sandhi's HTTP client has the full timeout surface — connect, read,
write, and end-to-end — that production consumers expect.*

- `connect_ms` via non-blocking connect: `O_NONBLOCK` + `connect()`
  → `poll(POLLOUT, ms)` → `getsockopt(SO_ERROR)`. Local syscall
  constants `_SANDHI_SYS_POLL=7`, `_SANDHI_SYS_GETSOCKOPT=55` in
  `conn.cyr`. Restores blocking mode on every exit path.
- `total_ms` via monotonic deadline: `clock_now_ms() + total_ms`
  computed at entry, threaded through `_sandhi_http_exchange` and
  `_sandhi_stream_run`. New `_sandhi_http_clamp_ms` helper bounds
  effective `connect_ms` against the deadline. New
  `sandhi_conn_recv_all_deadline` variant for the recv loop.
- Module-level `_sandhi_conn_last_err` lets the caller distinguish
  `SANDHI_ERR_TIMEOUT` from `SANDHI_ERR_CONNECT` / `_TLS` precisely
  (was: collapsed by `use_tls` flag).
- Per-hop `total_ms` semantics for redirect chains — each hop gets
  a fresh budget. End-to-end across hops is `max_hops × total_ms`;
  if a tighter end-to-end bound is needed, lower max_hops or shorten
  per-hop total_ms. Documented in the follow-loop comment.
- Live-network blackhole tests (TEST-NET-1 192.0.2.1) verify
  `connect_ms` and `total_ms` fire within budget against an unrouted
  destination.

**Deferred to a future patch**: end-to-end-across-redirects
(`overall_ms` option) — wait for a consumer ask. Multi-threaded
client model (which would need `_sandhi_conn_last_err` lifted to a
per-call ctx) — unblocked by 0.8.0's pool work.

### 0.7.2 deferred (continued)

- **Connection pool / keep-alive** → moved to **0.8.0** alongside
  HTTP/2. Rationale: h2 multiplexes streams over one connection, which
  changes the pool's checkout shape (per-stream rather than per-
  connection). Designing both at once avoids a mid-release refactor.

### 0.8.0 — HTTP/2 + connection pool (bundled) — ✅ shipped 2026-04-24

*Eight commit-sized "bites" landed: pool + 1.1 keep-alive (Bite 1),
HPACK + Huffman decode (Bites 2 + 2b), h2 frames (Bite 3), ALPN
surface (Bite 4), h2 connection lifecycle split into
scaffolding/request/response (Bites 5a/5b/5c), pool h2 glue (Bite
6), public h2 dispatch verb + version ship (Bite 7).*

- **Pool** (`src/http/pool.cyr`) — keyed by `host:port:tls`, LIFO
  take with stale-skip, FIFO eviction at cap. Default 8 conns/route,
  90 s idle timeout.
- **HPACK** (`src/http/h2/hpack.cyr` + `huffman.cyr`) — full RFC
  7541, all 5 header-field representations, Huffman decode tested
  against RFC C.4.1.
- **h2 frames** (`src/http/h2/frame.cyr`) — RFC 7540 §4.1+§6 wire
  format for SETTINGS / PING / WINDOW_UPDATE / RST_STREAM / GOAWAY
  + frame header.
- **ALPN surface** (`src/tls_policy/alpn.cyr`) — wire-format
  encoder ships; runtime negotiation stubbed (libssl + stdlib hook
  blockers).
- **h2 connection lifecycle** (`src/http/h2/conn.cyr` +
  `request.cyr` + `response.cyr`) — preface + SETTINGS handshake,
  HEADERS encoding via HPACK, frame loop dispatcher with
  CONTINUATION reassembly + DATA accumulation + PADDED handling.
- **Public h2 verb** (`src/http/h2/dispatch.cyr`) —
  `sandhi_h2_request(h2c, method, url, headers, body, body_len)`
  for manual h2 use.

**Auto-selection deferred to 0.8.1** because the libssl-pthread-
deadlock + missing-stdlib-tls-hook blockers mean live h2 never
fires today anyway.

### 0.8.1 — Auto-selection wiring — ✅ shipped 2026-04-24

*Strictly additive — no existing call-site behavior changes.*

- New `sandhi_http_request_auto(method, url, headers, body,
  body_len, opts)` in `dispatch.cyr` — checks the attached pool
  for an h2 conn matching the URL's route, dispatches via
  `sandhi_h2_request` if found, falls through to
  `_sandhi_http_dispatch` (1.1 path) otherwise.
- Per-method auto verbs (`sandhi_http_get_auto`, `_post_auto`, etc.)
  matching the 1.1 surface shape.
- Filed `docs/issues/2026-04-24-stdlib-tls-alpn-hook.md` for the
  upstream-ask: stdlib `tls_connect` needs an SSL_CTX hook so
  sandhi can call `SSL_CTX_set_alpn_protos` to advertise h2.

### 0.9.0 — Phase 1 security (P0 sweep)

*Ship-stopper findings from the 0.7.0 external audit. Each fix is
its own focused patch within the release, with a regression test.
Behavior changes are visible (e.g., redirects start stripping
`Authorization` cross-origin) — semver-wise this is a minor bump,
not a patch.*

1. **Chunked decoder**: require terminal 0-chunk + footer CRLF;
   `seen_digit` guard; reject `size == 0` mid-stream as truncation,
   not success. (`src/http/response.cyr`)
2. **CL + TE coexistence reject**: when both headers are present,
   400 on server / `SANDHI_ERR_PROTOCOL` on client. RFC 7230
   §3.3.3 mandatory. (`src/http/response.cyr` + `src/server/mod.cyr`)
3. **Chunk-size overflow guard**: reject chunk sizes > 2^31
   explicitly; unsigned-safe comparison before `memcpy`.
   (`src/http/response.cyr`)
4. **Redirect credential strip**: on each hop, compare scheme +
   host + port against the previous; strip `Authorization` /
   `Cookie` / `Proxy-*` when authority changes; refuse https→http;
   opt-in private-IP block for daimon-class consumers.
   (`src/http/client.cyr`)
5. **TLS-policy fail-closed**: when
   `sandhi_tls_policy_enforcement_available() == 0` AND policy has
   `PINNED | MTLS | CUSTOM_TRUST`, refuse the connection rather
   than silently downgrading. (`src/tls_policy/apply.cyr` +
   `src/http/client.cyr`)

### 0.9.1 — Phase 2 security (P1 sweep)

*Hardening / defense-in-depth. Each fix small and isolated; bundled
into one minor because individually they don't warrant releases.*

- **SSE re-entrance fix** — thread parser state via ctx struct
  rather than module-scope globals. (`src/http/sse.cyr`)
- **SSE id with NUL** — ignore per WHATWG (currently stored).
  (`src/http/sse.cyr`)
- **Header duplicate detection** for `Host` / `Content-Length` /
  `Transfer-Encoding` at parse time. (`src/http/headers.cyr`)
- **Header CRLF / NUL validation** on `sandhi_headers_add` / `_set`.
  (`src/http/headers.cyr`)
- **SPKI constant-time compare** — replace `streq` short-circuit
  with full-length compare. (`src/tls_policy/fingerprint.cyr`)
- **CL strict parse** — reject `+` / `,` / `0x` / multi-value on
  client + server. (`src/http/response.cyr` + `src/server/mod.cyr`)
- **URL port overflow guard** — clamp digit count before the
  65535 check. (`src/http/url.cyr`)
- **JSON escape-state tracking** — fix `\\\\` (consecutive
  backslashes) handling in dotted-path skip. (`src/rpc/json.cyr`)

### 0.9.2 — Pre-fold closeout

*Surface freeze + bundling. After this, no new verbs land until
post-fold (only-on-second-consumer-ask).*

- **Server symbol rename** — `http_get_method` /
  `http_send_response` / `http_server_run` etc. → `sandhi_server_*`.
  Last chance before the v5.7.0 fold freezes the names in stdlib
  permanently. Transitional `http_*` aliases retained through
  0.9.2; dropped at 1.0.0.
- **Surface freeze** — no new verbs past this point unless a second
  consumer asks. Speculative surface is doubly discouraged by a
  clean-break fold.
- **`dist/sandhi.cyr` generation** via `cyrius distlib`. First
  formal bundle, byte-for-byte identical to what stdlib will
  vendor at 1.0.0.
- **Consumer pin uplift** — coordinate with yantra / daimon /
  hoosh / ifran / sit / ark / mela to pin 0.9.2 tags for their
  v5.7.0-compatible cuts.

### Carried beyond 0.9.x (only when blockers clear)

- **ALPN runtime hookup** — needs the `lib/tls.cyr` SSL_CTX hook
  per `docs/issues/2026-04-24-stdlib-tls-alpn-hook.md`. When
  upstream lands, ~30 lines of sandhi-side changes.
- **Live HTTPS** — needs the libssl-pthread-deadlock fix per
  `docs/issues/2026-04-24-libssl-pthread-deadlock.md`.
- **Huffman encode** — wire-size optimization only (raw is
  spec-permitted). Add when a consumer reports bandwidth
  pressure.
- **HTTP/2 redirects + retry** — h2 dispatch path skips both
  today; auto-selection falls through to 1.1 when redirects/retry
  are needed via the existing `*_opts` variants. Bundle if a
  consumer wants h2-with-redirects.

### M6 — Fold into Cyrius stdlib (v1.0.0) — clean-break at v5.7.0

*Per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md): one event at the Cyrius v5.7.0 release gate, not a separate sandhi milestone. The 5.6.YY window is the notice period; 5.7.0 is the cutover.*

**5.6.YY window (before fold)**
- sandhi lands M2–M5 as a sibling crate; consumers pin via `[deps.sandhi]` for the non-server features
- Cyrius 5.6.YY releases emit a deprecation warning on `include "lib/http_server.cyr"` — names `lib/sandhi.cyr` as the replacement and v5.7.0 as the cutover
- `cyrius distlib` produces a clean self-contained `dist/sandhi.cyr` ready for upstream vendor
- sandhi freezes the public surface once M5 is green (no speculative verbs past that point)

**v5.7.0 (the fold event)**
- Cyrius stdlib adds `lib/sandhi.cyr` vendored from `dist/sandhi.cyr`
- Cyrius stdlib deletes `lib/http_server.cyr` — no alias, no passthrough, no empty stub
- Downstream consumers' 5.7.0-compatible tags switch `include "lib/http_server.cyr"` → `include "lib/sandhi.cyr"`, and any `[deps.sandhi]` pin is dropped
- sandhi repo enters maintenance mode; subsequent patches land via the Cyrius release cycle

**Acceptance** (checked at the 5.7.0 release gate, not in this repo):
- Consumer repos (yantra, hoosh, ifran, daimon, mela, vidya, sit-remote, ark-remote) build against 5.7.0 stdlib without `[deps.sandhi]` pins
- `dist/sandhi.cyr` is byte-identical to `lib/sandhi.cyr` at the fold commit
- No include of `lib/http_server.cyr` survives anywhere in AGNOS

### Post-v1 (stdlib-maintenance window)

*Deferred from the 0.7.0 review. Each item waits on a second-consumer
ask before it ships; the fold freezes the public surface, so anything
here lands via the Cyrius release cycle, not sandhi's.*

- **CONNECT / proxy tunneling** — no documented AGNOS egress-proxy
  need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing APIs. RFC 6265
  is a regret-magnet; wait for a real ask.
- **OCSP stapling / CT log check / HSTS preload** — operational
  footguns (HPKP retirement lessons). Pin + custom trust store covers
  AGNOS's actual threat model.
- **JSON Merge Patch (RFC 7396)** / **JSON-RPC 2.0 batch** — batch
  is the likelier ask (MCP tool-discovery latency); wait for it.
- **gRPC-Web / GraphQL-over-HTTP** — explicit non-goals.
- **Arena-per-request allocator** — profile first; stdlib `alloc` may
  already be a bump allocator.
- **Fuzzing harness** — Cyrius toolchain doesn't ship AFL/libFuzzer
  equivalent yet. Revisit when it does.
- **mDNS lookup + publishing** — blocked on stdlib `net.cyr`
  multicast primitives (`IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` /
  `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`). Request
  as a targeted stdlib patch when multicast becomes a priority for
  any consumer.
- **Session-resumption cache in tls_policy** — right moment is the
  v5.9.x native-TLS transition.
- **TLS ALPN extensions beyond `http/1.1`** — `h2` ships in 0.8.0;
  anything beyond that waits for a consumer ask.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD
  intrinsics; byte-at-a-time is perfectly adequate at SSE / HTTP
  parsing rates observed so far.

## What sandhi does NOT plan to do

Explicit non-goals (to survive the fold-into-stdlib filter):

- **Reimplement network primitives.** Those stay in stdlib.
- **Ship its own config parser.** Stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics.** bote + t-ron own protocol; sandhi::rpc::mcp is transport only.
- **Be a generic "service framework."** Keep the surface small and specific to what AGNOS consumers actually need. If something more general is called for, it's a case for the caller to own, not sandhi.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively.** Add only when a second consumer needs the same pattern.

## Why this roadmap exists

The fold-into-stdlib target is aggressive — sandhi's sibling-crate phase is the 5.6.x window, with the fold happening in one event at the v5.7.0 release gate. That constraint forces scope discipline: the roadmap's shape is "minimum viable + what existing consumers actually need + nothing speculative." M6's acceptance criteria are checked at the 5.7.0 release gate by existing repos continuing to build, not by new features landing in this repo.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) for the naming + thesis, [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) for the clean-break fold decision, and [`state.md`](state.md) for live progress.
