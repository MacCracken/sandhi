# sandhi — Roadmap

> Milestone plan toward fold-into-Cyrius-stdlib. State lives in [`state.md`](state.md); this file is the sequencing.

## Guiding objective

**Fold into Cyrius stdlib before v5.6.x closeout** (per the cyrius roadmap `sandhi repo extraction` item). Every M-level decision is made against *"is this what stdlib wants to carry long-term?"* — speculative surface area doesn't survive that filter and shouldn't land pre-fold.

## Milestones

### M0 — Scaffold (v0.1.0) — ✅ shipped 2026-04-24

- `cyrius init sandhi` + library-shape manifest (`[lib] modules`, `programs/smoke.cyr`, no top-level `main()`)
- Submodule skeletons across `http/`, `rpc/`, `discovery/`, `tls_policy/`, `server/`
- ADR 0001 captures naming + compose-don't-reimplement thesis
- Docs scaffolded per [first-party-documentation.md](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)
- Registration with agnosticos shared-crates awaits greenlight per current discipline (tag-time bumps only)

### M1 — `lib/http_server.cyr` lift-and-shift (v0.2.0)

*The migration item from the cyrius roadmap. Does the structural move before the feature work.*

- Copy `lib/http_server.cyr` contents verbatim into `src/server/mod.cyr`
- Add alias in stdlib: `lib/http_server.cyr` becomes a thin passthrough to `src/server/mod.cyr` symbols (preserves downstream compat)
- `dist/sandhi.cyr` bundle starts being produced by `cyrius distlib`
- Retire the stdlib alias at fold-into-stdlib (M6)

**Acceptance**: existing `lib/http_server.cyr` consumers build green against the aliased stdlib; sandhi's own smoke program exercises the migrated symbols.

### M2 — `sandhi::http::client` real implementation (v0.3.0)

*Absorbs the v5.7.x `lib/http.cyr depth` roadmap item (redundant with sandhi picking up client-side depth).*

- Full method surface: POST, PUT, DELETE, PATCH, HEAD (GET stays delegated to stdlib `http.cyr`)
- Custom headers via `sandhi::http::headers`
- HTTPS — when URL is `https://`, route through `lib/tls.cyr` before sending; transparent to callers
- Redirect following — opt-in, bounded (default max 5 hops), RFC 7231 semantics
- Chunked transfer encoding parse
- HTTP/1.1 request line with explicit `Connection: close` (behavior-equivalent to stdlib HTTP/1.0; standards-current)

**Acceptance**: live `sandhi_http_post("https://example.com/api/...", headers, body, len)` round-trips cleanly; all methods tested; redirect + chunked tcyr regression tests green.

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

### M6 — Fold into Cyrius stdlib (v1.0.0)

*Target: before v5.6.x closeout.*

- Coordinate with cyrius agent for the stdlib-side change
- `cyrius distlib` produces a clean self-contained `dist/sandhi.cyr`
- Cyrius stdlib adds `lib/sandhi.cyr` vendored from the bundle
- Downstream consumers switch from `[deps.sandhi]` to plain stdlib include
- Interim `lib/http_server.cyr` alias retires — now handled by `lib/sandhi.cyr`'s server module
- sandhi repo enters maintenance mode; subsequent patches land via the Cyrius release cycle

**Acceptance**: consumer repos (yantra, hoosh, ifran, daimon, mela, vidya, sit-remote, ark-remote) all build against stdlib-folded sandhi without pins. `dist/sandhi.cyr` is byte-identical to `lib/sandhi.cyr` at the fold commit.

## What sandhi does NOT plan to do

Explicit non-goals (to survive the fold-into-stdlib filter):

- **Reimplement network primitives.** Those stay in stdlib.
- **Ship its own config parser.** Stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics.** bote + t-ron own protocol; sandhi::rpc::mcp is transport only.
- **Be a generic "service framework."** Keep the surface small and specific to what AGNOS consumers actually need. If something more general is called for, it's a case for the caller to own, not sandhi.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively.** Add only when a second consumer needs the same pattern.

## Why this roadmap exists

The fold-into-stdlib target is aggressive (weeks, not months). That constraint forces scope discipline — the roadmap's shape is "minimum viable + what existing consumers actually need + nothing speculative." M6's acceptance criteria are checked by existing repos continuing to build, not by new features landing.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md) for the naming + thesis; [`state.md`](state.md) for live progress.
