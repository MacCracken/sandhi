# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides. Items here describe *how the world is*, not *what we chose* or *how to do something*.

## Items

- [001 — HPACK Huffman blob](001-hpack-huffman-blob.md) — `src/http/h2/huffman.cyr` embeds the 257-entry Appendix B table as a single 2570-character hex blob. One string literal = one fixup; the per-program fixup-table cap (32768) stayed comfortably under budget. General pattern for large lookup tables in Cyrius modules.
- [002 — Forward-reference via glue modules](002-forward-reference-via-glue-modules.md) — Cyrius compilation honors `cyrius.cyml [lib].modules` order. When an early module needs a symbol from a later one, add a glue module (e.g., `pool_glue.cyr`) that lives where the dependency resolves.
- [003 — libssl-pthread stubbing](003-libssl-pthread-stubbing.md) — what's stubbed today (TLS-policy enforcement, ALPN runtime, live h2 talk) and what needs to clear for the surface to light up. ~80 lines of sandhi-side wiring once the upstream blockers resolve.
- [004 — Native TLS is the default; libssl is a deprecated opt-in](004-native-tls-default.md) — 1.4.5 defaults to the native TLS backend. Why (libssl's glibc-malloc fights cyrius's brk heap → 4th-request SIGSEGV), the `-D CYRIUS_TLS_NATIVE` build requirement consumers must pass, the `sandhi_tls_use_libssl()` escape hatch and its caveats (native can't yet handshake every public host; policy enforcement still libssl-coupled), and the exit criteria for full libssl retirement.

Add numbered entries (`NNN-kebab-case.md`) when non-obvious invariants surface — e.g., keepalive teardown timing, mDNS listener lifecycle constraints, TLS handshake quirks crossing the stdlib / sandhi boundary, or any primitive-composition surprise.
