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

## Applying to a high-level HTTP request

Attach the policy to an options struct; the request opens through it (HTTPS only —
a policy on a plain-HTTP URL is ignored). Policy-bound connections are single-use
(not pooled).

```
var opts = sandhi_http_options_new();
sandhi_http_options_tls_policy(opts, pinned_policy);
var r = sandhi_http_get_opts(url, 0, opts);
```

## Applying to RPC (WebDriver / Appium / MCP)

The RPC convenience verbs (`sandhi_wd_*`, `sandhi_ap_*`, `sandhi_rpc_mcp_*`) take
only a `base_url` — they have no per-call options argument. To pin a *remote*
grid / cloud endpoint, register a **default policy keyed by the endpoint base URL**
once; every subsequent RPC call whose URL falls under that base inherits it
(longest-prefix match, path-boundary-aware). This guarantees no per-action call is
left unpinned.

```
# Register once (e.g. after verifying a sigil-signed pin descriptor).
sandhi_rpc_set_default_tls_policy("https://grid.example/wd/hub", pinned_policy);

# Every per-action call now opens through `pinned_policy`:
var sess = sandhi_wd_new_session("https://grid.example/wd/hub", caps_json);
var sid  = sandhi_wd_extract_session_id(sess);
sandhi_wd_navigate_to("https://grid.example/wd/hub", sid, "https://target.example");
sandhi_wd_find_element("https://grid.example/wd/hub", sid, "css selector", "#go");
# … all pinned, including sandhi_rpc_mcp_stream's SSE channel.

sandhi_rpc_clear_default_tls_policy("https://grid.example/wd/hub");  # when done
```

Same enforcement semantics as a request-attached policy: pin / mTLS / trust-store
enforced, conn not pooled, fail-closed if enforcement is unavailable. Plain-HTTP
endpoints (e.g. `http://127.0.0.1:4444` local drivers) are unaffected — the HTTP
layer ignores a policy when there is no TLS to enforce. Registry getters:
`sandhi_rpc_get_default_tls_policy(base_url)` (exact match) and
`sandhi_rpc_clear_all_default_tls_policy()`. Up to 16 distinct endpoints; `set`
returns `SANDHI_ERR_INTERNAL` when full.

## Fail-closed semantics

When a policy demands enforcement the active TLS backend can't deliver, sandhi
**refuses** the connection rather than silently downgrading to a policy-unaware
one. `sandhi_tls_policy_enforcement_available()` is **backend-aware**:

- **SPKI pinning** (`_new_pinned()`) is backend-agnostic and enforced on the
  **native** default backend (`sandhi_tls_policy_pin_available()` → 1).
- **Trust-store / mTLS** (`_new_trust_store()` / `_new_mtls()`) enforce on the
  **libssl** backend only; on native they **fail closed** until cyrius ships
  native `SSL_CTX_*` equivalents in `lib/tls_native.cyr`.

When a policy's enforcement is unavailable on the active backend,
`sandhi_conn_open_with_policy()` returns `0`. Check the classification:

```
var conn = sandhi_conn_open_with_policy(addr, port, 1, sni_host, pinned_policy);
if (conn == 0) {
    if (sandhi_conn_last_open_err() == SANDHI_CONN_OPEN_TLS) {
        # Policy enforcement unavailable; we refused rather than silent-downgrade.
    }
}
```

sandhi never silently downgrades an enforcing policy to a policy-unaware
connection. If you want best-effort default TLS with no enforcement requirement,
pass `sandhi_tls_policy_new_default()` explicitly.

## Default policy

For plain HTTPS (no pinning, no mTLS, no custom CA), the default policy goes
through stdlib `tls_connect` untouched and works on the native default backend.

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

SPKI bytes are read from the peer cert via stdlib `tls_get_peer_spki_der`
(backend-agnostic since 1.4.2), so SPKI pinning is enforced on the native
default backend.
