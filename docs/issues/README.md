# sandhi — issue & coordination log

Issues here fall into two buckets. Both live in this directory with
the `YYYY-MM-DD-kebab-case.md` naming convention so recency is
obvious at the directory level.

## Cross-repo coordination (sandhi consumer & producer integrations)

Each AGNOS crate that sandhi serves (or that sandhi depends on)
gets one focused doc with a paste-ready roadmap entry, a migration
example, and any known blockers. Handing one file to each crate's
modernization agent beats routing through sandhi's full repo.

| Doc | Crate | Side | Priority |
|-----|-------|------|----------|
| [`2026-04-24-yantra-sandhi-rpc.md`](2026-04-24-yantra-sandhi-rpc.md) | yantra | consumer | M2+ backend unblock |
| [`2026-04-24-daimon-registry-endpoints.md`](2026-04-24-daimon-registry-endpoints.md) | daimon | producer | pre-fold (sandhi calls it) |
| [`2026-04-24-daimon-sandhi-mcp-client.md`](2026-04-24-daimon-sandhi-mcp-client.md) | daimon | consumer | pre-fold |
| [`2026-04-24-hoosh-ifran-sandhi-http.md`](2026-04-24-hoosh-ifran-sandhi-http.md) | hoosh + ifran | consumer | pre-fold |
| [`2026-04-24-sit-sandhi-git-over-http.md`](2026-04-24-sit-sandhi-git-over-http.md) | sit | consumer | gated on sit local-VCS (TLS fix landed, cyrius 6.1.21) |
| [`2026-04-24-ark-sandhi-registry-ops.md`](2026-04-24-ark-sandhi-registry-ops.md) | ark | consumer | pre-fold |
| [`2026-04-24-mela-sandhi-marketplace.md`](2026-04-24-mela-sandhi-marketplace.md) | mela | consumer | pre-fold |
| [`2026-04-24-vidya-sandhi-fetch.md`](2026-04-24-vidya-sandhi-fetch.md) | vidya | consumer | future (low priority) |

Each doc carries its own "what's assumed vs. actual" note. sandhi's
side is shipped; the doc exists so the consumer/producer crate has
zero ambiguity on what to put on its roadmap.

## Sandhi-side defects

All sandhi-side defects filed to date are **resolved and archived** — see the
[Archived](#archived-resolved) table below. The 1.4.x arc closed the HTTP
close-path drain (1.4.1), the repeated-HTTPS-request SIGSEGV (1.4.5), the
high-level client TLS-policy threading gap (1.4.6), and the low-level
TLS-policy-enforcement live SIGSEGV (1.4.7); the AGNOS transport gap closed
across C1 (1.5.1) / C2 (1.5.2) with the build cascade clearing at 1.5.4 / cyrius
6.2.7. New sandhi-side defects land here as `YYYY-MM-DD-kebab-case.md` and move
to `archive/` when closed.

## Upstream dependencies (sandhi is blocked on stdlib / toolchain)

| Doc | Filed | Status | Summary |
|-----|-------|--------|---------|
| [`2026-05-22-cyrius-native-tls-in-6.0.x.md`](2026-05-22-cyrius-native-tls-in-6.0.x.md) | 2026-05-22 | ✅ CLOSED (1.6.0 / cyrius 6.2.8) | `lib/tls.cyr` native-TLS swap (off the fdlopen-libssl bridge). Native transport operational + no-flag default since 1.4.2 / cyrius 6.1.21. **Closed at cyrius 6.2.8 / sandhi 1.6.0**: 6.2.8 shipped the typed native trust-store + mTLS ctx verbs (`tls_ctx_load_verify_locations` / `_use_certificate_file` / `_use_private_key_file`); 1.6.0 migrated `apply.cyr` off the last `tls_dlsym("SSL_CTX_*")` callers → native now enforces trust-store + mTLS (Batch A1). Last libssl coupling for policy enforcement gone. Archive on the next sweep. |
| [`2026-05-10-daimon-server-max-conns.md`](2026-05-10-daimon-server-max-conns.md) | 2026-05-10 | sandhi-side ✅ 1.4.9 | Daimon's `serve_async` → shared-path collapse was blocked on `sandhi_server_options_max_conns` *enforcement*. **Sandhi side shipped at 1.4.9**: `sandhi_server_run_async` (epoll-cooperative, batched accept bounded by `max_conns`, per-handler buffers) — approach (2) from the filing. Residual is daimon-side (collapse its duplicated accept loop onto the shared verb); sandhi has nothing left to wire. |

## Archived (resolved)

| Doc | Closed at | Summary |
|-----|-----------|---------|
| [`archive/2026-06-15-cyrius-mdns-multicast-primitives.md`](archive/2026-06-15-cyrius-mdns-multicast-primitives.md) | sandhi 1.5.5 / cyrius 6.2.7 | cyrius `lib/net.cyr` lacked IPv4 multicast primitives (gated QM-mode mDNS). 6.2.7 shipped the join/option set from sandhi's filing; a 1.5.4 QM adoption was **reverted** (connected-socket `connect()` source-filter dropped answers — caught by adversarial review), then **resolved at 1.5.5** via a two-socket split (unconnected RX) — no upstream `sock_sendto`/`sock_recvfrom` needed — and verified with a loopback live receive test. Adopted as the opt-in `sandhi_discovery_local_mc_resolver` (Batch A3). *(Companion QU-resolver connect()-filter live-check still open.)* |
| [`archive/2026-06-14-agnos-socket-backend-gap.md`](archive/2026-06-14-agnos-socket-backend-gap.md) | sandhi 1.5.4 / cyrius 6.2.7 | AGNOS transport gap. **C1 (1.5.1)** socket-syscall compile (`#ifndef CYRIUS_TARGET_AGNOS` guards in `conn.cyr`/`server`) + **C2 (1.5.2)** DNS entropy (`/dev/urandom` → portable `sys_getrandom`) were the sandhi-side work; the remaining stdlib build cascade cleared at 1.5.4 / cyrius 6.2.7. `cyrius build --agnos` now produces a valid agnos ELF. Surfaced by sit adoption. |
| [`archive/2026-06-15-cyrius-thread-agnos-clone-dispatch.md`](archive/2026-06-15-cyrius-thread-agnos-clone-dispatch.md) | sandhi 1.5.4 / cyrius 6.2.7 | AGNOS full-build cascade. The "`mmap` `CLONE_VM` stub" / "unfixed upstream `thread.cyr`" framings were corrected (adversarial verification) to: a stale-`./lib` `thread.cyr` (already fixed in the 6.2.6 toolchain) + `async.cyr`'s raw `SYS_EPOLL_CREATE1`. **Resolved**: clean deps re-resolve clears `thread.cyr`; 6.2.7 routes `async.cyr` to a serial agnos peer. `--agnos` build succeeds. |
| [`archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`](archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md) | sandhi 1.5.0 / cyrius 6.2.6 | `cycc_aarch64` aborted with `error: unexpected enum` assembling stdlib `bayan` (sigil's transitive dep since the 1.4.11 6.2.1 pin); reproduced on every toolchain 6.0.21–6.2.1, x86_64 unaffected. Upstream dep-assembly defect (the "top-level init breaks later declarations" quirk on the aarch64 path). **Fixed upstream in cyrius 6.2.6** — `--aarch64` build produces a valid aarch64 ELF with zero sandhi change; CI/release aarch64 step restored to gating. |
| [`archive/2026-06-09-tls-policy-enforcement-live-segfault.md`](archive/2026-06-09-tls-policy-enforcement-live-segfault.md) | sandhi 1.4.7 | Low-level `sandhi_conn_open_with_policy` SIGSEGV'd on a LIVE network (native trust-store fed a native ctx to libssl `SSL_CTX_*`; libssl pinning hit a cyrius `tls_get_peer_spki_der` regression). **Fixed in 1.4.7**: `enforcement_available()` backend-aware (trust/mTLS → 0 on native) + new `pin_available()` (SPKI, backend-agnostic, libssl-excluded); `_sandhi_policy_pre_open_a` fails closed before the faulting paths. Enforcement-parity follow-ups (native `SSL_CTX_*`; cyrius libssl-SPKI fix) tracked cross-repo. |
| [`archive/2026-06-09-https-client-tls-policy-threading.md`](archive/2026-06-09-https-client-tls-policy-threading.md) | sandhi 1.4.6 | High-level client (`sandhi_http_*` / `sandhi_http_stream`) couldn't carry a TLS policy. **Fixed in 1.4.6**: `sandhi_http_options_tls_policy` + getter; HTTPS open bracketed by the policy pre/post-open helpers (fail-closed, post-handshake SPKI pin, pool/0-RTT bypass). Live gate `_https_policy_threading_gate.cyr` green. Surfaced by hoosh v2.2.0. |
| [`archive/2026-06-09-https-repeated-request-segfault.md`](archive/2026-06-09-https-repeated-request-segfault.md) | sandhi 1.4.5 / cyrius 6.1.19 | `sandhi_http_get`/`_post` SIGSEGV on the ~4th sequential HTTPS request to the same host. Root cause upstream — cyrius `alloc.cyr` `brk` heap × glibc-malloc contention via `fdlopen`-libssl. **Fixed in cyrius 6.1.19**: alloc heap → anonymous-mmap; sandhi default-switched to native TLS at 1.4.5. Surfaced by hoosh v2.2.0. |
| [`archive/2026-06-03-http-close-path-drains-until-eof.md`](archive/2026-06-03-http-close-path-drains-until-eof.md) | sandhi 1.4.1 | `Connection: close` request path (`_sandhi_http_exchange_a`) drained until EOF instead of framing by `Content-Length`; servers that send a complete CL-framed response but don't promptly close (chromedriver, Chromium DevTools) caused `SANDHI_ERR_TIMEOUT`. **Fixed in 1.4.1**: close path now uses `_sandhi_http_recv_framed` (shared with keep-alive). Verified live against chromedriver. |
| [`archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`](archive/2026-04-24-fdlopen-getaddrinfo-blocked.md) | cyrius v5.6.29-1 | Three logged symptoms: `fdlopen_init` incomplete (was stale doc text — actually landed v5.5.34); local-slot aliasing in response parser (worked around sandhi-side by extracting helpers); HTTPS infinite-loop (ROOT CAUSE: sandhi's `[deps.stdlib]` was missing `dynlib`/`fdlopen`/`mmap`, so `cyrius build` patched undef-fn call-sites with a placeholder disp32 that silently looped through `_cyrius_init`). Closed when sandhi added the missing deps and cyrius shipped a `ud2` fixup so the next missing-include mistake crashes loud instead of looping silent. |
| [`archive/2026-04-24-libssl-pthread-deadlock.md`](archive/2026-04-24-libssl-pthread-deadlock.md) | cyrius v5.6.39 | `SSL_connect` deadlocked on a futex-wait inside libssl's pthread-lock path in static cyrius binaries (no `__libc_pthread_init`). Closed when upstream completed the dynlib/locale/TLS bootstrap so libssl gets a properly pthread-initialised process. Stdlib raw probe round-trips real HTTPS bytes since the pin reached 5.6.39. |
| [`archive/2026-04-24-stdlib-tls-alpn-hook.md`](archive/2026-04-24-stdlib-tls-alpn-hook.md) | cyrius v5.6.40 | Stdlib `tls_connect` built its SSL_CTX privately so sandhi had no slot to call `SSL_CTX_set_alpn_protos`. Closed by `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)` + `tls_dlsym(name)` — Option A from the filing, smallest stdlib delta. End-to-end verified: advertise `h2,http/1.1` to Cloudflare → server picks `h2` via `SSL_get0_alpn_selected`. |
| [`archive/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md`](archive/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md) | cyrius v5.6.41 | Surfaced once libssl-pthread cleared. `tls_connect` SIGSEGV'd at its first instruction when invoked from a Cyrius function whose 7th param sat on the stack (SysV-ABI register/stack-arg boundary). `sandhi_conn_open_fully_timed` is exactly that shape. Closed by upstream calling-convention fix; `sandhi_http_get("https://example.com/")` returns 200 / 528 bytes since the pin reached 5.6.41. |
| [`archive/2026-05-09-stdlib-tls-staged-connect.md`](archive/2026-05-09-stdlib-tls-staged-connect.md) | cyrius v5.10.27 | Cyrius v5.10.21 shipped session/0-RTT primitives but `tls_connect_with_ctx_hook` ran `SSL_new`+`SSL_connect` in one shot — no timing window for `tls_set_session(ssl, ...)`. v5.10.27 split the connect flow (Option A from the filing): `tls_connect_alloc` + `tls_connect_complete`. Sandhi 1.3.1 wires the staged-connect into `_sandhi_conn_finalize_a` + adds `src/tls_policy/session_cache.cyr` for the SSL_SESSION* cache. |
| [`archive/2026-05-10-stdlib-tls-early-data-status.md`](archive/2026-05-10-stdlib-tls-early-data-status.md) | cyrius v5.10.34 | Cyrius v5.10.21 shipped `tls_write_early_data` / `tls_read_early_data` / `tls_supports_early_data` but not the post-handshake `SSL_get_early_data_status` accessor or the pre-attempt `SSL_SESSION_get_max_early_data` budget probe. Without those, client-side 0-RTT can't detect rejection or right-size the early-data write. v5.10.34 added typed wrappers `tls_get_early_data_status(ctx)` + `tls_session_get_max_early_data(session)` with safe defaults (NOT_SENT / 0) when libssl lacks the underlying symbols. Sandhi 1.3.2 composes both into the opt-in 0-RTT path. |

## How to use this directory

- **From inside a consumer repo**, grab the matching doc and drop
  the "Proposed roadmap entry" block into that repo's `roadmap.md`.
- **When a sandhi enhancement is gated** on upstream work, link
  to the upstream doc here rather than duplicating the context.
- **Never renumber** — append-only, like `docs/adr/`.

New docs in this directory land with the same naming convention and
a "Log" section at the bottom so recurring issues can add entries
without forking a new file.
