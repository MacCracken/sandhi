# 0002 — Clean-break fold at Cyrius v5.7.0

**Status**: Accepted
**Date**: 2026-04-24

> **Thesis**: sandhi folds into Cyrius stdlib in one event at v5.7.0 — `lib/http_server.cyr` is deleted, `lib/sandhi.cyr` arrives. No aliases, no passthroughs, no two-copies window. Consumers get a deprecation warning in 5.6.YY releases leading up to the cutover; no silent break.

## Context

ADR 0001 assigned sandhi the "fold-into-stdlib before v5.6.x closeout" target and paired it with a migration plan (roadmap M1, M6) built around stdlib-side aliases: stdlib `lib/http_server.cyr` would become a passthrough to sandhi symbols during a migration window, and the alias would retire at fold.

sandhi's side of M1 landed 2026-04-24 as v0.2.0 (verbatim lift into `src/server/mod.cyr`). Before starting the stdlib-side alias work, the plan was reconsidered. Two concerns with the alias-window model:

1. **Two copies, one source of truth.** During the alias window, the canonical code lives in sandhi while stdlib `lib/http_server.cyr` is a thin passthrough. Any stdlib-side divergence (hotfix applied to the alias and not upstreamed, or vice versa) creates silent drift that's invisible at the consumer.
2. **Two migration events, not one.** Consumers would cut over twice: once to adjust to the alias (minimal), and again at fold when the alias retires. Each cutover is a release-notes item, a pin-bump, a potential-bug surface.

Cyrius v5.7.0 is a natural consolidation point: it's the release where the `lib/http.cyr depth` roadmap item was already going to land (which sandhi absorbs), and several other stdlib reshuffles are planned.

## Decision

**One event at Cyrius v5.7.0** replaces the alias-window plan:

- **Stdlib drops `lib/http_server.cyr` entirely at v5.7.0.** No passthrough, no empty stub. Any include of it fails at build time.
- **Stdlib gains `lib/sandhi.cyr` at v5.7.0** via the `cyrius distlib` bundle produced from this repo.
- **Consumers update their includes** from `lib/http_server.cyr` → `lib/sandhi.cyr` in the same release cycle they adopt 5.7.0.
- **5.6.YY releases emit a deprecation warning** when `lib/http_server.cyr` is included. The warning text names `lib/sandhi.cyr` as the replacement and the v5.7.0 cutover date. Adequate notice without coupling two copies together.
- **M6 (fold-into-stdlib) collapses into the v5.7.0 release event** — no longer a separate sandhi milestone. The roadmap's M6 acceptance criteria fold into Cyrius's 5.7.0 release gate.

sandhi continues as a sibling crate through 5.6.x for M2–M5 feature work (HTTP client depth, RPC dialects, discovery, TLS policy). Those milestones must land pre-5.7.0 so the folded `lib/sandhi.cyr` ships with the full intended surface — the fold freezes the public surface.

## Consequences

- **Positive**
  - Single source of truth throughout. sandhi owns the server module end-to-end; stdlib never ships a competing copy.
  - Consumers make one include change (`lib/http_server.cyr` → `lib/sandhi.cyr`) when they adopt 5.7.0 — same release-cycle cost as any other stdlib reshuffle.
  - No `[deps.sandhi]` pin-management window specifically for the server module — the lift-and-shift work done in sandhi v0.2.0 goes straight to stdlib at 5.7.0.
  - Deprecation warning in 5.6.YY gives consumers a clear, noisy signal during the notice window without creating a stdlib-owned copy of the code.
  - M6 collapses into a Cyrius release gate, not a separate sandhi release.
- **Negative**
  - Timeline pressure on M2–M5 concentrates: anything sandhi plans to ship must land pre-5.7.0 since the public surface freezes at fold. Speculative surface is doubly discouraged.
  - Consumers that miss the deprecation warning (or pin to 5.6.YY and skip straight to 5.7.0 without reading release notes) will see a hard build break on first 5.7.0 build. Acceptable because (a) the warning is there and (b) a hard break is discoverable in a way that a silent alias isn't.
  - During 5.6.x, consumer crates that want the non-server sandhi features (HTTP client, RPC dialects, discovery, TLS policy) still carry a `[deps.sandhi]` pin. Those pins retire at 5.7.0.
- **Neutral**
  - ADR 0001's fold-timing clause ("before v5.6.x closeout") is superseded in part by this ADR. The thesis (compose-don't-reimplement, sibling-before-fold, naming rationale, submodule ownership) remains accepted.
  - The 5.6.YY deprecation warning is a Cyrius-side change, not a sandhi-side change. Coordination with the cyrius agent; sandhi repo is unaffected.

## Alternatives considered

- **Alias-window migration (original M1/M6 plan).** Rejected for the two-copies-drift risk and the unnecessary second migration event.
- **No fold — sandhi as permanent sibling.** Rejected because the stdlib-stays-thin argument still wants one place downstream consumers look for service-boundary code, and `lib/sandhi.cyr` at 5.7.0 delivers that. Permanent sibling also creates indefinite `[deps.sandhi]` pin maintenance across every consumer crate.
- **Silent cutover with no deprecation warning in 5.6.YY.** Rejected — a build-time warning is cheap, clearly scoped, and gives consumers an early-binding signal without creating a second copy of the code. A silent break at 5.7.0 saves nothing and costs discoverability.
- **Move the fold to a 5.7.YY later than 5.7.0 to gain more sibling-crate runway.** Considered. Rejected because 5.7.0 is the cleanest vehicle (other stdlib reshuffles ride along) and pushing further risks sandhi's sibling-crate phase outliving its usefulness — the fold's value is front-loaded.
