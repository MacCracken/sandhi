# 2026-10-04 — the native TLS server decodes a PEM private key on every accept, on the global heap

**Status:** ✅ **Fixed in cyrius 6.6.16** (see *Resolution* at the end; recorded by cyrius 2026-10-05). The doc/probe follow-ups are [`2026-10-05-adopt-cyrius-6616.md`](2026-10-05-adopt-cyrius-6616.md) item 5. Was: open — cyrius-side (stdlib `lib/tls_native_hs13.cyr` + sigil `pem_decode_privkey`).
**Severity:** **P3** — unbounded but slow heap growth in a long-running HTTPS server; no correctness or
security impact. A DER key avoids it entirely.
**Reporter:** sandhi (found while measuring the 1.10.7 pooled-TLS per-request arena fix).
**Toolchain:** cyrius 6.6.15 (sigil 3.13.9 in its snapshot).
**Affects:** every server that hands `tls_accept_alloc_in` (or `tls_accept_alloc`) a **PEM** key. In sandhi
that is `sandhi_server_run_tls` / `sandhi_server_run_pooled_tls` with a PEM key in
`sandhi_server_options_tls`.

## What happens

The server credentials are passed to the handshake on every accept. For each one:

1. `lib/tls.cyr:1214` calls `tls_native_server_load_creds(nctx)`.
2. `lib/tls_native_hs13.cyr:1221` (`_tn_load_privkey`) calls sigil's auto-detecting
   `pem_decode_privkey(key, key_len, kmat, 48, &ao)` for any key that is not raw DER.
3. `lib/sigil.cyr:20456` (`pem_decode_privkey`): `var pool = alloc(pem_len);` — from the **global** bump
   allocator, which never frees, and not from the arena the server passed to `tls_accept_alloc_in`.

So every TLS accept leaves `pem_len` bytes (rounded to 8) on the global heap.

## Measured (sandhi 1.10.7, cyrius 6.6.15)

`programs/_server_tls_probe.cyr` check [8] reads the server process's `alloc_used()` before and after 40
HTTPS requests to `sandhi_server_run_pooled_tls` with a per-request arena configured, so every sandhi-side
allocation is rewound:

- Ed25519 `key.pem` (119 bytes): **120 B per request**, all of it this decode.
- The same key as DER: **0 B per request**.

## Workaround (consumer side, today)

Pass the private key as DER (`openssl pkey -in key.pem -outform DER -out key.der`). The native loader takes
raw DER (0x30) without calling the PEM decoder.

## Proposed fix (cyrius-side)

Either:

- decode into the allocator the handshake was given (the per-connection arena that
  `tls_accept_alloc_in` already threads), so the bytes are reclaimed with the connection; or
- decode the key once per server credential set and reuse the DER, since the PEM never changes between
  accepts.

Post-fold note: sandhi composes `tls_accept_alloc_in` and does not decode keys itself (ADR 0001), so this
is not patched in sandhi; the guide (`docs/guides/server.md`, Options) recommends a DER key meanwhile.

## Resolution — cyrius 6.6.16 (recorded by cyrius, 2026-10-05)

⛔ Do not push or tag a sandhi that pins cyrius 6.6.16 until cyrius 6.6.16 is out.

**Resolved in cyrius 6.6.16 (bite thr-2), entirely cyrius-side; sandhi needs no code change.** cyrius copied
this filing as `docs/development/issues/2026-10-04-sandhi-tls-server-pem-key-decoded-per-accept.md` and
archives it at the 6.6.16 close. The native TLS stack decodes a PEM private key once per process per distinct
key text, not on every accept:

- the first load of a text decodes it and caches sigil's answer on the global heap;
- every later accept copies that answer into its own ctx, inside the arena `tls_accept_alloc_in` was given.

The cache is keyed on the text, so sandhi's per-accept creds struct on the worker's stack is fine as it is.
Keys load and are refused exactly as before; at most 32 distinct key texts are cached.

Measured with sandhi's `programs/_server_tls_probe.cyr`, unmodified, built against the 6.6.16 tree: [8] reads
**0 B/request** where it read 120; `alloc_used()` is identical before and after the 41 requests; all eight
checks PASS, [4]'s 16 concurrent handshakes included. (The libssl backend is unaffected: it never decoded PEM
keys and still takes DER keys only.)

Follow-ups (the `docs/guides/server.md` DER-key bullet and tightening probe [8] to `per == 0`) are in
[`2026-10-05-adopt-cyrius-6616.md`](2026-10-05-adopt-cyrius-6616.md). Move this file to `archive/` when they
land.
