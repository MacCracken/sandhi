# sandhi — issue & coordination log

Issues here fall into two buckets. Both live in this directory with
the `YYYY-MM-DD-kebab-case.md` naming convention so recency is
obvious at the directory level.

## Cross-repo coordination (sandhi consumer & producer integrations)

Each AGNOS crate that sandhi serves (or that sandhi depends on)
gets one focused doc with a paste-ready roadmap entry, a migration
example, and any known blockers. Handing one file to each crate's
modernization agent beats routing through sandhi's full repo.

| Doc | Crate | Side | Priority |
|-----|-------|------|----------|
| [`2026-04-24-yantra-sandhi-rpc.md`](2026-04-24-yantra-sandhi-rpc.md) | yantra | consumer | M2+ backend unblock |
| [`2026-04-24-daimon-registry-endpoints.md`](2026-04-24-daimon-registry-endpoints.md) | daimon | producer | pre-fold (sandhi calls it) |
| [`2026-04-24-daimon-sandhi-mcp-client.md`](2026-04-24-daimon-sandhi-mcp-client.md) | daimon | consumer | pre-fold |
| [`2026-04-24-hoosh-ifran-sandhi-http.md`](2026-04-24-hoosh-ifran-sandhi-http.md) | hoosh + ifran | consumer | pre-fold |
| [`2026-04-24-sit-sandhi-git-over-http.md`](2026-04-24-sit-sandhi-git-over-http.md) | sit | consumer | gated on sit local-VCS + TLS fix |
| [`2026-04-24-ark-sandhi-registry-ops.md`](2026-04-24-ark-sandhi-registry-ops.md) | ark | consumer | pre-fold |
| [`2026-04-24-mela-sandhi-marketplace.md`](2026-04-24-mela-sandhi-marketplace.md) | mela | consumer | pre-fold |
| [`2026-04-24-vidya-sandhi-fetch.md`](2026-04-24-vidya-sandhi-fetch.md) | vidya | consumer | future (low priority) |

Each doc carries its own "what's assumed vs. actual" note. sandhi's
side is shipped; the doc exists so the consumer/producer crate has
zero ambiguity on what to put on its roadmap.

## Upstream dependencies (sandhi is blocked on stdlib / toolchain)

| Doc | Upstream | Effect |
|-----|----------|--------|
| [`2026-04-24-fdlopen-getaddrinfo-blocked.md`](2026-04-24-fdlopen-getaddrinfo-blocked.md) | cyrius-lang (stdlib `fdlopen.cyr` + `tls.cyr` + compiler local-slot aliasing) | DNS went native; HTTPS runtime pending; response parser split around the compiler quirk |

All three logged symptoms in the fdlopen doc are coordinated
through the cyrius-lang agent when bandwidth allows — sandhi is
unblocked (native DNS + plain-HTTP round-trips + refactored parser)
and doesn't need a specific timeline.

## How to use this directory

- **From inside a consumer repo**, grab the matching doc and drop
  the "Proposed roadmap entry" block into that repo's `roadmap.md`.
- **When a sandhi enhancement is gated** on upstream work, link
  to the upstream doc here rather than duplicating the context.
- **Never renumber** — append-only, like `docs/adr/`.

New docs in this directory land with the same naming convention and
a "Log" section at the bottom so recurring issues can add entries
without forking a new file.
