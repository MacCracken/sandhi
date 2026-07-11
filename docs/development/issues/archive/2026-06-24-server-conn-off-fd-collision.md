# 2026-06-24 — server/client `SandhiConnOff` symbol collision zeroed the client fd

**Status:** fixed in sandhi 1.6.13 (`src/server/mod.cyr`).
**Severity:** critical — every plaintext client request silently failed.
**Reported via:** thoth → hoosh roundtrip ("request prints to the terminal,
hoosh receives nothing").

## Symptom

A thoth turn against a local hoosh gateway printed the raw HTTP request to the
user's terminal and reported `hoosh stream error: CONNECT`, while hoosh logged
zero inbound requests. The TCP connection itself succeeded (the server saw an
accept), but the request bytes never reached the socket.

## Root cause

Two enums named `SandhiConnOff` coexisted with the **same member names but
different offsets**:

| Symbol | `src/http/conn.cyr` (client) | `src/server/mod.cyr` (server) |
| --- | --- | --- |
| `SANDHI_CONN_OFF_KIND`    | 0  | 0  |
| `SANDHI_CONN_OFF_FD`      | **8**  | **16** |
| `SANDHI_CONN_OFF_TLS_CTX` | 16 | —  |
| `SANDHI_CONN_OFF_HANDLE`  | —  | 8  |

cyrius resolves duplicate file-scope symbols as **last-definition-wins** (and
warns `duplicate symbol … redefined with conflicting value`). The server enum is
bundled after the client enum in `dist/sandhi.cyr`, so every reference to
`SANDHI_CONN_OFF_FD` — including the client path's — resolved to **16**.

In `_sandhi_conn_finalize_with_early_data_a` the stores run in order:

```
store64(conn + SANDHI_CONN_OFF_FD,      fd);       # offset 16 ← real fd (e.g. 3)
store64(conn + SANDHI_CONN_OFF_TLS_CTX, tls_ctx);  # offset 16 ← 0, CLOBBERS fd
```

So `sandhi_conn_fd(conn)` returned 0. `sandhi_conn_send_all` then `sys_write`'d
the request to **fd 0**: in a pipe that fails; in an interactive tty fd 0 is the
read/write terminal device, so the request echoed onto the screen. The real
socket (connected during open) received nothing and leaked until process exit.

This was nondeterministic-looking at the surface (sometimes an empty request,
sometimes the full request on screen, sometimes a bare `\r\n\r\n`) because the
downstream behavior depended on what fd 0 happened to be — but the cause was a
single deterministic offset collision.

## Fix

Namespace the server struct's offset members so they no longer share names with
the client struct:

- `enum SandhiConnOff` → `enum SandhiServerConnOff` (in `src/server/mod.cyr`)
- `SANDHI_CONN_OFF_KIND/HANDLE/FD` → `SANDHI_SRVCONN_OFF_KIND/HANDLE/FD`

The shared kind *values* (`SANDHI_CONN_PLAIN = 0`, `SANDHI_CONN_TLS = 1`) are
identical in both structs and stay shared — only the struct-layout offsets were
in conflict. All call sites for the renamed symbols live in `src/server/mod.cyr`.

## Verification

thoth pinned against the regenerated `dist/sandhi.cyr` (1.6.13) and streamed a
full completion from a live hoosh gateway on `127.0.0.1:8088`.

## Follow-ups

- A duplicate-symbol-with-conflicting-value across struct-offset enums should
  arguably be a hard error (not a warning) for offset/layout constants. Filed as
  a cyrius-side observation; sandhi's own guard is the namespacing above.
- Audit sandhi for any other cross-module enum/`var` name reuse that relies on
  last-definition-wins (the build also warns on `ERR_IO` and `chacha20_xor`).
