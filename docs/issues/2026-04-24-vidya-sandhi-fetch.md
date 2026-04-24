# 2026-04-24 — vidya adopts `sandhi::http` for external-knowledge fetch

**Status**: Awaiting vidya roadmap entry — **low priority, future milestone**
**Reporter**: sandhi post-M3 coordination sweep
**Target**: vidya's fetch milestone (no specific timing; treated as future)
**Depends on**: sandhi v0.3.0 (shipped)

## What's assumed vs. actual

ADR 0001 lists vidya as a "future" sandhi consumer for "any external-knowledge fetch path". Whether vidya's roadmap has a concrete fetch milestone is **not confirmed from this repo** — this is the lightest-commitment consumer and is flagged as future in sandhi's state.md itself.

Filing this doc so when vidya's fetch work opens up, the sandhi-side path is already documented rather than rediscovered.

## What sandhi now provides (ready for vidya)

- **`sandhi::http::client`** — `sandhi_http_get` handles the bulk of fetch patterns. POST for APIs that require it.
- **`sandhi::http::headers`** — custom User-Agent (polite scraping), Accept headers, Authorization if the source requires.
- **Redirect following** is probably the most useful piece for vidya: set `sandhi_http_options_new()` with `follow_redirects = 1` so link-chains to final content are transparent.
- **`sandhi::rpc::json`** where the external source is structured (APIs, RSS-as-JSON, etc.). For HTML / text sources, the raw body via `sandhi_http_body(r)` is what vidya wants.

## Minimal migration shape

```cyr
include "dist/sandhi.cyr"

var opts = sandhi_http_options_new();
sandhi_http_options_follow_redirects(opts, 1);
sandhi_http_options_max_hops(opts, 5);

var h = sandhi_headers_new();
sandhi_headers_set(h, "User-Agent", "vidya/1.0 (AGNOS)");

var r = sandhi_http_get_opts("https://example.org/knowledge.json", h, opts);
if (sandhi_http_err_kind(r) != SANDHI_OK) { /* failure */ }
var body = sandhi_http_body(r);
# Hand `body` to vidya's parser (HTML / JSON / whatever).
```

## Known caveats

- **HTTPS runtime currently blocked** (`2026-04-24-libssl-pthread-deadlock.md`). External knowledge sources are almost entirely HTTPS now; vidya's live work is therefore gated on the libssl pthread-lock fix.
- **Large responses** — same buffer caveat as sit / ark. Full Wikipedia articles etc. may exceed the 256 KB default. Add streaming / configurable buffer when vidya's fetch work opens and actually hits this.
- **Rate limiting / polite scraping** is vidya's concern, not sandhi's. sandhi ships no built-in rate limiter.

## Proposed vidya roadmap entry

> **Use `sandhi::http` for external fetch.** Opt into redirect following via `sandhi_http_options_new()`. Pin sandhi via `[deps.sandhi]` during the 5.6.x window; pin retires at the v5.7.0 fold. Reference: `sandhi/docs/issues/2026-04-24-vidya-sandhi-fetch.md`. **Blocked by**: stdlib TLS-init fix before live-HTTPS fetches work. **Priority**: future — pick up when vidya's fetch milestone opens.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Flagged as lowest-priority consumer since vidya itself lists this as future work in sandhi's state.md.
