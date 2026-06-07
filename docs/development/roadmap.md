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

## Shipped (M0 through 1.4.3)

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
- **1.3.1** — TLS 1.3 / 1.2 client-side session-resumption cache. New `src/tls_policy/session_cache.cyr` (process-wide singleton, keyed by `(sni_host, hook_fp_hex)`). `_sandhi_conn_finalize_a` switched to staged-connect (`tls_connect_alloc` → `tls_set_session` if hit → `tls_connect_complete` → `tls_get_session` capture). Default-OFF; opt-in via `sandhi_session_cache_enable(1)` (capability-gated). Toolchain pin 5.10.21 → 5.10.31. 906 assertions green (440 + 167 + 257 + 42).
- **1.3.2** — TLS 1.3 0-RTT (early data), opt-in. New per-request verb `sandhi_http_options_allow_0rtt(opts, on)` + getter; default 0 (off). Replay-safe methods only (GET/HEAD/OPTIONS via new `_sandhi_method_is_replay_safe`); 3-layer eligibility gate (opt-in + method-safe + cap + session-cache hit + cached session's `max_early_data >= req_len`). `_sandhi_conn_finalize_with_early_data_a` composes `tls_write_early_data` / `tls_get_early_data_status` / `tls_session_get_max_early_data`; new conn-struct slot `SANDHI_CONN_OFF_0RTT_STATUS` (32 → 40 bytes) latches the status. Both `_sandhi_http_exchange_a` and `_keepalive_a` gained ACCEPTED-skip / REJECTED-retry / NOT_SENT-passthrough handling at entry. Toolchain pin 5.10.31 → 5.10.34. 924 assertions green (440 + 167 + 275 + 42).
- **1.3.3** — Cred-strip-aware session-cache keying. Cache key extended from `(sni_host, hook_fp_hex)` to `(sni_host, hook_fp_hex, cred_digest)`. New `_sandhi_compute_cred_digest(headers)` (FNV-1a 64-bit over Authorization / Cookie / Proxy-Authorization values; per-header marker prefix; returns 0 when no cred-bearing headers — preserves common-path key shape). Module-level `_sandhi_cred_digest` flag mirrors the `_sandhi_allow_0rtt` precedent, set+restored by dispatch entry-points. Internal signature evolution on `_lookup` / `_store` / `_key_a` (sandhi is its own only consumer of these verbs). 938 assertions green (440 + 167 + 289 + 42).
- **1.3.4** — Stdlib annotation pass + cyrius pin 5.10.34 → 5.11.4. Every public fn across the 703-fn `src/` tree carries a `: i64` return-type annotation. Mechanical sed pass; 15 multi-line fn signatures hand-fixed. Parse-only, zero runtime / codegen change. The slot the 1.3.x roadmap originally pinned for TTL+eviction got diverted to ride along with the 5.11.4 pin; TTL+eviction moves to 1.4.0. 938 assertions green (no delta — annotation-only change).
- **1.3.5** — Cyrius pin 5.11.4 → 6.0.1 + binary-rename adaptation. Mechanical bump; zero source change. Cyrius v6.0.0 (2026-05-19) renamed compiler binaries: `cc5` → `cycc`, `cyrc` → `cybs`. Back-compat symlinks ship through v6.0.x; sandhi never reaches past the `cyrius` CLI wrapper, so the rename is transparent. v6.0.1 is a same-day hotfix for two stdlib-path resolution bugs. Workflows + CLAUDE.md updated for the new binary names. 938 assertions green. **1.3.x TLS arc CLOSED.**
- **1.4.0** — Session-cache TTL + max-size eviction (lead of 1.4.x closeout arc). +6 public verbs (`set_max_size` / `_max_size` / `set_max_age_ms` / `_max_age_ms` / `_evict_count` / `_age_evict_count`) plus `_clear()` and `_supported()`. Defaults 256 / 24h. Eviction-on-insert + age-check-on-lookup + touch-on-hit (LRU). Also closes two silent 1.3.1 bugs that prevented the cache from working in production: (a) `hashmap_*` → `map_*` naming (undef → NOP since 1.3.1); (b) `_key_a` strlen-past-stack on 1-byte buffer → non-deterministic keys. `enable()` contract relaxed (no longer gated on TLS capability; new `_supported()` getter separates the concern). 979 assertions green (+41 over 1.3.5's 938; 22 new in alloc/134, 19 from previously-skip-clean tests now running for real).
- **1.4.1** — HTTP/1.1 `Connection: close` read path frames by Content-Length / chunked instead of draining until EOF (fixes `SANDHI_ERR_TIMEOUT` hang vs chromedriver / Chromium DevTools; surfaced by yantra M2). `_sandhi_http_exchange_a` reuses the keep-alive `_sandhi_http_recv_framed` + `0 - 2` must-close sentinel; EOF-delimited HTTP/1.0 still works. cyrius pin 6.0.1 → 6.0.55. No public API change. 979 assertions green (unchanged). Verified live against chromedriver.
- **1.4.2** — Dropped the ALPN-read + SPKI-pin libssl bindings onto cyrius 6.0.82's typed backend-agnostic `tls_get_alpn_selected` / `tls_get_peer_spki_der`. sandhi now runs over the sovereign native TLS transport (`tls_set_backend`) with no ALPN/SPKI libssl coupling — closes the cyrius native-TLS Mini-arc E consumer rewire. Remaining `tls_dlsym` sites are pre-handshake `SSL_CTX_*` mTLS / trust-store config. cyrius pin 6.0.55 → 6.0.82. 167 h2 + 440 sandhi green.
- **1.4.3** — Buried-deferral gate sweep (drains the P2 closeout lead) + cyrius pin 6.0.82 → 6.0.87. All **12** untracked deferrals drained (the list of 8 undercounted — 4 more lived in `src/http/h2/`): real work → new Wait-for-second-consumer-ask roadmap bullets + comment crossref (per no-silent-scope-outs); incidental → reworded to drop the trigger; `HTTP_NOT_IMPLEMENTED` status constant → `#skip-lint`. CI lint gate flipped report-mode → fail-mode on untracked deferrals. Pin bump mechanical (full TLS ciphersuite enablement + macOS native-TLS fixes). Plus sigil transitive-deps fix (`ct` / `keccak` / `thread_local` added to `[deps]` + crypto-chain include in the live-gate probe so sigil's `sha256` links — native-clean, no FFI; sigil's packaging gap, surfaced consumer-side). 979 assertions green (unchanged); 0 untracked deferrals.
- **1.4.4** — Closeout housekeeping: roadmap slot-number realignment + `_sandhi_conn_connect_nb` factoring decision (option b — parallel evolution with `regression_network_probe`, no shared primitive; the only code change is a doc comment). Fixed roadmap drift: the `max_conns` / `connect_nb` slots were mislabeled "1.4.1" / "1.4.2" (those numbers shipped other work — 1.4.1 close-path, 1.4.2 ALPN/SPKI, 1.4.3 deferral sweep + pin + sigil); renumbered — `connect_nb` resolved here, `max_conns` → 1.4.5. 979 assertions green (unchanged); no public-API change.

## What's next

### Cleanup — buried-deferral gate sweep (P2) ✅ shipped 1.4.3

Drained all **12** untracked buried-deferrals the CI cyrlint gate
reports (the original work-list enumerated 8 — it missed 4 in
`src/http/h2/`) and flipped the gate from report-mode to **fail-mode**
in `ci.yml`. Real-work deferrals moved into the
**Wait-for-second-consumer-ask** bucket below (daimon resolver-ctx
auth/timeouts; client per-hop cred-digest on cross-authority redirect;
pool per-pool mutex; + h2 spec-completeness); incidental ones were
reworded to drop the trigger phrase; the `HTTP_NOT_IMPLEMENTED` status
constant got `#skip-lint`. See the 1.4.3 shipped-log line and
CHANGELOG [1.4.3].

### 1.1.x — post-fold patch window ✅ closed; track stays open

Small-fixes lane that cleared the 0.9.9 audit deferrals
(1.1.1 `Proxy-Authenticate` trailer-forbidden + cyrius pin
5.8.36→5.10.0; 1.1.2 request-builder dup-prevention).
**Lane stays open** for future small patches that don't fit
an arc shape; land as 1.1.3+ when they show up.

### 1.2.x — optimization arc ✅ closed at 1.2.8

Profile-driven hot-path optimization following the 1.1.0
allocator migration. Net: +49 public `_a` verbs across
1.2.0–1.2.4 (every alloc-touching public path has an `_a`
counterpart); +8 prof verbs at 1.2.5 (`src/obs/prof.cyr`);
+6 internal hardening fixes across 1.2.6–1.2.8; per-program
fixup-cap relief at 1.2.8 (sandhi.tcyr → split into
rpc.tcyr). The parked optimization candidates (HPACK Huffman
tie-break, `_sandhi_resp_new` collapse, pool LRU,
`_sandhi_conn_connect_nb` factoring) carried forward into
**1.4.x — profile-justified picks** rather than staying
pinned to a closed arc.

### 1.3.x — TLS arc ✅ closed at 1.3.5

**Theme**: take TLS policy from "wired up across the four
modes" to "production-grade with session-resumption +
0-RTT". Sandhi-owned composition over stdlib `tls_connect` —
cache, keying logic, policy gate, and 0-RTT dispatch all live
in sandhi.

**Scope boundary** (per ADR 0001 — sandhi composes, doesn't
reimplement): the `tls_connect` / hook-surface / ALPN / SNI
/ SPKI primitives are stdlib `lib/tls.cyr` work. If cyrius
swaps fdlopen-libssl for native TLS, that's a cyrius slot
against `lib/tls.cyr`; sandhi keeps calling the contract.
Native-transport prep is therefore not a sandhi item — see
"Cross-repo dependencies" below for the tracking note.

Slot-by-slot detail lives in `CHANGELOG.md`; the shipped log
above carries the compressed one-liners. Summary:

- **1.3.0** — live-network policy gate (CI infra) +
  typed-wrapper migration (`tls_set_alpn`).
- **1.3.1** — session-resumption cache + staged-connect
  wire-up.
- **1.3.2** — TLS 1.3 0-RTT (opt-in; replay-safe-method
  gated).
- **1.3.3** — cred-strip-aware session-cache keying.
- **1.3.4** — stdlib annotation pass + cyrius pin 5.10.34 →
  5.11.4. The TTL+eviction slot pinned in earlier roadmap
  revisions got diverted by the annotation pass; TTL+eviction
  moves to 1.4.0.
- **1.3.5** — cyrius pin 5.11.4 → 6.0.1 + cycc/cybs
  binary-rename adaptation. Arc closes.

### 1.4.x — closeout arc

**Theme**: drain the small/medium pending queue before
sit-adoption reshapes the roadmap. Each slot is concrete and
scoped; no speculative work. These are the items the 1.2.x /
1.3.x arcs deliberately parked because they didn't fit those
themes — bringing them in one at a time keeps the
ONE-thing-per-slot principle honest.

**Why a closeout arc and not a 1.5.x split**: nothing in the
queue forces a fresh-minor break. Each item is additive,
back-compat, and small enough to land as a patch on top of
1.3.5. The arc closes when **sit adoption** surfaces real
workload friction — that's the trigger for the 1.5.x reshape
(memory: sit-adoption drives the roadmap; don't pre-bake).
Sit can only adopt after cyrius lands **native TLS** in its
6.0.x arc; see "Cross-repo dependencies" below.

#### ~~1.4.0 — Session-cache TTL + max-size eviction~~ ✅ shipped 2026-05-22

Sandhi 1.3.1's cache grows unbounded — every successful TLS
handshake captures a session and stores it forever. Fine for
short-lived processes; long-running daemons accumulate stale
sessions whose servers have rotated session-ticket keys. The
cache entry already reserves a `last_used_ms` slot at 1.3.1
specifically for this.

**Scope** (~+2 public verbs):
- `sandhi_session_cache_set_max_size(n)` — default ~256.
- `sandhi_session_cache_set_max_age_ms(ms)` — default ~24h
  (TLS session-ticket lifetime is typically a few hours; 24h
  is the safe upper bound).
- Eviction-on-insert: when full, evict the entry with the
  oldest `last_used_ms`. Periodic sweep unnecessary.
- Age-check-on-lookup: if `now - last_used_ms > max_age`,
  evict + return miss (don't serve a stale ticket the server
  will reject).
- Tests: new `alloc/134/` groups (eviction order, age-evict
  on lookup, set/get round-trip, defaults).

Why lead: smallest, most concrete, half-implemented already
(`last_used_ms` slot present since 1.3.1). Closes the
session-cache subsystem so the 1.3.x TLS arc fully retires.

#### 1.4.5 — `sandhi_server_options_max_conns` enforcement

Daimon's filed ask:
[`docs/issues/2026-05-10-daimon-server-max-conns.md`](../issues/2026-05-10-daimon-server-max-conns.md).
Public setter / getter exist since 0.7.2; accept loop in
`sandhi_server_run_opts` remains single-flight today. Daimon
owns its own epoll-cooperative `serve_async` and wants to
collapse ~60 LOC into a shared `sandhi_server_run_opts` call
when enforcement lands.

**Design choice gates the slot** — pick the worker shape
first (could be a sub-slot or paired with the implementation):
- **(a)** in-process worker pool — N pre-spawned threads
  pulling from a single accept fd; back-pressure via
  blocking-accept when pool full.
- **(b)** epoll-cooperative — integrate with `lib/async.cyr`,
  consumer wires their own event loop.

Low severity (no security impact — daimon closed its own
slowloris exposure at 1.2.2). Pure refactor / dedup
unblocker. If the design choice itself drags out, ship 1.4.5
as a decision-only slot (CHANGELOG documents the pick) and
land the implementation as 1.4.6.

#### `_sandhi_conn_connect_nb` factoring decision ✅ resolved 1.4.4

Cyrius v5.9.42 carved `lib/regression.cyr`'s
`regression_network_probe` using the same non-blocking-connect
+ poll + SO_ERROR-readback shape as sandhi's
`_sandhi_conn_connect_nb` in `src/http/conn.cyr`. Two
viable choices:

- **(a)** file a cyrius issue asking for a `net_connect_nb`
  primitive in `lib/net.cyr`; sandhi + `regression_network_probe`
  both compose-use. Clean; needs a cyrius slot. *Cyrius-side
  ask — sandhi files the coordination doc only.*
- **(b)** **default** — document parallel evolution at both
  callsites. Connect-nb runs once per conn-open (not per
  request); profile almost certainly won't measure. No code
  change.

Likely doc-only slot — the CHANGELOG entry documents the
choice so the parallel evolution is intentional, not
accidental. If user picks (a), the coordination doc lands
here; the actual code change is filed against cyrius.

**Resolved 1.4.4 — option (b)**: parallel evolution documented at the
`_sandhi_conn_connect_nb` callsite (`src/http/conn.cyr`) + CHANGELOG. No
shared `net_connect_nb` primitive, no cyrius dependency (connect runs
once per conn-open, not per request — profile won't measure).

#### 1.4.x — profile-justified optimization picks (parked)

The 1.2.5 prof captures (`sandhi_prof_*`) are ready to
measure against; candidates with no profile evidence stay
parked. Each ships in its own slot when prof data justifies
it. **No pre-committed ordering.**

- **HPACK Huffman tie-break for short tokens** — current
  encoder picks Huffman when *strictly* shorter; ties go to
  raw. Short cookies / opaque tokens benefit from a
  tie-breaker that favors Huffman to keep dynamic-table state
  more compact.
- **`_sandhi_resp_new` allocation collapse** — central
  response-builder allocates header storage, body buffer, and
  Str header separately. If the call shape measures hot
  enough, fuse into a single allocation with internal offset
  slicing.
- **Connection-pool LRU eviction** — pool evicts on
  idle-timeout only; under sustained pressure the
  oldest-but-recently-touched entries can hold slots newer
  routes would benefit from. LRU policy behind an option
  flag; default keeps current semantics until profile shows
  benefit.

#### 1.4.x — `tests/sandhi.tcyr` cap drift watch

Background watch slot, not scheduled. The per-program
fixup-cap (architecture/001) re-baselined post-1.0 fold but
slot-by-slot fixup pressure can creep. If a slot's
implementation pushes sandhi.tcyr against the cap again,
carve out another `tests/<name>.tcyr` (mirroring 1.2.8's
sandhi.tcyr → rpc.tcyr split) in the same slot — don't let
it block the ship.

#### 1.4.x — closeout: P-1 / security / code-audit pass

**Theme**: full-codebase audit before the sit-adoption-driven
reshape opens 1.5.x. The 1.3.x TLS arc closed with the
session-cache subsystem operational (1.4.0 wired the eviction
+ uncovered two silent 1.3.1 bugs in the process). Before
sit-adoption surfaces real-workload friction, the closeout
slot does a full sweep so the audit history is in a known
state at the 1.5.x reshape boundary.

**Scope** (each line gets a checklist entry in the slot's
CHANGELOG):

- **P-1 / P-2 self-audit** — re-run the kind of audit
  shape that landed 0.9.0 (5 P0 fixes) and 0.9.1 (7 P1
  hardening fixes) against everything that shipped post-fold:
  the 1.1.0 allocator migration, the 1.2.x optimization arc,
  the 1.3.x TLS arc, 1.4.0's session-cache TTL/eviction +
  the contract relax on `enable()`. Look for unguarded OOM
  paths missed by the 1.2.6 / 1.2.7 / 1.2.8 audits, security
  regressions in the 0-RTT / cred-strip / session-resumption
  interactions, dup-prevention gaps similar to 1.1.2 in any
  new request paths, and trailer / header forbidden-list
  drift in any new chunked / SSE / h2 code.
- **`tls_dlsym` callers audit** — the 1.3.0 typed-wrapper
  migration covered ALPN; 7 other libssl symbols in
  `apply.cyr` stay on `tls_dlsym`. Inventory each callsite,
  confirm none leak symbol-name assumptions past the
  hook-surface contract that needs to survive a hypothetical
  native-TLS swap.
- **Static-analysis sweep** — `cyrius lint` across `src/`,
  `programs/`, `tests/`; review every accepted suppression
  for whether it still applies. The `src/http/h2/huffman.cyr`
  long-line allowlist entry stays (RFC table); anything else
  on the allowlist that's older than 1.0.0 gets reconfirmed
  or retired.
- **Memory + lifetime audit** — every `default_alloc()` use
  in `src/` reviewed for "is this actually process-singleton
  outliving any arena, or did we just default lazily?". Same
  shape as the 1.1.0 batch-by-batch singleton-vs-arena call,
  applied to additions since 1.1.0.
- **Public surface review** — diff `fn sandhi_*` declarations
  from 1.0.0 (fold-time) through 1.4.0 (current). Confirm
  every name added has its docstring + a test or probe;
  retire anything that's dead or that consumers never picked
  up. Mirror the 1.0.0 closeout's surface-confirmation pass.
- **Issue-directory tidy** — drive-by housekeeping; fold in
  the docs-update work (the issue-doc audits, the proposal
  archives, any consumer-coordination doc drift since the
  M0–M5 sweep). No source change for this part — pure docs.

**Acceptance**:

- All four test suites green (`sandhi.tcyr` / `h2.tcyr` /
  `alloc.tcyr` / `rpc.tcyr`).
- `cyrius lint` 0 warnings on `src/` (modulo the existing
  `huffman.cyr` allowlist entry).
- `cyrfmt --check` clean across `src/` + `tests/` + `programs/`.
- `cyrius distlib` clean rebuild.
- Live-network gate (`_policy_runtime_probe.cyr`) ALL GATES
  PASS.
- New audit findings either fixed in the same slot (P-1 / P-2),
  filed as their own 1.4.x slot (if scope-large), or deferred
  with explicit reasoning in the CHANGELOG.

**Closes 1.4.x.** After this slot, the arc is done; the next
release shapes against sit adoption (which gates on cyrius
native TLS).

### Cross-repo dependencies

Sandhi tracks (but does not own) these cyrius-side items
because consumer-adoption timelines depend on them. Each is a
cyrius-side issue / slot; sandhi notes the linkage so the
downstream timing isn't accidentally forgotten.

- **Native TLS in cyrius `lib/tls.cyr`** *(6.0.x arc;
  gates sit adoption)*. Sit will only pick up sandhi when
  the underlying TLS transport is native (not fdlopen-libssl
  bridged). The swap lives in cyrius's 6.0.x arc;
  sandhi's hook-surface contract is unchanged across the
  swap per CLAUDE.md ("No FFI"). When sit adopts
  post-native-TLS, that's the roadmap-reshape moment for
  1.5.x — surface scope from real-workload friction, don't
  pre-bake. (No corresponding sandhi slot lives here — the
  work is purely cyrius-side. This block exists so the
  cross-repo dependency stays visible.)
- **mDNS multicast primitives in cyrius `lib/net.cyr`**.
  Gates sandhi's `discovery/local.cyr` real implementation:
  `IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` /
  `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`.
  The 0.9.3 unicast-response (QU bit) implementation works
  against most responders without multicast support, so this
  is a quality-of-implementation gate, not a hard blocker.

When these cyrius-side items land, the corresponding sandhi
work opens. Until then, the wait is intentional.

### Post-arc — wait-for-trigger

*Items grouped by what unblocks them, not by version pin.
Cyrius-side prerequisites moved to "Cross-repo dependencies"
above so the cross-repo coupling stays explicit.*

**Wait-for-sit-adoption (1.5.x reshape trigger)**:

The 1.4.x closeout arc is the last pre-sit-adoption work.
When sit picks up sandhi (after cyrius lands native TLS),
real-workload friction surfaces concrete asks that drive
1.5.x scope. Speculatively pre-baking 1.5.x slots is exactly
what the memory [`project_sit_adoption_drives_roadmap`]
warns against. Until sit adopts, this bucket is empty by
design.

**Wait-for-second-consumer-ask**:

- **CONNECT / proxy tunneling** — no documented AGNOS
  egress-proxy need today.
- **Cookie jar** — no AGNOS consumer uses cookie-bearing
  APIs. RFC 6265 is a regret-magnet; wait for a real ask.
- **JSON Merge Patch (RFC 7396)** / **JSON-RPC 2.0 batch** —
  batch is the likelier ask (MCP tool-discovery latency);
  wait for it.
- **TLS ALPN extensions beyond `http/1.1` and `h2`** — both
  ship today; anything beyond that waits for a consumer ask.
- **h2 spec-completeness** — several h2 paths are first-cut and
  consumer-gated (drained from `src/http/h2/` comments at 1.4.3):
  (a) request-body DATA-frame fragmentation when `body_len >
  peer_max_frame` (today rejects with `_SANDHI_H2_ERR_BAD_LENGTH`
  rather than fragmenting — `request.cyr`); (b) flow-control
  window manager / `WINDOW_UPDATE` enforcement (today silently
  accepted; the peer's default window keeps responses bounded —
  `response.cyr`); (c) peer-SETTINGS `ENABLE_PUSH` /
  `MAX_HEADER_LIST_SIZE` enforcement (today not applied to conn
  state — `conn.cyr`; ENABLE_PUSH is moot client-side,
  MAX_HEADER_LIST_SIZE is advisory); (d) caller-overridable
  HEADERS-frame buffer cap (fixed 8 KB today — `request.cyr`).
  Each waits for a consumer whose traffic actually exercises the
  limit.
- **Per-hop cred-digest recompute on cross-authority
  redirect-follow** — the 1.3.3 session-cache cred-digest is
  computed once per top-level dispatch, so an A→B redirect reuses
  A's digest for the B handshake. Harmless for the AGNOS
  service-to-service common case (no consumer combines
  cred-bearing headers with cross-authority redirects). Fold the
  recompute into `_sandhi_http_follow_a`'s hop loop when a
  consumer needs it (`src/http/client.cyr`; CHANGELOG [1.3.3]).
- **Daimon resolver context: auth token + timeouts** — the
  daimon resolver ctx reserves its +8 slot (held 0) for a future
  auth token / per-request timeouts; daimon's registry contract
  defines no auth surface today
  (`docs/issues/2026-04-24-daimon-registry-endpoints.md`). Wire
  the slot when a consumer needs authenticated or timeout-bounded
  discovery (`src/discovery/daimon.cyr`).
- **Client connection-pool thread-safety (per-pool mutex)** —
  the pool is single-threaded today; multi-threaded clients would
  need a per-pool mutex. No consumer needs concurrent request
  dispatch yet (`src/http/pool.cyr`).

**Wait-for-stdlib-prerequisite** (sandhi-side once landed —
cyrius-side cross-repo deps are tracked separately above):

- **Fuzzing harness** — Cyrius toolchain doesn't ship AFL /
  libFuzzer equivalent yet. Revisit when it does.

**Optimization-grade, profile first** (deferred, not parked):

- **Arena-per-request adoption (consumer side)** — the 1.1.0
  `_a`-variant surface + 1.2.0 hot-path allocator review
  give consumers the foundation to pass per-request arenas
  end-to-end. Whether to evangelize the pattern across AGNOS
  consumers waits on profile evidence from a real workload.
- **SIMD / hot-path micro-optimization** — Cyrius has no
  SIMD intrinsics; byte-at-a-time is perfectly adequate at
  SSE / HTTP / HPACK parsing rates observed so far.

**Not sandhi's slot** (filed so the framing doesn't drift
back in):

- **`tls_connect` native-transport prep audit** — the hook
  surface (`tls_connect`, `tls_connect_with_ctx_hook`,
  ALPN / SNI / SPKI extraction) is owned by stdlib
  `lib/tls.cyr`. Auditing it for fdlopen-leaning assumptions
  ahead of the native-TLS swap is a cyrius-side issue against
  `lib/tls.cyr` (tracked in "Cross-repo dependencies" above).
  Sandhi keeps calling the contract; cyrius is responsible
  for keeping it byte-identical across any transport swap.
  ADR 0001 codifies this — sandhi composes, doesn't
  reimplement.

**Won't ship without strong cause**:

- **OCSP stapling / CT log check / HSTS preload** —
  operational footguns (HPKP retirement lessons). Pin +
  custom trust store covers AGNOS's actual threat model.
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

- **1.1.x** — small-fixes lane (closed; 1.1.1 / 1.1.2 cleared
  the 0.9.9 audit deferrals). Stays open as a track for
  future small patches that don't fit an arc shape.
- **1.2.x** — optimization arc (closed at 1.2.8). ONE item
  per slot, profile-justified.
- **1.3.x** — TLS arc (closed at 1.3.5). Sandhi-owned policy
  + state work over stdlib `tls_connect`.
- **1.4.x** — closeout arc. Drains the small/medium pending
  queue before sit-adoption reshapes the roadmap.
  1.4.0 = session-cache TTL + eviction;
  1.4.1 = HTTP close-path framing fix;
  1.4.2 = ALPN/SPKI libssl-binding drop (native-TLS rewire);
  1.4.3 = buried-deferral sweep + pin 6.0.87 + sigil deps;
  1.4.4 = slot realignment + conn_nb factoring decision;
  1.4.5 = max_conns enforcement (pending worker-shape pick);
  1.4.x  = profile-justified picks (parked);
  1.4.x  = cap-drift watch (background);
  **1.4.x closeout** = P-1 / security / code-audit pass.
  Drive-by docs work (issue audits, proposal archive
  cleanup, coordination-doc drift) folds into whichever slot
  it lands alongside — not a slot of its own.
- **1.5.x** — sit-driven reshape, when sit adopts
  post-native-TLS (cyrius 6.0.x). Don't pre-bake — surface
  scope from real-workload friction.

Beyond the arcs, items wait for their unblock signal —
consumer ask, profile evidence, stdlib prerequisite, or
cross-repo dependency. Cyrius-side prerequisites that gate
downstream consumer adoption are tracked in "Cross-repo
dependencies" so the coupling stays visible without sandhi
claiming work it doesn't own. Native-transport prep is
explicitly *not* sandhi's slot.

See [ADR 0001](../adr/0001-sandhi-is-a-composer-not-a-reimplementer.md)
for the naming + thesis, [ADR 0002](../adr/0002-clean-break-fold-at-cyrius-v5-7-0.md)
for the (now-shipped) clean-break fold decision, [ADR 0005](../adr/0005-public-surface-freeze-at-0-9-2.md)
for the surface freeze (now lifted post-1.0.0), and
[`state.md`](state.md) for live progress.
