# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

Not decisions (those live in [`../adr/`](../adr/)) and not guides. Items here describe *how the world is*, not *what we chose* or *how to do something*.

## Items

- [001 — HPACK Huffman blob](001-hpack-huffman-blob.md) — `src/http/h2/huffman.cyr` embeds the 257-entry Appendix B table as a single 2570-character hex blob. One string literal = one fixup; the per-program fixup-table cap (32768) stayed comfortably under budget. General pattern for large lookup tables in Cyrius modules.
- [002 — Forward-reference via glue modules](002-forward-reference-via-glue-modules.md) — Cyrius compilation honors `cyrius.cyml [lib].modules` order. When an early module needs a symbol from a later one, add a glue module (e.g., `pool_glue.cyr`) that lives where the dependency resolves.
- [003 — libssl-pthread stubbing](003-libssl-pthread-stubbing.md) — *historical*: what was stubbed pre-0.9.3 (TLS-policy enforcement, ALPN runtime, live h2 talk) and the surface-first / runtime-second pattern. The wire-up landed at 0.9.3.
- [004 — Native TLS is the default; libssl is a deprecated opt-in](004-native-tls-default.md) — native is the **no-flag default** since Cyrius 6.1.21 / sandhi 1.4.9 (`-D CYRIUS_TLS_LIBSSL` opts out to the deprecated bridge; legacy `-D CYRIUS_TLS_NATIVE` is a no-op alias). Why native (libssl's glibc-malloc fought cyrius's brk heap → 4th-request SIGSEGV, fixed at Cyrius 6.1.19), the `sandhi_tls_use_libssl()` escape hatch, and the libssl-retirement exit criteria — **all met** as of 1.6.0 / Cyrius 6.2.8: trust-store / mTLS enforcement landed on native (Batch A1), pinning was already backend-agnostic, so native has no functional gap and the opt-out's removal is held for the 2.0 break.
- [005 — aarch64 cross-build defect (resolved at Cyrius 6.2.6)](005-aarch64-bayan-cross-build.md) — `cycc_aarch64` aborted with `unexpected enum` assembling stdlib `bayan` across toolchains 6.0.21–6.2.1 (an upstream dep-assembly defect, not sandhi's; x86_64 unaffected). **Fixed upstream in Cyrius 6.2.6** (picked up at sandhi 1.5.0); the CI/release aarch64 step is a **gating** step again. The doc retains the best-effort-window history.

Add numbered entries (`NNN-kebab-case.md`) when non-obvious invariants surface — e.g., keepalive teardown timing, mDNS listener lifecycle constraints, TLS handshake quirks crossing the stdlib / sandhi boundary, or any primitive-composition surprise.
