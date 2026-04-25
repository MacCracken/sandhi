# 003 — Surfaces shipped stubbed; wire-up landed at 0.9.3

Several sandhi modules originally shipped fully-designed public
surfaces whose runtime path delegated to a stub. This was a
deliberate shape: the blocker wasn't the sandhi-side design, it
was a pair of external asks (one libssl, one stdlib) that needed
to clear first. Shipping the surface while the runtime stubbed
let consumers write against the permanent API immediately; when
the blockers cleared, the runtime filled in without a public-API
change and without a consumer code churn.

> **Status — 2026-04-25 (closed):** All three external blockers
> cleared between cyrius v5.6.39 and v5.6.41 (see `docs/issues/archive/`).
> Sandhi-side wire-up landed at 0.9.3 — `tls_policy/apply.cyr`
> resolves nine libssl/libcrypto symbols via stdlib `tls_dlsym`
> and exercises them through a `tls_connect_with_ctx_hook`
> callback (ALPN advertise + trust-store override + mTLS load) +
> a post-handshake SPKI extraction; `tls_policy/alpn.cyr`'s
> `_selected` / `_is_h2` accessors read a new
> `SANDHI_CONN_OFF_ALPN_DATA` slot on the conn struct, populated
> from `SSL_get0_alpn_selected`. `sandhi_tls_policy_enforcement_available()`
> returns 1 in normal operation; the fail-closed gate code stays
> in the source as a defense against future symbol regression
> (the test suite asserts `== 1` so a regression trips loud).
> This document is preserved as historical context for why the
> surface-first / runtime-second pattern was chosen. Sections
> below describe the original stub state, not the current state.

## What's stubbed

### `src/tls_policy/apply.cyr` — policy enforcement

`sandhi_conn_open_with_policy(addr, port, use_tls, sni_host,
policy)` reads the policy's `pinned_hash` / `mtls_cert` /
`trust_store` fields and decides what to do:

- If the policy demands enforcement (any of the three fields set)
  AND `sandhi_tls_policy_enforcement_available() == 0`, the call
  returns 0 with `_sandhi_conn_last_err = SANDHI_CONN_OPEN_TLS`
  (fail-closed per [ADR 0004](../adr/0004-security-first-refusal-model.md)).
- Otherwise, delegates to the default `sandhi_conn_open`
  (plain TCP or stdlib `tls_connect`).

`sandhi_tls_policy_enforcement_available()` returns **0** today.
The surface is complete — policy struct, constructors, combiner,
apply verb — but no actual pinning / mTLS / custom trust-store
enforcement fires.

What's needed to un-stub:

- `SSL_CTX_load_verify_locations` (custom trust store).
- `SSL_CTX_use_certificate_file` + `SSL_CTX_use_PrivateKey_file`
  (mTLS).
- `SSL_get_peer_certificate` + `X509_get_pubkey` + `i2d_PUBKEY`
  (SPKI extraction for pin comparison).
- A stdlib-side hook to customize the `SSL_CTX` that stdlib
  `tls.cyr` creates privately inside `tls_connect` — see
  `docs/issues/archive/2026-04-24-stdlib-tls-alpn-hook.md` for the
  function-pointer hook ask.

Plus the libssl-pthread-deadlock blocker
(`docs/issues/archive/2026-04-24-libssl-pthread-deadlock.md`) — until
`SSL_connect` stops hanging on a futex, live HTTPS doesn't work
at all, which is the prerequisite for any of the above exercising
anything.

### `src/tls_policy/alpn.cyr` — ALPN selection

`sandhi_alpn_encode_protos(protos_csv, out, out_cap)` fully
implements the RFC 7301 §3.1 `ProtocolNameList` wire-format
encoder. The default advertise list `SANDHI_ALPN_DEFAULT =
"h2,http/1.1"` serializes to the right 13 bytes; encode is
unit-tested in `tests/h2.tcyr`.

`sandhi_conn_alpn_selected(conn)` and `sandhi_conn_alpn_is_h2(conn)`
accessors ship with the public API at `src/tls_policy/alpn.cyr:83`
/ `:91`. They return **0** today (stub — "ALPN did not negotiate
anything"). `sandhi_http_request_auto` in
`src/http/h2/dispatch.cyr` handles 0 as "use HTTP/1.1", which is
correct degradation.

What's needed to un-stub:

- `SSL_CTX_set_alpn_protos` on the client SSL_CTX (to advertise
  the list).
- `SSL_get0_alpn_selected` post-handshake on the SSL object (to
  read the negotiated protocol).
- An `alpn_selected` slot on the conn struct, populated from
  `SSL_get0_alpn_selected` and returned by
  `sandhi_conn_alpn_selected`.

Same stdlib hook ask as policy enforcement — both need the
stdlib `tls.cyr`-side SSL_CTX factory hook.

### HTTP/2 — live transport

The h2 protocol stack (`src/http/h2/frame.cyr`,
`src/http/h2/hpack.cyr`, `src/http/h2/huffman.cyr`,
`src/http/h2/conn.cyr`, `src/http/h2/request.cyr`,
`src/http/h2/response.cyr`, `src/http/h2/dispatch.cyr`,
`src/http/h2/pool_glue.cyr`) is functionally complete and tested
against synthetic byte streams in `tests/h2.tcyr` (153
assertions). RFC 7541 Appendix C.3.1 + C.4.1 round-trips verified.

Live h2 talk — meaning a real HTTPS connection with ALPN
negotiation selecting `h2` — needs HTTPS to work at all. Same
libssl-pthread-deadlock blocker; same un-stub path.

## Why ship the surface now

[ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md) freezes
the public surface at 0.9.2. Anything not in the surface at fold
time ships as a post-fold 1.0.x stdlib patch, not as a 0.9.x
release.

Shipping the surface while the runtime stubs:

- Lets consumers write `sandhi_conn_open_with_policy` +
  `sandhi_alpn_encode_protos` + `sandhi_h2_request` call-sites
  today. Their code compiles, runs, and degrades correctly (TLS
  policy fails closed; ALPN returns no-h2; auto-dispatch uses
  1.1). When the blockers clear, the same code starts exercising
  the live path without any edit.
- Proves the surface shape through the sibling-crate phase. If
  a consumer call-site pattern is awkward, we find out now —
  while the public surface is still movable — not after fold.
- Avoids a 1.0.1 "wire up ALPN" stdlib patch that has to reason
  about every existing caller of `sandhi_conn_alpn_selected`.

## The un-stubbing is ~80 lines total

When both blockers clear:

- `src/tls_policy/apply.cyr` — ~50 lines: resolve the six
  OpenSSL symbols via `_dynlib_resolve_global`, call them in the
  right order during policy apply, populate
  `_sandhi_conn_last_err` precisely on failure. Flip
  `sandhi_tls_policy_enforcement_available()` to return 1.
- `src/tls_policy/alpn.cyr` — ~30 lines: resolve
  `SSL_CTX_set_alpn_protos` + `SSL_get0_alpn_selected`, add an
  `alpn_selected` slot to the conn struct, update the accessor
  to read it.

No public-API change. No CHANGELOG entry that says "behavior
change" — the surface has always documented the stub state via
`sandhi_tls_policy_enforcement_available()` and
`sandhi_conn_alpn_selected` returning 0.

0.8.1's `sandhi_http_request_auto` already routes through these
accessors. When ALPN un-stubs, auto-dispatch starts picking h2
without any consumer code change — see the CHANGELOG 0.8.1
"Limitations carried" note.

## Status signaling for callers

Two functions exist specifically so consumers can detect the stub
state at runtime:

- `sandhi_tls_policy_enforcement_available()` → 0 while stubbed,
  1 once wired. Consumers with hard-enforcement requirements
  (security-sensitive products) should check this at startup and
  refuse to run if it's 0.
- `sandhi_conn_alpn_selected(conn)` → 0 while stubbed, `"h2"` or
  `"http/1.1"` once wired. Callers that want h2-or-nothing can
  check `sandhi_conn_alpn_is_h2(conn)` and refuse to continue if
  it's 0.

## References

- `src/tls_policy/apply.cyr` — policy-apply with fail-closed gate.
- `src/tls_policy/alpn.cyr` — ALPN encoder + stubbed selection.
- `src/http/h2/` — protocol stack (complete, tested against
  synthetic streams).
- `docs/issues/archive/2026-04-24-libssl-pthread-deadlock.md` — the
  SSL_connect futex blocker.
- `docs/issues/archive/2026-04-24-stdlib-tls-alpn-hook.md` — the stdlib
  `tls.cyr` SSL_CTX factory hook ask.
- CHANGELOG 0.6.0, 0.8.0, 0.8.1, 0.9.0 P0 #5 — when the surface
  landed and when the fail-closed semantics firmed up.
