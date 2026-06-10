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

## Shipped (M0 through 1.4.10)

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
- **1.4.5** — native TLS by default + P1 repeated-request SIGSEGV **fixed** + cyrius pin 6.0.87 → **6.1.19**. Root-caused the 4th-request crash to **cyrius `lib/alloc.cyr` brk-heap × glibc-malloc contention** via `fdlopen`-libssl (reproduces with zero sandhi code; mmap-leak variant doesn't crash) — filed two upstream cyrius issues (alloc-brk-contention + native-handshake-gap), **both fixed in 6.1.19** (alloc → anonymous-mmap chunk-bump; native cert-chain ordering). sandhi also default-switched to the **native** TLS backend (no libssl/glibc → no contention); libssl demoted to opt-in (now crash-safe too at 6.1.19). +4 backend-selection verbs (`sandhi_tls_use_native`/`_use_libssl`/`_backend`/`_native_available`); native is the build default under `-D CYRIUS_TLS_NATIVE` (build/CI/Quick Start pass it; consumers must too — architecture/004). Fixed an unconditional `tls_get_session` session-ref leak on the libssl path. New CI gate `_https_native_loop_gate.cyr` (N≥4 native GETs, must not crash). 979 assertions green (unchanged). Verified at 6.1.19: native + libssl `sandhi_http_get` ×6 to example.com both 6/6 status 200, no crash. Full libssl *retirement* now gated only on native TLS-policy enforcement.
- **1.4.6** — high-level client TLS-policy threading + cyrius pin 6.1.19 → **6.1.20**. Closes the hoosh v2.2.0 P1: `sandhi_http_options_tls_policy` + getter; the high-level `sandhi_http_*` path (and `sandhi_http_stream`) brackets its HTTPS open with `_sandhi_policy_pre_open_a` / `_post_open_a` (refactored from `sandhi_conn_open_with_policy_a`) — fail-closed on unavailable enforcement, post-handshake SPKI pin, pool + 0-RTT bypassed for policy-bound requests; the request path's own v4/v6 timed opener is reused so deadlines + IPv6 thread for free. `policy` / `fingerprint` / `apply` modules reordered ahead of `client` / `stream` (25 include blocks) for single-pass reachability. New native live gate `_https_policy_threading_gate.cyr` (no-policy 200 / wrong-pin fail-closed TLS / correct-pin 200). Pin bump mechanical (6.1.20 folds sandhi 1.4.5 into `lib/sandhi.cyr` + a non-sandhi-facing macho-arm Darwin syscall port). Filed a pre-existing P2: low-level trust-store/mTLS enforcement SIGSEGVs on a live network (`2026-06-09-tls-policy-enforcement-live-segfault.md`). 992 assertions green (+13; new `alloc/146/`).
- **1.4.7** — backend-aware TLS-policy enforcement; eliminates the live-network SIGSEGV (no cyrius bump; stays 6.1.20). Fixes the P2 spun off from 1.4.6: native trust-store/mTLS fed the native ctx to libssl `SSL_CTX_*` → fault, and libssl SPKI-pin SIGSEGV'd in cyrius's `tls_get_peer_spki_der` (deprecated-backend regression). `sandhi_tls_policy_enforcement_available()` made backend-aware (trust/mTLS → 0 on native); **+1 verb** `sandhi_tls_policy_pin_available()` (SPKI backend-agnostic; native works without libssl; libssl excluded pending the cyrius fix). `_sandhi_policy_pre_open_a` gates the two modes separately + fails closed before arming the hook. `_policy_runtime_probe.cyr` reworked native (CI -D); `_https_policy_threading_gate.cyr` gates on `pin_available()`. Native gates ALL PASS, no crash. Cross-repo follow-ups (native `SSL_CTX_*`; cyrius libssl-SPKI fix) tracked under "native TLS-policy enforcement". 992 assertions green (unchanged).
- **1.4.8** — TLS backend flag-polarity flip (target convention) + interim green CI (no cyrius bump; stays 6.1.20). Docs/build-convention change: target is native-as-no-flag-default with `-D CYRIUS_TLS_LIBSSL` opt-in (inverse of the 1.4.5–1.4.7 `-D CYRIUS_TLS_NATIVE`), applied across CLAUDE.md / architecture/004 / gate-program comments / `src/tls_policy/mod.cyr` header. The target needs an upstream cyrius change not in 6.1.20 (`lib/tls.cyr` is still `#ifdef CYRIUS_TLS_NATIVE`), so CI/release keep `-D CYRIUS_TLS_NATIVE` on the native steps (interim banner) and build the libssl proof no-flag — keeping CI green and actually exercising native (native smoke 1.37 MB vs 562 KB libssl; 3 native gates PASS). Filed cyrius issue `2026-06-09-invert-tls-backend-default-native-no-flag.md` to complete the flip. 992 assertions green (unchanged).
- **1.4.9** — epoll-cooperative server; `max_conns` enforced + cyrius pin 6.1.20 → **6.1.21** (TLS flag flip completed). Closes the daimon ask: **+1 verb** `sandhi_server_run_async` over `lib/async.cyr` (worker shape decided (b) epoll-cooperative; handler stays cooperative). Batched accept up to `max_conns`/cycle → spawn handler task per conn → `async_run` → reset per-batch arena. Per-handler recv buffers (no-interleave invariant). New deps `async` + `atomic`. Sync `run`/`run_opts` unchanged. Filed cyrius cross-repo leak `2026-06-09-async-runtime-no-free-task-leak.md` (async.cyr no-free rt/task structs). **cyrius 6.1.21** inverted `lib/tls.cyr` (native = no-flag default; `-D CYRIUS_TLS_LIBSSL` opts out; legacy `-D CYRIUS_TLS_NATIVE` = no-op alias) + re-folded sandhi 1.4.5→1.4.8 — so CI/release dropped the 1.4.8 interim `-D CYRIUS_TLS_NATIVE` (libssl proof now `-D CYRIUS_TLS_LIBSSL`). Verified via forked `_server_async_smoke.cyr` (2/2 200) + 3-way polarity. 992 assertions green (unchanged).
- **1.4.10** — closeout audit (P-1 / security / code-audit pass); **closes the 1.4.x arc** (no pin change; stays 6.1.21). **P1 fixed**: async server DoS — `_sandhi_server_async_handler` did an infinite `async_await_readable` (epoll_wait −1) before recv, so a silent client hung the whole cooperative loop; dropped the await (recv under SO_RCVTIMEO), floored `idle_ms` > 0; silent-client regression added to the smoke. **P2 fixed**: `async_new()` null-check (server); `body_sb` + `chunk_state` null-checks (stream SSE/chunked path). **Audit-confirmed**: 1.4.7 native-fail-closed property HOLDS (full `tls_dlsym`/`SSL_CTX_*` gate coverage; key-without-cert safe); 1.4.5–1.4.9 verbs documented + covered; +2 standalone docstrings. 992 assertions green (unchanged).

## What's next

The **1.4.x closeout arc is closed** (ended at 1.4.10 — the P-1/security
audit pass). Nothing here is a committed dated slot anymore: the
remaining items are either gated on a cyrius-side primitive, parked
pending profile evidence, or background watches. The next *minor* break
is **1.5.x**, which opens when **sit adopts sandhi** (real-workload
friction drives the scope — don't pre-bake; see "Post-arc" below).

### Remaining work (un-gated → small patches; gated → wait)

#### Follow-up — async server: switch to arena-aware runtime (gated on cyrius)

**Opens when cyrius lands the arena-aware async runtime** filed at
[`2026-06-09-async-runtime-no-free-task-leak.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-06-09-async-runtime-no-free-task-leak.md)
(proposes `async_new_in(allocator)` so the runtime + task structs come
from a caller-owned arena instead of the no-free global bump). The 1.4.9
`sandhi_server_run_async` (`src/server/mod.cyr`) already bounds its own
per-connection recv buffers + arg structs in a reset-per-batch arena, but
`async_new()` + `async_spawn()` still leak ~32 B/connection (rt + task
structs) because `async_run` closes the epfd and forces a per-batch
recreate. **The repair, when the cyrius primitive ships:**

- Re-pin to the cyrius release that adds `async_new_in(allocator)`.
- In `sandhi_server_run_async`, create the runtime from the same per-batch
  arena (`async_new_in(arena)` instead of `async_new()`), so the rt + task
  structs are reclaimed by the existing `reset_via(arena)` each batch →
  **zero residual leak**, RSS flat over a sustained request stream.
- Update the memory note in `sandhi_server_run_async` + drop this slot;
  daimon's `serve_async` gets the same fix when it collapses onto the
  shared verb. Add a long-running RSS-flat assertion to the smoke gate.

Until then the residual leak is documented + bounded (fine for
bounded-lifetime / low-traffic; a quality gate for high-traffic). Tracked
as a cross-repo dependency below.

#### Profile-justified optimization picks (parked → carry to 1.5.x)

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

#### `tests/sandhi.tcyr` cap-drift watch (background)

Background watch slot, not scheduled. The per-program
fixup-cap (architecture/001) re-baselined post-1.0 fold but
slot-by-slot fixup pressure can creep. If a slot's
implementation pushes sandhi.tcyr against the cap again,
carve out another `tests/<name>.tcyr` (mirroring 1.2.8's
sandhi.tcyr → rpc.tcyr split) in the same slot — don't let
it block the ship.

### Cross-repo dependencies

Sandhi tracks (but does not own) these cyrius-side items
because consumer-adoption timelines depend on them. Each is a
cyrius-side issue / slot; sandhi notes the linkage so the
downstream timing isn't accidentally forgotten.

**Resolved upstream** (pin-trail context; full detail in CHANGELOG + the
cyrius issues): the repeated-request SIGSEGV root causes — `lib/alloc.cyr`
brk×glibc-malloc contention + native cert-chain ordering, both **6.1.19** —
and the **inverted TLS-backend default** (native compiled-in + selected
no-flag, **6.1.21**, which also re-folded sandhi 1.4.5→1.4.8). The native
TLS transport itself landed across the cyrius 6.0.x arc and has been
sandhi's default since 1.4.5. Open items:

- **Native TLS-policy enforcement (trust-store / mTLS)** — the last libssl
  coupling in sandhi's TLS surface. SPKI pinning is backend-agnostic (typed
  `tls_get_peer_spki_der`, 1.4.2) and live on native; 1.4.7 made enforcement
  backend-aware so the prior live SIGSEGVs are gone — native trust/mTLS now
  **fails closed** instead of feeding a native ctx to libssl `SSL_CTX_*`
  (sandhi-side P2
  [`2026-06-09-tls-policy-enforcement-live-segfault.md`](../issues/2026-06-09-tls-policy-enforcement-live-segfault.md)).
  Two cyrius-side items reach full parity (and let `sandhi_tls_use_libssl()`
  be dropped entirely):
  - **Native `SSL_CTX_*` equivalents** in `lib/tls_native.cyr` (custom trust
    store + client cert/key) so native trust/mTLS *enforces* rather than
    fails closed — mirrors the 1.4.2 ALPN/SPKI rewire.
  - **Fix the libssl `tls_get_peer_spki_der` regression** — a single libssl
    pinned open SIGSEGVs in the post-handshake SPKI extraction (worked at
    1.3.0; regressed since). sandhi excludes libssl from `pin_available()`
    until this lands.
- **mDNS multicast primitives in cyrius `lib/net.cyr`**.
  Gates sandhi's `discovery/local.cyr` real implementation:
  `IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` /
  `IP_MULTICAST_LOOP` / `SO_REUSEPORT` / `IP_MULTICAST_IF`.
  The 0.9.3 unicast-response (QU bit) implementation works
  against most responders without multicast support, so this
  is a quality-of-implementation gate, not a hard blocker.
- **`lib/async.cyr` arena-aware runtime (no-free task leak)** *(filed;
  affects 1.4.9 `sandhi_server_run_async`)*. `async.cyr` allocates its
  runtime + task structs from the global bump (no `free`) and closes the
  epfd in `async_run`, so the batched accept loop's per-batch recreate
  leaks ~32 B/connection. sandhi bounds its own per-connection buffers
  with a reset-per-batch arena; eliminating the residual leak needs an
  arena-aware constructor (`async_new_in(allocator)`). Filed
  [`cyrius .../2026-06-09-async-runtime-no-free-task-leak.md`](https://github.com/MacCracken/cyrius/blob/main/docs/development/issues/2026-06-09-async-runtime-no-free-task-leak.md).
  Same leak daimon's `serve_async` already carries; a quality gate for
  long-running high-traffic servers, not a correctness blocker for the
  bounded-lifetime / low-traffic case.

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
- **1.4.x** — closeout arc (**closed at 1.4.10**). Drained the
  small/medium pending queue before the sit-adoption reshape:
  session-cache TTL/eviction, the HTTP close-path fix, the
  native-TLS arc (default switch + P1 SIGSEGV root-fix +
  backend-aware policy enforcement + the no-flag flip), the
  high-level cert-pinning/mTLS threading, the epoll server, and
  the P-1/security audit pass. Per-release detail in the Shipped
  log above + CHANGELOG.
- **1.5.x** — sit-driven reshape, when sit adopts
  post-native-TLS (cyrius native landed at 6.1.21). Don't
  pre-bake — surface scope from real-workload friction.

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
