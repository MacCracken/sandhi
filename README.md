# sandhi

> Service-boundary layer for AGNOS — shared HTTP / TCP / TLS + service discovery.

**sandhi** (Sanskrit सन्धि — *junction, connection, joining*) is the layer that governs rules at the boundary where two services meet. Stdlib carries the thin network primitives (`http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`, `net.cyr`); sandhi composes them into full-featured client patterns + service discovery that multiple AGNOS consumers need.

The linguistic sense of sandhi (rules at the boundary where two morphemes or words meet) maps cleanly onto the service-mesh sense. Same abstract structure — grammar works on word boundaries, sandhi works on service boundaries — at two scales.

---

## Status

**0.1.0 — scaffold** (2026-04-24). Module skeletons + ADR 0001 (naming + thesis) landed first. Real implementation fills in next.

**Target window**: fold-into-Cyrius-stdlib before v5.6.x closeout, same pattern as sakshi / mabda / sankoch / sigil. See [`docs/development/roadmap.md`](docs/development/roadmap.md) for the milestone sequence.

## Modules

| Module | Purpose | Composes |
|--------|---------|----------|
| `src/http/client.cyr` | Full HTTP client — POST/PUT/DELETE/PATCH/HEAD, custom headers, HTTPS, redirects | `lib/http.cyr`, `lib/tls.cyr` |
| `src/http/headers.cyr` | Header management — case-insensitive lookup, multi-valued fields, canonicalization | stdlib primitives |
| `src/rpc/mod.cyr` | JSON-RPC dialects (WebDriver wire, Appium, MCP-over-HTTP) | `lib/json.cyr`, sandhi::http |
| `src/discovery/mod.cyr` | Service discovery — mDNS, daimon-registered, fallback chains | `lib/net.cyr`, bote |
| `src/tls_policy/mod.cyr` | Cert pinning, mTLS, trust-store management | `lib/tls.cyr` (→ native v5.9.x) |
| `src/server/mod.cyr` | HTTP server surface — absorbs `lib/http_server.cyr` per cyrius roadmap | stdlib `http_server.cyr` (during migration) |
| `src/error.cyr` | Unified error kinds across submodules | — |

## Consumers

Planned downstream (existing or in-flight):

- **yantra** — WebDriver + Appium JSON-RPC backends; CDP already uses `lib/ws.cyr` directly
- **sit** — remote clone/push/pull once the local VCS is done
- **ark** — remote registry operations
- **hoosh** — cleaner HTTP client surface for LLM-provider routing
- **ifran** — same
- **daimon** — MCP-over-HTTP + agent discovery
- **mela** — marketplace API calls

## Build

```sh
cyrius deps
cyrius build programs/smoke.cyr build/sandhi-smoke
cyrius test src/test.cyr
```

The built artifact is a smoke program that proves all submodules link clean. sandhi itself is a library — downstream consumers pull `dist/sandhi.cyr` via `[deps.sandhi]` (pre-fold) or `include "lib/sandhi.cyr"` (post-fold into stdlib).

## Why the name

*"services"* was the placeholder in both agnosticos and cyrius roadmaps through 2026-04-24. The name sandhi was assigned that day after confirming the planned crate had never received a proper one. Sandhi fits the AGNOS multilingual naming register (hoosh, sakshi, mabda, sigil, patra, yantra, sit/smriti, kula…) and its linguistic meaning — *rules at the boundary where two units meet* — is structurally identical to the crate's engineering purpose.

## License

GPL-3.0-only.

---

*Part of [AGNOS](https://github.com/MacCracken/agnosticos). Named 2026-04-24.*
