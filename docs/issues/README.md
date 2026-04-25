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
| [`2026-04-24-sit-sandhi-git-over-http.md`](2026-04-24-sit-sandhi-git-over-http.md) | sit | consumer | gated on sit local-VCS + TLS fix |
| [`2026-04-24-ark-sandhi-registry-ops.md`](2026-04-24-ark-sandhi-registry-ops.md) | ark | consumer | pre-fold |
| [`2026-04-24-mela-sandhi-marketplace.md`](2026-04-24-mela-sandhi-marketplace.md) | mela | consumer | pre-fold |
| [`2026-04-24-vidya-sandhi-fetch.md`](2026-04-24-vidya-sandhi-fetch.md) | vidya | consumer | future (low priority) |

Each doc carries its own "what's assumed vs. actual" note. sandhi's
side is shipped; the doc exists so the consumer/producer crate has
zero ambiguity on what to put on its roadmap.

## Upstream dependencies (sandhi is blocked on stdlib / toolchain)

None open as of cyrius v5.6.41. The three TLS-stack blockers all cleared 2026-04-25 and are listed in the archive table below. Live HTTPS through `sandhi_http_get` round-trips real bytes; ALPN advertise works through the new stdlib hook.

## Archived (resolved)

| Doc | Closed at | Summary |
|-----|-----------|---------|
| [`archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`](archive/2026-04-24-fdlopen-getaddrinfo-blocked.md) | cyrius v5.6.29-1 | Three logged symptoms: `fdlopen_init` incomplete (was stale doc text — actually landed v5.5.34); local-slot aliasing in response parser (worked around sandhi-side by extracting helpers); HTTPS infinite-loop (ROOT CAUSE: sandhi's `[deps.stdlib]` was missing `dynlib`/`fdlopen`/`mmap`, so `cyrius build` patched undef-fn call-sites with a placeholder disp32 that silently looped through `_cyrius_init`). Closed when sandhi added the missing deps and cyrius shipped a `ud2` fixup so the next missing-include mistake crashes loud instead of looping silent. |
| [`archive/2026-04-24-libssl-pthread-deadlock.md`](archive/2026-04-24-libssl-pthread-deadlock.md) | cyrius v5.6.39 | `SSL_connect` deadlocked on a futex-wait inside libssl's pthread-lock path in static cyrius binaries (no `__libc_pthread_init`). Closed when upstream completed the dynlib/locale/TLS bootstrap so libssl gets a properly pthread-initialised process. Stdlib raw probe round-trips real HTTPS bytes since the pin reached 5.6.39. |
| [`archive/2026-04-24-stdlib-tls-alpn-hook.md`](archive/2026-04-24-stdlib-tls-alpn-hook.md) | cyrius v5.6.40 | Stdlib `tls_connect` built its SSL_CTX privately so sandhi had no slot to call `SSL_CTX_set_alpn_protos`. Closed by `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)` + `tls_dlsym(name)` — Option A from the filing, smallest stdlib delta. End-to-end verified: advertise `h2,http/1.1` to Cloudflare → server picks `h2` via `SSL_get0_alpn_selected`. |
| [`archive/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md`](archive/2026-04-25-cyrius-7arg-frame-tls-connect-segfault.md) | cyrius v5.6.41 | Surfaced once libssl-pthread cleared. `tls_connect` SIGSEGV'd at its first instruction when invoked from a Cyrius function whose 7th param sat on the stack (SysV-ABI register/stack-arg boundary). `sandhi_conn_open_fully_timed` is exactly that shape. Closed by upstream calling-convention fix; `sandhi_http_get("https://example.com/")` returns 200 / 528 bytes since the pin reached 5.6.41. |

## How to use this directory

- **From inside a consumer repo**, grab the matching doc and drop
  the "Proposed roadmap entry" block into that repo's `roadmap.md`.
- **When a sandhi enhancement is gated** on upstream work, link
  to the upstream doc here rather than duplicating the context.
- **Never renumber** — append-only, like `docs/adr/`.

New docs in this directory land with the same naming convention and
a "Log" section at the bottom so recurring issues can add entries
without forking a new file.
