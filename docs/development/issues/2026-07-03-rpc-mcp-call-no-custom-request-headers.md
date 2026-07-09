# 2026-07-03 — rpc / mcp client calls accept no custom request headers (blocks trace-context + auth propagation)

> **WITHDRAWN / NOT A SANDHI BUG (corrected 2026-07-03, same day).** The premise
> was wrong. sandhi 1.7.0 **already** exposes the header-bearing variants —
> `sandhi_rpc_call_with_headers{,_a}` (`src/rpc/dispatch.cyr:348`) and
> `sandhi_rpc_mcp_call_with_headers{,_a}` (`src/rpc/mcp.cyr:79`) — plus the
> `sandhi_headers_new` / `sandhi_headers_set` builder. The filing read only the
> no-header convenience wrapper (`sandhi_rpc_mcp_call`) and missed the
> `_with_headers` variant sitting directly below it. A consumer already
> propagates `traceparent` / `Authorization` / correlation headers by building a
> `sandhi_headers` object and calling `sandhi_rpc_mcp_call_with_headers`.
> **No sandhi change needed**; the work is consumer-side (daimon adopts the
> existing API). Lesson: premise-check the full API surface, not just the
> convenience shim. The original (now-moot) analysis is kept below for the record.

**Severity:** Low–Medium. Low today (nothing is prevented from *functioning*);
Medium for distributed deployments — it blocks trace-context and
bearer/correlation propagation on any sandhi-driven outbound call.

## What

```cyrius
fn sandhi_rpc_mcp_call(endpoint_url, method_name, params_json): i64 {
    return sandhi_rpc_mcp_call_a(default_alloc(), endpoint_url, method_name, params_json);
}
fn sandhi_rpc_mcp_call_a(a, endpoint_url, method_name, params_json): i64 {
    var body = _sandhi_mcp_build_request_a(a, method_name, params_json);
    return sandhi_rpc_call_a(a, endpoint_url, "POST", body, SANDHI_RPC_DIALECT_JSONRPC);
}
```

Neither `sandhi_rpc_call{,_a}` nor `sandhi_rpc_mcp_call{,_a}` takes headers, so
the outbound request carries only sandhi's built-in set. A consumer forwarding a
request cannot attach:

- `traceparent` / `X-Trace-Id` — distributed trace-context propagation.
- `Authorization` — bearer/token pass-through to the downstream endpoint.
- idempotency / correlation / consumer-defined headers.

## Impact

daimon 1.3.3 added distributed tracing, but its external-MCP `mcp.forward` span
is **local-only** — the trace id reaches the downstream MCP endpoint through no
header, so that service starts a disconnected trace. Auth-bearing MCP forwards
are likewise impossible.

## Proposed fix

Add an optional headers argument to the client rpc surface, mirroring the server
side. Either shape works:

- a **CRLF-terminated extra-headers cstr** — exactly like
  `sandhi_server_send_response`'s `extra_headers` slot (cheapest; no new type), or
- a **`sandhi_headers`** object (the existing header type), threaded through
  `sandhi_rpc_call_a` into the outbound request builder.

Keep the current no-header signatures as thin wrappers passing `0`, for
back-compat.

## References

- Server-side precedent: `sandhi_server_send_response_a(..., extra_headers)`
  already appends a caller-supplied CRLF header block.
- Consumer: daimon 1.3.3 (`src/api_mcp.cyr` `api_mcp_call`, `src/trace.cyr`) —
  documents the missing propagation as a known limit in its CHANGELOG.
- W3C Trace Context — outbound propagation requires setting `traceparent` on the
  downstream request.
