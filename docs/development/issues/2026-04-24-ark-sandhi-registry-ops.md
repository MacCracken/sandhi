# 2026-04-24 — ark adopts `sandhi::http` + `sandhi::rpc::json` for remote registry ops

**Status**: **OPEN — confirmed not adopted** (re-checked 2026-09-23 against
`~/Repos/ark` @ 1.4.2: zero sandhi verbs in `src/`; first confirmed 2026-08-23 @ 1.4.1). No longer an assumption. The
sandhi-side surface has been ready since v0.4.0 and has only grown since
(streaming download at 1.6.4 is a direct fit for registry artifact pulls).
**Reporter**: sandhi post-M3 coordination sweep
**Target**: ark-scheduled (the pre-fold window this originally named has passed)
**Depends on**: sandhi v0.4.0 (shipped)

## What's assumed vs. actual

ADR 0001 lists ark as a planned sandhi consumer for "remote registry operations". Whether ark's roadmap has sandhi adoption scheduled is **not confirmed from this repo**. The sandhi-side surface is ready.

## What sandhi now provides (ready for ark)

- **`sandhi::http::client`** — GET/POST/PUT/DELETE for registry API calls (publish package, resolve version, fetch manifest, yank).
- **`sandhi::http::headers`** — `Authorization` tokens, `Content-Type: application/json`, `User-Agent: ark/...`.
- **`sandhi::rpc::json`** — build request payloads (publish metadata), extract fields from registry responses (`sandhi_json_get_string(body, "package.version")`, etc.).
- **Redirect following** opt-in via `sandhi_http_options_new()` — registries sometimes 301/307 on mirror migrations.
- **Optional `sandhi::discovery`** if ark wants to locate the registry via a chain resolver (daimon-registered → configured hostname → public fallback).

## Minimal migration shape

```cyr
include "lib/sandhi.cyr"      # stdlib; add "sandhi" to [deps] stdlib

# Publish
var h = sandhi_headers_new();
sandhi_headers_set(h, "Authorization", "Bearer <token>");

var manifest = sandhi_json_obj_new();
sandhi_json_add_string(manifest, "name", "mycrate");
sandhi_json_add_string(manifest, "version", "1.2.3");
var body = sandhi_json_build(manifest);

var r = sandhi_http_post("https://ark.example.com/v1/packages",
                         h, body, strlen(body));
if (sandhi_http_err_kind(r) != SANDHI_OK) { /* network / parse failure */ }
if (sandhi_http_status(r) >= 400) { /* registry refused */ }

# Resolve
var rr = sandhi_http_get("https://ark.example.com/v1/packages/mycrate", 0);
var version = sandhi_json_get_string(sandhi_http_body(rr), "latest.version");
```

## Known caveats

- **HTTPS works end-to-end** — the original libssl-pthread / stdlib-TLS-init blocker resolved upstream (cyrius v5.6.39; native TLS is the no-flag default since 6.1.21), so live HTTPS registry round-trips work today (see [`archive/2026-04-24-libssl-pthread-deadlock.md`](archive/2026-04-24-libssl-pthread-deadlock.md)).
- **Large package payloads** — both enhancements this caveat waited on have shipped. The buffered client caps a response at 256 KB by default; raise it per call with `sandhi_http_options_max_response_bytes(opts, n)` (an over-cap body fails as `SANDHI_ERR_PROTOCOL`, never a silent truncation). For artifact pulls, stream the body to an fd instead: `sandhi_http_download(url, fd, opts)` / `sandhi_http_download_headers(...)` (1.6.4 / 1.9.3) — no in-memory cap at all.

## Proposed ark roadmap entry

> **Adopt `sandhi::http` + `sandhi::rpc::json` for remote registry ops.** Use `sandhi_http_*` for publish / resolve / yank, `sandhi_http_download` for artifact fetch; JSON marshaling via `sandhi::rpc::json`; auth via `sandhi::http::headers`. sandhi ships in stdlib: add `"sandhi"` to `[deps] stdlib` and `include "lib/sandhi.cyr"` — there is no `[deps.sandhi]` pin post-fold. Reference: `sandhi/docs/development/issues/2026-04-24-ark-sandhi-registry-ops.md`.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep.
- **2026-09-23** (sandhi 1.10.0 issue sweep) — Re-checked: ark 1.4.2 still has zero sandhi
  verbs; stays open. Repaired the handoff: post-fold include shape, and the large-payload
  caveat now names the shipped `max_response_bytes` option + streaming download instead of
  telling ark to wait for them.
