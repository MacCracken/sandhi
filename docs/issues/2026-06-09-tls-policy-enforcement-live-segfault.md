# 2026-06-09 — low-level `sandhi_conn_open_with_policy` SIGSEGVs on a LIVE network (TLS-policy enforcement)

**Status:** Open — P2 (latent; offline CI is unaffected).
**Severity:** **P2** — only manifests with real network reachability;
`programs/_policy_runtime_probe.cyr` skip-cleans when offline (the CI
case), so it has not been failing CI. No consumer hits it today: the
high-level path (1.4.6) routes pinning through the backend-agnostic SPKI
read, which is live-safe.
**Discovered:** 2026-06-09, while extending the TLS-policy live gate for
1.4.6. **Pre-exists 1.4.6** — reproduces on pristine `main` (45847eb),
both backends. NOT introduced by the 1.4.6 threading work.
**Sandhi version:** observed at 1.4.5 / 1.4.6, cyrius 6.1.20.
**Affects:** the **low-level** `sandhi_conn_open_with_policy` /
`_with_policy_a` enforcement paths that reach for libssl `SSL_CTX_*`
symbols. The high-level 1.4.6 threading is unaffected for SPKI pinning.

## Summary

Running the live TLS-policy gate (`programs/_policy_runtime_probe.cyr`)
against a reachable network SIGSEGVs (exit 139) inside the policy-enforced
open, at different gates depending on the active TLS backend:

| Backend (`sandhi_tls_backend()`) | Crash gate | Operation |
|---|---|---|
| libssl (build **without** `-D CYRIUS_TLS_NATIVE`) | `[3]` | wrong-SPKI-pin open → post-handshake SPKI read |
| native (build **with** `-D CYRIUS_TLS_NATIVE`) | `[4]` | trust-store policy open → `SSL_CTX_load_verify_locations` |

Both are the **still-libssl-coupled** enforcement surface:

- On the **native** backend, `_sandhi_apply_hook`
  (`src/tls_policy/apply.cyr`) calls `tls_dlsym("SSL_CTX_load_verify_locations")`
  + `fncall3(fp, ssl_ctx, ...)`, but `ssl_ctx` is the **native** TLS
  context, not a libssl `SSL_CTX*` — calling a libssl fn on a native
  handle faults. (mTLS `SSL_CTX_use_certificate_file` /
  `_use_PrivateKey_file` are the same shape and would fault identically.)
- On the **libssl** backend, the gate faults at the post-handshake SPKI
  read on the second policy-enforced open of the run; the exact fault site
  in the SPKI path (`tls_get_peer_spki_der` → `sha256`) needs a narrower
  repro (single open in isolation vs. sequential opens) to localize
  libssl-read-vs-repeated-open.

`sandhi_tls_policy_enforcement_available()` returns 1 on **both** backends
(the libssl symbols resolve via `fdlopen` regardless of the active
backend), so it does **not** gate out the native trust-store/mTLS path —
that is the root mismatch: enforcement reports "available" but applying it
to a native ctx crashes.

## Reproduce

```sh
# native — crashes at gate [4] (trust-store)
cyrius build -D CYRIUS_TLS_NATIVE programs/_policy_runtime_probe.cyr build/p
build/p          # exit 139 after "[4] non-existent trust_store path"

# libssl — crashes at gate [3] (wrong-pin SPKI)
cyrius build programs/_policy_runtime_probe.cyr build/p_libssl
build/p_libssl   # exit 139 after "[3] WRONG SPKI pin ..."
```

Both reproduce on pristine `main` (stash all working changes first), so
this is independent of the 1.4.6 work.

## Why it hasn't bitten

- `programs/_policy_runtime_probe.cyr` runs a skip-cleanly cascade
  (`tls_available` → `regression_network_probe(1.1.1.1, 443, 3000)`); on an
  offline runner it exits 0 before reaching `[3]`/`[4]`. CI runners have no
  network, so the gate has stayed green.
- The 1.4.6 high-level threading gate
  (`programs/_https_policy_threading_gate.cyr`) deliberately exercises only
  the SPKI-pin path, which is **backend-agnostic since 1.4.2**
  (`tls_get_peer_spki_der`) and live-safe on native — it passes ALL GATES
  live.

## Proposed fix (cyrius + sandhi)

This is the same surface the roadmap tracks as **"native TLS-policy
enforcement"** — the gate for full libssl retirement. Two layers:

1. **Make enforcement backend-aware (sandhi, near-term).**
   `sandhi_tls_policy_enforcement_available()` checks libssl `SSL_CTX_*`
   symbol resolution (`tls_dlsym` via `fdlopen`), so it returns 0 whenever
   libssl is not present on the box — **even on a native build where SPKI
   pinning is fully backend-agnostic** (`tls_get_peer_spki_der`, 1.4.2).
   Because `_sandhi_policy_pre_open_a` fail-closes any enforcement-demanding
   policy when `enforcement_available()==0`, this means **SPKI pinning is
   currently blocked on a native-without-libssl box** (it works only where
   libssl happens to be installed — e.g. local dev, most distros — which is
   why the 1.4.6 gate passes locally but skip-cleans on a minimal CI runner).
   Fix: split the gate — a backend-aware **pin** availability (true on native
   without libssl, since `tls_get_peer_spki_der` carries it) vs. **trust-store
   / mTLS** availability (false on native until the `SSL_CTX_*` equivalents
   below land, so those policies fail closed instead of faulting).
2. **Native trust-store / mTLS config (cyrius `lib/tls_native.cyr`).**
   Typed, backend-agnostic verbs for custom trust store + client cert/key
   (the native analogues of `SSL_CTX_load_verify_locations` /
   `SSL_CTX_use_certificate_file`), so sandhi can drop the `tls_dlsym`
   `SSL_CTX_*` bindings entirely (mirrors the 1.4.2 ALPN/SPKI rewire). This
   is the cyrius-side dependency that finally unblocks libssl retirement.

## Acceptance

- Native: a trust-store / mTLS policy through `sandhi_conn_open_with_policy`
  either enforces correctly or **fails closed** (`SANDHI_ERR_TLS`) — never
  SIGSEGVs.
- `programs/_policy_runtime_probe.cyr` runs ALL GATES on a live network on
  both backends without crashing.
- libssl SPKI gate `[3]` localized + fixed (or confirmed a repeated-open
  artifact and handled).
