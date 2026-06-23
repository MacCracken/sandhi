# Request: JSON Merge Patch (RFC 7396) / JSON-RPC 2.0 batch

**Filed**: 2026-06-23 (consolidated out of the roadmap's wait-for-second-consumer list)
**Touches**: `src/rpc/json.cyr` (merge patch) / `src/rpc/dispatch.cyr` + `src/rpc/mcp.cyr` (batch)
**Gate**: a consumer needing RFC 7396 or JSON-RPC 2.0 batch

## Ask

Two related but distinct RPC-surface additions:

- **JSON Merge Patch (RFC 7396)** — apply a merge-patch document to a JSON
  value (recursive object merge, `null` deletes a member) in `src/rpc/json.cyr`.
- **JSON-RPC 2.0 batch** — send an array of request objects in one HTTP POST
  and demultiplex the array of responses by `id`, in the dispatch + MCP layers.

## Why it's a request, not roadmap work

Neither has a consumer today. **Batch is the likelier ask** — MCP
tool-discovery does many small calls and would benefit from batching their
round-trips — but until a consumer actually feels that latency the batch
demux error-handling (partial failures, notification-vs-request mixing,
ordering) is unconstrained design.

## When to promote

A consumer hitting MCP tool-discovery latency (→ batch first) or one whose
API speaks RFC 7396 (→ merge patch). Promote the specific half that's asked
for; they don't need to land together.
