# sandhi — AGNOS socket-backend gap (raw BSD-socket transport blocks the agnos target)

- **Filed**: 2026-06-14
- **Status**: ✅ **Compile gap closed at sandhi 1.5.1** (Batch C1). Every raw
  `SYS_*` socket-syscall site in `src/http/conn.cyr` + `src/server/mod.cyr` is
  now wrapped in `#ifndef CYRIUS_TARGET_AGNOS` (agnos counterpart under
  `#ifdef`), so a consumer that includes the bundle compiles for `--agnos`.
  Linux/macOS proven byte-identical. **Remaining (NOT C1 scope, tracked):** the
  `/dev/urandom` DNS-entropy runtime gap in `resolve.cyr` (roadmap C2), the
  upstream `lib/mmap.cyr` `CLONE_VM` agnos stub, and native `SSL_CTX_*` for the
  bundle's `fdlopen`/`tls_dlsym` TLS-policy path on agnos (Batch A1). See the Log
  below + CHANGELOG [1.5.1].
- **Severity**: blocker (for the AGNOS target only — Linux/macOS hosts unaffected)
- **Area**: `src/http/conn.cyr` (client connect machinery), `src/server/mod.cyr` (listen-fd nonblock)
- **Surfaced by**: `sit` adoption on AGNOS — `cyrius build --agnos` of any sandhi consumer fails to resolve raw socket syscall enums.
- **Toolchain**: the agnos backend needs `≥6.2.6` (the `tls`/`net` agnos peer that landed in cyrius 6.2.5/6.2.6). **Prerequisite satisfied as of sandhi 1.5.0** — the pin bumped `6.2.1 → 6.2.6`, so this work is now un-gated and ready to slot (tracked as 1.5.x Batch C1; near-term 1.5.1 candidate).

## Summary

sandhi's TLS layer is already backend-agnostic (it reaches the world only through the
stdlib `tls_*` / `net.cyr` contract — see `CLAUDE.md` "No FFI"). But sandhi's **transport
layer** is split into two idioms, and one of them does not compile for the AGNOS target:

1. **Portable** — DNS (`src/net/resolve.cyr`) and mDNS discovery (`src/discovery/local.cyr`)
   use the stdlib wrappers `sock_connect` / `sock_send` / `sock_recv` / `sock_bind` /
   `sock_listen` / `sock_close`. These resolve and work on AGNOS today (agnos exposes the
   same higher-level surface via syscalls #46-50 / #51-54; `dig` + `yo` already run on the
   kernel over them).
2. **Raw BSD sockets** — the HTTP client's *timeout-bounded non-blocking connect* and the
   async server's *non-blocking listen fd* drop straight to Linux syscall numbers
   (`SYS_SOCKET` / `SYS_CONNECT` / `SYS_FCNTL` / `SYS_POLL` / `SYS_GETSOCKOPT` /
   `SYS_SETSOCKOPT`). **AGNOS defines none of these** — it has no `fcntl` / `poll` /
   `getsockopt` concept at all. The enum constants are undefined on the agnos target, so the
   bundle fails to **compile** (not merely at runtime).

## Symptom

```
$ cd <sandhi-consumer e.g. sit>; cyrius build --agnos src/main.cyr build/x_agnos
error:lib/sandhi.cyr:1608: undefined variable 'SYS_FCNTL' (missing include or enum?)
```

(Line 1608 is the concatenated `dist/sandhi.cyr` bundle; real source is `src/http/conn.cyr`.)
The Linux/macOS host build at 6.2.6 is **clean** — the gap is agnos-target-only.

## Root cause — the raw-syscall sites (real source, file:line)

### `src/http/conn.cyr` — client connect timeout machinery
| Site | Syscall(s) | Role |
|------|-----------|------|
| `_sandhi_conn_connect_nb_a` @325 | `SYS_FCNTL` (×7), `SYS_POLL`, `SYS_GETSOCKOPT` | IPv4 non-blocking connect: set `O_NONBLOCK`, `sock_connect`, `poll(POLLOUT, timeout_ms)`, read `SO_ERROR`, restore blocking |
| `_sandhi_conn_connect_sa_nb_a` @451 | `SYS_FCNTL` (×8), `SYS_CONNECT` @456 | sockaddr-based nb-connect (v6) — same machinery |
| `_sandhi_conn_open_v6_fully_timed_a` @638 | `SYS_SOCKET` @644 (`AF_INET6,SOCK_STREAM`), `SYS_CONNECT` @662 | raw IPv6 socket create + blocking connect fallback |
| `_sandhi_conn_open_v6_fully_timed_with_early_data_a` @677 | `SYS_SOCKET` @684, `SYS_CONNECT` @702 | same, early-data variant |
| @292 | `SYS_SETSOCKOPT` | `SO_RCVTIMEO`/`SO_SNDTIMEO` per-op read/write deadlines |

### `src/server/mod.cyr` — async listen fd
| Site | Syscall(s) | Role |
|------|-----------|------|
| @804-805 | `SYS_FCNTL` (×2) | put listen fd in `O_NONBLOCK` so the accept queue drains cooperatively (EAGAIN ends the drain) |

Constants defined locally in `conn.cyr`: `_SANDHI_SYS_POLL=7`, `_SANDHI_SYS_GETSOCKOPT=55`,
`_SANDHI_F_GETFL=3`, `_SANDHI_F_SETFL=4`, `_SANDHI_O_NONBLOCK=0x800`, `_SANDHI_EINPROGRESS=115`
— all Linux x86_64 ABI numbers (the @1510 comment already flags aarch64 divergence).

## Why this is bounded (not a rewrite)

- The TLS seam is already abstract — no change there.
- DNS + mDNS already use the portable `sock_*` wrappers — no change there.
- Even the IPv4 nb-connect already calls the portable `sock_connect`; only the
  `fcntl`+`poll`+`getsockopt` *wrapper* around it is Linux-shaped.
- AGNOS sockets are **blocking** and have no readiness-poll surface. So on agnos the entire
  timeout machinery collapses to a plain blocking `sock_connect` — which is exactly the
  `connect_ms == 0` path the code already documents (`conn.cyr:393-395`).

## Recommended fix

Introduce one transport seam and give it a Linux impl (current machinery) + an agnos impl,
rather than scattering `#ifdef`s. Suggested shape:

```cyrius
# bounded connect — returns _SANDHI_CONN_NB_{OK,TIMEOUT,ERR}
fn _sandhi_connect_bounded_a(a, fd, addr, port, timeout_ms): i64 {
#ifdef CYRIUS_TARGET_AGNOS
    # agnos: no fcntl/poll/SO_ERROR. sock_connect is blocking; the kernel's
    # own connect handling bounds it on LAN/QEMU/localhost. timeout_ms is
    # advisory here (documented degradation), same as the connect_ms==0 path.
    var cr = sock_connect(fd, addr, port);
    if (is_err_result(cr) == 0) { return _SANDHI_CONN_NB_OK; }
    return _SANDHI_CONN_NB_ERR;
#endif
#ifndef CYRIUS_TARGET_AGNOS
    ... existing fcntl/poll/getsockopt body ...
#endif
}
```

Per-primitive agnos mapping:
- **nb-connect** (`_sandhi_conn_connect_nb_a`, `_sandhi_conn_connect_sa_nb_a`) → blocking `sock_connect`; drop fcntl/poll/getsockopt.
- **`SYS_SETSOCKOPT` SO_RCVTIMEO/SNDTIMEO** (@292) → no-op on agnos (agnos `sock_recv` is non-blocking/poll-against-deadline at the caller, mirroring the `dig` backend; no kernel SO_*TIMEO analog).
- **IPv6 raw path** (`_sandhi_conn_open_v6_*`, `SYS_SOCKET AF_INET6` + `SYS_CONNECT`) → AGNOS net stack is **IPv4-only** today; the agnos branch should fail v6 cleanly (`_sandhi_conn_last_err = SANDHI_CONN_OPEN_CONNECT; return 0`) rather than reference a v6 socket API that doesn't exist. Revisit when agnos gains AF_INET6.
- **server listen-fd `O_NONBLOCK`** (`server/mod.cyr:804-805`) → agnos branch: skip the fcntl (blocking accept); the cooperative-drain model is Linux-async-specific and not exercised by client consumers like `sit`. Must still **compile**.

## Toolchain

Bump sandhi's pin `6.2.1 → 6.2.6` to develop the agnos branch (so the stdlib `sock_connect`
/ `tls_native` agnos peers resolve). Byte-identity for the Linux target across that range can
be confirmed the usual way (build same VERSION under both pins, `cmp`).

## Validation

1. `cyrius build --agnos` of a sandhi consumer (use `sit`) resolves with no undefined-symbol error.
2. Linux host build + `tests/` stay green (the seam must not regress the existing machinery).
3. End-to-end on the kernel: `sit` git-over-HTTP(S) clone in ring 3 (rides the same #46-50 TCP
   path `dig`/`yo` already validated; see `agnos/scripts/net-tool-smoke.sh` for the harness shape).

## Why now / impact

sandhi's own `state.md` scopes the next release: *"Closes the 1.4.x arc — next release shapes
against **sit adoption (1.5.x)**."* This gap **is** that work — it's the transport half of sit
adoption on AGNOS. It blocks, in order:

- **`sit` on agnos** (sovereign git-over-HTTPS + server) — directly.
- **`owl` on agnos** — transitively (owl bundles `dist/sit.cyr` for its VCS gutter, so every
  sandhi symbol must resolve even though owl calls no network code).
- **`whirl`** (curl/wget) — if it builds on sandhi's HTTP client rather than rolling raw sockets.

## Related

- Precedent: the chrono agnos gap (`cyrius/docs/development/issues/2026-06-14-chrono-agnos-monotonic-sleep-stale-stubs.md`) — same shape (Linux-stub on the agnos target), fixed in cyrius 6.2.6.
- AGNOS net-syscall surface: `cyrius/docs/development/proposals/2026-06-14-agnos-net-entropy-clock-syscalls.md` (#45-#57).
- Working agnos consumers proving the higher-level socket surface: `dig` 0.3.2, `yo` 0.5.4 (`src/platform_agnos.cyr` in each).

## Log

- **2026-06-14** — filed; surfaced by sit adoption on AGNOS. Tracked as 1.5.x
  Batch C1 (first concrete sit-adoption-driven item). The ≥6.2.6 pin prerequisite
  landed at sandhi 1.5.0.
- **2026-06-15** — **compile gap closed at sandhi 1.5.1.** Implemented the
  transport seam via per-site `#ifdef CYRIUS_TARGET_AGNOS` / `#ifndef` guards
  (not the single-fn `_sandhi_connect_bounded_a` of the "Recommended fix"
  sketch — per-site guards keep the Linux body verbatim and gave a provable
  byte-identical Linux binary, matching the stdlib `chrono`/`net` precedent).
  Agnos mappings applied exactly as this doc proposed: nb-connect → blocking
  `sock_connect`; SO_*TIMEO → no-op; v6 → fail-closed (IPv4-only); listen-fd
  fcntl compiled out. Validation: (1) Linux `programs/smoke.cyr` `cmp`-identical
  before/after; (2) standalone agnos probe — a guarded `SYS_FCNTL` compiles
  `--agnos`, an unguarded one reproduces `undefined variable 'SYS_FCNTL'`;
  (3) structural sweep — all 26 raw-syscall sites guarded, zero unguarded;
  (4) 992 `.tcyr` assertions + aarch64 cross-build still green. A full
  `cyrius build --agnos` of sandhi-from-source remains blocked on the upstream
  `lib/mmap.cyr` `CLONE_VM` stub and the A1 native-`SSL_CTX_*` retirement —
  neither is C1's scope; both tracked (CHANGELOG [1.5.1] "Known follow-ups",
  roadmap C2/A1). The `/dev/urandom` DNS-entropy site in `resolve.cyr` compiles
  on agnos but is a latent runtime gap → roadmap C2.
