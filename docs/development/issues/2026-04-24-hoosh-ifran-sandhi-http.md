# 2026-04-24 — hoosh + ifran adopt `sandhi::http` + `sandhi::rpc::json` for LLM-provider routing

**Status**: **PARTIALLY RESOLVED — now an ifran-only item** (re-checked 2026-09-23;
first split 2026-08-23).

- **hoosh @ 2.6.10 — ADOPTED** (first confirmed @ 2.6.3). Uses `sandhi_http_post`, `sandhi_http_stream` +
  `sandhi_sse_event_data` / `sandhi_stream_err` / `_status` (streaming LLM responses,
  which is exactly the shape this doc proposed), plus `sandhi_headers_*`,
  `sandhi_resolve_ipv4`, `sandhi_net_parse_ipv4` and `sandhi_server_run`.
- **ifran @ 2.2.1 — NOT adopted.** Zero sandhi verbs in `src/` (unchanged since 2.2.0).

The doc deliberately covered both because their needs were identical. They have now
diverged, which is the condition its own header called out for splitting it. Everything
below still reads as written for ifran; hoosh's half is done.
**Reporter**: sandhi post-M3 coordination sweep
**Target**: ifran-scheduled (the pre-fold window this originally named has passed)
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
include "lib/sandhi.cyr"      # stdlib; add "sandhi" to [deps] stdlib

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

- **HTTPS works end-to-end** — the original libssl-pthread / stdlib-TLS-init blocker resolved upstream (cyrius v5.6.39; native TLS is the no-flag default since 6.1.21), so live HTTPS to production LLM providers works today (see [`archive/2026-04-24-libssl-pthread-deadlock.md`](archive/2026-04-24-libssl-pthread-deadlock.md)).
- **JSON array navigation** (`path.0.field`) isn't yet in `sandhi_json_get_string`. Consumers handle arrays either by `get_string` + manual substring scan, or by pre-built array fragments. If a second LLM-provider consumer needs array navigation, we'll add it.
- **Streaming (SSE)** shipped at M3.5 — `sandhi_http_stream` + `sandhi_sse_*` — and is what hoosh uses for provider streaming. The 1.9.15 read-boundary event-loss fix (a whole SSE event could vanish when a TCP read split it) reaches consumers only through a cyrius release that re-vendors `lib/sandhi.cyr`.

## Proposed roadmap entry (drop into both hoosh and ifran)

> **Adopt `sandhi::http` + `sandhi::rpc::json` for provider-routing HTTP traffic.** Replace any direct `lib/http.cyr` usage (GET-only, HTTP/1.0, no HTTPS) with sandhi's full client surface; use `sandhi_http_stream` + `sandhi_sse_*` for streamed completions. Use `sandhi::http::headers` for auth / org / user-agent. sandhi ships in stdlib: add `"sandhi"` to `[deps] stdlib` and `include "lib/sandhi.cyr"` — there is no `[deps.sandhi]` pin post-fold. hoosh is the working reference. Reference: `sandhi/docs/development/issues/2026-04-24-hoosh-ifran-sandhi-http.md`.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Pairs hoosh + ifran because ADR 0001 + state.md describe them as "same shape". Split when that stops being true.
- **2026-09-23** (sandhi 1.10.0 issue sweep) — Re-checked: ifran 2.2.1 still has zero sandhi
  verbs; stays open (hoosh 2.6.10 remains adopted). Not split into two files — renaming would
  break inbound links and the hoosh half needs no handoff; the status block carries the split.
  Repaired the pre-fold guidance: `include "lib/sandhi.cyr"` + `[deps] stdlib` instead of
  `dist/` + a `[deps.sandhi]` pin, and the SSE caveat (shipped, not deferred).
