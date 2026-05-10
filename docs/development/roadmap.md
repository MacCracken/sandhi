# sandhi — Roadmap

> Forward-looking sequencing post-fold. State lives in
> [`state.md`](state.md); shipped releases live in
> [`../../CHANGELOG.md`](../../CHANGELOG.md). This file is the
> remaining work.

## Guiding objective (post-fold)

**Fold landed at Cyrius v5.7.0 (sandhi 1.0.0)** per [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md).
Cyrius stdlib vendors `dist/sandhi.cyr` as `lib/sandhi.cyr`;
consumers `include "lib/sandhi.cyr"` and drop their
`[deps.sandhi]` pins.

This repo is now in **post-fold maintenance**. Patches still
land here first — `dist/sandhi.cyr` is regenerated and the
cyrius-side `lib/sandhi.cyr` refresh is a small cyrius slot
that picks up the change. The public surface is no longer
frozen (ADR 0005's freeze applied "between 0.9.2 and 1.0.0";
post-fold patches are explicitly allowed per the 1.1.0 ship).

## Shipped (M0 through 1.1.0)

Compressed log — one line per release. CHANGELOG carries the
details, state.md the current snapshot.

- **M0 — 0.1.0** — scaffold + library-shape manifest + ADR 0001
- **M1 — 0.2.0** — `lib/http_server.cyr` lift-and-shift to `src/server/mod.cyr`
- **M2 — 0.3.0** — full HTTP client (POST/PUT/DELETE/PATCH/HEAD/GET, redirects, native UDP DNS)
- **M3 — 0.4.0** — JSON-RPC dialects (WebDriver, Appium, MCP) + dialect-aware error envelopes
- **M4 — 0.5.0** — service discovery (chain resolver, daimon HTTP backend, mDNS interface)
- **M5 — 0.6.0** — TLS-policy surface (default / pinned / mTLS / trust-store + combine)
- **M3.5 — 0.7.0** — SSE streaming + incremental chunked decode + MCP-over-SSE
- **0.7.1** — quick-wins from external review (default UA / AE, max-response-bytes, err_message slot)
- **0.7.2** — read/write timeouts, retry wrappers, DNS hardening, AAAA resolver, sakshi tracing, server idle-timeout
- **0.7.3** — connect_ms + total_ms (non-blocking connect + monotonic deadline threading)
- **0.8.0** — HTTP/2 + connection pool (pool, HPACK, frames, ALPN surface, h2 lifecycle, public `sandhi_h2_request`)
- **0.8.1** — `sandhi_http_request_auto` + per-method auto verbs (pool h2-take → 1.1 fallback)
- **0.9.0** — Phase 1 security: 5 P0s from the 0.7.0 audit
- **0.9.1** — Phase 2 P1 sweep: 7 hardening fixes
- **0.9.2** — pre-fold closeout: server symbol rename + `dist/sandhi.cyr` + ADR 0005 surface freeze
- **0.9.3** — stub-elimination + CI hardening (TLS enforcement / ALPN / mDNS / IPv6 client / retry jitter)
- **0.9.4** — versioning refactor (auto-generated `src/version_str.cyr`) + chunked response trailers
- **0.9.5** — h2 redirect-following hoisted to auto layer + retry-through-auto routing
- **0.9.6** — ALPN-driven h2 auto-promotion (first release where live h2 fires end-to-end via the auto path)
- **0.9.7** — `TE: trailers` request signaling on both 1.1 and h2; te-conditional h2 forbidden filter
- **0.9.8** — HPACK Huffman encode wired into `_hpack_string_encode`; byte-exact RFC 7541 C.4.1 reference
- **0.9.9** — internal P1 self-audit: trailer forbidden list expanded; ALPN/Huffman/redirect/h2 filter audited sound
- **0.9.10** — pool stale-skip hardening: `_sandhi_pool_has_idle` peek now ignores conns past `idle_timeout_ms` so ALPN promotion fires deterministically
- **1.0.0** — fold-ready release. Transitional `http_*` aliases dropped; final `dist/sandhi.cyr` regenerated; vendored into Cyrius stdlib at v5.7.0
- **1.1.0** — allocator-as-first-arg migration. 6 commit-sized bites; ~150 new `_a` public verbs alongside back-compat wrappers. Toolchain pin 5.6.41 → 5.8.36. 792 assertions green (482 sandhi + 167 h2 + 143 alloc)
- **1.1.1** — `Proxy-Authenticate` trailer-forbidden (rounds out 0.9.9 proxy-auth pair); toolchain pin 5.8.36 → 5.10.0 (mechanical, profile-instrumentation only); CI fmt-check fix (broken `diff <(... --check) FILE` always reported drift — read exit code instead)
- **1.1.2** — request-builder dup-prevention. `_sandhi_client_build_request_v` filters caller-supplied `Host` / `Content-Length` / `Transfer-Encoding` / `Connection` out of `user_headers` (symmetric to `sandhi_headers_smuggle_dup` server-side at 0.9.1). 21-assert probe at `programs/_dup_prevention_probe.cyr`. 1.1.x small-fixes lane closed.
- **1.2.0** — hot-path allocator review Batch A: audit findings + request-orchestrator foundation. Audit found the 1.1.0 leaf-level migration was clean (zero `_a` fns calling bare paired helpers); the real leak was the *orchestration layer* above the leaves having no `_a` counterparts. Fixed buggy `_sandhi_client_build_request_a` (was dropping `a` on the floor); added `_a` variants for `_sandhi_http_do` / `_do_impl` / `_dispatch` / `_exchange` / `_exchange_keepalive` + `_sandhi_client_build_request_va`. Cyrius/lib.tls.cyr native-transport prep dropped from sandhi (filed cyrius-side instead). 804 assertions green (482 + 167 + 155).
- **1.2.1** — Batches B + C bundled: redirect-following + auto-dispatch + retry threading. Closes 1.2.0's partial-arena leaks. New `_a` variants: `_sandhi_http_follow_a`, `_sandhi_strip_sensitive_headers_a`, `_sandhi_http_try_h2_promote_a`, `_sandhi_http_auto_once_a`, `_sandhi_http_auto_follow_a`, `sandhi_http_request_auto_a`, `_sandhi_http_retry_a`. Bundled per cyrius v5.10.0 "items sharing the same cascade" rule (retry calls auto). 824 assertions green (482 + 167 + 175).
- **1.2.2** — Batch D: top-level public verbs `_a`. First release with consumer-visible end-to-end arena adoption. +6 `_a` verbs (`sandhi_http_get_a` / `_post_a` / `_put_a` / `_patch_a` / `_delete_a` / `_head_a`) — thin wrappers calling `_sandhi_http_dispatch_a`. Public-surface change documented (mirrors `sandhi_http_stream_a` shape). 837 assertions green (482 + 167 + 188).
- **1.2.3** — Batch E: opts / retry / auto user-facing `_a`. +12 verbs (2 `_opts` + 4 `_retry` + 6 `_auto`). Paint-on-top wrappers since dispatch / retry / auto paths are already `_a`-threaded. Total post-1.1.0 public `_a` surface for HTTP request path: 18 verbs. 851 assertions green (482 + 167 + 202).
- **1.2.4** — Batch F: RPC dialect `_a` (closes the optimization arc). +30 verbs across mcp (5) / webdriver (14) / appium (11) + 3 internal helpers. Plus internal `_sandhi_mcp_build_request_a`, `_sandhi_wd_build_path_a`, `_sandhi_wd_build_element_suffix_a`. Cumulative arc total: +49 public `_a` verbs (1.2.0–1.2.4); every alloc-touching public path has an `_a` counterpart. 861 assertions green (482 + 167 + 212). **Hot-path allocator review arc CLOSED.**
- **1.2.5** — profile instrumentation. New `src/obs/prof.cyr` (~140 lines) with per-request per-phase timing captures + recv-buffer cap/used tracking. Default-off; runtime toggle via `sandhi_prof_enable(1)`. 5 phase boundaries captured inside `_sandhi_http_do_impl_a`. +8 public verbs + `SANDHI_PROF_PHASE_*` enum. Mirrors cyrius v5.10.0's `_prof_*_end` capture pattern, adapted for runtime. Opens the next optimization arc with measurement instead of speculation. 875 assertions green (482 + 167 + 226).
- **1.2.6** — OOM-guard audit on 1.2.0–1.2.4 `_a` additions. Found two systemic SIGSEGV-on-OOM patterns: rbuf alloc in `_sandhi_http_exchange_a`/`_keepalive_a` (2 sites), and `sandhi_json_obj_new_a` chains in RPC dialect verbs (~12 sites across webdriver/appium/mcp). Fixed every site with null-check + graceful err-resp return. 885 assertions green (482 + 167 + 236; without the guards 7+ of these new tests would have SIGSEGV'd).
- **1.2.7** — Batch G server `_a` paint + OOM guards. 4 new `_a` verbs (`sandhi_server_send_status_a` / `_send_response_a` / `_send_204_a` / `_send_chunked_start_a`) closing the same SIGSEGV-on-OOM pattern 1.2.6 found in RPC dialects, this time on the server send-path. `_a` returns 0/-1 (OOM signal); bare versions back-compat wrap. 892 assertions green (482 + 167 + 243). The OOM-guard audit story is now complete for every `_a` verb shipped post-1.1.0.
- **1.2.8** — 1.1.0-era OOM-guard audit + tests/sandhi.tcyr cap relief. Bundled. Three real findings closed (h2/response.cyr SIGSEGV; sse.cyr SIGSEGV; client.cyr partial-arena leak). Carved 17 RPC test fns from sandhi.tcyr → new tests/rpc.tcyr (cap pressure relieved). Wired tests/alloc.tcyr + tests/rpc.tcyr into CI (closed pre-1.1.0 gap). 899 assertions green (440 + 167 + 250 + 42). **1.2.x optimization arc CLOSED.**
- **1.3.0** — opens 1.3.x TLS arc. Live-network TLS-policy gate (3 gates against 1.1.1.1:443 / one.one.one.one) with skip-cleanly cascade mirroring cyrius `_tls_live_gate`. Typed-wrapper migration: `_sandhi_alpn_hook` + `_sandhi_apply_hook` switched from `tls_dlsym + fncall3` to v5.10.13's `tls_set_alpn`. Toolchain pin 5.10.0 → 5.10.21; `regression` added to deps. CI gains "Live-network TLS-policy gate" step. 899 assertions green + 1 live gate (4 sub-cases).
- **1.3.1** — TLS 1.3 / 1.2 client-side session-resumption cache. New `src/tls_policy/session_cache.cyr` (process-wide singleton, keyed by `(sni_host, hook_fp_hex)`). `_sandhi_conn_finalize_a` switched to staged-connect (`tls_connect_alloc` → `tls_set_session` if hit → `tls_connect_complete` → `tls_get_session` capture). Default-OFF; opt-in via `sandhi_session_cache_enable(1)` (capability-gated). Toolchain pin 5.10.21 → 5.10.31 (5.10.27 was the staged-connect API the issue doc filed). 906 assertions green (440 + 167 + 257 + 42).
- **1.3.3** — Cred-strip-aware session-cache keying. Cache key extended from `(sni_host, hook_fp_hex)` to `(sni_host, hook_fp_hex, cred_digest)`. New `_sandhi_compute_cred_digest(headers)` (FNV-1a 64-bit over Authorization / Cookie / Proxy-Authorization values; per-header marker prefix; returns 0 when no cred-bearing headers — preserves common-path key shape). Module-level `_sandhi_cred_digest` flag mirrors the `_sandhi_allow_0rtt` precedent, set+restored by dispatch entry-points. Internal signature evolution on `_lookup` / `_store` / `_key_a` (sandhi is its own only consumer of these verbs). 938 assertions green (440 + 167 + 289 + 42).
- **1.3.2** — TLS 1.3 0-RTT (early data), opt-in. New per-request verb `sandhi_http_options_allow_0rtt(opts, on)` + getter; default 0 (off). Replay-safe methods only (GET/HEAD/OPTIONS via new `_sandhi_method_is_replay_safe`); 3-layer eligibility gate (opt-in + method-safe + cap + session-cache hit + cached session's `max_early_data >= req_len`). `_sandhi_conn_finalize_with_early_data_a` composes `tls_write_early_data` / `tls_get_early_data_status` / `tls_session_get_max_early_data`; new conn-struct slot `SANDHI_CONN_OFF_0RTT_STATUS` (32 → 40 bytes) latches the status. Both `_sandhi_http_exchange_a` and `_keepalive_a` gained ACCEPTED-skip / REJECTED-retry / NOT_SENT-passthrough handling at entry. Toolchain pin 5.10.31 → 5.10.34 (v5.10.34 closed the 0-RTT-status accessors gap filed at `docs/issues/archive/2026-05-10-stdlib-tls-early-data-status.md`). 924 assertions green (440 + 167 + 275 + 42).

## What's next

### 1.1.x — post-fold patch window (deferred-from-audit + small fixups)

*Small, well-scoped patches that don't fit the optimization-
pass shape of 1.2.0. Each ships independently when ready.
The 1.0.x window's per-program-fixup-cap deferrals re-baseline
post-fold (consumers' tests no longer re-concatenate sandhi's
`src/`), so both items below land cleanly here.*

- ~~**1.1.1 — `Proxy-Authenticate` trailer-forbidden**~~
  ✅ landed 2026-05-08 (also bumped toolchain pin 5.8.36
  → 5.10.0; CI fmt-check fix rode along).
- ~~**1.1.2 — Request-builder dup-prevention**~~
  ✅ landed 2026-05-08. Caller-supplied `Host` /
  `Content-Length` / `Transfer-Encoding` / `Connection`
  filtered from `user_headers` in
  `_sandhi_client_build_request_v`. 21-assert probe at
  `programs/_dup_prevention_probe.cyr`.

The 1.1.x small-fixes lane is now empty. Future small
patches that don't fit 1.2.0's optimization-pass shape
land as 1.1.3+ when they show up — the lane stays open as
a "small fixes" track separate from 1.2.0.

### 1.2.x — optimization arc

**Theme**: profile-driven hot-path optimization — the natural
follow-up to the 1.1.0 allocator migration and the cohort
sibling to cyrius v5.10.x's optimization arc. Each item gets
its own slot; profile evidence drives ordering past 1.2.0.
The cyrius v5.10.0 ONE-thing-per-slot principle applies:
bundling is justified only when items share a cascade.

#### ~~1.2.0 — Hot-path allocator review (lead)~~ ✅ shipped 2026-05-08

**Findings + Batch A landed**. Audit findings (the leaf-level
1.1.0 migration was clean — zero `_a` fn called a bare paired
helper; the real leak was the orchestration layer above the
leaves) are recorded in 1.2.0's CHANGELOG entry as the
permanent audit log. Batch A added `_a` variants for the
internal request-orchestrator foundation (`_sandhi_http_do` /
`_do_impl` / `_dispatch` / `_exchange` / `_exchange_keepalive`
+ `_sandhi_client_build_request_va`) and fixed the buggy
`_sandhi_client_build_request_a` that was dropping `a` on the
floor. 804 assertions green.

Singletons that MUST stay on `default_alloc()` (ALPN wire
literals, HPACK static, Huffman tree, server `_hsv_req_buf`
— process-wide, outlive any per-request arena) stay
documented at their callsites as intentional, not leaks.

**Batches still to land** (each its own slot per the
ONE-thing principle, modulo cascade-bundling like 1.2.1
demonstrated):

- ~~**1.2.1 — Batches B + C bundled**~~ ✅ shipped
  2026-05-08. Discovered at slot entry that retry's
  cascade depends on the auto path (it's been calling
  `sandhi_http_request_auto` since 0.9.5 for h2 pool
  selection); user-direction bundled the two cascades
  rather than route retry through the older
  `_sandhi_http_dispatch` and regress h2 selection
  temporarily.
- ~~**1.2.2 — Batch D**~~ ✅ shipped 2026-05-08. Six
  public-verb `_a` wrappers; +6 to public surface; first
  consumer-visible end-to-end arena adoption shipped.
- ~~**1.2.3 — Batch E**~~ ✅ shipped 2026-05-08. +12
  `_a` verbs (2 `_opts` + 4 `_retry` + 6 `_auto`).
  Confirmed at slot entry: only `get_opts` and
  `post_opts` exist as `_opts` verbs (not all six
  methods). `request_auto_a` already shipped at 1.2.1.
- ~~**1.2.4 — Batch F**~~ ✅ shipped 2026-05-08. +30
  public `_a` verbs across MCP (5) / WebDriver (14) /
  Appium (11). `sandhi_rpc_call_a` / `_with_headers_a`
  were already paired (1.1.0). `sandhi_rpc_mcp_error_code`
  intentionally not paired — no allocation. **Hot-path
  allocator review arc CLOSED**; cumulative +49 public
  `_a` verbs landed across 1.2.0–1.2.4.

#### 1.2.x — optimization candidates (profile-justified)

*No pre-committed ordering — profile data drives. Each lands
in its own slot when the profile evidence shows benefit.
"Optimization-grade" items that don't measure stay parked.*

- **HPACK Huffman tie-break for short tokens** — current
  encoder picks Huffman over raw when *strictly* shorter;
  ties go to raw. Some short cookies / opaque tokens
  benefit from a tie-breaker that favors Huffman to keep
  dynamic-table state more compact. Profile-gated.
- **`_sandhi_resp_new` allocation collapse** — the central
  response-builder allocates header storage, body buffer,
  and Str header separately. If the call shape is hot
  enough, fuse into a single allocation with internal
  offset slicing.
- **Connection-pool LRU eviction** — current pool evicts
  on idle-timeout only; under sustained pressure the
  oldest-but-recently-touched entries can hold slots
  newer routes would benefit from. LRU policy behind an
  option flag; default keeps current semantics until
  profiling shows benefit.
- **`_sandhi_conn_connect_nb` factoring decision (cyrius
  v5.9.42)** — cyrius v5.9.42 carved out
  `lib/regression.cyr` with `regression_network_probe`,
  using the same non-blocking-connect + poll +
  SO_ERROR-readback mechanics as sandhi's
  `_sandhi_conn_connect_nb` in
  [`src/http/conn.cyr`](https://github.com/MacCracken/sandhi/blob/main/src/http/conn.cyr).
  Decision at slot entry:
  (a) **stdlib factoring** — file a cyrius issue asking for
      a `net_connect_nb` primitive in `lib/net.cyr`; sandhi
      and `regression_network_probe` both compose-use.
      Cleaner; needs a cyrius slot. *This is a cyrius-side
      ask — sandhi files the coordination doc, not the
      patch.*
  (b) **document parallel evolution** — leave both helpers
      as-is; document at both callsites that the shape
      duplication is intentional. No code change.
  Default to (b) unless profiling surfaces a hot-path
  reason — connect-nb runs once per conn-open, not per
  request, so it almost certainly won't measure. Document
  the choice in the slot's CHANGELOG either way so the
  parallel evolution is intentional, not accidental.

### 1.3.x — TLS arc

**Theme**: take TLS policy from "wired up across the four
modes" to "production-grade with session-resumption +
0-RTT". Each item is a sandhi-owned composition over stdlib
`tls_connect` — the cache, the keying logic, the policy
gate, and the 0-RTT dispatch all live in sandhi.

**Scope boundary** (per ADR 0001 — sandhi composes, doesn't
reimplement): the `tls_connect` / hook-surface / ALPN / SNI
/ SPKI primitives are stdlib `lib/tls.cyr` work. If cyrius
swaps fdlopen-libssl for native TLS, that's a cyrius slot
against `lib/tls.cyr`; sandhi keeps calling the contract.
**Native-transport prep is therefore not a sandhi item**
— historical mentions in earlier roadmap revisions framed
this as sandhi-side work, which was wrong. The audit (if it
proves needed) is a cyrius-side issue against `lib/tls.cyr`.

#### 1.3.0 — Live-network TLS policy gate

**Why this leads the TLS arc**: pure CI infra; independent
of any cyrius signal. Builds the test-arc machinery that
1.3.1 / 1.3.2 land into. Exercises the four policy modes
(`default` / `pinned` / `mtls` / `trust_store`) end-to-end
against real endpoints, mirroring the cyrius `_tls_live_gate`
skip-cleanly cascade (cc5 / dlopen-helper / network /
upstream cert reachable). The `pinned` and `trust_store`
modes shipped surface tests at 0.6.0; `mtls` has been
unverified end-to-end since the stub-fill at 0.9.3.

#### ~~1.3.1 — Session-resumption cache in `tls_policy`~~ ✅ shipped 2026-05-10

Sandhi-side cache holds session tickets (TLS 1.3) / session
IDs (TLS 1.2) keyed by `(host, port, alpn)`; hands them to
`tls_connect` on reuse. Closes a meaningful TTFB gap on
repeated requests to the same authority. Keying must respect
the 0.9.0 cred-strip rules — no resumption across different
authentication contexts. Cache hits documented via existing
`sakshi.tracing` boundaries; no new public span verbs.

**Status — primitives shipped, call-sequence blocker open**:
Cyrius v5.10.21 shipped 12 typed wrappers covering session
resumption + 0-RTT (`tls_get_session` / `tls_set_session` /
`tls_session_free`, the 4 session-cache callbacks, capability
probes). Sufficient for capture / cleanup / probe. **NOT
sufficient for resume**: `tls_set_session` requires a
pre-`SSL_connect` timing window, but
`tls_connect_with_ctx_hook` runs the full
`SSL_new → SSL_connect` flow in one shot. No slot for sandhi
to inject the cached session.

Filed [`docs/issues/2026-05-09-stdlib-tls-staged-connect.md`](../issues/2026-05-09-stdlib-tls-staged-connect.md) —
needs either Option A (staged-connect API:
`tls_connect_alloc` + `tls_connect_complete`) or Option B
(post-`SSL_new` hook variant). 1.3.1 lands when cyrius does.

#### ~~1.3.2 — TLS 1.3 0-RTT (early data) — opt-in~~ ✅ shipped 2026-05-10

Replay-safe methods only (GET / HEAD / OPTIONS) per RFC 8446 §8.
Behind an explicit options flag (`sandhi_http_options_allow_0rtt`)
— the replay-attack surface means default-off is the only safe
default. Pairs with session-resumption since 0-RTT requires a
cached session.

**Closed the blocker**: cyrius v5.10.34 shipped the two
status accessors filed at
[`docs/issues/archive/2026-05-10-stdlib-tls-early-data-status.md`](../issues/archive/2026-05-10-stdlib-tls-early-data-status.md) —
`tls_get_early_data_status(ctx)` (with `TLS_EARLY_DATA_*` enum)
and `tls_session_get_max_early_data(session)`. Both with safe
defaults when libssl lacks the underlying symbols.

**Composition**:
- v5.10.21: `tls_write_early_data` / `tls_read_early_data` /
  `tls_ctx_set_max_early_data` / `tls_supports_early_data` —
  the write/read primitives + capability probe.
- v5.10.27: staged-connect (`tls_connect_alloc` +
  `tls_connect_complete`) — gives sandhi the slot to install
  the session BEFORE handshake and write early data between
  alloc and complete.
- v5.10.34: status accessors — sandhi reads
  `tls_get_early_data_status` after handshake to decide
  ACCEPTED-skip vs. REJECTED-retry, and checks
  `tls_session_get_max_early_data` before attempting the
  early-data write.

**Sandhi-side changes**:
- New per-request opt-in verb `sandhi_http_options_allow_0rtt(opts, on)`
  + getter. Options struct grew 64 → 72 bytes.
- New internal classifier `_sandhi_method_is_replay_safe(method)` —
  GET / HEAD / OPTIONS only, case-sensitive per RFC 7230 §3.1.1.
- `_sandhi_http_do_impl_a` restructured to build request bytes
  BEFORE conn-open (pure refactor — bytes don't depend on conn
  properties), so the request can be passed in as early-data.
- `_sandhi_conn_finalize_a` becomes a back-compat wrapper
  forwarding `early_data=0, early_data_len=0` to the new
  `_sandhi_conn_finalize_with_early_data_a`.
- Conn struct grew 32 → 40 bytes — new
  `SANDHI_CONN_OFF_0RTT_STATUS` slot latches the TLS_EARLY_DATA_*
  value at handshake completion. Exposed via public verb
  `sandhi_conn_0rtt_status(conn)`.
- Both `_sandhi_http_exchange_a` and `_keepalive_a` gained a
  status check at entry: ACCEPTED skips the request send,
  REJECTED sends normally on the established stream,
  NOT_SENT is the existing path (covers all plaintext, all
  non-resumed TLS, and the disabled-0-RTT majority).
- Dispatch surfaces (`_sandhi_http_dispatch_a` +
  `sandhi_http_request_auto_a`) save+restore the module-level
  `_sandhi_allow_0rtt` flag from
  `sandhi_http_options_get_allow_0rtt(opts)` — mirrors the
  existing `_sandhi_alpn_advertise_h2` pattern. h2 path
  doesn't enable 0-RTT today (CONNECTION preface vs.
  early-data ordering pinned for a later milestone).

924 assertions green (440 + 167 + 275 + 42); 18 new alloc
groups under `alloc/132/`. Toolchain pin 5.10.31 → 5.10.34.

#### ~~1.3.3 — Cred-strip-aware session-cache keying~~ ✅ shipped 2026-05-10

Sandhi 1.3.1 shipped the session cache keyed on
`(sni_host, hook_fp_hex)` — sufficient for default-policy
and policy-bound paths, but did NOT distinguish auth contexts.
If a consumer rotated Authorization / Cookie /
Proxy-Authorization headers across requests to the same
authority + same hook, the cache reused the session across
both auth contexts.

That wasn't a security regression at the TLS layer (the server
still authenticates per-request using the new HTTP-envelope
headers), but it was a layering concern: the 0.9.0 cred-strip
rules deliberately invalidate cached state on auth-context
change at the redirect layer, and the session cache should
mirror that for symmetry. 1.3.3 closed the gap.

**What landed**:
- New internal helpers in `src/http/client.cyr`:
  - `_sandhi_fnv1a_mix(h, s)` — running FNV-1a 64-bit
    byte-mixer using stdlib's offset basis / prime
    (`hash_str` in `lib/hashmap.cyr`).
  - `_sandhi_compute_cred_digest(headers)` — folds the
    values of Authorization / Cookie / Proxy-Authorization
    (case-insensitive lookup via `sandhi_headers_get`) into
    a single 64-bit digest. Per-header marker prefix
    (`A:` / `C:` / `P:`) before each value prevents
    same-value collisions across different cred header
    names. Returns 0 when no cred-bearing headers are
    present.
- Module-level `_sandhi_cred_digest` flag in `src/http/conn.cyr`
  — set+restored by `_sandhi_http_dispatch_a` and
  `sandhi_http_request_auto_a` for the duration of each
  dispatch. Mirrors the `_sandhi_allow_0rtt` and
  `_sandhi_alpn_advertise_h2` precedents (single-threaded
  client model, transient per-request state, avoids
  threading the digest through 8+ fn signatures).
- `_sandhi_session_cache_key_a` / `_lookup` / `_store`
  signatures gained `cred_digest` slot. Internal evolution
  inside sandhi (1.3.1 added these verbs; sandhi is the only
  consumer). Cache key now renders as
  `<sni>|<hook_fp_hex>|<cred_digest_hex>` — 16 hex digits
  per suffix.
- `_sandhi_conn_finalize_with_early_data_a` reads
  `_sandhi_cred_digest` when calling lookup / store, so the
  cache slot for a given `(host, hook)` splits across
  distinct auth contexts.

**Carry-over caveat**: redirect-follow's per-hop cred-strip
(`_sandhi_strip_sensitive_headers_a`) operates on the request
headers, but the dispatch-level digest is computed once at
top-level dispatch entry. A redirect from authority A to B
that crosses the cred-strip threshold would handshake against
B with the original digest. Today's AGNOS consumers don't
combine cred-bearing headers with cross-authority redirects;
the limitation is flagged in the dispatch comment for the
next consumer that needs it. Natural slot is to fold the
recompute into `_sandhi_http_follow_a`'s hop loop alongside
the existing cred-strip step.

938 assertions green (440 + 167 + 289 + 42); 14 new alloc
groups under `alloc/133/`. No toolchain bump (stays on
5.10.34). Default `cred_digest=0` preserves the 1.3.1 /
1.3.2 cache-key shape for service-to-service traffic, so
existing consumers see no behavior change unless they
explicitly carry cred-bearing headers.

#### 1.3.4 — Session-cache TTL + max-size eviction (provisional, may slip)

Sandhi 1.3.1's cache grows unbounded — every successful TLS
handshake captures a session and stores it forever. That's
fine for short-lived processes; long-running servers /
daemons would eventually accumulate stale sessions whose
servers have rotated session-ticket keys.

The cache entry already reserves a `last_used_ms` slot at
1.3.1 specifically for this — wiring it up is one slot of
work.

**Scope**:
- Per-cache config: `sandhi_session_cache_set_max_size(n)`
  (default ~256 entries) and
  `sandhi_session_cache_set_max_age_ms(ms)` (default
  24h — TLS session ticket lifetime is typically a few
  hours; 24h is the safe upper bound).
- Eviction policy: on insert, if cache is at max, evict
  the entry with the oldest `last_used_ms`. Periodic sweep
  is unnecessary — eviction-on-insert covers the bounded-
  size goal.
- Age check: on lookup, if `now - last_used_ms > max_age`,
  evict + return miss (so we don't serve a stale ticket
  that the server will reject).

**Provisional** — may slip if profile evidence shows the
cache stays small in practice, or if a consumer cares more
about another item.

### Post-arc — wait-for-trigger

*Same shape as before — items grouped by what unblocks
them, not by version pin.*

**Wait-for-second-consumer-ask**:

- **CONNECT / proxy tunneling** — no documented AGNOS egress-proxy need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing APIs. RFC 6265 is a regret-magnet; wait for a real ask.
- **JSON Merge Patch (RFC 7396)** / **JSON-RPC 2.0 batch** — batch is the likelier ask (MCP tool-discovery latency); wait for it.
- **TLS ALPN extensions beyond `http/1.1` and `h2`** — both ship today; anything beyond that waits for a consumer ask.

**Wait-for-stdlib-prerequisite**:

- **mDNS lookup + publishing** — blocked on stdlib `net.cyr` multicast primitives (`IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` / `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`). Request as a targeted stdlib patch when multicast becomes a priority for any consumer. The 0.9.3 unicast-response (QU bit) implementation works against most responders without multicast support.
- **Fuzzing harness** — Cyrius toolchain doesn't ship AFL/libFuzzer equivalent yet. Revisit when it does.

**Optimization-grade, profile first**:

- **Arena-per-request adoption (consumer side)** — the 1.1.0 `_a`-variant surface plus the 1.2.0 hot-path allocator review give consumers the foundation to pass per-request arenas end-to-end. Whether to evangelize the pattern across AGNOS consumers waits on profile evidence from a real workload.
- **SIMD / hot-path micro-optimization** — Cyrius has no SIMD intrinsics; byte-at-a-time is perfectly adequate at SSE / HTTP / HPACK parsing rates observed so far.

**Not sandhi's slot** (filed here so the framing doesn't drift back in):

- **`tls_connect` native-transport prep audit** — the hook surface (`tls_connect`, `tls_connect_with_ctx_hook`, ALPN / SNI / SPKI extraction) is owned by stdlib `lib/tls.cyr`. Auditing it for fdlopen-leaning assumptions ahead of a hypothetical native-TLS swap is a cyrius-side issue against `lib/tls.cyr`. Sandhi keeps calling the contract; cyrius is responsible for keeping it byte-identical across any transport swap. ADR 0001 codifies this — sandhi composes, doesn't reimplement.

**Won't ship without strong cause**:

- **OCSP stapling / CT log check / HSTS preload** — operational footguns (HPKP retirement lessons). Pin + custom trust store covers AGNOS's actual threat model.
- **gRPC-Web / GraphQL-over-HTTP** — explicit non-goals.

## What sandhi does NOT plan to do

Explicit non-goals (preserved from pre-fold; still hold):

- **Reimplement network primitives.** Those stay in stdlib.
- **Ship its own config parser.** Stdlib `cyml.cyr` / `toml.cyr` handle that.
- **Own MCP message semantics.** bote + t-ron own protocol; sandhi::rpc::mcp is transport only.
- **Be a generic "service framework."** Keep the surface small and specific to what AGNOS consumers actually need. If something more general is called for, it's a case for the caller to own, not sandhi.
- **Ship circuit breakers / bulkheads / rate-limiting middleware speculatively.** Add only when a second consumer needs the same pattern.

## Why this roadmap exists

Pre-fold, this file documented the path to v5.7.0. Post-fold,
its job is keeping the post-v1 patch window honest. The shape:

- **1.1.x** — small-fixes lane (closed for now; 1.1.1 / 1.1.2
  cleared the 0.9.9 audit deferrals). Stays open as a track
  for future small patches that don't fit the
  optimization-arc shape.
- **1.2.x** — optimization arc. ONE item per slot,
  profile-justified. 1.2.0 leads with the hot-path allocator
  review (the natural follow-up to 1.1.0).
- **1.3.x** — TLS arc. Sandhi-owned policy + state work over
  stdlib `tls_connect`. 1.3.0 = live-network gate;
  1.3.1 = session resumption; 1.3.2 = 0-RTT.

Beyond the arcs, items wait for their unblock signal —
consumer ask, profile evidence, or stdlib prerequisite.
Native-transport prep is explicitly *not* sandhi's slot
(see "Not sandhi's slot" above).

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md)
for the naming + thesis, [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
for the (now-shipped) clean-break fold decision, [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md)
for the surface freeze (now lifted post-1.0.0), and
[`state.md`](state.md) for live progress.
