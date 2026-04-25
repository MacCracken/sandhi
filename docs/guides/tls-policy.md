# TLS policy

sandhi's TLS policy layer carries declarative intent — "pin to this SPKI", "present
this client cert", "use this custom CA bundle" — that the connection layer applies
at handshake time. Policies are additive: combine `_pinned()` + `_mtls()` without
a combinatorial mess of constructors.

## When to use a policy

- **Pinning** — the server's certificate may rotate, but its public key hash is
  stable across rotations (or pinned to a specific CA). Defends against
  mis-issuance by rogue or coerced CAs.
- **mTLS** — server demands a client certificate (internal service-to-service
  auth with cert-based identity).
- **Custom trust store** — air-gapped environment, private CA, or just
  "ignore the system store and use this bundle".

If none of those apply, you don't need a policy — plain `sandhi_conn_open` /
`sandhi_http_get` uses the system trust store with peer verification enabled.

## Constructors

```
# Default: system trust store, peer verify on.
var p_def = sandhi_tls_policy_new_default();

# Pin to an SPKI hash (SHA-256 hex of Subject Public Key Info).
var p_pin = sandhi_tls_policy_new_pinned(
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

# mTLS with a PEM cert + key.
var p_mtls = sandhi_tls_policy_new_mtls("/etc/sandhi/client.pem",
                                          "/etc/sandhi/client.key");

# Custom CA bundle.
var p_trust = sandhi_tls_policy_new_trust_store("/etc/sandhi/ca-bundle.pem");
```

SPKI hash format: hex with optional `:` / space / tab delimiters, case-insensitive.
All of these compare equal via `sandhi_fp_eq`:

```
e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
e3:b0:c4:42:98:fc:1c:14:9a:fb:f4:c8:99:6f:b9:24:27:ae:41:e4:64:9b:93:4c:a4:95:99:1b:78:52:b8:55
```

## Composition

```
var pin = sandhi_tls_policy_new_pinned(spki_hex);
var mtls = sandhi_tls_policy_new_mtls(cert, key);
var combined = sandhi_tls_policy_combine(pin, mtls);
# combined carries PINNED | MTLS flags; pin SPKI + mtls cert/key both populated.
```

Right-hand fields win on conflict; flags OR together. `combine(a, 0)` returns `a`;
`combine(0, b)` returns `b`.

## Applying to a connection

```
var conn = sandhi_conn_open_with_policy(addr, port, use_tls, sni_host, policy);
if (conn == 0) {
    var oe = sandhi_conn_last_open_err();
    # Classify: SANDHI_CONN_OPEN_CONNECT / _TIMEOUT / _TLS.
}
```

`use_tls = 0` ignores the policy (plain TCP). `use_tls = 1` honors the policy if
it demands enforcement.

## 0.9.0 fail-closed semantics

Since 0.9.0, sandhi refuses connections when a policy demands enforcement we
can't deliver today. `sandhi_tls_policy_enforcement_available()` returns `0`
until two upstream blockers clear:

1. libssl-pthread-deadlock — `docs/issues/2026-04-24-libssl-pthread-deadlock.md`
2. Stdlib `tls.cyr` missing SSL_CTX hook for SPKI extraction / mTLS /
   trust-store override.

So any of `_new_pinned()`, `_new_mtls()`, `_new_trust_store()` applied via
`sandhi_conn_open_with_policy()` returns `0` today. Check the classification:

```
var conn = sandhi_conn_open_with_policy(addr, port, 1, sni_host, pinned_policy);
if (conn == 0) {
    if (sandhi_conn_last_open_err() == SANDHI_CONN_OPEN_TLS) {
        # Policy enforcement unavailable; we refused rather than silent-downgrade.
    }
}
```

Before 0.9.0, enforcement-unavailable silently fell through to the default TLS
path — a policy-unaware connection. That surface-only-shipped scaffolding mode
is gone. If you want the old "best effort default" behavior, pass
`sandhi_tls_policy_new_default()` explicitly — it has no enforcement
requirements.

## Default policy still works

For plain HTTPS (no pinning, no mTLS, no custom CA), the default policy goes
through stdlib `tls_connect` untouched. Once libssl-pthread-deadlock clears,
standard HTTPS starts working; pinning/mtls/trust-store policies remain
fail-closed until their own enforcement path wires up.

## Constant-time fingerprint compare

`sandhi_fp_eq(a, b)` is constant-time: it normalizes both fingerprints and walks
the full length with XOR into an accumulator, no early-exit. Cert-pinning is
auth-adjacent — a timing side-channel can brute-force one byte at a time when
the per-attempt cost is sub-millisecond. For SHA-256 pins the search space is
large enough that timing doesn't matter in absolute terms, but defensive
compares should always be constant-time on principle.

## Encoding helpers

- `sandhi_fp_normalize(hex)` — strip delimiters, lowercase, reject non-hex bytes.
- `sandhi_fp_byte_length(hex)` — 32 for SHA-256, 20 for SHA-1 (legacy; discouraged), 0 on malformed.
- `sandhi_fp_encode_bytes(bytes, nbytes)` — raw digest → lowercase hex.
- `sandhi_fp_eq(a, b)` — constant-time equality.

Extracting SPKI bytes from a peer cert requires OpenSSL symbols stdlib `tls.cyr`
does not currently resolve (`X509_get_pubkey`, `i2d_PUBKEY`,
`SSL_get_peer_certificate`) — that's part of the enforcement-wire-up pass.
