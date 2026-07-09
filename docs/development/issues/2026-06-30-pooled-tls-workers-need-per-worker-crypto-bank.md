# 2026-06-30 — `run_pooled_tls` workers must call `crypto_bank_set` (sigil banks are opt-in; all workers collide on bank 0)

> **WITHDRAWN / NOT A SANDHI BUG (corrected 2026-06-30, same day).** This was
> filed off a **stale local `lib/sigil.cyr`** in the consumer's checkout (Version
> 3.9.4, 8 banks, opt-in `cbank()`) — `cyrius lib sync` only refreshes the declared
> stdlib subset, so the consumer's transitively-pulled sigil was never updated and
> still had the pre-3.9.6 opt-in banking. The **actual sigil 3.9.7** (which cyrius
> 6.3.12 already bundles) **AUTO-ASSIGNS** a private lane per thread in `cbank()`
> (`_crypto_next_bank` atomic counter, 64 banks) — **no per-worker `crypto_bank_set`
> is needed**, and sigil's own `concurrent_tls_handshake.tcyr` / `banking_concurrent.tcyr`
> / `ecdsa_concurrent.tcyr` pass 18/18. Verified: with sigil 3.9.7 (`cyrius lib sync
> --full`), `run_pooled_tls` at `max_conns=4` **no longer SIGSEGVs**. So **sandhi
> needs no change** for the crash. (The remaining `max_conns>1` HTTPS failure is a
> separate cyrius `str_builder` bug corrupting response buffers mid-TLS-encryption →
> `SSL: BAD_SIGNATURE`; tracked as the cyrius `str_builder` gate slot, not here.)
> Leaving this file as a corrected record.

**Status:** WITHDRAWN (no sandhi change needed — sigil 3.9.7 auto-banks). Original
text below preserved for the trail.

Follow-up to `2026-06-28-pooled-tls-misleading-concurrency-comment.md`
(the comment was correctly fixed in 1.7.0 — it now says concurrent handshakes
aren't safe). ~~This is the **actual fix** that makes them safe, now that the sigil
prerequisite has shipped.~~ *(See withdrawal note above — sigil auto-banks; nothing
to do in sandhi.)*
**Severity:** high — `sandhi_server_run_pooled_tls` with `max_conns > 1` SIGSEGVs
on 2+ concurrent TLS handshakes, so HTTPS can only use one core (the whole point
of the pooled-TLS loop is parallel handshakes across cores).
**Reported via:** `yeo-cy-test` consumer, re-run on cyrius 6.3.12 (folds sigil
3.9.7 / sandhi 1.7.0 / patra 1.12.7).

## What changed since the 1.7.0 doc fix

sigil **3.9.7** eliminated the concurrent-TLS crypto-scratch race by lane-banking
every per-call crypto buffer across `SIGIL_CRYPTO_BANKS` (8) banks. So the crypto
is now race-free **IF each worker uses a distinct bank**. But the bank is
**opt-in per thread**, not automatic:

```
# folded sigil (lib/sigil.cyr)
fn cbank(): i64 {
    if (_crypto_tls_inited == 0) { crypto_tls_main_init(); }
    return thread_local_get(_SIGIL_CBANK_SLOT) & _SIGIL_CBANK_MASK;   # defaults to 0
}
fn crypto_bank_set(bank): i64 { ... }   # must be called per thread, bank in 1..7
```

`run_pooled_tls`'s worker threads (`_sandhi_server_pool_tls_worker`) never call
`crypto_bank_set`, so every worker's `_SIGIL_CBANK_SLOT` reads **0** → they all
share bank 0 → concurrent handshakes still race the (now single-bank) scratch and
crash. Verified on cyrius 6.3.12: `max_conns = 4`, 150 concurrent HTTPS POSTs →
**SIGSEGV** (server dead, 0/150 served); `max_conns = 1` is fine.

## Fix

In `sandhi_server_run_pooled_tls`, give each worker a distinct bank:
1. Call `crypto_tls_main_init()` **once on the main thread** before spawning workers
   (the bank `_init` allocations use the non-thread-safe bump allocator — sigil's
   documented main-thread-prewarm contract).
2. Have each worker call `crypto_bank_set(worker_index_in_1..7)` at startup, before
   its first handshake (e.g. pass the index in the per-worker arg struct).

Cap the effective TLS worker count at `SIGIL_CRYPTO_BANKS - 1` (= 7) distinct
banks, or document that beyond that workers share banks (re-introducing the race) —
worth surfacing as a sigil ask if a consumer needs > 7 TLS workers.

The plaintext `run_pooled` pool needs none of this (no crypto). The same wiring
would also let `run_tls` (single-flight) stay correct if it ever fans out.

## Consumer status

`yeo-cy-test` pins its TLS pool to `max_conns = 1` until this lands; it can't inject
per-worker init into sandhi's pool. Plaintext HTTP stays at 4 workers.
