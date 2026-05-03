# Proposal: thread Cyrius Allocator-as-first-arg through sandhi

**Filed:** 2026-05-03 (the day cyrius v5.8.36 deferred sandhi from
its stdlib pass 2 because sandhi entered maintenance mode at v1.0.0)
**Status:** OPEN — handed off to a parallel agent
**Target version:** sandhi v1.0.1 (small) → v1.1.0 if scope grows
**Affects:** every alloc-touching source file in `src/`
(27 files, ~135 alloc sites)

## Why now

Cyrius v5.8.33–v5.8.36 shipped the Allocator-as-parameter convention
(Zig-style):

- v5.8.33: `Allocator` vtable + 3 default impls (`bump_allocator()`,
  `arena_allocator(cap)`, `test_allocator()`) + dispatch helpers
  (`alloc_via` / `realloc_via` / `free_via` / `reset_via`) in
  `lib/alloc.cyr`.
- v5.8.34: failing-allocator harness `fail_after_n_allocs(n)` in
  `lib/assert.cyr`.
- v5.8.35: stdlib pass 1 — `_a` variants for vec/str/hashmap;
  `default_alloc()` lazy-init singleton.
- v5.8.36: stdlib pass 2 — json/toml/cyml/http migrated; sandhi
  intentionally deferred (this proposal closes that deferral).

The headline benefit for sandhi specifically is the
**per-request-arena pattern** for HTTP servers: an HTTP handler can
build response headers, body, parsed URL, and the response struct
itself all into a per-request arena that gets reset when the request
completes. Zero leakage between requests; deterministic memory
ceiling; failing-allocator coverage drives OOM tests of every
handler path.

## Migration shape (the cyrius v5.8.35 / v5.8.36 pattern)

For every alloc-touching public fn:

```cyrius
# Before:
fn sandhi_X_new(args) {
    var x = alloc(SIZE);
    ...
    return x;
}

# After (back-compat preserved):
fn sandhi_X_new_a(a, args) {
    var x = alloc_via(a, SIZE);
    if (x == 0) { return 0; }   # OOM check
    ...
    return x;
}

fn sandhi_X_new(args) {
    return sandhi_X_new_a(default_alloc(), args);
}
```

The `_a` variant takes the Allocator as the **first** argument
(consistent with Zig and with cyrius v5.8.35 stdlib). Internal
helpers also gain `_a` variants and thread the allocator through.
Every wrapper that exists for back-compat passes `default_alloc()`.

## Scope (hard data)

Per-file alloc count (from `grep -rc "alloc(" src/`):

| count | file |
|------:|------|
| 15 | `src/net/resolve.cyr` |
| 15 | `src/http/conn.cyr` |
| 13 | `src/http/h2/hpack.cyr` |
|  9 | `src/server/mod.cyr` |
|  8 | `src/http/stream.cyr` |
|  8 | `src/http/sse.cyr` |
|  8 | `src/http/response.cyr` |
|  7 | `src/http/h2/conn.cyr` |
|  7 | `src/http/client.cyr` |
|  6 | `src/rpc/json.cyr` |
|  5 | `src/http/url.cyr` |
|  5 | `src/http/h2/response.cyr` |
|  4 | `src/tls_policy/apply.cyr` |
|  4 | `src/http/headers.cyr` |
|  4 | `src/discovery/local.cyr` |
|  3 | `src/http/h2/huffman.cyr` |
|  3 | `src/discovery/daimon.cyr` |
|  2 | `src/tls_policy/policy.cyr` |
|  2 | `src/tls_policy/fingerprint.cyr` |
|  2 | `src/rpc/webdriver.cyr` |
|  2 | `src/rpc/dispatch.cyr` |
|  2 | `src/http/pool.cyr` |
|  2 | `src/http/h2/request.cyr` |
|  2 | `src/discovery/service.cyr` |
|  1 | `src/http/retry.cyr` |
|  1 | `src/http/h2/frame.cyr` |
|  1 | `src/http/h2/dispatch.cyr` |

Total: **27 files, ~135 alloc sites**.

## Recommended migration order

Bottom-up — leaves first, then aggregators. Each batch is a self-
contained commit/patch.

### Batch 1 — leaves (low coupling)

| file | rationale |
|------|-----------|
| `src/http/url.cyr` | URL struct is the entry point for every HTTP request; small + isolated. Start here. |
| `src/http/headers.cyr` | Used by every response/request; no internal callers in this file. |
| `src/discovery/service.cyr` | Tiny (2 allocs); standalone struct. |
| `src/discovery/daimon.cyr` | 3 allocs; isolated. |
| `src/http/pool.cyr` | 2 allocs; isolated pool struct. |
| `src/http/h2/frame.cyr` | 1 alloc; standalone. |

### Batch 2 — TLS + h2 leaves

| file | rationale |
|------|-----------|
| `src/tls_policy/fingerprint.cyr` | 2 allocs. |
| `src/tls_policy/policy.cyr` | 2 allocs. |
| `src/tls_policy/apply.cyr` | 4 allocs; depends on policy. |
| `src/http/h2/huffman.cyr` | 3 allocs; codec leaf. |
| `src/http/h2/hpack.cyr` | 13 allocs; headers compression — depends on huffman. |

### Batch 3 — discovery + rpc

| file | rationale |
|------|-----------|
| `src/discovery/local.cyr` | 4 allocs; depends on service. |
| `src/rpc/dispatch.cyr` | 2 allocs. |
| `src/rpc/webdriver.cyr` | 2 allocs. |
| `src/rpc/json.cyr` | 6 allocs; RPC json structures. |

### Batch 4 — HTTP response/request foundation (highest-value)

| file | rationale |
|------|-----------|
| `src/http/response.cyr` | 8 allocs; `_sandhi_resp_new` is THE central response constructor — every error path goes through here. Start of the per-request-arena win. |
| `src/http/h2/response.cyr` | 5 allocs; h2 response variant. |
| `src/http/h2/request.cyr` | 2 allocs. |

### Batch 5 — connection layer

| file | rationale |
|------|-----------|
| `src/http/conn.cyr` | 15 allocs; biggest internal API. Threads through every public sandhi_conn_* fn. |
| `src/http/h2/conn.cyr` | 7 allocs; h2 connection. |
| `src/net/resolve.cyr` | 15 allocs; DNS resolver. |

### Batch 6 — client + streaming + server

| file | rationale |
|------|-----------|
| `src/http/client.cyr` | 7 allocs; consumer-facing client API + options. |
| `src/http/stream.cyr` | 8 allocs; streaming response path. |
| `src/http/sse.cyr` | 8 allocs; Server-Sent Events. |
| `src/http/retry.cyr` | 1 alloc; retry logic. |
| `src/http/h2/dispatch.cyr` | 1 alloc; h2 dispatch. |
| `src/server/mod.cyr` | 9 allocs; server-side response builder. |

## Acceptance gates

For each batch:

1. **Existing 649-assertion suite stays green** (482 sandhi + 167 h2).
   `cyrius test` from sandhi root.
2. **`_a` variants exist for every public alloc-touching fn** in the
   batch's files. Internal helpers also threaded.
3. **Back-compat wrappers preserve byte-identical behavior** —
   `sandhi_X_new(args)` should compile + run identically to its
   pre-migration form.
4. **One new tcyr per batch** demonstrating the per-request-arena
   pattern: build a sandhi struct inside an `arena_allocator(cap)`,
   verify reset clears all allocations.
5. **OOM handling via `fail_after_n_allocs(n)`** for at least one
   `_a` variant per batch; OOM should propagate as 0 (not abort).
6. **`build/cyrlint <file>`** clean (no new warnings introduced).
7. **`build/cyrdoc --check <file>`** clean (every new public fn
   has a leading doc comment).

## At-end-of-migration

1. Bump VERSION to 1.0.1 (single-batch ship) or 1.1.0 (full
   migration). User's call.
2. CHANGELOG retrospective covering all batches.
3. `cyrius distlib` to regenerate `dist/sandhi.cyr` from the
   migrated `src/`.
4. Cyrius-side update: refresh `cyrius/lib/sandhi.cyr` snapshot
   from `sandhi/dist/sandhi.cyr`. This is its own small cyrius
   slot (probably v5.8.37 patch or whichever cyrius version is
   current at sandhi 1.0.x ship).
5. Downstream consumers that pin sandhi (cyrius itself via
   `lib/sandhi.cyr`; vidya/samvada via `lib/sandhi.cyr`) get
   refreshed snapshots automatically through the next pass of
   `cyrius deps` resolution.

## Process notes (lessons from cyrius v5.8.33–v5.8.36)

- **Snapshot-ping-pong protection.** sandhi's `lib/*.cyr` are
  consumer-managed (vendored from cyrius via `cyrius deps`). Edits
  to `src/sandhi/...` don't trigger the ping-pong, but if the
  Allocator-side helpers in `lib/alloc.cyr` need extension during
  this work, follow the v5.8.23 mitigation recipe.
- **Doc-coverage gate.** Every new `_a` variant needs a leading
  comment. The cyrius gate caught 8 undocumented fns at v5.8.33
  ship; lesson stuck — write the comment as part of the fn
  definition, not as a follow-up.
- **OOM-threshold tuning in tcyr.** When testing grow-path OOM,
  count the EXACT alloc sequence and pick `fail_after` to fall
  right at the trigger point. v5.8.35's first-draft map_set_a
  test used `fail_after=4` but the test loop exhausted before
  grow #2 fired; re-tuned to `fail_after=2`.
- **Tcyr cstr-vs-byte type confusion.** Cyrius's i64-everything
  model lets `load64(struct + offset)` return a pointer when you
  expected a byte. Use `load8(load64(struct + offset))` when
  asserting on string content.
- **Lint long-line gate.** 120-char max. New `if (alloc_via(a,
  N) == 0) { return ... }` one-liners often exceed; reformat to
  multi-line block style preemptively.

## References

- Cyrius v5.8.33 CHANGELOG: Allocator vtable + 3 impls
- Cyrius v5.8.34 CHANGELOG: failing-allocator harness
- Cyrius v5.8.35 CHANGELOG: vec/str/hashmap migration
- Cyrius v5.8.36 CHANGELOG: json/toml/cyml/http migration + sandhi
  deferral note
- Cyrius `lib/alloc.cyr`: Allocator interface source of truth
- Cyrius `tests/tcyr/alloc_iface.tcyr`: vtable test patterns
- Cyrius `tests/tcyr/alloc_stdlib.tcyr` /
  `alloc_stdlib_pass2.tcyr`: per-module migration test patterns
- Cyrius roadmap §v5.8.33-38 (allocators-as-parameter convention)
