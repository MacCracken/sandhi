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
- HTTPS via `lib/tls.cyr` wrap — compiles clean; runtime blocked on a stdlib TLS-init issue (see `docs/issues/2026-04-24-fdlopen-getaddrinfo-blocked.md`)
- Redirect following — opt-in via `sandhi_http_options_new()`, bounded (default max 5 hops), RFC 7231 §6.4 semantics (303 → GET, 301/302/307/308 preserve method) ✅
- Chunked transfer encoding decode ✅
- HTTP/1.1 request line with explicit `Connection: close` (behavior-equivalent to stdlib HTTP/1.0; standards-current) ✅
- **Plus**: native UDP DNS resolver (`src/net/resolve.cyr`) added to unblock hostname URLs without waiting for stdlib `fdlopen_getaddrinfo`.

**Acceptance**: live `http://example.com/` round-trip returns 200 end-to-end (`cyrius run programs/http-probe.cyr`). 173 tcyr unit assertions green across headers / URL / response / client / redirect / DNS groups. `sandhi_http_post("https://...")` pending stdlib TLS-init fix; the same code works clean over plain HTTP so the surface is validated, just not the specific TLS transport.

### M3 — `sandhi::rpc` WebDriver + Appium dialects (v0.4.0)

*Unblocks yantra M2 (Firefox + WebKit WebDriver + Android UiAutomator2 + iOS XCUITest backends).*

- `sandhi::rpc::call(endpoint, method, params_json)` generic dispatch
- `sandhi::rpc::webdriver` — W3C WebDriver wire format (Firefox / WebKit)
- `sandhi::rpc::appium` — Appium extensions (Android / iOS)
- `sandhi::rpc::mcp` — MCP-over-HTTP (transport only; bote / t-ron own protocol semantics)
- Streaming response support (SSE / chunked)
- Dialect-aware error envelopes

**Acceptance**: yantra M2 runs `yantra_web_open("firefox")` end-to-end against a headless Firefox via sandhi::rpc::webdriver. Same for Android emulator via Appium dialect.

### M4 — `sandhi::discovery` (v0.5.0)

*The genuinely new surface.*

- `sandhi::discovery::local` — mDNS / local-link resolution
- `sandhi::discovery::daimon` — query daimon's registered-service map
- `sandhi::discovery::chain` — fallback sequence (try backends in order, accept first hit)
- `sandhi::discovery::register` / `deregister` — publish / withdraw a service
- Design: pluggable, no single resolver is load-bearing; chain-resolvers let consumers tolerate resolver outages

**Acceptance**: service registered via daimon is discoverable via `sandhi::discovery::daimon` lookup; chain resolver falls through gracefully when the first resolver is absent.

### M5 — `sandhi::tls_policy` (v0.6.0)

- `sandhi::tls_policy::default` — standard trust store, cert verification on
- `sandhi::tls_policy::pinned(fp)` — SPKI fingerprint pinning
- `sandhi::tls_policy::mtls(cert, key)` — mTLS client certificates
- `sandhi::tls_policy::trust_store` — custom CA bundle management
- Wraps `lib/tls.cyr` FFI today; transitions to native TLS when Cyrius v5.9.x ships (no sandhi-side change needed when that happens — same policy surface, different underlying TLS impl)

**Acceptance**: pinned-cert tcyr test rejects a cert with wrong fingerprint; mTLS tcyr test authenticates with a client cert; trust-store override works.

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
