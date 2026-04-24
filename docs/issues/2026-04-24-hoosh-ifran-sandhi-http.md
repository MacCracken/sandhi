# 2026-04-24 — hoosh + ifran adopt `sandhi::http` + `sandhi::rpc::json` for LLM-provider routing

**Status**: Awaiting hoosh / ifran roadmap entries
**Reporter**: sandhi post-M3 coordination sweep
**Target**: hoosh & ifran base-OS modernization pass (pre-sandhi-fold at Cyrius v5.7.0)
**Depends on**: sandhi v0.4.0 (shipped)

> hoosh (LLM provider routing) and ifran (same shape as hoosh) have identical sandhi needs, so one doc covers both. If their implementation paths diverge during modernization, split this into two.

## What's assumed vs. actual

sandhi was scaffolded with "cleaner HTTP client surface for LLM-provider routing" as one of the justifications (see ADR 0001). Whether hoosh or ifran have adopted sandhi on their own roadmaps is **not confirmed from this repo**. The sandhi-side surface is ready.

## What sandhi now provides (ready for hoosh / ifran)

- **`sandhi::http::client`** — full method surface (`sandhi_http_get` / `_post` / `_put` / `_delete` / `_patch` / `_head`), auto Content-Length for body-bearing methods, HTTP/1.1 with `Connection: close`, native DNS (A-records via `/etc/resolv.conf` + public fallback), chunked response decoding. Opt-in redirect following via `sandhi_http_options_new()` + `_opts`-suffix variants.
- **`sandhi::http::headers`** — real key-value store (`set` / `add` / `get` / `remove` / `has` / serialize / parse). Pass as the `headers` param to any request verb; `Authorization: Bearer ...` and provider-specific headers land here.
- **`sandhi::rpc::json`** — nested JSON build + dotted-path extract. Needed for typical LLM request/response shapes (`{"model": "...", "messages": [...]}` → `{"choices": [{"message": {"content": "..."}}]}`).
- **`sandhi::discovery`** — *optional* for hoosh/ifran. A chain resolver lets callers hit providers via hostname, via daimon-registered local gateway, or via mDNS (interface only today). Configured base URLs work without any discovery layer.

## Minimal migration shape

```cyr
include "dist/sandhi.cyr"

# Auth + body
var h = sandhi_headers_new();
sandhi_headers_set(h, "Authorization", "Bearer <token>");

var body_obj = sandhi_json_obj_new();
sandhi_json_add_string(body_obj, "model", "claude-opus-4-7");
# Build `messages` array via add_raw after construction, or use a helper.
sandhi_json_add_raw(body_obj, "messages", "[{\"role\":\"user\",\"content\":\"hi\"}]");
var body = sandhi_json_build(body_obj);

var r = sandhi_http_post("https://api.anthropic.com/v1/messages", h, body, strlen(body));
if (sandhi_http_err_kind(r) != SANDHI_OK) { /* connect / DNS / TLS failure */ }

var reply = sandhi_json_get_string(sandhi_http_body(r),
                                   "content.0.text");
# (subscript access would need sandhi_json to grow array navigation;
#  for now, dotted-path + a shim helper in the consumer is fine.)
```

## Known caveats

- **HTTPS runtime currently blocked** (`2026-04-24-libssl-pthread-deadlock.md`). Every production LLM provider uses HTTPS. hoosh / ifran can build against the sandhi surface and test against a local plain-HTTP mock (`programs/http-probe.cyr` shape) while the libssl pthread-lock fix lands — the API doesn't change when TLS starts working.
- **JSON array navigation** (`path.0.field`) isn't yet in `sandhi_json_get_string`. Consumers handle arrays either by `get_string` + manual substring scan, or by pre-built array fragments. If a second LLM-provider consumer needs array navigation, we'll add it.
- **Streaming (SSE)** deferred to sandhi M3.5. Chunked responses decode correctly today; SSE-as-iterator-callbacks awaits a consumer explicitly asking.

## Proposed roadmap entry (drop into both hoosh and ifran)

> **Adopt `sandhi::http` + `sandhi::rpc::json` for provider-routing HTTP traffic.** Replace any direct `lib/http.cyr` usage (GET-only, HTTP/1.0, no HTTPS) with sandhi's full client surface. Use `sandhi::http::headers` for auth / org / user-agent. Pin sandhi via `[deps.sandhi]` during the 5.6.x window; pin retires at the v5.7.0 fold. Reference: `sandhi/docs/issues/2026-04-24-hoosh-ifran-sandhi-http.md`. **Blocked by**: stdlib TLS-init fix before live-HTTPS round-trips pass.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Pairs hoosh + ifran because ADR 0001 + state.md describe them as "same shape". Split when that stops being true.
