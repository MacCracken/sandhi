# 2026-04-24 — ark adopts `sandhi::http` + `sandhi::rpc::json` for remote registry ops

**Status**: Awaiting ark roadmap entry
**Reporter**: sandhi post-M3 coordination sweep
**Target**: ark's base-OS modernization pass (pre-sandhi-fold at Cyrius v5.7.0)
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
include "dist/sandhi.cyr"

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

- **HTTPS runtime currently blocked** (`2026-04-24-fdlopen-getaddrinfo-blocked.md`). Production registries are HTTPS; ark can build against the sandhi surface while the stdlib TLS-init fix lands. Local-mirror plain-HTTP flows work today.
- **Large package payloads** — same buffer-size caveat as sit. Typical package manifests and tarballs under a few MB fit in the 256 KB default; larger payloads would need the sandhi streaming / configurable-buffer enhancement to land first.

## Proposed ark roadmap entry

> **Adopt `sandhi::http` + `sandhi::rpc::json` for remote registry ops.** Use `sandhi_http_*` for publish / resolve / yank / fetch; JSON marshaling via `sandhi::rpc::json`; auth via `sandhi::http::headers`. Pin sandhi via `[deps.sandhi]` during the 5.6.x window; pin retires at the v5.7.0 fold. Reference: `sandhi/docs/issues/2026-04-24-ark-sandhi-registry-ops.md`. **Blocked by**: stdlib TLS-init fix before live-HTTPS registry round-trips pass.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep.
