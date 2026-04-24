# sandhi — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable); this file is **state** (volatile). Add release-hook wiring when the repo's release workflow lands.

## Version

**0.1.0** — scaffolded 2026-04-24 via `cyrius init sandhi` + library-shape manifest tuning. Module skeletons + ADR 0001 + compile-link smoke program landed first; no real implementation yet. Named 2026-04-24 after confirming the planned "services" crate in two roadmaps had never received a proper name.

## Toolchain

- **Cyrius pin**: `5.6.22` (in `cyrius.cyml [package].cyrius`)

## Fold-into-stdlib status

**Pre-fold, target before v5.6.x closeout.** Follows the sakshi / mabda / sankoch / sigil precedent: start as sibling crate, fold into `lib/sandhi.cyr` once the public API stabilizes and consumer pins are green.

## Source

Scaffold only. Line counts populate as submodules fill in.

Submodules (all stubs today):

| Module | Lines | Status |
|--------|-------|--------|
| `src/main.cyr` | ~35 | scaffold — public API declarations |
| `src/error.cyr` | ~30 | scaffold — error kinds defined |
| `src/http/client.cyr` | ~35 | scaffold — verb stubs |
| `src/http/headers.cyr` | ~20 | scaffold — verb stubs |
| `src/rpc/mod.cyr` | ~30 | scaffold — dialect plan documented |
| `src/discovery/mod.cyr` | ~25 | scaffold — verb stubs |
| `src/tls_policy/mod.cyr` | ~15 | scaffold — verb stubs |
| `src/server/mod.cyr` | ~20 | scaffold — awaiting `lib/http_server.cyr` lift-and-shift |

Build output: `build/sandhi-smoke` (smoke program that proves all submodules link clean).

Planned `dist/sandhi.cyr` bundle via `cyrius distlib` — lands when implementation reaches M1 (http_server lift-and-shift complete).

## Tests

- `tests/sandhi.tcyr` — unit tests (not yet written)
- `tests/integration/` — cross-submodule integration (lands with first real implementation)

## Dependencies

Declared in `cyrius.cyml` (all Cyrius stdlib):

- **Core**: `syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`, `vec`, `args`, `hashmap`, `process`, `thread`, `fnptr`, `chrono`, `tagged`, `assert`
- **Network primitives** (the things sandhi composes): `net`, `http`, `http_server`, `tls`, `ws`, `json`, `base64`
- **Infrastructure** (already folded into stdlib): `sakshi`, `sigil`

No external git deps. sandhi is pure-stdlib-composition.

## Consumers

**Active (pinning expected within days of real implementation)**:
- **yantra** — M2+ backends (WebDriver, Appium JSON-RPC) need `sandhi::rpc`. Currently sandhi-less; CDP backend (M1) uses stdlib `ws.cyr` directly and can stay that way.

**Planned**:
- **sit** — remote clone/push/pull once the local VCS is done
- **ark** — remote registry ops
- **hoosh** — LLM provider routing
- **ifran** — same shape as hoosh
- **daimon** — MCP-over-HTTP dispatch + agent discovery
- **mela** — marketplace API
- **vidya** — any external-knowledge fetch path (future)

**Not consumers** (deliberately):
- daimon's core agent orchestration (daimon owns that)
- bote / t-ron (MCP protocol semantics stay there)
- sigil (sandhi uses sigil for cert fingerprints; does not reimplement crypto)

## Migration status

- `lib/http_server.cyr` — still in stdlib (interim); scheduled for lift-and-shift into `src/server/mod.cyr` during the v5.6.x late cycle. stdlib alias retained during migration window; retired at fold-into-stdlib.

## Next

Immediate sequence:

1. **M1 — `lib/http_server.cyr` lift-and-shift.** Move verbatim; keep stdlib alias. Coordination with cyrius agent for the stdlib-side change. One patch.
2. **M2 — `sandhi::http::client` real implementation.** POST/PUT/DELETE/PATCH/HEAD + headers + HTTPS (via `lib/tls.cyr`) + redirect following. Absorbs the v5.7.x `lib/http.cyr depth` roadmap item (now redundant with sandhi picking it up).
3. **M3 — `sandhi::rpc` WebDriver + Appium dialects.** Unblocks yantra M2. JSON-RPC dispatch layer, streaming responses, dialect-aware error envelopes.
4. **M4 — `sandhi::discovery` chain resolver + daimon integration.** The genuinely new surface.
5. **M5 — `sandhi::tls_policy` cert pinning + mTLS.** Wraps `lib/tls.cyr` today; transitions to native when Cyrius v5.9.x TLS ships.
6. **Fold-into-stdlib** — targets pre-v5.6.x-closeout per the cyrius roadmap. Public surface frozen at fold; subsequent changes via cyrius release cycle.

Receipts-oriented: sandhi's fold-into-stdlib moment is the anchor for a short-form article ("sandhi folded — the service-boundary layer has a home") in the same micro-article shape as [what-5.5.x-taught-5.6.x.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/what-5.5.x-taught-5.6.x.md) and [micro-work-and-agent-deferment.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md). Outlined at fold time, not before.
