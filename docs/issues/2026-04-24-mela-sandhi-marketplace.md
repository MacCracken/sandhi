# 2026-04-24 — mela adopts `sandhi::http` + `sandhi::rpc::json` for marketplace API

**Status**: Awaiting mela roadmap entry
**Reporter**: sandhi post-M3 coordination sweep
**Target**: mela's base-OS modernization pass (pre-sandhi-fold at Cyrius v5.7.0)
**Depends on**: sandhi v0.4.0 (shipped)

## What's assumed vs. actual

ADR 0001 lists mela as a planned sandhi consumer for "marketplace API". Whether mela's roadmap has sandhi adoption scheduled is **not confirmed from this repo**. Sandhi-side surface is ready.

## What sandhi now provides (ready for mela)

- **`sandhi::http::client`** — GET/POST/PUT/DELETE for marketplace endpoints (list items, fetch listing, submit purchase, auth).
- **`sandhi::http::headers`** — customer / org / auth tokens, `Content-Type`, custom X-headers.
- **`sandhi::rpc::json`** — request / response JSON with dotted-path extraction for nested marketplace shapes (`listing.price.amount`, `listing.seller.id`, …).
- **Redirect following** opt-in via `sandhi_http_options_new()`.

## Minimal migration shape

```cyr
include "dist/sandhi.cyr"

var h = sandhi_headers_new();
sandhi_headers_set(h, "Authorization", "Bearer <token>");
sandhi_headers_set(h, "Accept", "application/json");

var r = sandhi_http_get("https://marketplace.example/v1/listings?q=cyrius",
                        h);
if (sandhi_http_err_kind(r) != SANDHI_OK) { /* network / parse failure */ }

# Nested extract
var first_price = sandhi_json_get_string(sandhi_http_body(r),
                                         "results.0.price.amount");
# (array-index navigation is pending — for now, consumers either
# walk the body manually or pre-parse an array fragment.)
```

## Known caveats

- **HTTPS runtime currently blocked** (`2026-04-24-fdlopen-getaddrinfo-blocked.md`). Real marketplaces are HTTPS. mela builds against the surface today; live round-trips wait for the stdlib TLS-init fix.
- **JSON array navigation** (`path.N.field`) is not in sandhi today; mela gets string extraction + whole-body navigation. If marketplace shapes demand array traversal often, file as a sandhi follow-up — it's a small addition to `rpc/json.cyr`.

## Proposed mela roadmap entry

> **Adopt `sandhi::http` + `sandhi::rpc::json` for marketplace API traffic.** Pin sandhi via `[deps.sandhi]` during the 5.6.x window; pin retires at the v5.7.0 fold. Reference: `sandhi/docs/issues/2026-04-24-mela-sandhi-marketplace.md`. **Blocked by**: stdlib TLS-init fix before live-HTTPS marketplace calls work.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep.
