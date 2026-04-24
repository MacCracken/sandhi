# 0001 — sandhi is a composer, not a reimplementer

**Status**: Accepted
**Date**: 2026-04-24

> **Thesis**: stdlib owns the thin network primitives (`http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`, `net.cyr`, `base64.cyr`, `http_server.cyr`). sandhi composes those primitives into the full-featured client patterns + service discovery that multiple AGNOS consumers need. Same relationship sakshi has to logging, mabda to GPU primitives, sankoch to compression. See also [agnosticos `design-patterns.md` §9 *Reference Don't Mimic*](https://github.com/MacCracken/agnosticos/blob/main/docs/design-patterns.md#9-reference-dont-mimic) — sandhi is not "Cyrius's gRPC" or "Cyrius's nghttp2"; it's the shape AGNOS consumers actually need, at the scale AGNOS actually operates.

## Context

Two pre-existing planning pointers named a "services" crate:

1. **agnosticos/docs/development/roadmap.md** Future Shared Crates table — *"Service mesh: Cyrius services need shared HTTP/TCP/TLS layer + service discovery. Like sakshi for services."*
2. **cyrius/docs/development/roadmap.md** Deferred consumer projects — *"Services repo extraction: lib/http_server.cyr is currently interim stdlib; planned to extract to a dedicated services repo as a tagged dep."*

Both referenced a named crate that had never actually been named. Both identified the same need: stdlib network primitives were growing, but downstream consumers (vidya, hoosh, ifran, daimon, mela, yantra, future sit-remote, future ark-remote) kept re-implementing the same client patterns (POST with headers, HTTPS unification, JSON-RPC dispatch, service lookup) against the thin stdlib base.

Two structural questions were open on 2026-04-24:

1. **Grow stdlib directly, or scaffold a sibling crate?**
   - Growing stdlib: every consumer gets the depth for free once shipped; no transitive-dep problem. But stdlib bloats, and not every consumer needs the full surface (someone using Cyrius for a CLI tool doesn't need JSON-RPC dispatch).
   - Sibling crate: cleaner separation; stdlib stays thin; consumers that don't need service patterns don't pay for them. Follows the established precedent of mabda / sankoch / sigil / sakshi (all started as sibling crates, folded to stdlib when mature).
2. **What's the name?**
   - *"services"* was the functional placeholder in both roadmaps. English, generic, outside the AGNOS multilingual naming register (hoosh, sakshi, mabda, sigil, patra, yantra, sit / smriti, kula, dhara, …).
   - Exhaustive search confirmed no proper name had ever been assigned. Naming gap masquerading as lost memory.

## Decision

**sandhi** (Sanskrit सन्धि — *junction, connection, joining*) is scaffolded as a sibling crate that composes stdlib network primitives into service-boundary patterns. Target fold-into-stdlib: **before v5.6.x closeout**, pulled in from the original "after v5.6.x, before v6.0.0" plan per the 2026-04-24 scope decision.

Scope of what sandhi owns:

- **`sandhi::http`** — full HTTP client (POST/PUT/DELETE/PATCH/HEAD, headers, HTTPS unification via `tls.cyr`, redirect following, eventually keepalive / conn pooling).
- **`sandhi::rpc`** — JSON-RPC dialects (WebDriver wire, Appium, MCP-over-HTTP). Streaming responses. Dialect-aware error envelopes.
- **`sandhi::discovery`** — service discovery. mDNS, daimon-registered lookup, chained fallback. The genuinely new surface that didn't exist anywhere.
- **`sandhi::tls_policy`** — cert pinning, mTLS, trust-store management. Wraps `lib/tls.cyr` FFI today; transitions to native TLS when Cyrius v5.9.x ships.
- **`sandhi::server`** — lifts `lib/http_server.cyr` out of interim stdlib (per cyrius roadmap), adds routing + middleware + auth primitives.

Scope of what sandhi does **not** own:

- **The primitives themselves.** `http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`, `net.cyr`, `base64.cyr` all stay in stdlib. If a primitive needs depth, that's a stdlib patch, not a sandhi feature.
- **High-level agent orchestration.** daimon owns that.
- **MCP protocol semantics.** bote + t-ron own that. sandhi::rpc carries MCP-over-HTTP as a transport dialect but does not parse MCP message semantics.
- **Cryptographic primitives.** sigil owns every hash / signature / cipher in AGNOS. sandhi::tls_policy uses sigil for cert fingerprint verification, doesn't reimplement.

**Naming rationale**: sandhi in Sanskrit linguistics refers to rules at the boundary where two morphemes or words meet (e.g., *namas + te → namaste*). Engineering-sandhi governs rules at the boundary where two services meet — wire format, cert policy, retry behavior, discovery fallback. Same abstract structure at two scales. Shares Sanskrit roots with vyakarana's grammar domain, which reads as kinship (both layers operate on boundaries) rather than crosstalk.

## Consequences

- **Positive**
  - Stdlib stays thin. Cyrius programs that don't need service patterns don't pay for them.
  - Downstream consumers (yantra, sit-remote, ark-remote, daimon, hoosh, ifran, mela, vidya) share one policy / dialect / discovery layer instead of re-implementing in each.
  - `lib/http_server.cyr` gets a proper home. Current "interim stdlib" status is acknowledged debt; sandhi is where that debt is paid.
  - Fold-into-stdlib precedent is established (sakshi, mabda, sankoch, sigil all did it). sandhi following the same arc is low-risk.
  - The v5.7.x `lib/http.cyr depth` roadmap item becomes redundant — sandhi absorbs it. The `lib/json.cyr depth` item partially absorbs too (stdlib keeps baseline for config/data; RPC-grade handling moves here).
- **Negative**
  - One more crate to maintain during the pre-fold window.
  - Consumers need to add a `[deps.sandhi]` pin until the fold lands.
  - The fold timing is aggressive (before v5.6.x closeout). If it slips, sandhi lives as a sibling crate longer than originally planned.
- **Neutral**
  - Creates a natural home for future service-boundary work (circuit breakers, rate-limit-aware retries, observability hooks) that would otherwise sit ambiguously between stdlib and individual consumers.

## Alternatives considered

- **Grow `lib/http.cyr` + `lib/json.cyr` directly in stdlib (original v5.7.x plan).** Rejected 2026-04-24 in favor of the sandhi-sibling approach for the stdlib-stays-thin argument and the precedent from sakshi / mabda / sankoch / sigil all starting as siblings before folding.
- **Keep "services" as the name.** Rejected — every other AGNOS subsystem has a Sanskrit / Arabic / Persian / Hebrew / Greek name in the multilingual register, and the generic English "services" drifted away from house style. See the README's §"Why the name" for more.
- **Fold directly into Cyrius stdlib without a sibling-crate phase.** Tempting because it skips the `[deps.sandhi]` pin work. Rejected because the shape hasn't been proven under real consumer load yet — the sibling-crate phase is where we learn which submodules are genuinely load-bearing and which are speculative. Skipping straight to stdlib risks committing permanent surface area to things that turn out to be transitory.
- **Split into multiple sibling crates (sandhi-http, sandhi-rpc, sandhi-discovery).** Considered. Rejected — the submodules share enough plumbing (error types, logging via sakshi, the HTTP transport underneath RPC) that splitting would force artificial cross-crate boundaries. If one submodule ends up dramatically larger than its siblings, that's when to consider splitting — not prospectively.
