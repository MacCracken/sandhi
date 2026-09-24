# 2026-04-24 — vidya adopts `sandhi::http` for external-knowledge fetch

**Status**: **OPEN — but the framing has changed** (re-checked 2026-09-23 @ 2.8.5;
first reframed 2026-08-23 @ 2.8.4). vidya **is already a sandhi consumer** — just not for fetch. It includes
`lib/sandhi.cyr` in 2 files and uses the **server** surface (`sandhi_server_run`,
`_get_path`, `_get_param[_a]`, `_path_segment`, `_send_response`, `_url_decode_a`,
`sandhi_json_escape`). The external-knowledge **fetch** ask in this doc is still unmet.

That makes this cheaper than filed: vidya has already paid the adoption cost and knows
the library. Adding the client surface is additive, not a new dependency. Still
consumer-scheduled, still low priority.
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
include "lib/sandhi.cyr"      # already in vidya's build (server surface)

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

- **HTTPS works end-to-end** — the original libssl-pthread / stdlib-TLS-init blocker resolved upstream (cyrius v5.6.39; native TLS is the no-flag default since 6.1.21), so live HTTPS fetches work today (see [`archive/2026-04-24-libssl-pthread-deadlock.md`](archive/2026-04-24-libssl-pthread-deadlock.md)); vidya's only remaining gate is its own future fetch milestone.
- **Large responses** — full Wikipedia articles etc. can exceed the buffered client's 256 KB default. Both remedies have shipped: `sandhi_http_options_max_response_bytes(opts, n)` raises the cap per call (an over-cap body fails as `SANDHI_ERR_PROTOCOL`, never a silent truncation), and `sandhi_http_download` streams a body of any size to an fd.
- **Rate limiting / polite scraping** is vidya's concern, not sandhi's. sandhi ships no built-in rate limiter.

## Proposed vidya roadmap entry

> **Use `sandhi::http` for external fetch.** Opt into redirect following via `sandhi_http_options_new()`. vidya already includes stdlib's `lib/sandhi.cyr` for its server, so this adds verbs, not a dependency. Reference: `sandhi/docs/development/issues/2026-04-24-vidya-sandhi-fetch.md`. **Priority**: future — pick up when vidya's fetch milestone opens.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Flagged as lowest-priority consumer since vidya itself lists this as future work in sandhi's state.md.
- **2026-09-23** (sandhi 1.10.0 issue sweep) — Re-checked vidya 2.8.5: same eight server-side
  verbs, no fetch path of any kind yet; stays open. Repaired the handoff's pre-fold include /
  pin guidance and the large-response caveat (both remedies have shipped).
