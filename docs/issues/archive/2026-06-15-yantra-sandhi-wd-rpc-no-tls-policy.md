# 2026-06-15 — sandhi WebDriver/Appium RPC can't carry a TLS policy (blocks endpoint cert pinning)

> **RESOLVED — sandhi 1.6.3 (2026-06-15).** Implemented **option (2)** from
> *What's missing* below: an endpoint-keyed default TLS policy registry at the
> shared RPC dispatch layer (`src/rpc/dispatch.cyr`). New public verbs:
> `sandhi_rpc_set_default_tls_policy(base_url, policy)` /
> `_clear_default_tls_policy(base_url)` / `_get_default_tls_policy(base_url)` /
> `_clear_all_default_tls_policy()`. A consumer registers the
> `sandhi_tls_policy_new_pinned(spki_hex)` handle once per endpoint; every
> `sandhi_wd_*` / `sandhi_ap_*` / `sandhi_rpc_mcp_*` call whose URL falls under
> that `base_url` (longest-prefix match, path-boundary-aware) opens through the
> policy with the same pin / mTLS / trust-store semantics as
> `sandhi_http_options_tls_policy` — no per-verb `_opts` churn at the call site,
> and no way to leave one action unpinned. The MCP SSE stream
> (`sandhi_rpc_mcp_stream_a`) carries it too. Plain-HTTP URLs are unaffected (the
> HTTP layer ignores a policy on non-TLS), so yantra's current `127.0.0.1`
> backends see no behavior change. Tests: `tests/rpc.tcyr` 42 → 63. See
> CHANGELOG [1.6.3]. **yantra action:** call
> `sandhi_rpc_set_default_tls_policy(grid_base_url, pin_policy)` after building the
> sigil-verified pin in `src/security.cyr`, before driving the session.
>
> ---
>
> **Class:** feature gap. sandhi exposes a rich TLS-policy API
> (`sandhi_tls_policy_new_pinned` / `_mtls` / `_trust_store` / `_combine`,
> attachable to a request via `sandhi_http_options_tls_policy`), but its
> **WebDriver/Appium RPC convenience layer** (`sandhi_wd_*` / `sandhi_ap_*`) takes
> only a `base_url` (+ call args) — **no options parameter, no TLS policy, and no
> base-URL-keyed default policy**. So a consumer driving a *remote* WebDriver grid
> / Appium cloud over HTTPS cannot pin the endpoint cert (or require mTLS / a
> custom trust store) on the per-action calls.
>
> **Status (filed):** triage / enhancement request. Surfaced by yantra M8.

## How this surfaced

yantra 0.7.x opened its M8 security milestone: "WebDriver / Appium endpoints
authenticate via sigil-verified HTTPS certs." yantra already verifies a
sigil-signed SPKI cert-pin descriptor and produces a
`sandhi_tls_policy_new_pinned(spki_hex)` handle (`src/security.cyr`,
`yantra_tls_pin_verify_ed25519` / `_hybrid`, tested in `tests/m8.tcyr`).

But there is **nowhere to attach that policy** for the actual driver traffic. The
RPC functions yantra drives are, e.g.:

```
fn sandhi_wd_new_session(base_url, capabilities_json): i64
fn sandhi_wd_navigate_to(base_url, session_id, target_url): i64
fn sandhi_wd_find_element(base_url, session_id, strategy, selector): i64
fn sandhi_wd_element_click(base_url, session_id, element_id): i64
fn sandhi_wd_element_send_keys(base_url, session_id, element_id, text): i64
fn sandhi_wd_execute_script(base_url, session_id, script, args_json): i64
fn sandhi_wd_delete_session(base_url, session_id): i64
# … and the sandhi_ap_* Appium variants
```

Only the **session-create POST** can currently be secured, because yantra issues
*that* one itself via `sandhi_http_post_opts(url, headers, body, len, opts)` and
can set a policy on `opts`. Every subsequent per-action call goes through the
`sandhi_wd_*` convenience functions, which build their own request internally
with no caller-supplied options — so navigate/find/click/sendkeys/execute/delete
would fall back to default trust with no pinning. A half-pinned session is not a
meaningfully pinned session.

## What's missing

A way to attach a `tls_policy` (and ideally the rest of `sandhi_http_options_*`:
timeouts, pooling) to the WebDriver/Appium RPC path. Any of:

1. **`_opts` variants** — `sandhi_wd_navigate_to_opts(base_url, session_id, url, opts)`
   etc. (and `sandhi_ap_*_opts`), threading the existing options struct through
   the internal request build. Most explicit; verbose (one per verb).
2. **A base-URL-keyed default policy** — `sandhi_wd_set_default_tls_policy(base_url, policy)`
   (or a session/client object that carries the policy), so all RPC to that
   endpoint inherits it. Least churn at call sites; needs sandhi to hold the
   mapping.
3. **A WebDriver "client" handle** — `sandhi_wd_client_new(base_url, opts)` that
   the `sandhi_wd_*` calls take instead of a bare `base_url`. Cleanest long-term;
   biggest API change.

Recommendation: (2) or (3) — a single place to set the policy per endpoint, so
consumers don't repeat it on every verb and can't accidentally leave one call
unpinned.

## Adjacent note (not blocking this)

sandhi's HTTPS today is the localhost-irrelevant case for yantra — all current
yantra backends are `127.0.0.1` plain HTTP. So this is forward-looking for
remote-grid support; there is no live exposure. It is filed now because the
sigil verification half is already implemented in yantra and the policy it
produces has no application point until this lands.

## References

- yantra: `src/security.cyr` (sigil-verified pin → `sandhi_tls_policy_new_pinned`),
  `tests/m8.tcyr` (verification gate, 14/14), `docs/audit/2026-06-15-audit.md` F-2.
- sandhi TLS policy API: `sandhi_tls_policy_new_pinned` / `_mtls` /
  `_trust_store` / `_combine`, `sandhi_http_options_tls_policy`.
