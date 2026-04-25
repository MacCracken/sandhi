# Redirects and security

sandhi does not follow HTTP redirects by default. Opt in when you want to; sandhi's
follower is bounded, security-aware, and refuses protocol downgrades.

## Opt in

```
var opts = sandhi_http_options_new();
sandhi_http_options_follow_redirects(opts, 1);
sandhi_http_options_max_hops(opts, 5);  # default; override if needed

var resp = sandhi_http_get_opts(url, 0, opts);
```

By default, `max_hops = 5`. The follower honors 301, 302, 303, 307, 308.

On exceeding `max_hops`, sandhi returns the last redirect response unchanged —
the caller sees a 3xx with a `Location` header. On a hop with no `Location`
header, sandhi also stops and returns that response.

## 303 method rewrite

`303 See Other` rewrites the method to `GET` and drops the body on the next hop.
This matches RFC 7231 §6.4.4. `301 / 302 / 307 / 308` preserve method and body.

## 0.9.0 security model

Two defenses apply per-hop:

### https → http downgrade: refused

If the current URL is HTTPS and the `Location` points to HTTP, sandhi **refuses to
follow**. The function returns the redirect response with `err_kind` set to
`SANDHI_ERR_TLS`, so the caller sees the refusal rather than transparently leaking
credentials in plaintext to an attacker-controlled `Location:`.

```
if (sandhi_http_err_kind(resp) == SANDHI_ERR_TLS
 && sandhi_http_status(resp) >= 300 && sandhi_http_status(resp) < 400) {
    # The server redirected us from https to http; we refused.
}
```

This is informed by the curl CVE-2025-0167 / 14524 cluster lessons. Rationale:
any secret your code sent to an HTTPS origin was bound to that origin; handing it
to an HTTP follower defeats the transport guarantee.

### Cross-authority sensitive-header strip

When a redirect crosses authorities (different scheme, host, or port), sandhi
strips three headers from the follow-up request:

- `Authorization`
- `Cookie`
- `Proxy-Authorization`

A caller's secret was bound to the origin it was presented to; the redirect
target may be hostile. If the chain bounces back to the original authority on a
later hop, the original headers are restored — same behavior as curl, matches the
spirit of RFC 7235 §2.2.

"Same authority" = same scheme + same host + same port. `http://a.com/` →
`http://a.com:8080/` is cross-authority (different port).

## When NOT to use redirect following

Auth flows where the `302` is expected to honor the `Authorization` header won't
work through sandhi's follower — the header gets stripped on the cross-authority
hop, and the downstream service will see an unauthenticated request.

In those cases, either:

- Re-architect to handle the redirect explicitly: disable following, inspect the
  `Location` yourself, decide whether to re-auth for the new origin, then issue
  the second request with appropriate credentials.
- Keep the auth flow within a single authority (same host+port) so the
  strip-on-cross-authority rule doesn't fire.

Never work around this by forking the follower with the strip disabled —
silently forwarding secrets across origins is a real-world vulnerability.

## Interaction with timeouts

Each hop gets a **fresh `total_ms` budget**. A 5-hop chain with
`total_ms = 10000` can consume up to ~50 s of wall time if every hop takes the
full 10 s. To bound the end-to-end time, lower `max_hops` or enforce a wrapping
deadline in your caller.

Per-op knobs (`connect_ms`, `read_ms`, `write_ms`) apply to each hop
independently — each fresh TCP/TLS handshake re-honors `connect_ms`.

## Interaction with the pool

Pool + follow_redirects work together. Each hop takes/puts against the pool
per-route, so redirects between the same authority reuse conns cleanly.
Redirects across authorities open fresh conns (different route key).
