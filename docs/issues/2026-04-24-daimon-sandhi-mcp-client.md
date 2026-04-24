# 2026-04-24 — daimon adopts `sandhi::rpc::mcp` for MCP-over-HTTP dispatch

**Status**: Awaiting daimon roadmap entry (consumer-side)
**Reporter**: sandhi post-M3 coordination sweep
**Target**: daimon's base-OS modernization pass (pre-sandhi-fold at Cyrius v5.7.0)
**Depends on**: sandhi v0.4.0 (shipped)
**Pairs with**: [2026-04-24-daimon-registry-endpoints.md](2026-04-24-daimon-registry-endpoints.md) (producer side)

> daimon has two sandhi touchpoints. The other doc covers the **producer** side (registry endpoints sandhi calls). This doc covers the **consumer** side (daimon calling MCP-over-HTTP endpoints for tool / prompt / sampling dispatch). Split so each can land on daimon's roadmap independently.

## What's assumed vs. actual

sandhi's M3 landed `sandhi::rpc::mcp` as transport-only per ADR 0001. Whether daimon has adopted it on its own roadmap is **not confirmed from this repo**. The sandhi-side surface is ready and unit-tested.

## What sandhi now provides (ready for daimon)

- **`sandhi_rpc_mcp_call(endpoint_url, method_name, params_json)`** — builds a JSON-RPC 2.0 envelope with a monotonic request ID, POSTs it, returns an `rpc-response`. Caller supplies the method (e.g. `"tools/list"`, `"resources/read"`) and params as a pre-built JSON fragment (or 0 for none).
- **`sandhi_rpc_mcp_call_with_headers(...)`** — same, plus caller-supplied headers for auth tokens, session cookies, etc.
- **Result / error helpers** — `sandhi_rpc_mcp_result_raw(resp)` pulls the raw `result` JSON cstr out of a success response; `sandhi_rpc_mcp_error_code` / `_error_message` extract JSON-RPC error envelopes without needing daimon-side JSON parsing.
- **Transport-only, per ADR 0001**. Tool discovery, prompt schemas, sampling semantics stay in bote / t-ron. sandhi hands daimon a raw JSON `result` value; daimon re-parses into its typed MCP shapes.

## Minimal migration shape

```cyr
include "dist/sandhi.cyr"  # pre-fold; lib/sandhi.cyr post-fold

# Call an MCP endpoint.
var params = sandhi_json_obj_new();
sandhi_json_add_string(params, "cursor", "abc");
var r = sandhi_rpc_mcp_call("http://mcp.example:9000/rpc", "tools/list", sandhi_json_build(params));

if (sandhi_rpc_ok(r) == 0) {
    # JSON-RPC error envelope already extracted for us.
    var code = sandhi_rpc_mcp_error_code(r);
    var msg  = sandhi_rpc_mcp_error_message(r);
    # surface to caller...
}
var result_json = sandhi_rpc_mcp_result_raw(r);
# Hand `result_json` to bote / t-ron for message-shape parsing.
```

## Known caveats

- **MCP message semantics stay in bote / t-ron.** sandhi will not grow tool-typed or prompt-typed verbs. If daimon needs a helper for a common MCP pattern, that pattern lives in bote.
- **HTTPS runtime currently blocked** (cross-link to `2026-04-24-libssl-pthread-deadlock.md`). MCP endpoints that speak plain HTTP work fine; https:// MCP servers wait on the libssl pthread-lock fix.

## Proposed daimon roadmap entry

> **Adopt `sandhi::rpc::mcp` for MCP-over-HTTP dispatch.** Replace any hand-rolled JSON-RPC 2.0 envelope construction in daimon's MCP dispatch path with `sandhi_rpc_mcp_call`. Keep MCP message-shape parsing in bote / t-ron. Pin sandhi via `[deps.sandhi]` during the 5.6.x window; pin retires at the v5.7.0 fold. Reference: `sandhi/docs/issues/2026-04-24-daimon-sandhi-mcp-client.md`.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Split from the daimon-registry-endpoints doc so the consumer + producer sides of daimon's sandhi integration can land independently.
