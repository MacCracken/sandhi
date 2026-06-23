# 2026-06-09 — high-level HTTP client can't carry a TLS policy (cert-pinning / mTLS unreachable from `sandhi_http_*`)

> **RESOLVED (2026-06-09, sandhi 1.4.6 / cyrius 6.1.20).** Added
> `sandhi_http_options_tls_policy(opts, policy)` + getter; the high-level
> `sandhi_http_*` path (and `sandhi_http_stream`) now brackets its HTTPS
> open with the policy pre/post-open helpers — fail-closed when
> enforcement is unavailable, post-handshake SPKI pin check, pool + 0-RTT
> bypassed for policy-bound requests. Live gate
> `programs/_https_policy_threading_gate.cyr` (native): no-policy 200,
> wrong-pin fail-closed `err=TLS`, correct-pin 200 — ALL GATES PASS. See
> CHANGELOG [1.4.6]. (Note: the *low-level* trust-store/mTLS enforcement
> still SIGSEGVs on a live network — a separate pre-existing issue:
> [`2026-06-09-tls-policy-enforcement-live-segfault.md`](2026-06-09-tls-policy-enforcement-live-segfault.md).)

**Status:** ✅ Resolved 1.4.6 (was Open — P1; feature gap, wiring not new crypto).
**Severity:** **P1** — blocks a consumer hardening requirement (hoosh v2.2.0
certificate pinning). No security regression today (pinning is simply
unavailable on the high-level path), but the building blocks already ship and
exist one layer down, so the gap is "unreachable", not "unbuilt".
**Reporter:** hoosh (AI inference gateway, v2.2.0 — remote provider transport).
**Sandhi version:** 1.4.5 (bundled at cyrius 6.1.20 as `lib/sandhi.cyr`).
**Affects:** every consumer that forwards over the high-level client
(`sandhi_http_get` / `_post` / `_put` / … and `sandhi_http_stream`) and wants to
pin a server SPKI, present a client cert (mTLS), or override the trust store.

## Summary

sandhi already has a **complete, live** TLS-policy layer:

- `sandhi_tls_policy_new_pinned(spki_hex)` / `_new_mtls(cert, key)` /
  `_new_trust_store(bundle)` / `_combine(a, b)` (`src/tls_policy/policy.cyr`).
- `sandhi_conn_open_with_policy(addr, port, use_tls, sni_host, policy)` enforces
  them at handshake time — `_sandhi_apply_hook` runs the `SSL_CTX_*` config
  (trust store / mTLS), `_sandhi_check_spki` does the post-handshake SPKI pin
  compare in constant time (`sandhi_fp_eq`), fail-closed per ADR 0004. Wired and
  live since cyrius v5.6.41; the SPKI path moved onto the typed
  `tls_get_peer_spki_der` at 1.4.2.

The gap is purely that the **high-level HTTP client never threads a policy**:

- `sandhi_http_options` has setters for redirects / hops / max-bytes / read-ms /
  write-ms / connect-ms / total-ms / pool — but **no `tls_policy` field**.
- The request path opens its connection with the **plain** opener, not the
  policy-aware one:
  - non-stream: `_sandhi_http_do_impl_a` → `sandhi_conn_open_fully_timed_a`
  - stream: `sandhi_http_stream_opts_a` → `sandhi_conn_open_fully_timed_a`
    (`src/http/stream.cyr` ~8228) — both bypass `sandhi_conn_open_with_policy`.

So a consumer can pin only if it abandons the high-level client and hand-rolls
the request/response (and, for streaming, the chunked + SSE decode) directly over
`sandhi_conn_open_with_policy`. For hoosh that means losing
`sandhi_http_stream`'s SSE machinery — not worth it for a hardening item, hence
deferred consumer-side and filed here.

## What hoosh wanted to write (and couldn't)

```
# desired: pin api.anthropic.com's SPKI on the forwarded request
var pol  = sandhi_tls_policy_new_pinned("e3b0c442:98fc1c14:...");
var opts = sandhi_http_options_new();
sandhi_http_options_tls_policy(opts, pol);          # <-- does not exist
var r = sandhi_http_post_opts(url, headers, body, blen, opts);
```

## Proposed fix (wiring; no new crypto)

1. Add a policy slot to the options struct + accessors:
   `sandhi_http_options_tls_policy(opts, policy)` / `_get_tls_policy(opts)`
   (default 0 = today's behavior, no enforcement).
2. In `_sandhi_http_do_impl_a` and `sandhi_http_stream_opts_a`, when
   `opts` carries a policy and the scheme is HTTPS, open via
   `sandhi_conn_open_with_policy` (or a timed `_with_policy` variant that also
   threads connect/read/write deadlines — the timed opener and the policy opener
   need to converge) instead of `sandhi_conn_open_fully_timed_a`.
3. Honor the existing fail-closed gate: if the policy demands enforcement and
   `sandhi_tls_policy_enforcement_available() == 0`, fail the request with
   `SANDHI_ERR_TLS` rather than silently opening unpinned.
4. Pool interaction: a pooled connection was opened under whatever policy
   created it — either key the pool on policy identity or skip the pool when a
   policy is set (simpler; pinning requests are rare). Document the choice.

## Acceptance

- `sandhi_http_post_opts` / `sandhi_http_stream_opts` with a pinned policy
  succeed against a matching SPKI and fail `SANDHI_ERR_TLS` against a mismatch
  (live gate, mirroring the existing TLS-policy live gate from 1.3.0).
- No behavior change when no policy is set (default 0).

## Consumer status

hoosh v2.2.0 deferred cert pinning pending this. The other v2.2.0 criticals
(Anthropic system-message hoist, Gemini shaping, incremental remote streaming via
`sandhi_http_stream`) shipped on sandhi 1.4.5 / cyrius 6.1.20.
