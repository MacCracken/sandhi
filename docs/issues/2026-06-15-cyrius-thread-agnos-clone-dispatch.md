# 2026-06-15 — `lib/thread.cyr` clone-spawn path has no AGNOS dispatch (`CLONE_VM` undefined on agnos)

**Status**: Open — filed upstream. Blocks a full `cyrius build --agnos`
of any sandhi consumer that transitively pulls `thread` (sandhi does,
via `tls_native.cyr` → `thread.cyr`, and declares `thread` +
`thread_local` directly). x86_64 / macOS / Windows are unaffected.
**Filed**: sandhi side, against the cyrius repo.
**Side**: Upstream (cyrius stdlib `lib/thread.cyr` target dispatch).
**Sandhi-side surface**: None. Per ADR 0001 and CLAUDE.md
("compose-don't-reimplement", "No FFI") sandhi neither forks
`lib/thread.cyr` nor defines `clone` flags itself. This filing keeps
the cross-repo coupling visible; the fix is purely cyrius-side.

## Why this supersedes the earlier "`mmap.cyr` `CLONE_VM` stub" framing

sandhi's 1.5.1 / 1.5.2 notes attributed the agnos full-build failure to
`lib/mmap.cyr` because the compiler reports the error against
`mmap.cyr:184`. That was a **mis-localization**: `mmap.cyr` (63 lines)
contains no `CLONE_VM` token. The `mmap.cyr:184` position is a cyrius
single-pass **include-offset artifact** — `lib/thread.cyr` includes
`lib/mmap.cyr` near its top, so an error at `thread.cyr:199` surfaces
against the `mmap.cyr` include span. The real defect is in
`lib/thread.cyr`. This doc is the corrected, precise filing.

## Symptom

```
$ cd <sandhi or any consumer pulling `thread`>
$ CYRIUS_DCE=1 cyrius build --agnos programs/smoke.cyr build/smoke-agnos
error:lib/mmap.cyr:184: undefined variable 'CLONE_VM' (missing include or enum?)
```

The x86_64 build of the identical source is clean. Reproduced twice
(with and without `CYRIUS_DCE`) on cyrius 6.2.6.

## Root cause (real source, file:line — cyrius 6.2.6)

- `lib/thread.cyr` target-dispatches **only** Windows:
  ```
  #ifdef CYRIUS_TARGET_WIN
  include "lib/thread_win.cyr"
  #endif
  #ifndef CYRIUS_TARGET_WIN
  ... real clone(2)-based thread body ...
  #endif
  ```
  AGNOS is not `WIN`, so the agnos build compiles the `clone`-based body.
- `lib/thread.cyr:199` (the spawn path) builds the clone flags
  **unconditionally**:
  ```
  var flags = CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND;
  flags = flags | CLONE_THREAD | CLONE_SYSVSEM;
  flags = flags | CLONE_PARENT_SETTID | CLONE_CHILD_CLEARTID;
  flags = flags | CLONE_SETTLS;
  ```
- The agnos syscall table `lib/syscalls_x86_64_agnos.cyr` defines **no
  `clone` constants** (`grep -i clone` → nothing). `CLONE_VM` is defined
  only in `syscalls_x86_64_linux.cyr` / `syscalls_aarch64_linux.cyr` /
  `syscalls_macos.cyr`, none of which is selected under
  `#ifdef CYRIUS_TARGET_AGNOS` in `syscalls.cyr`. → `CLONE_VM` is
  undefined on agnos and `thread.cyr` fails to compile.

## Notable: the fix material partly exists but is unwired

A `lib/thread_agnos.cyr` peer **exists in the cyrius toolchain**
(`~/.cyrius/lib/thread_agnos.cyr`) but is (a) not referenced by
`thread.cyr`'s dispatch (which special-cases only `WIN`), and (b) not
vendored into a consumer's resolved `./lib`. This mirrors the
`net.cyr` / `chrono.cyr` AGNOS-peer pattern that already works for
sockets and the clock.

## Resolution path (cyrius-side)

Route AGNOS to its peer the same way WIN is routed, e.g.:

```
#ifdef CYRIUS_TARGET_WIN
include "lib/thread_win.cyr"
#endif
#ifdef CYRIUS_TARGET_AGNOS
include "lib/thread_agnos.cyr"
#endif
#ifndef CYRIUS_TARGET_WIN
#ifndef CYRIUS_TARGET_AGNOS
... existing clone(2) body ...
#endif
#endif
```

(or guard the `clone`-flag block itself behind
`#ifndef CYRIUS_TARGET_AGNOS`). AGNOS's threading model — whether
`thread_agnos.cyr` offers real threads or a serial fallback like
`thread_win.cyr` — is cyrius's call; sandhi only needs `thread.cyr` to
**compile** on the agnos target so the bundle links. Until then the
agnos build of any `thread`-pulling consumer is blocked.

## Why it isn't a sandhi-side fix

Per ADR 0001 + CLAUDE.md "No FFI": sandhi composes stdlib primitives
and does not fork `lib/thread.cyr` or define `clone` flags. The
remaining `--agnos` blockers for sandhi are this item and the native
`SSL_CTX_*` enforcement work (the other open cross-repo dependency);
sandhi's own AGNOS transport surface (socket syscalls, DNS entropy)
was completed sandhi-side at 1.5.1 / 1.5.2 (Batch C1 / C2). Tracked
under roadmap "Cross-repo dependencies" + the AGNOS adoption issue
[`2026-06-14-agnos-socket-backend-gap.md`](2026-06-14-agnos-socket-backend-gap.md).

## Log

- **2026-06-15** — filed at sandhi 1.5.3 close, on cyrius 6.2.6 pin.
  Root-caused during the upstream-claims verification pass that
  corrected the earlier `mmap.cyr` mis-localization. Reproduced twice;
  `thread_agnos.cyr` peer confirmed present-but-unwired in the toolchain.
