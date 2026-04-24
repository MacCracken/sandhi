# sandhi — Current State

> Refreshed every release. CLAUDE.md is preferences/process/procedures (durable); this file is **state** (volatile). Add release-hook wiring when the repo's release workflow lands.

## Version

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
| `src/main.cyr` | 33 | scaffold — public API declarations |
| `src/error.cyr` | 33 | scaffold — error kinds defined |
| `src/http/headers.cyr` | 258 | **M2 done** — key-value store, case-insensitive lookup, wire-format serialize + parse |
| `src/http/url.cyr` | 193 | **M2 done** — http/https parser with CRLF hardening |
| `src/http/conn.cyr` | 140 | **M2 done** — tagged plain/TLS connection abstraction |
| `src/http/response.cyr` | 282 | **M2 done** — Content-Length + chunked + close-delimited body framing |
| `src/net/resolve.cyr` | 290 | **M2 done** — native UDP DNS (RFC 1035), /etc/resolv.conf + 8.8.8.8 fallback |
| `src/http/client.cyr` | 333 | **M2 done** — POST/PUT/DELETE/PATCH/HEAD/GET, redirect following, options struct |
| `src/rpc/mod.cyr` | 25 | scaffold — dialect plan documented (M3) |
| `src/discovery/mod.cyr` | 22 | scaffold — verb stubs (M4) |
| `src/tls_policy/mod.cyr` | 15 | scaffold — verb stubs (M5) |
| `src/server/mod.cyr` | 478 | **M1 done** — verbatim lift from `lib/http_server.cyr` |

Build outputs:
- `build/sandhi-smoke` — link-proof smoke program.
- `build/dns-probe` — ad-hoc live DNS check (not part of test suite; `cyrius run programs/dns-probe.cyr <host>`).
- `build/http-probe` — ad-hoc live HTTP round-trip (`cyrius run programs/http-probe.cyr <url>`). Plain HTTP works end-to-end; HTTPS known-issue (TLS init).

Planned `dist/sandhi.cyr` bundle via `cyrius distlib` — can now be produced any time (M1 complete); first formal bundle pairs with M6 fold prep.

## Tests

- `tests/sandhi.tcyr` — **173 assertions green** across 38 test groups: smoke, server helpers (url-decode / path / param / parse / identity), http/headers (basic / set / add / remove / serialize / parse), http/url (scheme / port / query / no-path / case / malformed / CRLF), http/response (Content-Length / chunked / hex / extension / close-delimited / status / malformed / empty), http/client (ipv4-parse / full-path / host-header / build-get / build-post / empty-body / user-headers / bad-url / unresolvable-hostname), http/redirect (is-redirect / absolute / relative / bad-location / options), net/resolve (label-encode / parse-synthetic / NXDOMAIN / no-answer).
- `tests/integration/` — cross-submodule integration not yet a separate file; loopback client+server round-trip deferred until the HTTPS TLS-init issue resolves.

## Dependencies

Declared in `cyrius.cyml` (all Cyrius stdlib):

- **Core**: `syscalls`, `alloc`, `fmt`, `io`, `fs`, `str`, `string`, `vec`, `args`, `hashmap`, `process`, `thread`, `fnptr`, `chrono`, `tagged`, `assert`
- **Network primitives** (the things sandhi composes): `net`, `http`, `tls`, `ws`, `json`, `base64` — `http_server` dropped at M1 since the content now lives in `src/server/mod.cyr`.
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

- `lib/http_server.cyr` — **sandhi-side lift-and-shift complete** (v0.2.0). Canonical implementation now at `src/server/mod.cyr`; sandhi's own build pulls the module directly and no longer depends on stdlib `http_server`.
- **No stdlib-side alias.** Per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md), stdlib keeps `lib/http_server.cyr` unchanged through the 5.6.x window, emits a deprecation warning in 5.6.YY releases, and deletes it outright at v5.7.0 as the `lib/sandhi.cyr` fold lands in the same release. This is a cyrius-agent-side change; sandhi repo is unaffected.

## Next

All M2–M5 must land before the Cyrius v5.7.0 fold event (public surface freezes at fold per ADR 0002).

1. ~~**M1 — `lib/http_server.cyr` lift-and-shift.**~~ ✅ landed 2026-04-24 (v0.2.0).
2. ~~**M2 — `sandhi::http::client` real implementation.**~~ ✅ landed 2026-04-24 (v0.3.0). HTTPS runtime still blocked on stdlib TLS-init (see issue doc); compiles clean, runs fine over plain HTTP. Unblocks M3 once tls-init is resolved or sidestepped.
3. **M3 — `sandhi::rpc` WebDriver + Appium dialects.** Unblocks yantra M2. JSON-RPC dispatch layer, streaming responses, dialect-aware error envelopes. Ride on the working HTTP client; TLS is not on the critical path for CDP/WebDriver localhost use.
4. **M4 — `sandhi::discovery` chain resolver + daimon integration.** The genuinely new surface. DNS is solved (see `src/net/resolve.cyr`); mDNS + daimon-registered resolvers stack on top.
5. **M5 — `sandhi::tls_policy` cert pinning + mTLS.** Wraps `lib/tls.cyr` today; transitions to native when Cyrius v5.9.x TLS ships. **Partially gated on the tls-init fix** — the policy surface can land before runtime works, but integration tests are stuck until it does.
6. **Fold-into-stdlib at v5.7.0** — one event: stdlib deletes `lib/http_server.cyr`, adds `lib/sandhi.cyr`, consumers migrate their includes in the same release. 5.6.YY releases carry the deprecation warning. Checked at the Cyrius release gate, not in this repo.

Receipts-oriented: sandhi's fold-into-stdlib moment is the anchor for a short-form article ("sandhi folded — the service-boundary layer has a home") in the same micro-article shape as [what-5.5.x-taught-5.6.x.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/what-5.5.x-taught-5.6.x.md) and [micro-work-and-agent-deferment.md](https://github.com/MacCracken/agnosticos/blob/main/docs/articles/micro-work-and-agent-deferment.md). Outlined at fold time, not before.
