# sandhi — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** —
> durable rules that change rarely. Volatile state (current version,
> module line counts, fold-into-stdlib status, active consumers, in-flight
> milestones) lives in [`docs/development/state.md`](docs/development/state.md).
> Do not inline state here.

## Project Identity

**sandhi** (Sanskrit सन्धि — *junction, connection, joining*) — service-boundary layer for AGNOS. Named 2026-04-24 (formerly the "services" / "service mesh" placeholder in both agnosticos and cyrius roadmaps).

- **Type**: Library
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Version**: `VERSION` at the project root is the source of truth
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)

## Goal

Be the one place AGNOS consumers go for service-to-service communication — HTTP client + JSON-RPC + WebSocket + TLS policy + service discovery — composed cleanly on top of the thin stdlib primitives.

Stdlib carries the primitives; sandhi carries the patterns. Same relationship sakshi has to tracing, mabda to GPU, sankoch to compression. Scaffolded as a sibling crate; fold-into-stdlib target is the **v5.7.0 clean-break fold** per [ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — revised from the original "before v5.6.x closeout" plan once the alias-window tradeoffs got concrete.

## Current State

> Volatile state — module line counts, fold-into-stdlib status, in-flight
> consumer pins (yantra / sit-remote / ark-remote / daimon), migration
> status of `lib/http_server.cyr` — lives in
> [`docs/development/state.md`](docs/development/state.md).

This file (`CLAUDE.md`) is durable rules.

## Scaffolding

Project was scaffolded with `cyrius init sandhi` on 2026-04-24. **Do not manually create project structure** — use the tools. If the tools are missing something, fix the tools.

## Quick Start

```bash
cyrius deps                                                # resolve stdlib deps
cyrius build programs/smoke.cyr build/sandhi-smoke        # build (link proof)
cyrius test src/test.cyr                                   # unit tests
cyrius lint src/*.cyr                                      # static checks
CYRIUS_DCE=1 cyrius build programs/smoke.cyr build/sandhi-smoke  # release-parity build
```

## Architecture

Module responsibilities (file list in `state.md`):

- **`src/main.cyr`** — public API / library root. Top-level verbs + version. No top-level `main()` (library, not binary).
- **`src/error.cyr`** — unified error kinds across submodules (SANDHI_ERR_PARSE, CONNECT, TLS, TIMEOUT, REMOTE, PROTOCOL, AUTH, DISCOVERY, INTERNAL).
- **`src/http/client.cyr`** — full HTTP client. Absorbs the cyrius-roadmap `lib/http.cyr depth` item.
- **`src/http/headers.cyr`** — header management.
- **`src/rpc/mod.cyr`** — JSON-RPC dialects (WebDriver, Appium, MCP). Absorbs the RPC-grade side of the `lib/json.cyr depth` item.
- **`src/discovery/mod.cyr`** — service discovery (mDNS, daimon-registered, chained fallback). The genuinely new surface.
- **`src/tls_policy/mod.cyr`** — cert pinning, mTLS, trust store. Wraps `lib/tls.cyr` (FFI-to-libssl now; transitions to native when Cyrius v5.9.x TLS lands).
- **`src/server/mod.cyr`** — canonical home of the HTTP server surface (lifted from `lib/http_server.cyr` at M1). Stdlib deletes its copy at Cyrius v5.7.0 per [ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md); until then, stdlib 5.6.YY emits a deprecation warning on include.

## Key Constraints

- **Compose, don't reimplement.** Stdlib primitives (`http.cyr`, `ws.cyr`, `tls.cyr`, `json.cyr`, `net.cyr`) already exist; sandhi wraps them with policy + dialect + pooling + discovery layers. Do not fork the primitives into sandhi — if a primitive needs work, that's a stdlib patch, not a sandhi feature.
- **`lib/http_server.cyr` migration is lift-and-shift first, enhance second.** The verbatim lift into `src/server/mod.cyr` landed at M1 (v0.2.0). Routing / middleware layer on top in later milestones. No stdlib-side alias — stdlib deletes its copy in the v5.7.0 clean-break fold per [ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md). No architectural rework mid-migration.
- **No FFI.** All transport is first-party Cyrius-stdlib today; native TLS replaces the current `lib/tls.cyr` FFI when v5.9.x lands.
- **Dialect code stays in `src/rpc/`.** When a consumer (yantra, daimon, etc.) needs a new JSON-RPC dialect, the dialect wrapper lives here, not in the consumer. One dialect = one small file. Keeps the public surface of consumer crates clean.
- **Discovery is pluggable, not load-bearing on any single backend.** `sandhi_discover_chain` lets consumers fall back gracefully; no resolver is a hard dependency.
- **Fold-into-stdlib is the explicit target.** Keep the public surface small enough to fold cleanly. If sandhi grows wildly, it's a sign to push work into sibling crates rather than let sandhi balloon.

## Development Process

### Work Loop

1. Pick the next item from `docs/development/roadmap.md`
2. Implement the submodule; keep changes scoped to one submodule per patch (single-focus-per-patch)
3. `cyrius build` → `cyrius test` → link check
4. Update `CHANGELOG.md` and `docs/development/state.md` if milestone boundary crossed
5. Version bump only at milestone close

### Fold-into-stdlib preparation

When the public API stabilizes and consumer pins are all green:
1. Coordinate with cyrius agent to schedule the fold into a specific v5.6.YY patch
2. `cyrius distlib` → verify `dist/sandhi.cyr` is self-contained
3. Consumers switch from `[deps.sandhi]` git-pin to stdlib include
4. `lib/http_server.cyr` stdlib entry retires (aliases → sandhi::server)

### Closeout Pass (before minor/major bump)

1. Full test suite — `.tcyr` green
2. `cyrius lint src/*.cyr` — no unaddressed findings
3. All consumer pins up to date with the new tag
4. `dist/sandhi.cyr` re-generated cleanly
5. Version triple (`VERSION`, `cyrius.cyml`, CHANGELOG header) in sync
6. `state.md` current — fold status, consumer pins, module line counts

## Key Principles

- **Compose stdlib primitives; don't fork them.** The network primitives in stdlib are the single source of truth for their layer; sandhi sits above them.
- **Pluggable discovery, opinionated policy.** Discovery is chain-based (multiple backends, fallback-ordered); TLS and auth policy are opinionated defaults with explicit override paths.
- **Small public surface.** Fold-into-stdlib wants this, and the v5.7.0 clean-break fold ([ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)) freezes the surface at fold time. Every new verb earns its spot; speculative surface is doubly discouraged since it ships permanently with stdlib.
- **One dialect per file.** RPC dialects (WebDriver, Appium, MCP) each live in `src/rpc/<dialect>.cyr`. When a consumer needs a new one, add a file, don't grow an existing one.
- **Reference don't mimic.** sandhi isn't "Cyrius's gRPC" or "Cyrius's nghttp2." It's the service-boundary layer AGNOS needs, shaped by AGNOS consumers. Incumbent shapes inform, don't dictate.

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- Do not reimplement stdlib primitives. If a primitive needs depth, that's a stdlib patch, not sandhi scope.
- Do not add C deps / FFI. Native Cyrius only.
- Do not grow the public surface speculatively — wait for a second consumer asking for the same thing before generalizing.
- Do not inline volatile state in this file — `docs/development/state.md` is the home for that.
- Do not bypass `cyrius build` with raw `cc5` invocations.
- **Public surface frozen at 0.9.2.** No new public verbs land between 0.9.2 and the v5.7.0 fold (1.0.0). The fold ships sandhi into stdlib's `lib/sandhi.cyr` permanently — every name in the public surface at fold-time becomes a permanent stdlib API. Bug fixes and internal refactors are fine; new verbs are not. If a consumer asks for something post-0.9.2, it lands as a 1.0.x stdlib patch after fold, not as 0.9.x.

## Cyrius Conventions

- `var buf[N]` is N **bytes**, not N elements
- `&&` / `||` short-circuit; mixed requires parens
- No closures — named functions
- No negative literals — `(0 - N)`, not `-N`
- Test exit pattern: `syscall(60, assert_summary())`

## CI / Release

- **Toolchain pin** — `cyrius.cyml [package].cyrius` is the only authority. **Never** create a `.cyrius-toolchain` file.
- **Release artifacts** — source tarball, `dist/sandhi.cyr` via `cyrius distlib`, SHA256SUMS.
- **State sync** — release post-hook bumps `docs/development/state.md`.
- **Fold-into-stdlib** retires this repo's releases at some point. Track the retirement in `state.md` when it happens.

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why did we choose X over Y?* Start with ADR 0001: the naming + compose-don't-reimplement thesis.
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints and quirks
- [`docs/guides/`](docs/guides/) — task-oriented how-tos
- [`docs/examples/`](docs/examples/) — runnable examples
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — milestone sequence toward fold-into-stdlib
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes

New quirks and constraints land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`). New decisions land in `docs/adr/` using [`template.md`](docs/adr/template.md). **Never renumber either series.**

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Submodule-scoped changes get their submodule name in the entry (e.g., *"http: add POST method support"*). Fold-into-stdlib status gets its own **Stdlib** subsection when it happens.
