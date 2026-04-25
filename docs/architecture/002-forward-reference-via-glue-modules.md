# 002 — Glue modules work around Cyrius forward-reference constraint

Cyrius's compilation honors the `cyrius.cyml [lib].modules` order
strictly: a module registered earlier in the list cannot reference
symbols defined in a module registered later. This is a real
constraint that shapes how sandhi's submodules fit together. When
an early module needs a symbol from a later module, the pattern is
to split the early module's work in two — keep the data in the
early module, put the operations in a glue module registered after
both.

## Canonical case: pool + h2/conn

`src/http/pool.cyr` (early) owns the connection pool struct,
including the `h2_map` field at `SANDHI_POOL_OFF_H2_MAP = 32` that
holds `host:port:tls → sandhi_h2_conn` entries.

`src/http/h2/conn.cyr` (later) owns the h2 conn struct and its
accessors — `sandhi_h2_conn_underlying`,
`sandhi_h2_conn_goaway_received`, etc. (see
`src/http/h2/conn.cyr:72`).

Closing the pool wants to walk `h2_map` and close each stored
conn's underlying socket via `sandhi_h2_conn_underlying`. But
`pool.cyr` can't call `sandhi_h2_conn_underlying` — that symbol is
defined later in the build order. If you try, compilation fails at
link time.

`src/http/pool.cyr` handles this by doing the minimum it can —
allocating the `h2_map` with `map_new()` on pool construction and
clearing it with `map_clear(h2m)` on pool close — and documenting
the gap inline (pool.cyr:116):

    # The h2_map is cleared but its h2-conn values are NOT walked
    # here — pool.cyr can't reference sandhi_h2_conn_underlying
    # without violating the build order (Bite 6 added the h2_map
    # slot but the h2 conn lives in a later module).

`src/http/h2/pool_glue.cyr` (registered **after** both `pool.cyr`
and `h2/conn.cyr`) provides the actual h2-aware helpers:

- `sandhi_http_pool_take_h2(pool, host, port, tls)` — reads
  `SANDHI_POOL_OFF_H2_MAP`, does the GOAWAY-check via
  `sandhi_h2_conn_goaway_received`.
- `sandhi_http_pool_put_h2(pool, host, port, tls, h2c)` — stores
  into the map.
- `sandhi_http_pool_close_h2_conns(pool)` — walks the map, calls
  `sandhi_h2_conn_underlying` on each, closes via
  `sandhi_conn_close`. Callers invoke this **before**
  `sandhi_http_pool_close` to avoid the fd leak that `pool.cyr`'s
  close-without-walking would otherwise produce.

## The general pattern

When module A (early) wants to interact with module B (later):

1. A owns the data — struct layout, slot offsets, basic
   construction / destruction.
2. A does the minimum it can without touching B's symbols (e.g.,
   allocates an empty map, clears a vec).
3. A documents the gap in a comment where the missing operation
   would have gone — "see `<glue>.cyr` for the walk".
4. A glue module C registered after both A and B carries the
   operations that need both sides. C is typically small
   (< 100 lines) and focused on one interaction surface.
5. Public verbs that consumers call live in C, not A. `pool.cyr`
   exposes `sandhi_http_pool_new` / `_close` / `_take` / `_put`
   (all 1.1-safe); `pool_glue.cyr` exposes the `_h2` variants.

The `cyrius.cyml [lib].modules` order encodes the dependency
explicitly — this is deliberate, since it makes the wiring legible
in one place rather than scattered across imports.

## Where this appears in sandhi

- **`src/http/h2/pool_glue.cyr`** (75 lines) — the canonical case
  described above. 0.8.0 Bite 6.
- **`src/http/h2/dispatch.cyr`** — less stark, but the same shape:
  public `sandhi_h2_request` orchestrates primitives from
  `h2/request.cyr` + `h2/response.cyr` + `h2/conn.cyr`, registered
  after all three.
- **`src/tls_policy/apply.cyr`** — registered after
  `src/http/conn.cyr` so `sandhi_conn_open_with_policy` can call
  `sandhi_conn_open` + touch `_sandhi_conn_last_err`. See
  `cyrius.cyml [lib].modules` — `tls_policy/*` lives after `http/*`
  in the build order for exactly this reason (documented in the
  0.6.0 CHANGELOG entry).

## Tradeoffs

- **Accepts**: a second module for what would otherwise be
  inline code. `pool_glue.cyr` is three functions that "belong" in
  `pool.cyr` but can't be. The split reads clearly when the
  comment in `pool.cyr` explains the gap.
- **Accepts**: the caller-ordering constraint
  (`_close_h2_conns` before `_close`). Glue-module split means
  the cleanup is not unified under a single "close the pool"
  call. `docs/guides/` is where the correct teardown order for
  consumers gets written down.
- **Gains**: build-order stays linear and auditable. No forward
  declarations, no header-file-style split, no build system
  trickery. The `cyrius.cyml` module list is the authoritative
  dependency graph.
- **Gains**: the split forces clean seams. Glue modules tend to
  be small and focused (75 lines for `pool_glue.cyr`, well
  under the per-function / per-program fixup considerations from
  [architecture/001](001-hpack-huffman-blob.md)).

## When *not* to reach for this pattern

- When the forward reference is one-off and reordering the
  offending modules works. Do the reorder first — it's cheaper.
- When the "glue" would be more than ~200 lines. At that scale,
  what you actually have is a new submodule, not glue; name it
  accordingly.

## References

- `src/http/pool.cyr` — early module, reserves `h2_map` slot.
- `src/http/h2/pool_glue.cyr` — glue module.
- `src/http/h2/conn.cyr:72` — the `sandhi_h2_conn_underlying`
  accessor the glue reaches for.
- `cyrius.cyml [lib].modules` — the authoritative build order.
- 0.8.0 Bite 6 (CHANGELOG entry) — when `pool_glue.cyr` landed.
