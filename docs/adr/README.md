# Architecture Decision Records

Decisions about sandhi — what we chose, the context, and the consequences we accept.

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** Supersessions add a new ADR and mark the old `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## Index

- [0001 — sandhi is a composer, not a reimplementer](0001-sandhi-is-a-composer-not-a-reimplementer.md) — stdlib owns network primitives; sandhi wraps them with policy / dialect / pooling / discovery layers. Naming rationale captured here too.
