# 2026-04-24 — stdlib `tls.cyr` needs an SSL_CTX hook for ALPN

**Status**: Open — filed 0.8.1
**Side**: Upstream (cyrius stdlib)
**Sandhi-side surface**: `src/tls_policy/alpn.cyr` (Bite 4 of 0.8.0).

## What sandhi has today

- Wire-format encoder for the ALPN ProtocolNameList — fully tested
  (`sandhi_alpn_encode_protos("h2,http/1.1")` → 12 bytes).
- Default advertise list: `h2,http/1.1`.
- `sandhi_conn_alpn_selected(conn)` accessor — returns 0 (stubbed).
- `sandhi_conn_alpn_is_h2(conn)` predicate — reads the above; returns 0.
- 0.8.1's `sandhi_http_request_auto` consults this predicate and
  falls through to HTTP/1.1 when no h2 negotiated. Today that's
  always the path.

## What sandhi can't do without stdlib help

ALPN runtime requires two OpenSSL calls to actually fire:

1. **`SSL_CTX_set_alpn_protos(ctx, protos, len)`** — must be called
   on the SSL_CTX *before* the handshake starts. This sets what we
   advertise.
2. **`SSL_get0_alpn_selected(ssl, &out, &outlen)`** — called on the
   SSL session *after* `SSL_connect` returns to read what the
   server picked.

Sandhi can resolve these symbols itself via `_dynlib_resolve_global`
(matching the pattern stdlib `tls.cyr` already uses for everything
else). The blocker is that stdlib's `tls_connect(sock, host)` builds
its SSL_CTX privately inside the function and doesn't expose it.
Sandhi has no opportunity to slot the
`SSL_CTX_set_alpn_protos` call between context creation and handshake.

## What we'd like

A small extension to stdlib `tls.cyr` that lets the caller hand it a
fully-prepared SSL_CTX or a pre-handshake hook. Options, ordered
roughly by least-invasive first:

### Option A — `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)`

```cyr
fn tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx) {
    # ... build SSL_CTX as today ...
    if (hook_fp != 0) { fncall2(hook_fp, hook_ctx, ssl_ctx); }
    # ... continue with SSL_new, SSL_connect, etc. ...
}
```

Sandhi passes a hook that calls `SSL_CTX_set_alpn_protos` with the
ALPN bytes. Existing `tls_connect` becomes `tls_connect_with_ctx_hook(
sock, host, 0, 0)`. No churn for existing consumers.

### Option B — expose the SSL_CTX

Split into:
- `tls_ctx_new()` → SSL_CTX (caller owns; can call any SSL_CTX_set_*)
- `tls_connect_ctx(sock, host, ctx)` → tls_session

More flexible long-term but more API surface.

### Option C — built-in ALPN parameter

```cyr
fn tls_connect_alpn(sock, host, alpn_bytes, alpn_len) { ... }
```

Simple but baked-in. Doesn't generalize to other SSL_CTX_set_*
needs (mTLS, custom verify, trust store) which `tls_policy` will
also want once libssl works.

## Sandhi's preference: Option A

Function-pointer hook is the smallest stdlib delta and gives sandhi
(or any other consumer) freedom to call any SSL_CTX_set_* it wants,
including ALPN, mTLS cert loading, custom trust stores, verify
flags, etc. Same pattern several other Cyrius primitives already
use (e.g., `lib/sakshi.cyr`'s output-target callback).

## Why this matters now

This blocker — together with the libssl-pthread-deadlock
(`docs/issues/2026-04-24-libssl-pthread-deadlock.md`) — is the gate
that keeps sandhi 0.8.0+'s h2 stack from auto-firing on real HTTPS
traffic. The libssl side is the bigger one (no live HTTPS without
it); ALPN just lets us auto-negotiate once HTTPS works at all.

When both clear, sandhi 0.8.1's `sandhi_http_request_auto` starts
selecting h2 transparently. No consumer code change.

## Cross-links

- Sandhi side: `src/tls_policy/alpn.cyr`,
  `src/http/h2/dispatch.cyr`'s `sandhi_http_request_auto`.
- Companion blocker:
  `docs/issues/2026-04-24-libssl-pthread-deadlock.md` (live HTTPS).
- Sandhi 0.8.0 + 0.8.1 CHANGELOG entries note the deferral.

## Log

- **2026-04-24** — Filed at 0.8.1 alongside the auto-selection
  wiring landing. No urgency from sandhi — degradation to HTTP/1.1
  is the same path consumers use today, so we lose nothing while
  this remains open.
