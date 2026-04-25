# Architecture Decision Records

Decisions about sandhi — what we chose, the context, and the consequences we accept.

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** Supersessions add a new ADR and mark the old `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## Index

- [0001 — sandhi is a composer, not a reimplementer](0001-sandhi-is-a-composer-not-a-reimplementer.md) — stdlib owns network primitives; sandhi wraps them with policy / dialect / pooling / discovery layers. Naming rationale captured here too.
- [0002 — Clean-break fold at Cyrius v5.7.0](0002-clean-break-fold-at-cyrius-v5-7-0.md) — stdlib deletes `lib/http_server.cyr` and gains `lib/sandhi.cyr` in one event. No alias window; 5.6.YY emits a deprecation warning as the notice period.
- [0003 — HTTP/2 and connection pool bundled at 0.8.0](0003-http2-and-pool-bundled.md) — h2 stream multiplex and 1.1 keep-alive share the pool's checkout shape; designing both at once avoided a mid-release pool refactor.
- [0004 — Refuse-don't-interpret on ambiguous protocol input](0004-security-first-refusal-model.md) — sandhi rejects malformed/ambiguous HTTP rather than applying defensive heuristics. The throughline of 0.9.0 + 0.9.1's security work.
- [0005 — Public surface frozen at 0.9.2](0005-public-surface-freeze-at-0-9-2.md) — operational corollary of ADR 0002. No new public verbs between 0.9.2 and the v5.7.0 fold; post-fold additions ship as 1.0.x stdlib patches.
