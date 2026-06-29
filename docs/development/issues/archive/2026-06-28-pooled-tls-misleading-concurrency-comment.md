# 2026-06-28 — `sandhi_server_run_pooled_tls` doc-comment falsely claims concurrent-handshake safety

**Status:** RESOLVED (doc/gate half) at sandhi 1.7.0 (2026-06-29) — the
`src/server/mod.cyr` comment + `state.md` mirror now state concurrent TLS
handshakes are unsafe and recommend `max_conns = 1`, cross-referencing the sigil
issue; `_server_tls_probe.cyr` gained the `[4]` non-gating concurrent-handshake
watch (live: 0/16 survive, confirming the crash; promote to gating once sigil
lands). The **root crash** remains open cyrius/sigil-side
(`2026-06-28-concurrent-tls-handshake-global-scratch-race`). Archived.
**Severity:** high (correctness-by-omission) — the shipped comment actively
invites a consumer to enable multi-worker HTTPS, which then crashes (SIGSEGV) on
the first two simultaneous TLS handshakes. The comment, not just the gap, is the
hazard.
**Reported via:** `yeo-cy-test` consumer (SecureYeoman → Cyrius probe), adopting
`sandhi_server_run_pooled_tls` and pointing concurrent clients at it.

## The misleading comment

`src/server/mod.cyr:1742-1749` (the `sandhi_server_run_pooled_tls` header):

> "Worker ctxs are fully independent; the only shared mutable state is the
> process-global allocator (CAS-locked) — concurrent handshakes are validated by
> the live gate `programs/_server_tls_probe.cyr`."

Both load-bearing clauses are false:

1. **"the only shared mutable state is the CAS-locked allocator."** Not true — the
   TLS handshake drives `sigil`, whose crypto primitives use ~dozens of
   process-global scratch buffers (HKDF live-state, the per-thread crypto *banks*
   that exist but are never activated for TLS, ed25519_sign scratch, AES-NI/SHA-NI
   state, bignum accumulators). Two concurrent handshakes race them → ECONNRESET
   or **SIGSEGV** (filed cyrius/sigil side:
   `2026-06-28-concurrent-tls-handshake-global-scratch-race`).
2. **"concurrent handshakes are validated by the live gate."** The gate
   (`programs/_server_tls_probe.cyr`) never drives two *simultaneous* handshakes:
   its "burst of 8" is a single-threaded parent `while` loop (each `_https_get`
   completes before the next), and its `[3]` "isolation" pins a worker by holding a
   **plaintext** (`use_tls=0`) silent socket, not a second TLS handshake. So the
   multi-worker pool's core promise — parallel handshakes across cores — is
   *unvalidated*, and in fact broken upstream.

## Why it matters

A consumer reading this comment reasonably sets `max_conns > 1` for HTTPS to scale
handshakes across cores (the whole reason the pooled-TLS loop exists) and inherits
a crash. The probe pinned its TLS pool to **1 worker** as the only safe option.

## Fix

1. Correct `src/server/mod.cyr:1742-1749` (and the mirror note in
   `docs/development/state.md`): state that **concurrent TLS handshakes are not
   yet safe** (sigil crypto scratch is process-global / banks unactivated for TLS),
   cross-reference the sigil issue, and recommend `max_conns = 1` for the TLS pool
   until sigil is fixed.
2. Extend `_server_tls_probe.cyr` to drive **≥2 genuinely simultaneous completed
   TLS handshakes** (e.g. N client threads over `lib/thread.cyr`) so the gate
   actually exercises what the comment claims — it should currently FAIL, turning
   this into a real regression guard once sigil lands.
