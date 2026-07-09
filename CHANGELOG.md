# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.7.3] — 2026-07-09

**Cyrius language pin `6.4.32` → `6.4.33`.** Completes the 1.7.2 pin refresh: 1.7.x's
native-TLS large-response fix depends on the partial-record `READ_HOLD` hold buffer,
which shipped in cyrius **6.4.33** (not the 6.4.32 that 1.7.2 pinned) — so a consumer
building against pristine 6.4.32 stdlib would still hit the original bug. Validated:
`cyrius deps` + the native `CYRIUS_DCE=1 cyrius build programs/smoke.cyr` link proof
pass clean against 6.4.33, and the `READ_HOLD` offsets are present in the resolved TLS
stdlib. No source or dist behavior change beyond the version string.

## [1.7.2] — 2026-07-09

**Cyrius language pin refreshed `6.3.5` → `6.4.32`.** A maintenance bump keeping
sandhi's toolchain pin current with the shipping cyrius release (the pin had
trailed by a full minor). Validated: `cyrius deps` + the native `CYRIUS_DCE=1
cyrius build programs/smoke.cyr` link proof pass clean against 6.4.32 — only the
always-tolerated `sys_chdir` / `random_bytes` unreachable-undefs remain on the
native path; the deprecated `-D CYRIUS_TLS_LIBSSL` backend's reachable-undef
warnings are unchanged and non-gating (cyrius issue
`2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x`, retires at sandhi 2.0). No
source or dist behavior change beyond the version string — the 1.7.1 native-TLS
record-layer fix ships unchanged.

## [1.7.1] — 2026-07-09

**Native-backend HTTPS large responses now work (root cause + efficiency
companion to a cyrius stdlib TLS fix).** Fetching any real-world HTTPS URL over
the **sovereign native TLS backend** failed for responses whose body arrived in a
full 16 KB TLS record (i.e. essentially every non-trivial page); small responses
(e.g. `example.com`) slipped through, so the failure looked host-specific but was
purely **response-size**-dependent. Root-caused to the stdlib native TLS record
layer (see below); consumers on the libssl backend were unaffected, which is why
the bote/daimon web tools masked it behind a libssl fallback.

### Changed — `src/http/pool.cyr`

- **`_sandhi_http_recv_framed` reads in whole-TLS-record steps** (`step` 4096 →
  16384). This is an **efficiency** change, not a correctness one: the native
  `tls_read` now delivers partial records and holds any remainder (like libssl
  always has), so a sub-record `ask` is correct — but a record-sized `ask` lets
  each `tls_read` return a whole record in one call instead of several
  hold-buffer slices, cutting recv/decrypt round-trips on large responses. (The
  prior 4096 step is what first *exposed* the stdlib bug: a full record could not
  be delivered into a 4 KB ask.)

### Requires — cyrius stdlib TLS fix (folds into the toolchain)

The load-bearing fix is in the **stdlib native TLS module** (`lib/tls_native_*`),
which sandhi vendors from the toolchain — it is **not** sandhi-owned source, so it
ships via a cyrius toolchain release, not this crate. Two defects, both fixed:

- **Off-by-one in the record-decrypt output buffer** (`tls_native_read` /
  `tls_native_record_open`). A maximum-size TLS 1.3 record decrypts to an inner
  plaintext of `content(2^14) + inner-content-type byte` = **16385** bytes, but
  the decrypt scratch + `out_max` were sized at `TLS_RECORD_MAX_PLAINTEXT`
  (16384). Any peer sending a full record tripped `TLS_ERR_BUFFER_FULL`,
  discarding the decrypted record **after** its AEAD sequence had advanced —
  wedging the connection. Fixed by sizing the decrypt buffer to
  `TLS_RECORD_MAX_CIPHERTEXT` (16640) and re-asserting the RFC 8446 §5.4 content
  limit with an explicit `record_overflow` guard.
- **`tls_native_read` now delivers partial records.** It buffered "whole record
  or `TLS_ERR_BUFFER_FULL`", so a caller reading in sub-record chunks (an h2
  9-byte frame header, the tail of a bounded response buffer, any small ask)
  still wedged and silently lost the decrypted record. It now delivers up to
  `maxlen` and **holds the remainder** in the ctx, honoring its documented "up to
  maxlen" contract for every caller and chunk size.

Verified end-to-end on the native backend against real hosts (anthropic.com,
secureyeoman.ai, robertmaccracken.com, cyriusb.com — 200 with byte-lengths
identical to libssl) and via sub-record reads down to a 9-byte ask. Two
independent adversarial reviews (the first caught an incomplete first cut).

## [1.7.0] — 2026-06-29

**Two yeo-cy-test (SecureYeoman → Cyrius) consumer-filed bugs + cyrius pin
`6.2.37 → 6.3.5`.** Both surfaced adopting `sandhi_server_run_pooled_tls` + the h2
client against folded sandhi in cyrius 6.3.x. The pin bump is a parity move (the
fixes are pure sandhi-side composition; no new cyrius primitive), but 6.3.x's
linker now **refuses to emit a binary with reachable-undefined functions** (was a
NOP'd warning), which surfaced an incomplete include list in `tests/alloc.tcyr`.

### Fixed — `src/http/h2/dispatch.cyr`

- **h2-promote IPv6 conn-open arity.** The h2-promotion IPv6 branch called the
  9-arg `_sandhi_conn_open_v6_fully_timed_a` with only 8 args — it missed the
  trailing per-call request `ctx` added in the 1.6.9 thread-safety change (the
  IPv4 sibling and `client.cyr`'s IPv6 call were updated; this branch was missed).
  Result: a build warning for every consumer (`expects 9 arguments, got 8` out of
  the folded `dist/sandhi.cyr`) and, on the IPv6 + h2-promote client path, the 9th
  slot read as a garbage `ctx`. h2-promote threads no request context, so it now
  passes `0` (the ctx==0 fallback — identical to what the IPv4 sibling's public
  `sandhi_conn_open_fully_timed_a` defaults to). Closes
  `docs/development/issues/2026-06-28-h2-promote-v6-conn-open-arity.md`.

### Fixed — `src/server/mod.cyr` (doc-correctness) + `programs/_server_tls_probe.cyr`

- **Misleading `sandhi_server_run_pooled_tls` concurrency comment.** The header
  claimed concurrent TLS handshakes were "validated by the live gate" and that
  "the only shared mutable state is the CAS-locked allocator" — both false. The
  gate's [1]-[3] checks are *sequential* handshakes plus a *plaintext* isolation
  socket, so genuinely-simultaneous handshakes were never exercised; and the TLS
  handshake drives sigil, whose crypto primitives use process-global scratch — so
  two parallel handshakes race → ECONNRESET/SIGSEGV. The comment invited consumers
  to set `max_conns > 1` for HTTPS and inherit a crash. Corrected to state
  concurrent TLS handshakes are **not yet safe**, recommend `max_conns = 1` for the
  TLS pool, and cross-reference the upstream sigil issue
  (`2026-06-28-concurrent-tls-handshake-global-scratch-race`). The plaintext pool
  `sandhi_server_run_pooled` is unaffected (no sigil scratch on its path). Root
  crash is sigil's; this is the doc/gate-correctness half. Closes
  `docs/development/issues/2026-06-28-pooled-tls-misleading-concurrency-comment.md`.
- **Gate now exercises concurrent handshakes (`[4]`, non-gating watch).**
  `_server_tls_probe.cyr` gained a `[4]` check that forks pairs of clients
  handshaking at the same instant — the multi-worker pool's core promise. Because
  the underlying race is an unfixed upstream sigil defect, `[4]` reports a
  **KNOWN-LIMITATION** and does **not** fail CI (a shortfall is expected today;
  live run: 0/16 survived, confirming the crash). When sigil is fixed all pairs
  survive and the watch should be promoted to gating (instructions in the `[4]`
  block). `[3]` relabelled "accept-loop isolation" since its silent socket is
  plaintext, not a concurrent TLS handshake.

### Fixed — `tests/alloc.tcyr`

- **Complete the include list for cyrius 6.3.x's stricter linker.** 6.3.x refuses
  to emit with reachable-undefined functions; the subset suite included the h2
  dispatch path but not `src/tls_policy/apply.cyr` (policy pre/post-open helpers)
  or `src/tls_policy/alpn.cyr` (`sandhi_conn_alpn_is_h2`) it references. Added both
  (mirrors `tests/sandhi.tcyr`); no assertion change (342 still green).

### Toolchain

- **cyrius pin `6.2.37 → 6.3.5`.** Parity bump to latest; clean deps re-resolve
  (`rm -rf lib cyrius.lock && cyrius deps`), all four suites green (1112
  assertions: sandhi 540 / h2 167 / alloc 342 / rpc 63), native DCE build OK,
  lint 0/0.
- **Deprecated libssl smoke build is now non-gating in CI.** 6.3.x's
  reachable-undefined linker error fails the `-D CYRIUS_TLS_LIBSSL` link-proof:
  the libssl config leaves 4 of sigil's transitive crypto symbols
  (`thread_local_init/set/get`, `ct_select`) reachable-but-unlinked — a cyrius-side
  DCE artifact of the libssl `#ifdef`, NOT a sandhi/sigil source defect (the native
  build links them all and is the real link proof). The CI step is now
  `continue-on-error`; filed cyrius-side
  (`issues/2026-06-29-cyrius-libssl-dce-reachable-undef-6.3.x.md`), and the step
  drops entirely at the 2.0 libssl retirement. No source/FFI workaround.

## [1.6.13] — 2026-06-24

**Client connections silently lost their socket fd (server/client `SandhiConnOff`
symbol collision).** `src/server/mod.cyr` defined an `enum SandhiConnOff` whose
members reused the exact names of the client conn struct's enum in
`src/http/conn.cyr` — but with different offsets (`SANDHI_CONN_OFF_FD = 16` server
vs `8` client). Under cyrius single-pass "last definition wins", every client TU
resolved `SANDHI_CONN_OFF_FD` to `16`, colliding with the client's own
`SANDHI_CONN_OFF_TLS_CTX = 16`: `_sandhi_conn_finalize_*` wrote the real fd at
offset 16, then immediately wrote `tls_ctx` (0) to the same slot, zeroing the fd.
Result: every client request (`sandhi_http_post` / `sandhi_http_stream`) went to
**fd 0** instead of the socket — connect succeeded, but the gateway received
nothing (and in an interactive tty the raw request echoed to the screen). Fix:
namespace the server struct's offsets to `SANDHI_SRVCONN_OFF_*` (enum renamed
`SandhiServerConnOff`) so the names no longer collide; the kind values
(`SANDHI_CONN_PLAIN`/`_TLS`, identical in both) stay shared. **`src/server/mod.cyr`
only; pin stays 6.2.37.** See `docs/development/issues/2026-06-24-server-conn-off-fd-collision.md`.

## [1.6.12] — 2026-06-23

**Default mDNS resolver now actually receives (QU two-socket fix).** The default
unicast-response (QU) `.local` resolver `sock_connect`ed to the mDNS group then
`sock_recv`ed on the *same* socket — so Linux's connect()-source-filter dropped
every reply (the answer arrives from the responder's own unicast IP, not the
group: the 1.5.4 bug, never fixed on the QU path). A second latent bug compounded
it: the query used a random TXID, but mDNS responses carry ID=0 (RFC 6762 §18.1),
so even a received reply would have been rejected on ID mismatch. The 1.5.5 QM
fix didn't transfer trivially — a QU reply is unicast to the *querier's source
port*, not the group — so this needed a tailored two-socket setup. **`src/discovery/local.cyr`
only; pin stays 6.2.37.**

### Fixed — `src/discovery/local.cyr`

- **Two-socket QU receive.** Factored a shared `_sandhi_local_query_2sock_a(a,
  name, qclass_hi, tx_port)` helper (the module was reordered so the RX/recv
  helpers precede the default resolver). RX is **unconnected**, bound to 5353 +
  `SO_REUSEPORT` + group-joined — it sees the answer from any source. TX is
  connected to the group (send-only). For QU it binds the TX to **5353** so the
  responder's unicast reply lands on the RX's port; the connect()-filter on the TX
  rejects that reply (source ≠ group), so it falls to the unconnected RX. The
  group-join also catches a multicast answer. Query **ID = 0** now. The opt-in QM
  resolver (1.5.5) now shares this helper (`qclass_hi=0x00, tx_port=0` — ephemeral
  TX; byte-identical behaviour, verified by its existing loopback gate).
- **`sandhi_discovery_local_available()` is AGNOS-aware** (returns 0 on AGNOS).
  The default resolver now joins the multicast group, so it shares the QM
  resolver's AGNOS limitation (the net multicast helpers return −1 there → a clean
  miss); Linux/macOS unchanged (1). No verb signature change.

### Verified

- **1112 assertions green** (sandhi 540 / h2 167 / alloc 342 / rpc 63; sandhi 539
  → 540: the new `discovery/local/qu_unicast` loopback gate — an unconnected RX
  bound to a port receives a **unicast** datagram even with a connected TX
  coexisting on the same port via `SO_REUSEPORT`, the dispatch crux; a regression
  to a single connect()ed socket drops the reply and fails it). The QM loopback
  gate + the discovery smoke still pass (no regression from the refactor). Smoke +
  `CYRIUS_DCE=1` builds OK; `cyrius lint src/discovery/local.cyr` 0/0;
  `dist/sandhi.cyr` regenerated at v1.6.12. **Live-LAN note**: validation is via
  the loopback dispatch gate (the same standard 1.5.5 used) + the structural
  argument — this environment had no mDNS responder reachable (avahi-daemon not
  running). Closes the Batch C QU-mDNS item.

## [1.6.11] — 2026-06-23

**Native custom-trust-store enforcement proven by VERIFY-fail, not just
load-fail.** The 1.6.0 live gate proved native enforces a custom trust store by
*refusing* a bogus one — but via a **load failure** (`[4]` passes
`/nonexistent/ca.pem`, so the open aborts pre-handshake when the file can't
load). That left the actual question unproven: does native *verify the server
chain against the custom anchor*, or could the system trust leak through? This
adds the stronger proof. **Test-only — no `src/` change, no public surface
change, no new fixture.**

### Added — `programs/_policy_runtime_probe.cyr`

- **Gate `[5]` — loadable-but-wrong CA → handshake verify-fail.** Sets the custom
  trust store to `programs/_tls_fixtures/cert.pem` — a real, parseable Ed25519
  cert (already the `_server_tls_probe` client trust anchor, so proven-loadable)
  that signs the *local* fixture, **not** one.one.one.one. So the store loads
  cleanly, and — verified live on cyrius 6.2.37 — the custom store **replaces**
  the system trust, so the public CA that actually signs one.one.one.one is no
  longer trusted and the chain verification rejects: the open is refused with
  `err=TLS`. Opening here would mean native loaded the custom anchor but never
  verified against it (system store leaked through, or verify skipped) — a
  security regression `[4]`'s load-fail case cannot catch. New exit code `6`
  (loadable wrong-CA opened → security). Closes the Batch C native-trust-store
  verify-fail wiring-proof item.

### Verified

- The gate runs green live against **1.1.1.1 / one.one.one.one:443** on cyrius
  6.2.37 (`[2]` default round-trip, `[3]` wrong-pin fail-closed, `[4]`
  bogus-CA load-refuse, **`[5]` loadable-wrong-CA verify-fail** — ALL GATES PASS,
  exit 0); skip-cleanly offline. **1111 unit assertions unchanged** (this is a
  standalone live-gate program, not part of the `.tcyr` suites). The
  replace-vs-append semantics the roadmap flagged are now empirically settled:
  **replace** (a custom anchor that doesn't sign the server fails the handshake).
  Pin stays **6.2.37**.

## [1.6.10] — 2026-06-23

**Server-TLS handshake rides the `lib/tls.cyr` contract (flat RSS).** 1.6.8's
server-TLS handshake bootstrap (`_sandhi_server_tls_handshake`) reached past the
backend-agnostic contract into the native server primitives
(`tls_native_new_server` / `_set_alpn` / `_server_load_creds` / `_accept`),
because `lib/tls.cyr` exposed `tls_connect*` but no symmetric server handshake —
and the native server ctx was bump-allocated with no per-connection free, so a
long-running TLS server's RSS grew per accepted connection. Both were filed
cyrius-side; **both prerequisites landed at cyrius 6.2.37** (already the 1.6.9
pin), so this patch adopts them. No new pin, no public surface change — a pure
internal refactor of `src/server/mod.cyr`.

### Changed — `src/server/mod.cyr`

- **Handshake migrated onto `tls_accept_alloc_in` + `tls_accept_complete`** (the
  symmetric mirror of the client `tls_connect_alloc` / `_complete`). The bootstrap
  (`_sandhi_server_tls_handshake_a`) now packs the borrowed DER cert/key into the
  4-slot creds struct and drives the handshake through the contract — **no
  native-server symbol is reached anymore**. ALPN (`http/1.1`) rides the **same**
  backend-agnostic `_sandhi_alpn_hook` + `_sandhi_alpn_h11_wire` the client uses
  (`tls_set_alpn` dispatches the backend), so the server- and client-side ALPN
  paths are now one mechanism. Closes the filed
  `2026-06-18-lib-tls-cyr-no-server-handshake-wrapper`.
- **Flat RSS via a per-connection arena.** `tls_accept_alloc_in(a, …)` backs the
  native server ctx + the whole per-handshake/record footprint + the shim (and the
  `SandhiConn`) from a caller arena. Both serve loops (`sandhi_server_run_tls`
  single-flight + each `sandhi_server_run_pooled_tls` worker) now allocate **one**
  `arena_allocator(SANDHI_SERVER_TLS_ARENA_CAP)` (128 KiB — the contract's
  worst-single-handshake guidance; sandhi serves plain server TLS 1.3, no mTLS) and
  `reset_via` it per connection. Per-connection RSS growth is gone; a pooled server
  is `workers × 128 KiB` fixed for its TLS arenas. Closes the filed
  `2026-06-18-tls-native-server-ctx-not-arena-aware`.

### Verified

- **1111 assertions unchanged** (539 / 167 / 342 / 63 — this is a behavior-
  preserving refactor of a live-socket path the unit suite doesn't exercise; no
  new unit assertion was warranted). The proof is the existing CI live gate
  `programs/_server_tls_probe.cyr`, re-run green against the migrated path: a
  pooled TLS server over real **TLS 1.3** with Ed25519 fixtures — trusted burst
  **8/8 → 200+body** (ALPN negotiated through the reused hook), untrusted
  default-policy client **rejected** (cert verify not bypassed), worker-pinned
  isolation 8/8, all across `reset_via`'d connections. Smoke + `CYRIUS_DCE=1`
  builds OK; `cyrius lint src/server/mod.cyr` 0/0; `dist/sandhi.cyr` regenerated at
  v1.6.10. Pin stays **6.2.37**.

## [1.6.9] — 2026-06-23

**Client dispatch is thread-safe under concurrent workers (thoth bite).** The
buffered HTTP client stashed four pieces of per-request state in **module
globals** — set on entry to a dispatch, read deep in the connect path: the
0-RTT opt-in (`_sandhi_allow_0rtt`), the credential digest for the session-cache
key (`_sandhi_cred_digest`), the pending TLS policy (`_sandhi_tls_policy_pending`),
and the open-error classification (`_sandhi_conn_last_err`). The save→write→call→restore
idiom is correct for the single-threaded redirect recursion it was built for, but
two dispatches on separate OS threads race the shared word — surfaced by **thoth**
(the agentic-coding TUI) designing N concurrent `sandhi_http_post_a` workers over
`lib/thread.cyr`. The dangerous one is the credential digest: worker A could do its
TLS session lookup/store under worker B's digest, cross-wiring resumption state
between differently-credentialed requests. cyrius pin `6.2.22 → 6.2.37` (parity
bump to latest; the fix is pure sandhi-side composition — no new primitive).

### Fixed — per-call request context (`src/http/conn.cyr`, `src/http/client.cyr`, `src/tls_policy/apply.cyr`)

- **Lifted the four globals into a per-call context** threaded through the
  buffered dispatch path. `_sandhi_http_dispatch_a` arena-allocates a small
  32-byte context (`SANDHI_REQCTX_*`), fills the 0-RTT opt-in / cred-digest /
  TLS policy, and threads a pointer through `_sandhi_http_do_a` →
  `_sandhi_http_follow_a` → `_sandhi_http_do_impl_a` → the conn-open functions →
  `_sandhi_conn_finalize_with_early_data_a` (+ the policy `_sandhi_policy_pre_open_a`
  / `_post_open_a` helpers). The connect path now classifies its open error into
  that context and `do_impl` reads it back from there, instead of the shared
  `_sandhi_conn_last_err`. With distinct per-request arenas + fresh connections,
  concurrent `sandhi_http_*_a` workers are now structurally safe.
- **`_sandhi_reqctx_*` accessors** (`conn.cyr`) encapsulate the lift: each takes a
  `ctx` and falls back to the module global when `ctx == 0`, so **every
  single-threaded caller is byte-identical**. The public conn-open verb
  `sandhi_conn_open_fully_timed_a` becomes a `ctx=0` wrapper over a new internal
  `_sandhi_conn_open_fully_timed_ctx_a`; `sandhi_conn_last_open_err()` and the
  streaming / download / h2-auto / `sandhi_conn_open_with_policy` paths keep
  reading/writing the globals exactly as before. **No public surface change** —
  no new public verb, no API break.
- **Correctness bonus (single-threaded too):** routing the TLS-policy SPKI-mismatch
  error through the context fixed a latent misclassification — on the ctx path a
  pinned-cert mismatch in `_sandhi_policy_post_open_a` would otherwise have been
  reported as `CONNECT` instead of `TLS`.

### Scope / known limits

- The fix covers the **buffered dispatch path** (`sandhi_http_get`/`_post`/… and
  their `_a` variants) — thoth's exact workload. The **h2-auto path**
  (`sandhi_http_request_auto_a`) and the **policy hook-override** globals
  (`_sandhi_tls_hook_override*` / `_sandhi_alpn_advertise_h2`) are only armed on
  the h2-auto / policied-HTTPS paths, which no consumer drives concurrently;
  those remain single-threaded (a documented follow-on, not thoth's path). The
  client connection-**pool** is still single-threaded (pre-existing
  wait-for-consumer roadmap item).

### Verified

- **1111 assertions green** (sandhi 539 / h2 167 / alloc 342 / rpc 63; sandhi
  525 → 539: the new `_sandhi_reqctx_*` mechanism — ctx==0 global fallback +
  per-call isolation, proving a context's open-error / cred-digest don't leak
  into a sibling context or the module global). Smoke + `CYRIUS_DCE=1` builds OK;
  `cyrius lint src/*.cyr` 0/0; `dist/sandhi.cyr` regenerated at v1.6.9. Clean deps
  re-resolve on the new pin (`rm -rf lib cyrius.lock && cyrius deps`); all four
  suites green on 6.2.37 both before and after the change.

## [1.6.8] — 2026-06-18

**Server-side TLS — sandhi can now SERVE HTTPS.** Closes the headline
yeo-cy-test bite ("sandhi has NO server-side TLS"): before 1.6.8 the serve
loops took only `{idle_ms, max_conns}` and every send path wrote plaintext via
`sock_send`, so the SecureYeoman probe had to bypass the serve loops entirely
and hand-roll an `accept → tls_native_accept → read → dispatch → write → close`
loop. SecureYeoman's entire auth stack (OIDC/PKCE, WebAuthn, tokens, secrets)
is meaningless over plaintext, so this is the highest-value server capability
that was missing. It ships on the **native** TLS stack (the default + future;
the libssl backend retires at 2.0 and never had a server side). cyrius pin
`6.2.19 → 6.2.22` (parity bump to latest; the feature is pure composition — no
new cyrius primitive required).

**Architecture (No-FFI intact).** All TLS I/O rides the backend-agnostic
`lib/tls.cyr` contract — `tls_write` / `tls_read` / `tls_close` on the standard
24-byte ctx shim `[inner_ctx, 0, fd]`. The one piece that contract does not yet
expose is a *server handshake* (it has `tls_connect*` but no symmetric
`tls_accept`), so the handshake bootstrap composes the native server primitives
(`tls_native_new_server` / `_set_alpn` / `_server_load_creds` / `_accept`) and
wraps the result in that shim. No FFI, no dlopen — pure native composition. A
`lib/tls.cyr` `tls_accept` wrapper (symmetric to the client `tls_connect_alloc`
/ `_complete` that already landed cyrius-side) is filed as a cyrius-side
follow-up; when it lands, this one bootstrap migrates onto it (exactly as
1.6.1/1.6.2 migrated `conn.cyr`'s raw socket syscalls onto `net.cyr` helpers).

### Added — server-side TLS (`src/server/mod.cyr`)

- **TLS server options.** `sandhi_server_options_tls(opts, cert, cert_len, key,
  key_len)` enables HTTPS by storing the server cert chain (leaf-first; **DER**
  for the native leaf parser) + private key (PEM or DER; **Ed25519 / ECDSA
  P-256 / P-384** — RSA is unsupported by the native server stack). Buffers are
  borrowed (must outlive the server). `sandhi_server_options_get_tls`.
- **Transport seam — `SandhiConn`.** A tiny tagged handle (`{kind, handle,
  fd}`) so one handler set serves both transports: `sandhi_server_conn_plain[_a]`
  (wrap a raw fd), `sandhi_server_conn_is_tls`, `sandhi_server_conn_fd`, and the
  seam `sandhi_server_conn_write(conn, buf, len)` (plaintext → looped `sock_send`;
  TLS → `tls_write`). `sandhi_server_recv_request_c` reads a full request over
  either transport.
- **Conn-aware response framing.** `sandhi_server_send_response_c[_a]` /
  `sandhi_server_send_status_c[_a]` — the fd-based `send_*` stay byte-identical
  for the plaintext path; these write through the seam so they work over TLS.
- **Conn-aware routing** (shares the SAME router table as the 1.6.7 fd path).
  `sandhi_router_dispatch_c` + `sandhi_server_router_handler_c` (for the `_tls`
  loops, which deliver a `SandhiConn`) + `sandhi_server_router_handler_cp` (a
  plaintext adapter that wraps the cfd in a plain conn) — so ONE conn-based
  route-handler set (`fn(app_ctx, conn, buf, blen, params)`, writing via
  `send_*_c`) serves both the plaintext loops and the TLS loops.
- **HTTPS serve loops.** `sandhi_server_run_tls` (single-flight, mirrors
  `run_opts`) and `sandhi_server_run_pooled_tls` (fixed worker-thread pool — TLS
  handshakes are CPU-heavy, so the pool is what makes HTTPS scale across cores).
  Each does its own per-connection handshake; same SIGPIPE / SO_RCVTIMEO /
  smuggling-reject guards as the plaintext loops. Handler shape `fn(ctx, conn,
  buf, blen)`.
- **`+18` public verbs.**

### Fixed — pooled handoff-channel depth (`src/server/mod.cyr`)

- **Accept backlog decoupled from worker count** (yeo-cy-test 🔵). New
  `sandhi_server_options_backlog` (default 128) sizes BOTH the kernel `listen`
  backlog AND the pooled handoff channel, instead of `run_pooled` sizing the
  channel to `max_conns` (the worker count). A burst beyond the worker count now
  queues up to `backlog` accepted connections instead of shedding to the kernel
  backlog immediately. Applied to `run_pooled` and `run_pooled_tls`.

### Known limitations (filed, not blocking)

- **Native server ctx is not arena-aware** — `tls_native_new_server` + the
  per-handshake buffers are bump-allocated with no per-connection free, so RSS
  grows per accepted TLS connection until an arena-aware native server ctx lands
  upstream (cyrius-side; roadmap). Correctness of serving is unaffected — the
  same property the proven probe shipped with.
- **h2 over TLS not served** — NOT an ALPN gap (native server-side ALPN
  selection landed at cyrius 6.2.22, so sandhi's `http/1.1` offer is genuinely
  negotiated). sandhi has no HTTP/2 *server* (its h2 is client-side only) and
  offers only `http/1.1`; an h2-over-TLS server is a separate, larger sandhi
  feature, not a cyrius prerequisite.
- **macOS server SIGPIPE guard** still open (ground-first: needs a macOS box +
  the stdlib `signal_ignore` helper) — unchanged from 1.6.6.

### Verified

- **1097 assertions green** (sandhi 525 / h2 167 / alloc 342 / rpc 63; sandhi
  503 → 525: TLS options + backlog decouple, conn-seam accessors + conn-aware
  send, conn-aware dispatch/handler 200/404/405) on the 6.2.22 pin.
- New live gate **`programs/_server_tls_probe.cyr`** (wired into CI): forks a
  pooled TLS server (Ed25519 fixtures) and drives it with sandhi's OWN client
  over real **TLS 1.3** handshakes — a trust-store-anchored burst 200s with the
  routed body, a default-policy client is **rejected** (cert verify not
  bypassed), and real requests still serve while a worker is pinned (pool
  isolation). Deterministic across repeated runs. DCE build OK; lint 0/0; cyrfmt
  clean; `dist/sandhi.cyr` regenerated at v1.6.8 (13828 lines).

## [1.6.7] — 2026-06-17

**The server side a real service needs: route table + thread-pool serve mode.**
Driven by **SecureYeoman** (via the yeo-cy-test → Cyrius port probe) — its
axum/Tokio backend needs path-param routing + real multi-core parallelism, so
both ship now rather than waiting for a second asker (same direct-consumer
trigger as the 1.6.4 takumi download). The two pair into "the server side a real
service needs"; both lifted from the probe's reference
(`secureyeoman/yeo-cy-test/src/httpd.cyr`) into sandhi's idiom. cyrius pin
unchanged (**6.2.19**) — pure composition of stdlib `thread` / `chan_*` /
`fnptr` + the existing server accessors; no new primitive.

### Added — server routing (`src/server/mod.cyr`)

- **Method+path route table with `:name` params.** `sandhi_server_route_match`
  (segment-by-segment match, exact literals + `:name` capture, equal-segment-count
  so `/api/notes` ≠ `/api/notes/:id`) into a caller-owned param buffer
  (`sandhi_route_params_init` on a per-request stack buffer — pool-safe, no alloc,
  no leak); `sandhi_route_param_count` / `_param_int` (non-negative decimal or `-1`
  for absent/empty/non-numeric → clean 400) / `_param_a` / `_param`. Plus a thin
  route table — `sandhi_router_new[_a]` / `sandhi_router_add` /
  `sandhi_router_dispatch` (first pattern+method match wins → `fncall5(fp, ctx,
  cfd, buf, blen, params)`; pattern-match-but-no-method → 405; none → 404) — and a
  ready-made `sandhi_server_router_handler` that plugs a router into ANY serve
  loop (`run` / `run_async` / `run_pooled`) via the standard `fn(ctx, cfd, buf,
  blen)` handler shape.

### Added — thread-pool server (`src/server/mod.cyr`)

- **`sandhi_server_run_pooled(addr, port, handler_fp, ctx, opts)`** — a fixed pool
  of `max_conns` worker threads (here `max_conns` is the **worker count**, not a
  per-drain cap as in `run_async`). The accept loop feeds accepted fds to a
  bounded channel; workers pull and serve one connection each, so a
  blocking/CPU-bound handler ties up only its own worker — true multi-core
  parallelism the single-flight `run` and cooperative `run_async` can't give. Same
  handler signature as `run` / `run_async` (so existing handlers and
  `sandhi_server_router_handler` drop straight in), same SIGPIPE guard (1.6.6) +
  per-connection SO_RCVTIMEO slow-peer bound + CL.TE / dup-header smuggling
  rejects. Per-worker recv buffer (no interleave); composes the thread-safe global
  `alloc`.

### Added — tests + live gate

- `tests/sandhi.tcyr` **475 → 503** (+28): `route_match` (exact / single + multi
  `:name` capture / both-direction segment-count mismatch / literal mismatch /
  non-absolute / empty `:name`), param accessors (`_param_int` numeric +
  non-numeric→-1 + oob→-1, `_param` string + oob→""), router table (add + cap-full
  → 0), and `router_dispatch` (matched route fires with `:id` captured, wrong
  method → 405 not-invoked, unknown path → 404 not-invoked, query stripped before
  match). Suite totals **1047 → 1075**.
- `programs/_server_pool_probe.cyr` — live gate that forks a **pooled + routed**
  server (4 workers, `GET /notes/:id`) and asserts end to end over loopback: route
  + `:id` capture (200), query stripped (200), unknown path (404), wrong method
  (405), an 8-request rapid burst, and **slow-client isolation** (a silent client
  pins one worker; the other workers still serve 8/8 — the whole point of the pool
  over the single-flight loop). New CI step.

### Notes

- **Server-only-drags-the-whole-client-surface** (the probe's third 🔵) is
  **closed as won't-fix on the sandhi side — it's a cyrius issue, not a sandhi
  one**: the ~400 KB of static h2/hpack/tls `.bss` a server-only consumer links is
  the toolchain's bundled-libs packaging + DCE-keeps-`.bss` behavior. No
  sandhi-side change fixes it (splitting sandhi into sub-libs would be sandhi
  inventing packaging the toolchain owns). Filed against cyrius; closed in our
  roadmap.
- New public verbs ship permanently into stdlib's `lib/sandhi.cyr` at the next
  re-fold; these 12 are earned by a concrete consumer (SecureYeoman) per the
  small-but-earned-surface discipline.

## [1.6.6] — 2026-06-17

**SIGPIPE DoS fix from the yeo-cy-test (SecureYeoman → Cyrius) server-adoption
probe.** cyrius pin **6.2.18 → 6.2.19**. yeo-cy-test ported its hand-rolled
`httpd.cyr` onto `sandhi_server_*` and, in doing so, surfaced one HIGH-severity
security bug plus a couple of doc rough edges. This release fixes them.

### Security — server (`src/server/mod.cyr`)

- 🔴 **HIGH: the HTTP server no longer dies of SIGPIPE when a client disconnects
  mid-response.** `net.cyr`'s `sock_send` is a bare `sys_write` with no
  `MSG_NOSIGNAL`, so a peer that sent a request line then closed (or dropped
  during the response write) raised SIGPIPE — whose **default disposition
  terminates the process**. A trivial unauthenticated remote DoS against any
  sandhi server (verified by the probe: signal 13). Both serve loops
  (`sandhi_server_run` / `_run_opts` and `sandhi_server_run_async`) now install
  `SIG_IGN` for SIGPIPE once at startup via `_sandhi_server_ignore_sigpipe()`; a
  send to a dead peer now fails with EPIPE on the `sock_send` (whose return both
  loops already ignore) instead of killing the process. Server-side and
  security-relevant (ADR 0004) — shipped without waiting for a second asker.
  - **Why a raw syscall here** (the one place the server path reaches past a
    stdlib helper): `sock_send` can't pass `MSG_NOSIGNAL` (no flags arg; forking
    the primitive is forbidden) and stdlib exposes no signal-disposition helper
    (no `signal_ignore`; SIGPIPE isn't even in the `Signal` enum). The proper
    long-term home — a stdlib `signal_ignore` / `sock_send` `MSG_NOSIGNAL` — is
    filed as a roadmap deferral; this migrates onto it when it lands, exactly as
    1.6.1/1.6.2 migrated `conn.cyr`'s raw socket syscalls onto `net.cyr` helpers.
  - **Portability**: `rt_sigaction(SIGPIPE, SIG_IGN)` on Linux (x86_64 syscall
    13 / aarch64 134; one 32-byte `{sa_handler=SIG_IGN, 0, 0, 0}` struct is
    correct for both ABIs since every field past `sa_handler` is zero). macOS /
    Windows: a documented no-op (the macOS ESYSXLAT whitelist doesn't cover
    `sigaction`, so a raw call would mis-dispatch) — see the new roadmap entry.
    AGNOS: moot (no signals; `sock_listen` Errs before the loop).

### Docs

- **`sandhi_server_run_async` stale leak comment corrected.** The function header
  still claimed it "leaks ~32 B/connection" via `lib/async.cyr` task structs,
  contradicting the inline 1.5.3 note + the `async_new_in(arena)` code that
  eliminated it. Rewrote the header to match: zero residual leak, RSS flat.
- **README gains a "Requires (companion stdlib modules)" note.** Cyrius libs are
  opt-in, so a consumer adding `sandhi` hits undefined `tls_*` / `async_*` /
  `random_*` / `fdlopen_*` / `dynlib_*` with no hint the fix is an extra dep;
  and `bayan` (not `json`) is the JSON module (both define `json_v_*`, so opting
  into both collides). The note lists the companion modules and the bayan-not-json
  rule. Pure documentation.

### Toolchain

- Cyrius pin **6.2.18 → 6.2.19**. Pure parity bump (no new primitive needed for
  this release — the SIGPIPE fix is a sandhi-side syscall); clean deps re-resolve
  (`rm -rf lib cyrius.lock && cyrius deps`), all four `.tcyr` suites green on the
  new pin.

### Tests

- `tests/sandhi.tcyr` **473 → 475** (+2): `_sandhi_server_ignore_sigpipe()`
  returns 0 (rt_sigaction success — proves the per-arch syscall number + struct
  layout are valid) and is idempotent. Suite totals **1045 → 1047**.

### Deferred (named roadmap entries — no silent scope-outs)

- **macOS server SIGPIPE guard** — the fix is Linux-only today; macOS needs the
  BSD `sigaction` ABI / `SO_NOSIGPIPE` and a macOS box to verify. Filed.
- **Stdlib `signal_ignore` / `sock_send` `MSG_NOSIGNAL`** — the proper home for
  the SIGPIPE guard; sandhi's raw syscall migrates onto it when it lands. Filed.

## [1.6.5] — 2026-06-17

**Live-network download gate + two bugs it caught.** Closes the 1.6.4 loose end:
a `programs/_download_probe.cyr` CI gate that proves a real **redirected binary
download round-trips to disk** end-to-end (the 1.6.4 coverage was unit-level only).
The gate immediately earned its keep by surfacing two defects the unit tests
couldn't — the value of an end-to-end probe over synthetic fixtures.

### Fixed — http/download (`src/http/download.cyr`)

- **Download no longer inherits the buffered client's 256 KiB size cap.** The
  download path read `opts.max_response_bytes` (default
  `SANDHI_HTTP_DEFAULT_MAX_BYTES` = 262144) and treated it as a hard ceiling —
  so a default-options download of anything larger than 256 KiB aborted with a
  spurious `SANDHI_ERR_PROTOCOL`, **defeating the feature's entire purpose** (a
  10.4 MB tarball died at ~256 KiB). `max_response_bytes` bounds an *in-memory*
  body buffer in the buffered client; a streaming download has no such buffer, so
  the field is now **deliberately ignored** on this path (documented in the module
  header). Consumers bound a download via the sink (return `<0`) or
  `opts.total_ms`; the timeout matrix + redirect cap + TLS policy are still
  honored. *(Found by the new gate: the 10.4 MB git-tag tarball now streams to
  disk in full — `bytes == Content-Length`, verified by read-back.)*

### Fixed — http/stream (`src/http/stream.cyr`)

- **Chunked decoder: re-sync on a split inter-chunk CRLF.** When a chunk's
  trailing `\r\n` arrived split across a buffer refill, the leftover byte(s)
  lingered at the head of the next size line; `_sandhi_chunk_parse_size` then
  found no hex digit and spun returning `-1` ("need more") forever while the
  buffer grew until it overflowed (a spurious `PROTOCOL` error on large **chunked**
  bodies). The size parser now skips a leading `CRLF`/`LF` and folds it into the
  consumed offset. Latent bug shared by the SSE streaming path (`sandhi_http_stream*`),
  not just download — large chunked bodies are simply the first traffic to cross
  enough recv boundaries to hit it. (codeload serves the gate's tarball with
  `Content-Length`, so the gate hit the cap bug above; this one is covered by new
  unit tests that fail pre-fix.)

### Added

- `programs/_download_probe.cyr` — live gate: follows the github→codeload
  redirect, streams the binary body to a temp fd via `sandhi_http_download`
  (redirect-follow on), then re-reads the file and asserts `on-disk bytes ==
  reported bytes` at `status == 200`. Skip-cleanly offline (CONNECT / DISCOVERY /
  TIMEOUT → SKIP). Default target is GitHub's canonical demo-repo archive; pass a
  URL as `argv(1)` to point it at a larger artifact. Mirrors
  `_https_native_loop_gate.cyr`. New CI step.

### Tests

- `tests/sandhi.tcyr` **467 → 473** (+6): the split-inter-chunk-CRLF decoder fix —
  `_sandhi_chunk_parse_size` on a leading-CRLF buffer, and a two-append decode
  round-trip with the CRLF split across the boundary (both fail pre-fix, verified
  by temporary revert). Suite totals **1039 → 1045**. The 256 KiB-cap fix is
  covered by the live gate (it needs a real large response).

### Docs

- README refreshed to the current snapshot (1.6.5 / cyrius 6.2.18 / 1045
  assertions; download module added to the map; takumi listed as the download
  consumer) — snapshot only, per the README-is-not-a-fix-diary discipline.
- `docs/examples/01`–`04` had stale include preambles (pre-1.4.6 `tls_policy`
  ordering, missing `version_str` / `obs/prof` / `session_cache`) that no longer
  compiled — their "Build:/Run:" instructions were broken. Regenerated all four
  include blocks from the canonical `cyrius.cyml` module order; **all now build**.
  Added `docs/examples/05-download.cyr` (download-to-fd, verified end-to-end).

## [1.6.4] — 2026-06-17

**Binary streaming download — `sandhi_http_download` / `_download_sink`.** cyrius
pin **6.2.11 → 6.2.18**. First consumer: **takumi** source download (takumi
`docs/adr/0006-source-download.md`). Promotes the parked *Streaming GET to an fd /
body-sink* roadmap item (was held under wait-for-second-consumer; a direct
consumer ask is the trigger).

The buffered client (`sandhi_http_get_opts`) allocates the whole response body up
front — so takumi capped source tarballs at 128 MiB in-memory to avoid exhausting
the bump allocator. The only incremental path, `sandhi_http_stream*`, force-feeds
every decoded chunk through the **SSE** parser, so it can carry only
`text/event-stream` — not a binary artifact. takumi needed a *third* shape:
stream a binary body to disk without ever holding it in memory.

### Added — http/download (`src/http/download.cyr`, new module)

- **`sandhi_http_download_sink(url, cb, ctx, opts)`** (+ `_a` arena variant) — the
  primitive: streams the response body to a caller byte-sink
  `cb(ctx, buf, len) -> int` (return `1` continue, `0` clean early-stop, `<0`
  abort-with-error). The body is **never fully buffered** — decoded bytes are
  flushed to the sink each pass and the fixed-size work buffers reset, so resident
  memory is bounded regardless of artifact size (the 128 MiB cap lifts).
- **`sandhi_http_download(url, fd, opts)`** (+ `_a` variant) — convenience wrapper
  that writes straight to an open fd via an internal partial-write-looping sink.
  takumi's call is `sandhi_http_download(url, tarball_fd, opts)`.
- **Result struct** (`SANDHI_DOWNLOAD_RESULT_SIZE`, 32 B) + accessors
  `sandhi_download_status` / `_bytes` / `_err` / `_stopped`.
- **Reuses, does not fork:** the header drain + chunked decoder + buffer helpers
  from `stream.cyr`, and the security-aware redirect-follow helpers from
  `client.cyr` (https→http downgrade refused → `SANDHI_ERR_TLS`;
  Authorization / Cookie / Proxy-Authorization stripped across authorities).
  Honors the same timeout matrix + TLS-policy fields as the buffered client.
- **Download-appropriate framing:** only a **2xx** final response streams to the
  sink; any other final status (a 4xx, or an unfollowable 3xx) returns its code
  with `err_kind = REMOTE` and writes **nothing** — a download never splatters an
  error page into the destination. Chunked bodies decode incrementally; plain
  bodies honor `Content-Length` as an early stop (so a keep-alive server that
  ignores `Connection: close` can't hang) and otherwise read to EOF.

### Changed — toolchain

- cyrius pin **6.2.11 → 6.2.18** (clean deps re-resolve). No new cyrius primitive
  needed — the download path is pure composition of the existing conn / stream /
  client / tls-policy surface. All four `.tcyr` suites green on the new pin before
  the feature landed.

### Tests

- `tests/sandhi.tcyr` **451 → 467** (+16): download-result accessors; the fd-write
  sink round-tripped through a real temp file + its write-error signal; and the
  redirect-target resolver across 302-follows / 200-terminal / follow-disabled /
  hops-exhausted / no-Location / https→http-downgrade-sentinel cases. (The shared
  chunked decoder + redirect-follow security semantics already carry dedicated
  coverage in the stream + client suites.) Suite totals **1023 → 1039**.

## [1.6.3] — 2026-06-15

**WebDriver / Appium / MCP RPC can now carry a TLS policy — endpoint-keyed
default policy registry.** cyrius pin **6.2.10 → 6.2.11**. Closes
[`2026-06-15-yantra-sandhi-wd-rpc-no-tls-policy.md`](docs/development/issues/archive/2026-06-15-yantra-sandhi-wd-rpc-no-tls-policy.md)
(filed by yantra M8). sandhi exposed a rich TLS-policy API attachable to an HTTP
request via `sandhi_http_options_tls_policy`, but the RPC convenience verbs
(`sandhi_wd_*` / `sandhi_ap_*` / `sandhi_rpc_mcp_*`) took only a `base_url` and
built their request internally with no options — so a consumer driving a *remote*
WebDriver grid / Appium cloud over HTTPS could pin only the session-create POST it
issued itself; every subsequent per-action call fell back to default trust. A
half-pinned session is not a pinned session.

Resolution is **option (2)** from the issue — a single place to set the policy per
endpoint, so consumers can't accidentally leave one verb unpinned, with **no new
`_opts` verb per dialect call** (which would have ballooned the public surface
against the small-surface discipline).

### Added — rpc/dispatch (`src/rpc/dispatch.cyr`)

- **Endpoint-keyed default TLS policy registry** (+4 public verbs):
  - `sandhi_rpc_set_default_tls_policy(base_url, policy)` — register / replace the
    default policy for an endpoint (policy `0` clears). Returns `SANDHI_OK`, or
    `SANDHI_ERR_INTERNAL` on OOM / table-full (cap 16 endpoints).
  - `sandhi_rpc_clear_default_tls_policy(base_url)` — remove one (exact key).
  - `sandhi_rpc_get_default_tls_policy(base_url)` — exact-match inspect getter.
  - `sandhi_rpc_clear_all_default_tls_policy()` — drop all (test / teardown).
- Per-call resolution is **longest-prefix match** with a path boundary (so
  `host:444` does not falsely match `host:4444/…`). Every RPC call whose URL falls
  under a registered `base_url` opens through the policy — pin / mTLS / trust-store
  enforced, conn **not** pooled — identical semantics to
  `sandhi_http_options_tls_policy`. Plain-HTTP URLs are resolved scheme-agnostically
  but the HTTP layer ignores a policy on non-TLS, so the localhost-`127.0.0.1`
  backends stay unaffected.
- `_sandhi_rpc_http_send` reworked into `_sandhi_rpc_http_send_a(a, …)` — resolves
  the endpoint policy and threads it through `_sandhi_http_dispatch_a` via an
  options struct (the per-method `sandhi_http_*` verbs are thin wrappers over that
  dispatch, so all methods get the opts path uniformly). With no policy resolved,
  `opts == 0` → byte-identical to the pre-1.6.3 bare `sandhi_http_*` calls.
- Registry storage is a lazily-allocated fixed-capacity table in `default_alloc()`
  (policies + dup'd base-URL keys outlive any per-request arena — mirrors the
  session-cache's allocator choice).

### Changed — rpc/mcp (`src/rpc/mcp.cyr`)

- `sandhi_rpc_mcp_stream_a` carries the resolved endpoint policy onto the long-lived
  SSE channel too (via `sandhi_http_stream_opts_a`), so a pinned MCP endpoint stays
  pinned for its notification stream, not just its unary calls.

### Tests

- `tests/rpc.tcyr` **42 → 63** (+21): registry set/get/replace, longest-prefix
  resolution, the host-boundary false-match guard, scheme-agnostic resolution,
  clear / clear-all / nested-survives-sibling-clear, and the 16-endpoint cap +
  replace-at-cap path. Suite total **1002 → 1023**.

### Toolchain

- Cyrius pin **6.2.10 → 6.2.11** (clean deps re-resolve). No new cyrius primitive
  required — the fix composes the existing `sandhi_http_options_tls_policy` /
  `_sandhi_http_dispatch_a` / `sandhi_http_stream_opts_a` surface.

## [1.6.2] — 2026-06-15

**macOS transport port completed — IPv6 + server listen socket (compose cyrius
6.2.10's v6-on-Darwin primitives).** cyrius pin **6.2.9 → 6.2.10**. 1.6.1 ported
the IPv4 connect + per-op timeout to Darwin; this closes the v6 + server-listen
follow-on. cyrius 6.2.10 shipped the `lib/net.cyr` v6-on-Darwin surface sandhi
filed for ([`archive/2026-06-15-cyrius-net-v6-darwin.md`](docs/development/issues/archive/2026-06-15-cyrius-net-v6-darwin.md)),
so sandhi composes it and **deletes its hand-rolled duplicates + every Linux-only
raw socket constant** (ADR 0001). No Linux-only socket constant remains anywhere
in sandhi. Fully closes
[`archive/2026-06-06-macos-nonblocking-connect.md`](docs/development/issues/archive/2026-06-06-macos-nonblocking-connect.md).

### Fixed — http/conn (`src/http/conn.cyr`)

- **IPv6 open paths now compose stdlib's Darwin-correct `sockaddr_in6` +
  `net_connect_sa_nb`** (cyrius 6.2.10) and create the socket with the per-target
  `AF_INET6` (Linux 10 / Darwin 30) instead of a hardcoded `10`. Previously the v6
  socket domain, the `sockaddr_in6` (Linux `AF_INET6=10`, no BSD `sin6_len` byte),
  and the nb-connect dance were all Linux-only → v6 was broken on macOS (masked by
  v4 fallback). `net_connect_sa_nb`'s `_NET_CONN_NB_*` sentinels alias sandhi's
  `_SANDHI_CONN_NB_*` one-for-one.

### Fixed — server (`src/server/mod.cyr`)

- **The accept-loop listen socket now composes stdlib `sock_set_nonblocking`**
  (cyrius 6.2.10) instead of a hardcoded Linux `O_NONBLOCK=0x800` fcntl (Darwin's
  is `0x0004`). The helper is itself an agnos no-op, so the prior
  `#ifndef CYRIUS_TARGET_AGNOS` guard is gone.

### Removed — http/conn

- **Deleted the hand-rolled v6 shims** `_sandhi_conn_sockaddr_in6[_a]` /
  `_sandhi_conn_connect_sa_nb[_a]` (superseded by the stdlib primitives) and **all
  eight Linux-only raw socket constants** (`_SANDHI_O_NONBLOCK`,
  `_SANDHI_EINPROGRESS`, `_SANDHI_SO_ERROR`, `_SANDHI_SYS_POLL`,
  `_SANDHI_SYS_GETSOCKOPT`, `_SANDHI_F_GETFL`, `_SANDHI_F_SETFL`,
  `_SANDHI_POLLOUT`) — no consumer hand-rolls the dance anymore. `src/http/conn.cyr`
  905 → 804 lines.

### Tests

- No assertion-count change (**1002**: 451 + 167 + 342 + 42). The v6 / listen
  paths aren't unit-tested without a live network; the four `.tcyr` suites stay
  green on the 6.2.10 pin. macОS+aarch64+agnos cross-builds OK; lint 0/0;
  `fmt --check` clean.

### Stdlib / cross-repo

- cyrius pin **6.2.9 → 6.2.10** (clean deps re-resolve). 6.2.10 shipped the
  v6-on-Darwin `lib/net.cyr` surface (per-target `AF_INET6`, `sockaddr_in6`,
  `net_connect_sa_nb`, `net_connect_nb6`, `sock_set_nonblocking`/`_clear`) from
  sandhi's upstream filing. `dist/sandhi.cyr` regenerated at v1.6.2.

## [1.6.1] — 2026-06-15

**macOS non-blocking-connect fix — compose the Darwin-correct stdlib transport
primitives.** cyrius pin **6.2.8 → 6.2.9**. The IPv4 non-blocking-connect path
and the per-operation socket timeout in `src/http/conn.cyr` hardcoded **Linux**
socket constants (`O_NONBLOCK=0x800`, `EINPROGRESS=115`, `SO_RCVTIMEO=20`/
`SO_SNDTIMEO=21`, 64-bit `tv_usec`), so any `sandhi_http_*` call with
`connect_ms > 0` failed with a spurious `SANDHI_ERR_CONNECT` on aarch64 macOS —
even against a listening localhost server (yantra's iOS Appium `POST /session`
repro). The fix re-points both helpers at the stdlib primitives that already
carry the platform-branched Darwin values + agnos fallback, retiring sandhi's
duplicate of the machinery (ADR 0001 — compose, don't reimplement). Linux + AGNOS
behaviour unchanged. Closes the IPv4 + per-op-timeout halves of
[`docs/issues/archive/2026-06-06-macos-nonblocking-connect.md`](docs/development/issues/archive/2026-06-06-macos-nonblocking-connect.md)
(fully resolved at 1.6.2; archived).

### Fixed — http/conn (`src/http/conn.cyr`)

- **`_sandhi_conn_connect_nb_a` now delegates to stdlib `net_connect_nb`** instead
  of running its own fcntl/poll/getsockopt dance against Linux-only flag/opt
  values. stdlib carries the Darwin-branched `_NET_O_NONBLOCK` / `_NET_EINPROGRESS`
  / `SockOpt` (verified on arm64 macOS) and the agnos blocking-connect fallback.
  The stdlib sentinels (`_NET_CONN_NB_OK`/`_TIMEOUT`/`_ERR` = 0/-2/-1) match
  sandhi's `_SANDHI_CONN_NB_*` one-for-one, so the open path's failure
  classification is unchanged.
- **`_sandhi_conn_set_timeout_ms_a` now delegates to stdlib
  `sock_set_recv_timeout` / `sock_set_send_timeout`** (chosen by the `opt`
  selector). stdlib owns the per-target `SO_*TIMEO` opt value (Linux 20/21 vs
  Darwin `0x1006`/`0x1005`) and the Darwin `struct timeval` `tv_usec`-is-32-bit
  quirk a 64-bit write would have overrun. The helper is now arena-independent
  (`a` retained only for caller-signature stability).

### Changed — http/conn

- The sandhi-local `_SANDHI_O_NONBLOCK` / `_SANDHI_EINPROGRESS` / `_SANDHI_SO_ERROR`
  / poll/getsockopt constants now have just two direct consumers — the internal
  IPv6 sockaddr nb-connect (`_sandhi_conn_connect_sa_nb_a`) and the server
  accept-loop listen socket — both still Linux-only. Comment block updated to flag
  that those two sites are **not** Darwin-ported (the SYSXLAT backend translates
  the syscall numbers but not these flag/opt values); filed as a roadmap follow-on
  ("IPv6 nb-connect + server listen socket not Darwin-ported").

### Tests

- `tests/alloc.tcyr` `test_alloc_batch5_conn_timeout_arena` — the assertion that
  pinned the old "timeval allocated into arena `a`" + arena-OOM→-1 behaviour was
  repurposed to assert the helper is now **arena-independent** (composes the
  stdlib setters, never touches `a`). Net −1 assertion (alloc suite 343 → 342;
  **1002 total**: 451 + 167 + 342 + 42). All four suites green.

### Stdlib / cross-repo

- cyrius pin **6.2.8 → 6.2.9** (clean deps re-resolve). `dist/sandhi.cyr`
  regenerated at v1.6.1.

## [1.6.0] — 2026-06-15

**Batch A1 — native TLS-policy enforcement (the last libssl coupling for policy
enforcement).** cyrius pin **6.2.7 → 6.2.8**, which shipped the typed,
backend-aware pre-handshake trust-store + mTLS config verbs that sandhi's
`src/tls_policy/apply.cyr` was the named consumer for. Native now **enforces**
custom trust stores + mTLS — it failed closed on native from 1.4.7, because the
enforcing path was libssl-`SSL_CTX_*`-only. +2 assertions (1003 total).

### Changed — tls_policy (`src/tls_policy/apply.cyr`)

- **`_sandhi_apply_hook` migrated off `tls_dlsym("SSL_CTX_*")`** onto the typed,
  backend-aware stdlib verbs `tls_ctx_load_verify_locations` /
  `tls_ctx_use_certificate_file` / `tls_ctx_use_private_key_file` (cyrius 6.2.8).
  Under native they route to the `tls_native` trust-store + client-auth
  machinery; under libssl, to the core `SSL_CTX_*` symbols. The hook now gets the
  native ctx under native (vs `SSL_CTX*` under libssl) and the typed verbs
  dispatch internally — sandhi's surface is unchanged across the swap (No-FFI;
  ADR 0001).
- **`sandhi_tls_policy_enforcement_available()` is now backend-aware-true:**
  returns `tls_available()` — trust/mTLS enforce on **both** backends. The 1.4.7
  "0 on native → fail-closed" is retired. Native enforcement is real:
  `_tls_native_alloc` defaults verify-peer + system CA, and `tls_native_connect`
  is fail-closed (verifies chain-to-root + hostname before `TLS_OK`).
- `sandhi_tls_policy_pin_available()` unchanged — SPKI pinning was already
  backend-agnostic + live on native (1.4.2 / 1.4.7); still libssl-excluded
  pending the cyrius libssl-SPKI fix (orthogonal — native covers pinning).

### Removed — tls_policy

- The `_sandhi_apply_load_verify_fp` / `_use_cert_fp` / `_use_key_fp` fn-pointer
  cache + the `_sandhi_apply_resolve_fns` lazy-resolve step — the typed verbs
  resolve the backend internally, so the `tls_dlsym` cache is dead.

### Tests

- `tests/sandhi.tcyr` `test_tls_enforcement_flag` — +2 deterministic assertions:
  on the native backend, `enforcement_available()` == 1 (the A1 flip) and
  `pin_available()` == 1. Guarded for the deprecated libssl-only build. (1003
  total: 451 + 167 + 343 + 42.)
- `programs/_policy_runtime_probe.cyr` — gate `[4]` hardened from a warn-tolerant
  note to a **hard native trust-store enforcement assertion**: a bogus custom
  trust store MUST be refused with err=TLS (exit 5 if it opens — a silently
  ignored custom CA is a security regression). Verified live: `backend=1
  pin_available=1 trust_mtls_available=1`; `[2]` default round-trip, `[3]`
  wrong-pin fail-closed, `[4]` bogus-trust refused → `ALL GATES PASS`.

### Stdlib / cross-repo

- Closes the sandhi side of the long-running native-TLS filing
  (`docs/issues/2026-05-22-cyrius-native-tls-in-6.0.x.md`, Batch A1): the last
  libssl coupling for **policy enforcement** is gone. Native is now functionally
  complete for TLS policy (pinning + trust-store + mTLS); the deprecated
  `-D CYRIUS_TLS_LIBSSL` opt-out is a pure legacy escape hatch with no remaining
  functional gap. This unblocks the libssl **retirement** scheduled for sandhi
  **2.0** (dropping `sandhi_tls_use_libssl()` + the build flag — a breaking
  change; see the roadmap).

### Known follow-up

- The live gate proves the custom trust store is **enforced** (a bogus CA is
  refused, not silently ignored) and the default system-CA path round-trips. A
  *loadable-but-wrong* CA verify-fail proof (swap the trust anchor to a CA that
  doesn't sign the server → handshake rejects) needs a CA PEM fixture + the
  cyrius CA-bundle replace-vs-append semantics; flagged as a live check (see
  roadmap). Chain-verify correctness itself is cyrius's tested responsibility
  (the CVE-18 fail-closed `tls_native_connect`).

## [1.5.5] — 2026-06-15

**Batch A3 — opt-in multicast (QM) mDNS resolver, done right (two-socket split +
a live loopback test).** No cyrius pin change (stays 6.2.7). This redoes the 1.5.4
A3 attempt that was reverted for a connect()-source-filter blocker — this time the
receive path is **verified live**, not assumed. **+3 public verbs**; +9 test
assertions (1001 total, was 992).

### Added — multicast (QM) resolver (`src/discovery/local.cyr`)

For mDNS responders that ignore the QU bit and multicast their answer to
224.0.0.251:5353, sandhi joins the group and listens. The 1.5.4 attempt used one
`connect()`ed socket for both send and receive — but Linux's connect()
source-filter then drops every answer (responders send from their own unicast IP,
not the group). **Fix: a two-socket split** that composes the cyrius 6.2.7
primitives without needing the `sock_sendto`/`sock_recvfrom` this filing had
requested:

- **RX socket** — UNCONNECTED, `SO_REUSEPORT` + bound to 5353 + `net_join_multicast`.
  `sock_recv` (`sys_read`) on an unconnected bound socket delivers the next
  datagram from **any** source, so it sees the multicast answer.
- **TX socket** — connected to the group, used only to send the plain-IN ID=0
  query (`sys_write` needs a connected socket).
- Recv-loop matches by answer-name (the shared parser, `expected_id=0`), bounded
  by an `SO_RCVTIMEO` deadline + a hard attempt cap; drops membership + closes
  both sockets on every exit path.

- **+3 public verbs**: `sandhi_discovery_local_mc_resolver_a` /
  `sandhi_discovery_local_mc_resolver` / `sandhi_discovery_local_mc_available`.
  **Opt-in** — the unicast QU resolver stays the default fast path, unchanged
  (the builder was refactored to `_sandhi_local_build_query_cls(…, qclass_hi)`
  with QU as the back-compat wrapper). On **AGNOS** the net multicast helpers
  return -1, so `_sandhi_local_mc_rx_open` fails → the resolver degrades to a clean
  miss (`sandhi_discovery_local_mc_available()` → 0).
- **The rx_open + recv-loop are factored as `_sandhi_local_mc_rx_open(group, port,
  iface)` + `_sandhi_local_mc_recv_match(a, fd, expected_id)`** so the live test
  drives the exact resolver receive code.

### Tested — a control-calibrated LIVE loopback multicast gate (the missing 1.5.4 test)

`tests/sandhi.tcyr` `discovery/local/mc_qm` is a **hard regression gate**, not just
a positive probe (per the review of the first cut). It opens two unconnected join
sockets over the loopback interface on an isolated admin-scoped group
(239.255.0.99): a plain **control** socket (proves the env delivers loopback
multicast at all) and the resolver's **real** `_sandhi_local_mc_rx_open`. A
loopback-IF sender multicasts a synthetic A-record answer to each port; then — **if
the control receives, the resolver's rx MUST receive too, else the test fails
RED** (a connect()-on-rx regression filters the rx answer while the control still
gets it). It skips cleanly only where the control also fails (no loopback multicast
in the env). **Verified both directions**: green + firing live on the dev box, and
goes red under a negative control that re-injects the 1.5.4 connect()-on-rx bug.
Plus wire-level checks (QM plain-IN QCLASS + ID=0, QU builder unchanged).

### Resolved

The mDNS-multicast filing
[`docs/issues/archive/2026-06-15-cyrius-mdns-multicast-primitives.md`](docs/development/issues/archive/2026-06-15-cyrius-mdns-multicast-primitives.md)
is resolved + archived: 6.2.7 shipped the join/option primitives; the connected-
socket insufficiency is worked around sandhi-side with the two-socket split
(filing option 2), so the requested upstream `sock_sendto`/`sock_recvfrom` are
no longer needed for A3. *(The pre-existing **QU** resolver still uses one
connected socket — its receive correctness against real responders is unverified;
flagged for a live-network check, tracked in the filing.)*

### Verified

1001 assertions green (449 + 167 + 343 + 42); `_server_async_smoke` 16/16;
`cyrius lint` 0/0; `cyrius fmt --check` clean; aarch64 + agnos builds green
(agnos resolver degrades to QU); `dist/sandhi.cyr` regenerated at v1.5.5.

## [1.5.4] — 2026-06-15

**cyrius pin `6.2.6` → `6.2.7` — the AGNOS build cascade is resolved (cyrius
shipped the fix from sandhi's filing).** No public-surface change; no sandhi
source change (the cascade cleared by the pin + a clean deps re-resolve). A1
(native `SSL_CTX_*`) re-verified **still open** on 6.2.7. **Batch A3 (mDNS
multicast) NOT shipped** — 6.2.7 landed the join/option primitives, but an
adversarial review found them *insufficient* for a working resolver, so the
adoption was reverted (details below). 992 assertions green (unchanged).

### Changed — cyrius pin → 6.2.7 (clean deps re-resolve)

Bumped the pin and **clean-resolved deps** (`rm -rf lib cyrius.lock && cyrius
deps`) so the vendored stdlib snapshot actually tracks 6.2.7 — plain `cyrius
deps` is a no-op against an existing lockfile, which is how the `./lib` snapshot
silently goes stale after a toolchain bump (see the agnos cascade note below).

### Fixed — AGNOS full-build cascade resolved (no sandhi code change)

`cyrius build --agnos programs/smoke.cyr` now **succeeds**, producing a valid
`ELF 64-bit … x86-64` agnos binary (1.4 MB) — the cascade documented at 1.5.3 is
cleared entirely by the 6.2.7 pin + clean re-resolve:

- **`thread.cyr`** — the agnos clone-dispatch fix (already in the 6.2.6 toolchain)
  now lands in the vendored `./lib` via the clean re-resolve (it was only ever a
  stale-snapshot artifact, never an upstream defect).
- **`async.cyr`** — 6.2.7 routes the epoll runtime to a serial/blocking agnos
  peer (`#ifdef CYRIUS_TARGET_AGNOS`), exactly as `thread.cyr → thread_agnos.cyr`,
  resolving the raw `SYS_EPOLL_CREATE1` gap (cyrius cites
  `2026-06-15-cyrius-thread-agnos-clone-dispatch.md` §2 in the source). With
  thread + async cleared, the full sandhi bundle compiles for agnos.

This is the **compile** cascade; agnos runtime behavior (server serial-peer
semantics, native TLS) is a separate concern verified consumer-side (sit). The
agnos transport issue (C1 socket 1.5.1 + C2 entropy 1.5.2 + this cascade) and the
cascade filing are archived.

### Reverted — Batch A3 mDNS multicast adoption (primitives landed, but insufficient)

cyrius 6.2.7 shipped the IPv4 multicast primitives sandhi filed at 1.5.3
(`net_join_multicast` / `net_drop_multicast` / `net_set_multicast_ttl` / `_loop`
/ `_if` / `sock_reuseport` + per-target constants + `ip_mreq` — the source cites
sandhi's filing). A QM (multicast) resolver was written to compose them, then
**reverted after an adversarial review found a blocker**: `lib/net.cyr`'s
`sock_send` / `sock_recv` require a *connected* socket, so the resolver had to
`sock_connect` to the group — and on Linux **`connect()` on a UDP socket installs
a source-address filter**, so the socket drops every mDNS answer (responders send
from their own unicast IP, not the group). The join/`SO_REUSEPORT`/TTL primitives
are real but inert with a connected receive socket. A working QM resolver also
needs unconnected `sock_sendto` / `sock_recvfrom` in `net.cyr` (not present), or a
two-socket send/recv split — plus a loopback live-multicast test. The mDNS filing
[`docs/issues/2026-06-15-cyrius-mdns-multicast-primitives.md`](docs/development/issues/archive/2026-06-15-cyrius-mdns-multicast-primitives.md)
is un-archived and corrected with the full requirement; Batch A3 stays open. (The
review also noted the pre-existing **QU** resolver has the same connect()-filter
shape — its "works against most responders" claim is unverified and needs a live
check.) Net: **no public-surface change, no `local.cyr` change** in 1.5.4.

### Still open — A1 native `SSL_CTX_*` (re-verified on 6.2.7)

`lib/tls.cyr` still exposes only `tls_set_verify` (mode/callback) — no native
trust-store / client-cert / client-key wrappers. sandhi's native trust/mTLS
enforcement stays fail-closed (1.4.7); `2026-05-22-cyrius-native-tls-in-6.0.x.md`
remains open.

### Verified

992 assertions green (440 + 167 + 343 + 42, unchanged — the A3 tests were reverted
with the code); `_server_async_smoke` 16/16; `cyrius lint` 0/0; `cyrius fmt
--check` clean; aarch64 cross-build green; **`cyrius build --agnos` green (valid
agnos ELF)**; `dist/sandhi.cyr` regenerated at v1.5.4.

## [1.5.3] — 2026-06-15

**1.5.x Batch A2 — async-server arena-aware runtime (residual leak eliminated).**
No cyrius pin change (stays 6.2.6). No public-surface change. Plus two doc
corrections from a verification pass that re-checked the "still upstream-blocked"
claims against the actually-installed cyrius 6.2.6.

### Fixed — `sandhi_server_run_async` no longer leaks the runtime + task structs

The 1.4.9 epoll-cooperative server bounded its per-connection recv buffers + arg
structs in a reset-per-batch arena, but created the async runtime with
`async_new()` — so the runtime struct (40 B) and every `async_spawn` task struct
(32 B/conn) came from the no-free global bump. Because `async_run` closes the
runtime's epfd (single-use), the batched accept loop recreates the runtime each
batch, leaking ~32 B/conn + 40 B/batch forever (a quality gate for long-running
high-traffic servers; bounded-lifetime use was unaffected).

**This was tracked as "gated on cyrius shipping `async_new_in(allocator)`" — but
that primitive had already LANDED upstream in cyrius v6.1.22** (verified at
`lib/async.cyr:47`; the claim was stale, same pattern as the aarch64 fix and the
agnos `sys_getrandom` surface). So this is pure sandhi-side adoption, not new
upstream work: `sandhi_server_run_async` now creates the runtime with
`async_new_in(arena)` at both the initial and per-batch-recreate sites, so the rt
+ tasks come from the existing reset-per-batch arena and `reset_via(arena)`
reclaims them along with the buffers/args → **zero residual leak, RSS flat over a
sustained request stream**. The arena was already sized for this (the per-conn
`+64` covers arg 32 B + task 32 B; the `+4096` slack covers the rt). No new dep
(`async` already declared); no API change.

- `programs/_server_async_smoke.cyr` strengthened from 2 to **16** sequential
  requests — each is its own batch, so the run cycles
  `async_run → reset_via → async_new_in(arena)` 16 times, robustly exercising the
  arena-backed recreate path (16/16 pass, with the silent-client DoS regression
  still held). An RSS-sampling probe was deliberately NOT added: the leak is
  sub-page-per-batch (~296 B), so a runtime RSS assertion would need thousands of
  iterations to signal and would be flaky; the fix is leak-free by construction
  (arena-backed + `reset_via` reclaims; arena pre-sized) and the 16-cycle smoke
  guards the recreate path.

### Docs — corrections from the upstream-claims verification pass

- **A2 reclassified**: `lib/async.cyr` `async_new_in(allocator)` is no longer an
  open cross-repo dependency — it landed at cyrius v6.1.22 and is adopted here.
  The roadmap / state.md cross-repo-deps entries are updated; the upstream
  cyrius filing `2026-06-09-async-runtime-no-free-task-leak.md` is satisfied.
- **AGNOS full-build blocker re-characterized — twice, ending accurate.** The
  `cyrius build --agnos` failure was first attributed to a "`lib/mmap.cyr`
  `CLONE_VM` stub"; an adversarial verification pass then proved **both that and
  an interim "unfixed upstream `thread.cyr` defect" framing wrong**. The true
  picture: (1) the `mmap.cyr:184` error is a single-pass include-offset artifact —
  the token is `thread.cyr:199`; (2) `thread.cyr`'s AGNOS dispatch is **already
  fixed in the cyrius 6.2.6 toolchain** (it routes agnos to a `thread_agnos.cyr`
  peer) — the failure is sandhi's **stale vendored `./lib` snapshot** (a pre-fix
  `thread.cyr`, no `thread_agnos.cyr`); and (3) refreshing `thread.cyr` clears
  `CLONE_VM` and exposes the **next** gap (`lib/async.cyr`'s raw
  `SYS_EPOLL_CREATE1`, which agnos doesn't define — it has `SYS_EPOLL_CREATE` +
  the portable `sys_epoll_create` wrapper). So the agnos full-build is a
  **cascade** — part **sandhi-side** (refresh the vendored stdlib snapshot) and
  part **upstream** (real stdlib agnos-compile gaps), needing a systematic
  agnos-completeness pass rather than a point fix. The corrected, honest filing is
  [`2026-06-15-cyrius-thread-agnos-clone-dispatch.md`](docs/development/issues/archive/2026-06-15-cyrius-thread-agnos-clone-dispatch.md);
  the agnos issue + roadmap + state.md are corrected to match. The x86_64
  authoritative build is byte-identical across the `thread.cyr` refresh, so none
  of this touches sandhi's release artifacts.
- **A3 (mDNS multicast) now has a proper upstream filing.** The verification
  pass confirmed cyrius `lib/net.cyr` still ships no IPv4 multicast primitives
  (no `IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` / `_LOOP` / `_IF` / `SO_REUSEPORT`,
  no `ip_mreq` struct, no join helper — only generic `sys_setsockopt`), and that
  it was the one Batch-A item tracked only as an inline roadmap bullet. Filed a
  paste-ready cyrius-side coordination doc with the exact constants / struct /
  preferred `net_join_multicast` helper sandhi needs for QM-mode + RFC 6763
  browsing (the QU-bit unicast resolver ships today and needs none of it):
  [`2026-06-15-cyrius-mdns-multicast-primitives.md`](docs/development/issues/archive/2026-06-15-cyrius-mdns-multicast-primitives.md).
  Closes the last untracked upstream item in sandhi's Batch A.

### Verified

- 992 assertions green (440 + 167 + 343 + 42); `_server_async_smoke` 16/16 PASS
  (silent-client regression held); lint 0/0; `cyrius fmt --check` clean; aarch64
  cross-build green; `dist/sandhi.cyr` regenerated at v1.5.3.

## [1.5.2] — 2026-06-15

**1.5.x Batch C2 — AGNOS DNS-entropy gap (sit-adoption-driven follow-up to C1).**
Closes the runtime half of the AGNOS adoption work surfaced in
[`2026-06-14-agnos-socket-backend-gap.md`](docs/development/issues/archive/2026-06-14-agnos-socket-backend-gap.md).
No cyrius pin change (stays 6.2.6). No public-surface change.

### Fixed — DNS TXID entropy portable across targets (`src/net/resolve.cyr`)

`_sandhi_resolve_random_u16` (the per-query DNS transaction-ID source that closes
the Kaminsky cache-poisoning window) seeded its 2 random bytes by opening
`/dev/urandom` via **bare Linux syscall numbers** (`open`=2 / `read`=0 /
`close`=3). Those are integer literals so they *compiled* on AGNOS (which is why
C1 didn't catch this), but at runtime the numbers mean different syscalls on the
agnos ABI and agnos has no `/dev/urandom` — so the TXID would fall through to the
weak clock-based fallback (or worse) on agnos, leaving DNS spoofable.

Replaced the hand-rolled `/dev/urandom` open/read/close with the stdlib
`sys_getrandom(buf, len, 0)` syscall-selector primitive (`syscalls` dep, already
declared — no new dependency). It is portable across **every** sandhi target via
the per-target selector — Linux `getrandom(2)`, **AGNOS #45** (kernel CSPRNG,
landed agnos 1.45.0), and the macOS / Windows peers (macOS routes through
`syscalls_linux_common.cyr` on both arches) — needs no filesystem access (works
under chroot / landlock / early boot), and is a strict upgrade over the old path
on Linux too. The portable clock-nanos fallback is unchanged. This is the
canonical "compose the stdlib primitive, don't hand-roll" move (CLAUDE.md), so it
needed **no `#ifdef`** — one portable call replaces the Linux-only block.

### Verified

- **AGNOS**: `sys_getrandom` resolves clean on `cyrius build --agnos` (standalone
  probe mirroring sandhi's exact call shape; `#45` links, no undefined symbol).
- **Linux runtime**: two successive `_sandhi_resolve_random_u16`-shape reads
  return valid in-range, distinct u16s (real CSPRNG, not the fallback).
- **All targets covered**: `sys_getrandom` is defined for Linux x86_64/aarch64,
  macOS x86_64/arm64, AGNOS, and Windows in the vendored syscall selector — the
  build emits no `undefined function 'sys_getrandom'`.
- 992 assertions green (440 + 167 + 343 + 42); lint 0/0; `cyrius fmt --check`
  clean; aarch64 cross-build green; `dist/sandhi.cyr` regenerated at v1.5.2.

### Status of AGNOS adoption (issue follow-ups)

With C1 (1.5.1, socket-syscall compile) + C2 (this release, DNS entropy), the
**sandhi-side** AGNOS transport work is complete. A full `cyrius build --agnos`
of a consumer still needs two items outside sandhi's scope, both tracked: the
upstream `lib/mmap.cyr` `CLONE_VM` agnos stub, and native `SSL_CTX_*` for the
bundle's `fdlopen`/`tls_dlsym` TLS-policy path (Batch A1). Separately, the ad-hoc
`programs/dns-probe.cyr` has a pre-existing stale include list (references
`SANDHI_PROF_PHASE_*` without including `obs/prof.cyr`) — not a C2 regression and
not in the gated test suite; noted for a future cleanup.

## [1.5.1] — 2026-06-15

**1.5.x Batch C1 — AGNOS socket-backend gap (sit-adoption-driven).** Closes the
compile half of [`2026-06-14-agnos-socket-backend-gap.md`](docs/development/issues/archive/2026-06-14-agnos-socket-backend-gap.md):
sandhi's transport layer no longer references raw Linux socket syscalls that the
AGNOS target leaves undefined, so a consumer (sit) that includes the bundle can
compile for `--agnos`. No cyrius pin change (stays 6.2.6, the pin 1.5.0 landed —
the prerequisite for this work).

### Fixed — agnos transport seam (`src/http/conn.cyr`, `src/server/mod.cyr`)

The HTTP client's timeout-bounded non-blocking connect and the async server's
non-blocking listen fd dropped to raw Linux syscalls (`SYS_FCNTL` / `SYS_SOCKET`
/ `SYS_CONNECT` / `SYS_SETSOCKOPT` + `SOL_SOCKET`) whose enum constants are
undefined on AGNOS, so `cyrius build --agnos` of any sandhi consumer failed to
**compile** (`undefined variable 'SYS_FCNTL'`). Every such site is now wrapped in
`#ifndef CYRIUS_TARGET_AGNOS` with an agnos counterpart under
`#ifdef CYRIUS_TARGET_AGNOS` (the stdlib `chrono`/`net` precedent). Per-primitive:

- **Bounded nb-connect** (`_sandhi_conn_connect_nb_a`) → agnos collapses to a
  blocking `sock_connect` (already portable via `lib/net.cyr`); `timeout_ms` is
  advisory there, identical to the existing `connect_ms == 0` path.
- **Per-op SO_RCVTIMEO/SO_SNDTIMEO** (`_sandhi_conn_set_timeout_ms_a`) → no-op on
  agnos (no `setsockopt` timeout analog; agnos `sock_recv` is
  poll-against-deadline at the caller, like the `dig`/`yo` backend).
- **IPv6 raw path** (`_sandhi_conn_connect_sa_nb_a`,
  `_sandhi_conn_open_v6_fully_timed_a` + its early-data twin) → AGNOS is
  IPv4-only today; the agnos branch fails closed (`SANDHI_CONN_OPEN_CONNECT`) so
  the client falls back to v4 without referencing a v6 socket API. Revisit when
  agnos gains `AF_INET6`.
- **Server listen-fd `O_NONBLOCK`** (`src/server/mod.cyr`) → fcntl compiled out
  on agnos; `sock_listen` already returns `Err` there (inbound TCP is agnos
  Phase B), so the async server bails before the cooperative accept loop.

**Linux/macOS unaffected — proven byte-identical**: the pre-change and
post-change `programs/smoke.cyr` binaries are `cmp`-identical (the `#ifndef`
blocks compile to the same code; the directives emit none). 992 assertions green
(440 + 167 + 343 + 42), lint 0/0, aarch64 cross-build still green,
`dist/sandhi.cyr` regenerated at v1.5.1. The agnos strip + the negative control
(unguarded `SYS_FCNTL` reproduces `undefined variable 'SYS_FCNTL'` on `--agnos`,
guarded compiles clean) were verified with a standalone probe.

### Known follow-ups (tracked, not silently scoped out)

The C1 fix closes the **socket-syscall compile** gap. A full `cyrius build
--agnos` of a sandhi consumer additionally needs, none of which are C1's scope:

- **DNS TXID entropy** (`src/net/resolve.cyr`) — random TXID still opens
  `/dev/urandom` via bare Linux syscall numbers (open=2/read=0/close=3). These
  are integer literals so they **compile** on agnos (not a blocker), but they're
  a latent runtime gap — agnos sources entropy via a syscall, not `/dev/urandom`.
  Tracked as roadmap C2 (wait for the agnos entropy-syscall surface to firm up).
- **Upstream stdlib agnos stubs** — sandhi's from-source build still trips a
  `lib/mmap.cyr` `CLONE_VM` agnos gap (same Linux-stub class as the cyrius-6.2.6
  chrono fix); cyrius-side.
- **Native `SSL_CTX_*` on agnos** (Batch A1) — the bundle's `fdlopen`/`tls_dlsym`
  TLS-policy path must retire onto native equivalents for agnos (where there is
  no libssl). Already tracked as the A1 cross-repo dependency.

## [1.5.0] — 2026-06-14

**cyrius pin `6.2.1` → `6.2.6`; the aarch64 `bayan` cross-build defect is fixed
upstream — aarch64 is a gating artifact again.** Opens the **1.5.x arc** as a
toolchain + cross-repo-issue cleanup pass (the resolved-defect backlog is
archived and the remaining open items are batched into the arc; see
`docs/development/roadmap.md`).

### Fixed

- **aarch64 cross-build resolved (cyrius 6.2.6).** The `cycc_aarch64`
  `error: unexpected enum` abort while assembling stdlib `bayan` (filed
  2026-06-12, reproduced on every toolchain 6.0.21–6.2.1) no longer occurs on
  6.2.6: `CYRIUS_DCE=1 cyrius build --aarch64 programs/smoke.cyr
  build/sandhi-smoke-aarch64` produces a valid `ELF 64-bit … ARM aarch64`
  binary. Zero sandhi-side change — the fix is purely in the upstream
  `cycc_aarch64` dependency-assembly path, as the filing predicted. Issue
  archived (`docs/issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`);
  [architecture/005](docs/architecture/005-aarch64-bayan-cross-build.md) updated
  to record the resolution.

### Changed

- **cyrius pin → 6.2.6.** Mechanical bump from 6.2.1; no source change. Full
  `.tcyr` suite green (440 + 167 + 343 + 42 = 992), `cyrius lint` 0 warnings /
  0 deferrals, `dist/sandhi.cyr` regenerated via `cyrius distlib`.
- **CI/release: aarch64 cross-build restored to a gating step.** With the
  upstream defect resolved, the "Cross-build aarch64" steps in `ci.yml` /
  `release.yml` drop the 1.4.11 best-effort warn-and-skip-on-failure tolerance
  and once again fail the job if the build fails (the "skip cleanly when
  `cycc_aarch64` is absent from the toolchain" guard is retained). The release
  ships the aarch64 convenience binary alongside the authoritative x86_64
  binary + source tarball + `dist/sandhi.cyr` again.

### Docs — issue backlog cleanup

- Archived five resolved issues to `docs/issues/archive/`: the aarch64
  cross-build defect (resolved here) plus the four sandhi-side defects closed
  across the 1.4.x arc — HTTP close-path drains-until-EOF (1.4.1), repeated
  HTTPS-request SIGSEGV (1.4.5), high-level client TLS-policy threading (1.4.6),
  and low-level TLS-policy-enforcement live SIGSEGV (1.4.7). `docs/issues/README.md`
  moved their rows from the active tables to the Archived table.
- Updated the two cross-repo coordination docs whose **sandhi side** is now
  delivered: `2026-05-10-daimon-server-max-conns.md` (sandhi-side enforcement
  shipped at 1.4.9 via `sandhi_server_run_async`; daimon-side collapse now
  unblocked) and `2026-05-22-cyrius-native-tls-in-6.0.x.md` (native transport
  operational + default since 1.4.5 / cyrius 6.1.21 — the sit-adoption gate is
  cleared; the residual pre-handshake `SSL_CTX_*` native enforcement stays
  tracked as a cross-repo dependency in the roadmap).

## [1.4.11] — 2026-06-12

**cyrius pin `6.1.21` → `6.2.1` (ecosystem-wide stdlib pin sweep).** Building
against the 6.2.1 snapshot surfaced two stdlib modules that no longer exist:
both were carved into **bayan** at cyrius 6.1.25.

### Changed

- **cyrius pin → 6.2.1.**
- **`[deps]`: dropped `json`, replaced `bigint` + `base64` with `bayan`.**
  - `json` was dead weight — sandhi rolls its own JSON-RPC codec in
    `src/rpc/json.cyr` (all `sandhi_json_*`-namespaced, no collision with the
    stdlib module it never called).
  - `bigint` + `base64` are sigil's transitive crypto deps (u256_* arithmetic
    for the SPKI-pin digest path, base64). Both now live in `bayan`, which
    re-exports the legacy `u256_*` / `base64_*` names via its compat aliases.
    `bayan` is ordered before `sigil` so those symbols resolve first.
- Verified green on 6.2.1: `cyrius deps` resolves cleanly, full `.tcyr` suite
  42/42, bench 4/4, `dist/sandhi.cyr` regenerated via `cyrius distlib`.

### Fixed

- **CI/release: aarch64 cross-build no longer gates the release.** The 6.2.1
  pin pulled stdlib `bayan` into `[deps]` (sigil's transitive dep), and
  `cycc_aarch64` aborts at parse time assembling it — `error: unexpected enum`.
  Reproducible with zero sandhi code (`deps = [syscalls, alloc, bayan]` + a
  three-line `main`); the x86_64 build of the identical source is clean, and
  every installed toolchain 6.0.21–6.2.1 reproduces it. This is an upstream
  `cycc_aarch64` dep-assembly/parser defect — sandhi can't patch stdlib or the
  compiler (No-FFI / compose-don't-reimplement). The "Cross-build aarch64
  (best-effort)" steps in `ci.yml` / `release.yml` now warn and skip the
  aarch64 artifact on failure instead of failing the job; the Archive step
  already guards on file presence, so the release ships its authoritative
  x86_64 binary + source tarball + `dist/sandhi.cyr` unaffected. Filed upstream
  at `docs/issues/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`; documented in
  [architecture/005](docs/architecture/005-aarch64-bayan-cross-build.md) and
  tracked as a cross-repo dependency in `docs/development/roadmap.md`.

## [1.4.10] — 2026-06-09

**Closeout audit (P-1 / security / code-audit pass) — closes the 1.4.x arc.**
Full-codebase sweep over everything post-fold, with the heaviest scrutiny on the
least-audited 1.4.6–1.4.9 surfaces (TLS-policy threading, backend-aware
enforcement, the epoll server). Findings fixed in-slot; no cyrius pin change
(stays 6.1.21).

### Fixed — P1: async server hang on a silent client (DoS)

`_sandhi_server_async_handler` (1.4.9) called `async_await_readable(cfd)` before
recv, but `lib/async.cyr`'s await is an `epoll_wait(..., -1)` with an **infinite
timeout** — a client that connected and sent nothing blocked the entire
cooperative loop forever (and every other connection in the batch). Fix: the
handler no longer awaits — it recvs directly under the per-connection
`SO_RCVTIMEO` (the runtime is run-to-completion, so the await bought no
concurrency anyway). `sandhi_server_run_async` now also **floors `idle_ms` > 0**
(default 30 s) and always sets the recv timeout, since a cooperative loop must
bound every recv (a 0/blocking idle_ms is safe single-flight but not here).
Regression added to `programs/_server_async_smoke.cyr`: a silent connection is
held open while the real requests must still complete (the harness `timeout`
catches the pre-fix hang).

### Fixed — P2: unguarded allocations (null-after-alloc → SIGSEGV-on-OOM)

- `src/server/mod.cyr` — `async_new()` result now null-checked at both
  construction sites (matches the established "null-check every alloc" pattern;
  a null runtime into `async_spawn`/`async_run` would SIGSEGV on OOM).
- `src/http/stream.cyr` — `body_sb` (`_sandhi_sb_new_a`) and `chunk_state`
  (`_sandhi_chunk_state_new_a`) in the SSE/chunked read loop were used without a
  guard while their siblings (`header_sb`/`scratch`, `total_events_cell`/
  `stop_cell`) were checked; both now return `SANDHI_ERR_INTERNAL` on OOM. On the
  read path the 1.4.6 policy threading now drives into — a gap the 1.2.6–1.2.8
  OOM-guard audits missed.

### Audited — confirmed sound (no change)

- **1.4.7 native-fail-closed property HOLDS.** Inventoried every `tls_dlsym`
  callsite (3, all `SSL_CTX_*` in `apply.cyr`) and proved the only armer of
  `_sandhi_apply_hook` (`_sandhi_policy_pre_open_a`, via all of
  `sandhi_conn_open_with_policy_a` / `_sandhi_http_do_impl_a` /
  `sandhi_http_stream_opts_a`) gates on `enforcement_available()` — which is 0 on
  native via the active-backend check — before arming. Native never feeds a native
  ctx to a libssl `SSL_CTX_*` fn. The key-without-cert edge is safe (no
  constructor yields `mtls_key` without `mtls_cert`).
- **Public surface (1.4.5–1.4.9)**: all eight new verbs
  (`sandhi_tls_use_*` / `_backend` / `_native_available`, `_pin_available`,
  `http_options_tls_policy` / `_get_tls_policy`, `server_run_async`) have
  docstrings + test/probe coverage.

### Docs — docstrings + tidy

Added docstrings to two standalone verbs that lacked them
(`sandhi_hpack_encode_literal_indexed_name`, `sandhi_discovery_chain_as_resolver`).
Bare default-alloc wrappers intentionally rely on their `_a` twin's docstring
(codebase-wide convention) — not treated as gaps.

### Verified

- 992 assertions green (440 + 167 + 343 + 42; unchanged).
- `programs/_server_async_smoke.cyr` (with the silent-client regression): 2/2,
  PASS in ~1.4 s; `_policy_runtime_probe.cyr` ALL GATES PASS.
- Native (no-flag) + libssl (`-D CYRIUS_TLS_LIBSSL`) smoke link; `cyrius lint`
  0 warnings / 0 deferrals; `cyrfmt --check` clean; `dist/sandhi.cyr` at v1.4.10.

**Closes the 1.4.x arc.** The next release shapes against sit adoption (1.5.x).

## [1.4.9] — 2026-06-09

**Epoll-cooperative server (`max_conns` enforced) + cyrius pin 6.1.20 → 6.1.21
(TLS flag flip completed).** The server's `max_conns` option, a no-op since
0.7.2, is now enforced via a new concurrent accept loop (worker shape **decided:
epoll-cooperative**, `lib/async.cyr`); and the 1.4.8 native-as-no-flag-default
convention is now real, since cyrius 6.1.21 inverted its `lib/tls.cyr` default.

### Added — `sandhi_server_run_async(addr, port, handler_fp, ctx, opts)` (+1 verb, `src/server/mod.cyr`)

- Batched cooperative accept loop over the stdlib `lib/async.cyr` runtime:
  drain the accept queue non-blocking up to `max_conns` (default 128) per cycle,
  spawn a handler task per connection, run the batch to completion via
  `async_run`, reset the per-batch arena, repeat; block on the listen fd
  (`async_await_readable`) when the queue is empty. `max_conns` is the per-drain
  concurrency cap — the enforcement daimon asked for.
- The handler signature matches the sync path
  (`fn handler(ctx, cfd, req_buf, req_len)`) and runs **single-threaded /
  cooperative** — no thread-safety requirement (the rejected thread-pool shape
  would have needed it), but it must not block indefinitely (per-connection
  `idle_ms` / SO_RCVTIMEO bounds slow peers, as on the sync path). Smuggling
  rejection (CL+TE / dup Host/CL/TE → 400) is applied per connection, mirroring
  the sync loop.
- **Per-handler recv buffers** (the no-interleave invariant a concurrent server
  must own — the sync path's process-global `_hsv_req_buf` is unsafe under
  concurrency): each handler's buffer + arg struct come from a single
  `max_conns`-sized arena, reset each batch, so the large allocations don't
  accumulate. New `deps`: `async` + `atomic`.

### Unchanged — sync path

`sandhi_server_run` / `sandhi_server_run_opts` stay single-flight; the async loop
is strictly opt-in. daimon can now collapse its hand-rolled `serve_async` (accept
loop + per-call buffer + smuggling-check duplication) onto `sandhi_server_run_async`.

### Filed — cyrius-side `lib/async.cyr` leak (cross-repo)

`cyrius/docs/development/issues/2026-06-09-async-runtime-no-free-task-leak.md` —
`async.cyr` allocates its runtime + task structs from the global bump allocator
(no `free`) and `async_run` closes the runtime's epfd, forcing a per-batch
recreate, so each drained batch leaks ~32 B/connection there. sandhi bounds its
own buffers via the arena; eliminating the residual leak needs an arena-aware
async runtime (`async_new_in(allocator)`) upstream. Same leak daimon's
`serve_async` already has. Tracked as a roadmap cross-repo dependency.

### Changed — cyrius pin 6.1.20 → 6.1.21; TLS flag flip completed

cyrius 6.1.21 inverted its `lib/tls.cyr` backend default (the change filed at
1.4.8): **native is now the no-flag default**, `-D CYRIUS_TLS_LIBSSL` opts out to
the deprecated libssl-only build, and legacy `-D CYRIUS_TLS_NATIVE` is a no-op
alias. 6.1.21 also re-folded sandhi 1.4.5→1.4.8 into `lib/sandhi.cyr`. So the
1.4.8 interim is removed:

- `ci.yml` + `release.yml`: dropped `-D CYRIUS_TLS_NATIVE` from the native smoke
  link-proof + the three native live gates (native is the no-flag default now);
  the libssl link-proof builds with `-D CYRIUS_TLS_LIBSSL`. The interim flag
  banner is gone.
- Verified on 6.1.21: no-flag build → native (`tls_get_backend()` = native,
  smoke 1.38 MB); `-D CYRIUS_TLS_LIBSSL` → libssl (0.57 MB); legacy
  `-D CYRIUS_TLS_NATIVE` → native (no-op alias).
- The "Inverted-default TLS build" roadmap cross-repo dependency is resolved.
  CLAUDE.md / `docs/architecture/004` updated to drop the "depends on upstream /
  until it lands" caveat.

### Verified

- `programs/_server_async_smoke.cyr` (forked: child serves, parent drives two
  sequential localhost requests across batch-drain → arena-reset → next-batch):
  2/2 → 200, PASS.
- 992 assertions green (440 + 167 + 343 + 42; unchanged — the async server is a
  live/forked smoke gate, not a backend-agnostic unit suite).
- Native + libssl smoke link; `cyrius lint` 0 warnings / 0 deferrals;
  `cyrfmt --check` clean; `dist/sandhi.cyr` regenerated at v1.4.9.

## [1.4.8] — 2026-06-09

**TLS backend flag-polarity flip (target convention) + interim green CI.**
Documentation/build-convention change; no functional source change (cyrius pin
stays **6.1.20**).

### Changed — TLS backend flag polarity flipped to native-as-no-flag-default

The repo's **target convention** is now: native is the no-flag default and
`-D CYRIUS_TLS_LIBSSL` is the explicit opt-in for the deprecated libssl bridge —
the inverse of the 1.4.5–1.4.7 `-D CYRIUS_TLS_NATIVE` opt-in. Applied across the
docs + gate programs: `CLAUDE.md` Quick Start + TLS note, `docs/architecture/004`,
the four `programs/*.cyr` gate comments + the probe skip message, and the
`src/tls_policy/mod.cyr` backend-selection header.

### Interim — CI/release keep `-D CYRIUS_TLS_NATIVE` until the cyrius flip lands

The target convention needs an **upstream cyrius change** that is NOT in the
pinned toolchain (6.1.20) or cyrius HEAD — `lib/tls.cyr` is still
`#ifdef CYRIUS_TLS_NATIVE` (native opt-IN; a no-flag build resolves to libssl,
verified directly). So `ci.yml` + `release.yml` **keep `-D CYRIUS_TLS_NATIVE`**
on the native smoke link-proof + the three native live gates
(`_policy_runtime_probe`, `_https_native_loop_gate`, `_https_policy_threading_gate`),
with an interim banner pointing at the filed cyrius issue; the libssl link-proof
builds with no flag (the real 6.1.20 default). This keeps CI **green and actually
exercising native** (native smoke 1.37 MB with the native stack linked vs 562 KB
libssl; all three native gates PASS) instead of the no-flag builds silently
falling back to libssl. When cyrius ships the inverted default and the pin moves
to it, drop `-D CYRIUS_TLS_NATIVE` from the native steps + add
`-D CYRIUS_TLS_LIBSSL` to the libssl step, and remove the banner.

### Filed — cyrius-side inverted-default (completes the flip)

`cyrius/docs/development/issues/2026-06-09-invert-tls-backend-default-native-no-flag.md`
— the exact `lib/tls.cyr` change (invert `#ifdef CYRIUS_TLS_NATIVE` →
`#ifndef CYRIUS_TLS_LIBSSL`: native compiled-in + default, `-D CYRIUS_TLS_LIBSSL`
opts out), keeping `-D CYRIUS_TLS_NATIVE` as a no-op alias for the transition,
plus the binary-size trade-off + acceptance criteria. Tracked as a roadmap
cross-repo dependency ("Inverted-default TLS build").

### Verified

- Native smoke (`-D CYRIUS_TLS_NATIVE`, DCE) links the native stack (1.37 MB);
  libssl smoke (no flag) builds (562 KB).
- All three native live gates PASS for real on the native build (not skip).
- 992 assertions green; `cyrius lint` 0 warnings / 0 deferrals; `cyrfmt --check`
  clean; `dist/sandhi.cyr` regenerated at v1.4.8.

## [1.4.7] — 2026-06-09

**Backend-aware TLS-policy enforcement — eliminates the live-network
SIGSEGV.** Fixes `docs/issues/2026-06-09-tls-policy-enforcement-live-segfault.md`:
the low-level policy openers crashed on a reachable network. No cyrius pin
change (sandhi-side fix; stays on 6.1.20).

### Fixed — TLS-policy enforcement SIGSEGV on a live network (both backends)

Two distinct faults, both now fail closed instead of crashing:
- **native + trust-store / mTLS** — `_sandhi_apply_hook` fed the *native*
  TLS ctx to libssl `SSL_CTX_load_verify_locations` / `_use_certificate_file`
  / `_use_PrivateKey_file` (resolved via `tls_dlsym`), which faults — those
  fns only apply to a libssl `SSL_CTX`.
- **libssl + SPKI pin** — a single libssl pinned open SIGSEGV'd in cyrius's
  libssl `tls_get_peer_spki_der` extraction (a **cyrius regression** on the
  deprecated backend — it worked at 1.3.0; localized: `[L-trust]` with a
  hooked handshake refuses cleanly, only `[L-pin]` faults, in the
  post-handshake SPKI read).

### Changed — `sandhi_tls_policy_enforcement_available()` is backend-aware (+1 verb)

- `sandhi_tls_policy_enforcement_available()` (trust-store / mTLS) now
  returns 0 on the **native** backend — there's no libssl `SSL_CTX` to
  configure, so a trust/mTLS policy **fails closed** (`SANDHI_ERR_TLS`)
  instead of faulting. (Available again once cyrius ships native
  `SSL_CTX_*` equivalents — cross-repo dep.)
- **New** `sandhi_tls_policy_pin_available()` — SPKI pinning is
  backend-agnostic (`tls_get_peer_spki_der`, 1.4.2), so it's available on
  native even with **no libssl present** (this is what lets high-level
  pinning work on a native-only box; the 1.4.6 gate previously skipped
  there). Excludes the libssl backend pending the cyrius SPKI fix, so
  libssl pinning fails closed rather than crashing.
- `_sandhi_policy_pre_open_a` (`src/tls_policy/apply.cyr`) now gates the
  two enforcement modes separately — trust/mTLS on `enforcement_available()`,
  pinning on `pin_available()` — and fails closed BEFORE arming the hook, so
  the faulting paths are never reached. Flows through the low-level
  `sandhi_conn_open_with_policy` and the 1.4.6 high-level threading alike.

### Changed — live gates

- `programs/_policy_runtime_probe.cyr` reworked + built native
  (`-D CYRIUS_TLS_NATIVE`, CI updated): per-backend availability report +
  default-policy / wrong-pin-fail-closed / trust-store-refused, all crash-free
  on the native default. (Switching backends mid-process after a native
  handshake destabilizes the deprecated libssl stack — not a real consumer
  scenario, noted in the probe + issue — so it tests native only; libssl
  crash-safety verified during development.)
- `programs/_https_policy_threading_gate.cyr` now gates on `pin_available()`
  instead of the libssl-coupled `enforcement_available()`, so it runs for
  real on native (incl. native-without-libssl) rather than skipping.

### Still tracked (cyrius-side, cross-repo)

The SIGSEGV is gone, but full enforcement parity needs cyrius: (a) native
`SSL_CTX_*` equivalents in `lib/tls_native.cyr` to make native trust-store /
mTLS *enforce* (not just fail closed); (b) fix the libssl
`tls_get_peer_spki_der` regression so libssl pinning works again. Both folded
into the roadmap "native TLS-policy enforcement" gate for libssl retirement.

### Verified

- 992 assertions green (440 + 167 + 343 + 42; unchanged — backend-agnostic
  unit suites; enforcement-availability is covered by the live gates, not
  unit-tested since it touches `tls_dlsym`).
- `programs/_policy_runtime_probe.cyr` (native, live): backend=native,
  pin_available=1, trust_mtls_available=0; default PASS, wrong-pin
  fail-closed (err=TLS), trust-store refused — no crash.
- `programs/_https_policy_threading_gate.cyr` (native, live): ALL GATES PASS.
- Isolation repro (dev): all four (backend × {pin, trust}) refuse cleanly,
  exit 0 — was SIGSEGV on libssl-pin and native-trust before.
- `cyrius lint` 0 warnings / 0 deferrals; `cyrfmt --check` clean.
- `dist/sandhi.cyr` regenerated at v1.4.7.

## [1.4.6] — 2026-06-09

**High-level client TLS-policy threading + cyrius pin 6.1.19 → 6.1.20.**
Closes the hoosh v2.2.0 P1: a TLS policy (cert pinning / mTLS /
trust-store) can now be attached to `sandhi_http_options` and is enforced
through the high-level `sandhi_http_*` request path — including
`sandhi_http_stream` — instead of only the low-level
`sandhi_conn_open_with_policy`. Wiring only; no new crypto.

### Added — `sandhi_http_options_tls_policy` (+2 verbs, `src/http/client.cyr`)

- `sandhi_http_options_tls_policy(opts, policy)` — attach a policy built
  via `sandhi_tls_policy_new_pinned` / `_new_mtls` / `_new_trust_store` /
  `_combine`. Default 0 = today's behavior (no enforcement).
- `sandhi_http_options_get_tls_policy(opts)` — getter (0 for null opts).
- Options struct grew 72 → 80 bytes (new slot at offset 72).

### Changed — HTTPS request path honors the attached policy

- `_sandhi_http_do_impl_a` (`src/http/client.cyr`) and
  `sandhi_http_stream_opts_a` (`src/http/stream.cyr`): when `opts` carries
  a policy and the scheme is HTTPS, the open is bracketed by
  `_sandhi_policy_pre_open_a` / `_sandhi_policy_post_open_a`
  (`src/tls_policy/apply.cyr`) — arm the `_sandhi_tls_hook_override` for
  trust-store / mTLS layering, then run the post-handshake SPKI pin check.
  The existing v4/v6 timed opener is reused, so connect/read/write
  deadlines + IPv6 are threaded for free.
- **Fail-closed**: if the policy demands enforcement and
  `sandhi_tls_policy_enforcement_available()` is 0, the request returns
  `SANDHI_ERR_TLS` rather than opening unpinned (matches ADR 0004).
- **Pool + 0-RTT bypass**: a policy-bound HTTPS request skips the
  connection pool (a pooled conn was opened under whatever policy created
  it; policy conns are single-use) and skips 0-RTT.
- Threaded via a module-level `_sandhi_tls_policy_pending` flag in the
  dispatch entry-points (save+restore, mirroring the 0-RTT / cred-digest
  flags); the streaming path reads the policy straight off `opts`. The
  policy applies to every hop of a redirect-follow within a dispatch (a
  pinned host that 30x's cross-authority fails closed on the next hop's
  SPKI — the safe default; per-hop re-pin waits for a consumer ask).

### Changed — module order (`cyrius.cyml` + program/test includes)

- `tls_policy/policy.cyr` + `fingerprint.cyr` + `apply.cyr` moved ahead of
  `http/client.cyr` / `http/stream.cyr` so the high-level paths call the
  policy pre/post-open helpers directly under cyrius's single-pass model.
  The trio depends only on `conn.cyr` (ALPN wire + hook-override globals)
  + stdlib + sigil, so it rides high in the order. 25 program/test include
  blocks reordered to match; no behavioral change for any module.

### Added — live gate `programs/_https_policy_threading_gate.cyr`

Native-built (`-D CYRIUS_TLS_NATIVE`). Three gates vs one.one.one.one:
no-policy GET succeeds (unset path unchanged); WRONG-pin GET fails closed
with `err=TLS`; a pin captured live from the peer SPKI succeeds (proves
pinning accepts a matching cert, not just "always reject"). Skip-cleanly
offline. Wired into CI. The SPKI path is backend-agnostic since 1.4.2, so
this gate is live-safe on native.

### Changed — cyrius pin 6.1.19 → 6.1.20

Mechanical bump (zero runtime source change). cyrius 6.1.20 folds sandhi
1.4.5 into `lib/sandhi.cyr` (the consumer-side companion to 6.1.19's TLS
fixes) and lands a macho-arm `*at()`/stat Darwin syscall port — **not
sandhi-facing** (arm64-macOS backend only; x86 / aarch64-Linux
byte-identical). Silences the toolchain-drift warning against the local
6.1.20 cycc.

### Filed — pre-existing TLS-policy enforcement live SIGSEGV (not 1.4.6)

`docs/issues/2026-06-09-tls-policy-enforcement-live-segfault.md`: the
**low-level** `sandhi_conn_open_with_policy` faults on a LIVE network in
the still-libssl-coupled enforcement (libssl SPKI read on the libssl
backend; trust-store `SSL_CTX_*` config on the native backend). Pre-exists
1.4.6 (reproduces on pristine `main`); `programs/_policy_runtime_probe.cyr`
skip-cleans offline so CI stays green. Tied to the tracked "native
TLS-policy enforcement" gate for full libssl retirement. The 1.4.6
high-level gate deliberately exercises only the backend-agnostic SPKI
path, which is live-safe. **Caveat (same root):** because
`sandhi_tls_policy_enforcement_available()` gates on libssl symbol
resolution (not backend-aware), the high-level pinning path fails closed —
and the new gate skip-cleans — on a native build where **libssl is not
present** (minimal CI runners); it works wherever libssl is installed
(local dev, most distros). Making SPKI-pin availability backend-aware is
part of the filed P2.

### Verified

- 992 assertions green (440 sandhi + 167 h2 + 343 alloc + 42 rpc; +13 over
  1.4.5's 979 — new `alloc/146/` groups: tls_policy roundtrip, pending-flag
  default, options-layout-intact).
- `programs/_https_policy_threading_gate.cyr` (native, live): ALL GATES
  PASS — no-policy 200, wrong-pin fail-closed TLS, correct-pin 200.
- `cyrius build -D CYRIUS_TLS_NATIVE programs/smoke.cyr` green.
- `cyrius lint` 0 warnings / 0 untracked deferrals; `cyrfmt --check` clean.
- `dist/sandhi.cyr` regenerated at v1.4.6.

## [1.4.5] — 2026-06-09

**Native TLS by default + P1 repeated-request SIGSEGV fixed + cyrius
pin 6.0.87 → 6.1.19.** Root-caused the hoosh-reported 4th-request HTTPS
crash to an upstream cyrius allocator/fdlopen bug, switched sandhi's default
TLS backend to the native stack, and re-pinned to cyrius 6.1.19 which lands
the two upstream root fixes — verified end-to-end.

### Fixed — P1: HTTPS repeated-request SIGSEGV (root cause = upstream; fixed 6.1.19)

`sandhi_http_get`/`_post` to one HTTPS host SIGSEGV'd on the ~4th
sequential call (reported by hoosh v2.2.0;
`docs/issues/2026-06-09-https-repeated-request-segfault.md`). Traced to
**cyrius `lib/alloc.cyr`'s `brk(2)` bump heap colliding with glibc
malloc's brk arena** (pulled in by `lib/fdlopen.cyr` loading libssl) —
two brk managers, one program break; the collision lands when cyrius's
heap first grows past its initial 1 MB (request #4, given the high-level
client leaks ~256 KB/request into `default_alloc()`). **Not a sandhi
conn-lifecycle bug** — reproduces with zero sandhi code, and switching
the per-iter leak from `brk` `alloc()` to `mmap` eliminates it (the
smoking gun). Filed two upstream cyrius issues, **both fixed in cyrius
6.1.19**:
- `2026-06-09-brk-bump-heap-vs-fdlopen-libssl-malloc.md` — cyrius moved the
  Linux heap off raw `brk(2)` onto an **anonymous-`mmap` chunk-bump
  allocator**; no more brk-vs-glibc contention.
- `2026-06-09-native-tls-handshake-gap-public-servers.md` — cyrius fixed
  cert-chain / intermediate ordering so the native stack handshakes
  Cloudflare-fronted hosts (example.com), not just 1.1.1.1.

Verified at 6.1.19: **native** `sandhi_http_get` ×6 to example.com → 6/6
status 200, no crash (was handshake-fail at 6.1.18); **libssl opt-in** ×6 to
example.com → 6/6 status 200, EXIT 0 (was SIGSEGV/139 on the 4th).

### Changed — native TLS is the default backend; libssl is a deprecated opt-in

sandhi now defaults to the native TLS stack (`lib/tls_native.cyr`), which
loads no libssl/glibc and so has no brk contention — verified crash-free
(6/6 sequential native `sandhi_http_get` to one HTTPS host). The native
stack is the build default **only when compiled with `-D CYRIUS_TLS_NATIVE`**
(no manifest-level define exists); sandhi's build, CI, and Quick Start
pass it, and **consumers must too** to get the native default. See
`docs/architecture/004-native-tls-default.md`.

### Added — TLS backend-selection surface (+4 verbs, `src/tls_policy/mod.cyr`)

- `sandhi_tls_use_native()` — switch to native (returns -1 if not compiled in).
- `sandhi_tls_use_libssl()` — opt out to the deprecated libssl bridge
  (safe on repeated requests as of the 6.1.19 alloc fix; still deprecated).
- `sandhi_tls_backend()` — active backend (0 = libssl, 1 = native).
- `sandhi_tls_native_available()` — 1 if the native stack was compiled in.

### Fixed — unconditional `tls_get_session` session-ref leak (libssl path)

`_sandhi_conn_finalize_with_early_data_a` (`src/http/conn.cyr`) captured a
refcount-bumped `SSL_SESSION` on **every** TLS connection, even with the
session cache off (the default) — where `_store` is a no-op that never
frees it, leaking one session ref per connection on the libssl backend.
Gated the capture on `sandhi_session_cache_enabled()`.

### Added — P1 regression gate

`programs/_https_native_loop_gate.cyr` — N≥4 sequential native
`sandhi_http_get` to one HTTPS host must complete crash-free
(skip-cleanly when offline). Wired into CI; targets 1.1.1.1 (a host the
native stack handshakes today). CI also gains a libssl-path link proof so
the opt-in keeps building.

### Verified

- 979 assertions green (440 sandhi + 167 h2 + 330 alloc + 42 rpc;
  unchanged — backend-agnostic unit suites).
- Native HTTPS loop gate: backend=native, 6/6 requests OK, no crash (vs
  1.1.1.1). libssl path still builds.
- `cyrius build -D CYRIUS_TLS_NATIVE programs/smoke.cyr` green; libssl
  smoke build green.

### Notes

The two upstream cyrius P1 fixes landed in 6.1.19 (re-pinned here). Full
libssl *retirement* now has one remaining blocker: wiring TLS policy
enforcement (pinning / mTLS / trust-store in `apply.cyr`, still
`tls_dlsym`/libssl-coupled) for the native backend. Plain HTTPS is native
today; policy-bearing connections still imply libssl.

## [1.4.4] — 2026-06-07

**Closeout housekeeping batch: roadmap slot realignment +
`_sandhi_conn_connect_nb` factoring decision.** Two small closeout-arc
items; the only code change is a doc comment. No public-API or behavioral
change. (The sigil transitive-deps fix landed in 1.4.3, documented there.)

### Changed — `_sandhi_conn_connect_nb` factoring decision (option b)

Resolved the parked factoring slot. sandhi's `_sandhi_conn_connect_nb`
(nb-connect + `poll(POLLOUT)` + `SO_ERROR` readback) shares its shape
with cyrius `regression_network_probe`. Decision: **(b) parallel
evolution** — do not extract a shared `net_connect_nb` primitive.
Connect runs once per conn-open (not per request), so a shared primitive
would not measure. Documented at the callsite (`src/http/conn.cyr`) and
here; no code change, no cyrius dependency.

### Changed — roadmap slot-number realignment

The 1.4.x closeout-arc subsections still labeled the pending `max_conns`
/ `connect_nb` slots "1.4.1" / "1.4.2", but those version numbers shipped
other work (1.4.1 close-path framing fix; 1.4.2 ALPN/SPKI native-TLS
rewire; 1.4.3 buried-deferral sweep + pin + sigil deps). Renumbered to
the real sequence: `connect_nb` resolved here at 1.4.4; `max_conns`
enforcement → 1.4.5 (still gated on the worker-shape design pick).
Updated the shipped log + the "Why this roadmap exists" slot mapping.

Also refreshed `docs/development/state.md`'s live-state sections, which
had drifted to pre-fold / 1.4.0-era values: Toolchain pin → 6.0.87;
Fold-status → folded / post-fold maintenance; Source module
statuses/counts (dropped stale "scaffold"/"stubbed" on done modules —
`error`, `apply`, `local`); Tests → 979 across four suites;
Dependencies → actual `[deps]` (incl. the 1.4.3 `ct`/`keccak`/
`thread_local` crypto deps); Next → 1.4.5 as the unambiguous next-up.

### Verified

- 979 assertions green (440 sandhi + 167 h2 + 330 alloc + 42 rpc;
  unchanged — no behavioral change).
- `cyrius lint` 0 warnings, 0 untracked deferrals; `cyrfmt --check` clean.
- `cyrius build programs/smoke.cyr` green; `dist/sandhi.cyr` regenerated
  at v1.4.4.

## [1.4.3] — 2026-06-07

**Buried-deferral gate sweep (drains the 1.4.x closeout queue's P2
lead) + cyrius pin 6.0.82 → 6.0.87 + sigil transitive-deps fix.**
Bundled closeout housekeeping — the deferral drain is comment-only, the
pin bump is source-free, and the sigil fix is a `[deps]` / build-include
change (mirrors 1.3.4's annotation-pass + pin-bump bundling).

### Changed — buried-deferral gate drained + flipped to fail-mode

The CI cyrlint **buried-deferral gate** flags `src/` comments carrying
deferral vocabulary (`for now` / `out of scope` / `follow-up` /
`not yet` / `deferred` / `NOT_IMPLEMENTED`) that aren't cross-referenced
to a CHANGELOG / issue / roadmap entry. It ran in report mode (sub-`warn`,
so it never gated a ship). This slot drains every untracked deferral and
flips the gate to fail-mode.

- **12 sites drained.** The roadmap's enumerated list of 8 was an
  undercount — it missed 4 in `src/http/h2/`; the gate reports the full 12.
  Resolution per site:
  - **Real deferred work → tracked in roadmap** (per the
    no-silent-scope-outs rule), comment reworded to reference it:
    - `src/discovery/daimon.cyr` — resolver-ctx +8 reserved slot
      (auth token / timeouts).
    - `src/http/client.cyr` — per-hop cred-digest recompute on
      cross-authority redirect-follow (also CHANGELOG [1.3.3]).
    - `src/http/pool.cyr:31` — per-pool mutex / thread-safety.
    - four `src/http/h2/` items grouped under a new **h2
      spec-completeness** roadmap bullet: peer-SETTINGS `ENABLE_PUSH` /
      `MAX_HEADER_LIST_SIZE` enforcement (`conn.cyr`); HEADERS-frame
      buffer-cap override + request-body DATA-frame fragmentation
      (`request.cyr`); flow-control window manager (`response.cyr`).
    All land in the **Wait-for-second-consumer-ask** bucket — none is
    committed work; each unblocks on a consumer whose traffic exercises it.
  - **Incidental / permanent-by-design → reworded** to drop the trigger
    phrase: `src/discovery/local.cyr` (RFC 6763 DNS-SD is a distinct
    feature class, not a deferral); `src/http/pool.cyr:380` +
    `src/http/stream.cyr:116` (sentinel-value comments);
    `src/http/response.cyr:313` (historical narration of work that
    shipped at 1.1.1).
  - **False-positive on a constant name → `#skip-lint`**:
    `src/server/mod.cyr` `HTTP_NOT_IMPLEMENTED = 501` is the standard
    RFC 7231 §6.6.2 status constant, not a deferral.
- **Gate flipped to fail-mode** — `.github/workflows/ci.yml`'s lint step
  now fails on any `deferral line N: untracked` cyrlint output (previously
  only `warn` lines gated). Future untracked deferrals are caught at PR time.

### Changed — cyrius pin 6.0.82 → 6.0.87

Mechanical bump; zero sandhi source change. 6.0.83–6.0.87 are a TLS /
Windows / AGNOS-env band; the sandhi-relevant pieces are **full TLS
ciphersuite enablement** + **macOS native-TLS fixes** (directly relevant
since 1.4.2 put sandhi's transport on the sovereign native-TLS backend).
The Windows-pillar + AGNOS getenv/envp work is not sandhi-facing. Pin
floor 6.0.82 → 6.0.87 (latest 6.0.x; tested green).

### Fixed — sigil transitive deps (`sha256` linkage)

`src/tls_policy/apply.cyr`'s SPKI-pin digest calls sigil's one-shot
`sha256`, but sigil does not declare its own transitive deps
(`ct` / `keccak` / `thread_local`). With only `sigil` in `[deps] stdlib`,
`cyrius deps` left `sha256` unresolved — the symbol dropped from the link
(a `ud2` fixup that SIGILLs if the SPKI digest path executes). Fixed
sandhi-side, native-clean (no FFI): added `ct` / `keccak` /
`thread_local` to `[deps] stdlib`, and included the crypto chain
explicitly in `programs/_policy_runtime_probe.cyr` (the live-gate target)
so `sha256` links there. Verified `sha256` links and hashes correctly
(`SHA-256("ABC")` → `b5d4…`). This is sigil's packaging gap surfaced from
the consumer side; the fix is declaring the deps, never re-adding libssl
FFI (ADR 0001 / CLAUDE.md "No FFI"). The live SPKI gate's remaining fault
is in the **deprecated libssl backend**'s cert-extraction path (inside
libcrypto) — that backend is retiring for native TLS and is out of
sandhi's scope.

### Verified

- **Buried-deferral sweep**: 0 untracked deferrals across `src/` (was 12).
- **sigil `sha256`**: links + hashes correctly (`SHA-256("ABC")` → `b5d4…`).
- **979 assertions green** against the 6.0.87 snapshot (440 sandhi + 167
  h2 + 330 alloc + 42 rpc; unchanged — comment / pin / deps-list only).
- `cyrius lint` 0 warnings (modulo the `huffman.cyr` allowlist);
  `cyrfmt --check` clean across `src/` + `programs/` + `tests/`.
- `cyrius build programs/smoke.cyr` green; ELF OK.
- `dist/sandhi.cyr` regenerated via `cyrius distlib` at v1.4.3.

## [1.4.2] — 2026-06-06

### Changed

- **Dropped the ALPN-read + SPKI-pin libssl bindings** — moved onto cyrius 6.0.82's typed,
  backend-agnostic stdlib verbs `tls_get_alpn_selected` / `tls_get_peer_spki_der`. sandhi no
  longer reads the raw libssl `SSL*` (`load64(tls_ctx+8)`) or `tls_dlsym`-resolves
  `SSL_get0_alpn_selected` / `SSL_get1_peer_certificate` / `X509_get_pubkey` / `i2d_PUBKEY`
  for these post-handshake reads — they live in `lib/tls.cyr` now and work on either the
  libssl or the native TLS backend. Closes the cyrius native-TLS Mini-arc E consumer rewire:
  with this, sandhi runs over the sovereign native TLS transport (`tls_set_backend`) with no
  ALPN/SPKI libssl coupling. `_sandhi_alpn_read_selected` → `tls_get_alpn_selected`;
  `_sandhi_check_spki` → `tls_get_peer_spki_der` + SHA-256. Pinned cyrius 6.0.55 → 6.0.82.
  (The remaining `tls_dlsym` sites are pre-handshake `SSL_CTX_*` mTLS / trust-store config —
  a separate rewire when typed wrappers ship for those.) Tests: h2 167, sandhi 440 — green.

## [1.4.1] — 2026-06-03

**HTTP/1.1 `Connection: close` read path now frames by Content-Length /
chunked instead of draining until EOF + cyrius pin 6.0.1 → 6.0.55.** Fixes a
hang/timeout against servers that send a complete, Content-Length-framed
response with `Connection: close` but do not promptly close the socket —
notably **chromedriver** and **Chromium's DevTools** HTTP endpoint (filed
`docs/issues/2026-06-03-http-close-path-drains-until-eof.md`, surfaced by
yantra's M2 WebDriver work). `_sandhi_http_exchange_a` (the non-keep-alive
path, `src/http/client.cyr`) called `sandhi_conn_recv_all_deadline`, which
reads until EOF / max / deadline and never consults the framing headers; the
peer's complete CL-framed response sat buffered while the read blocked to the
deadline and returned `SANDHI_ERR_TIMEOUT`. Fix swaps in
`_sandhi_http_recv_framed` — the **same** incremental, header-framed reader the
keep-alive path (`_sandhi_http_exchange_keepalive_a`) has used since 0.8.0 — and
mirrors its `0 - 2` must-close-sentinel handling (the close path closes the conn
right after, so the sentinel just means "full response received"). EOF-delimited
HTTP/1.0 responses (no CL, no chunked) still work — `_sandhi_http_recv_framed`
returns the bytes read at EOF. No public API change; read-path behavior only.
**Verified**: live GET to chromedriver `/status` now returns `err_kind=0
status=200` (was `err_kind=4` TIMEOUT); a normal Content-Length+close server
still returns 200 (no regression). **979 assertions green** (440 sandhi + 167
h2 + 330 alloc + 42 rpc; unchanged — the fix reuses already-tested framing).
`cyrius lint` 0 warnings; `cyrfmt --check` clean. Pin floor 6.0.1 → 6.0.55
(latest 6.0.x; tested green). `dist/sandhi.cyr` regenerated at v1.4.1.

## [1.4.0] — 2026-05-22

**Session-cache TTL + max-size eviction (lead of 1.4.x
closeout arc).** Also closes two silent-prereq bugs carried
since 1.3.1 that prevented the cache from working in any
realistic environment.

### Added — TTL + max-size eviction

The 1.3.1 entry-struct slot documented as reserved for
`last_used_ms` is now wired up. Cache no longer grows
unbounded; entries age out + LRU-evict when at the size cap.

- **New public verbs** (+5):
  - `sandhi_session_cache_set_max_size(n)` — default 256.
    Clamps to 1 on `n < 1`.
  - `sandhi_session_cache_max_size()` — query current.
  - `sandhi_session_cache_set_max_age_ms(ms)` — default
    86_400_000 (24h). Clamps to 1 on `ms < 1`. TLS
    session-ticket lifetime is typically a few hours; 24h
    is the safe upper bound for "the server hasn't rotated
    keys this long ago."
  - `sandhi_session_cache_max_age_ms()` — query current.
  - `sandhi_session_cache_evict_count()` /
    `_age_evict_count()` — observability counters
    (eviction-on-insert and age-on-lookup respectively).
- **`sandhi_session_cache_clear()`** — drop every cached
  entry (releases SSL_SESSION* via `tls_session_free`, frees
  entry structs). Useful on logout / context-rotation /
  shutdown. Counters are NOT reset — call `_reset_stats()`
  for that.
- **Entry struct** — internal 16-byte struct
  `[session_ptr: i64, last_used_ms: i64]` allocated in
  `default_alloc()`. Same lifetime as the cached session
  (process-wide singleton); freed via `free_via` on eviction.
- **Eviction-on-insert** — when a NEW key arrives and
  `map_size() >= max_size`, `_sandhi_session_cache_evict_oldest()`
  walks all entries, finds the one with the smallest
  `last_used_ms`, and evicts it (releases the session,
  deletes the map key, frees the entry, bumps
  `evict_count`).
- **Age-check-on-lookup** — on a key-hit, if
  `now - last_used_ms > max_age_ms`, the entry is evicted
  (releases the session, deletes the key, frees the entry,
  bumps `age_evict_count` and `miss_count`) and lookup
  returns 0. Otherwise, `last_used_ms` is touched to `now`
  — which gives LRU semantics for the eviction walk.
- **Replace-in-place** when the key already exists — the
  prior entry struct is reused (just updates `session_ptr`
  + `last_used_ms`), so a re-store doesn't count against
  the eviction counter.

### Fixed — silent `hashmap_*` → `map_*` naming (1.3.1)

`src/tls_policy/session_cache.cyr` called `hashmap_new_a` /
`hashmap_get` / `hashmap_set_a` / `hashmap_len` — none of
which are stdlib symbols (stdlib exports `map_*` and
`map_u64_*`). cyrius warned `undefined function` and NOPed
the call sites, so every lookup returned 0 and every store
was silently a no-op. The cache was non-functional in
production since 1.3.1; the 1.3.1 / 1.3.3 round-trip tests
passed only because they skip-cleaned when
`sandhi_session_cache_enable(1) != 1` (which it always was,
since `map_new_a` NOPed → map=0 → enable refused). Fixed by
renaming every call site to `map_*` in this slot — same
patch that wires the eviction logic. Smoke build no longer
emits the `undefined function 'hashmap_*'` warnings.

### Fixed — `_sandhi_session_cache_key_a` strlen on 1-byte stack buffer (1.3.1)

The 1.3.1 key builder did `var ch[1]; store8(&ch, hex_char);
str_builder_add_cstr_a(..., &ch)`. The `_add_cstr_a` path
calls `strlen(cstr)` which reads until a null terminator —
past the 1-byte stack buffer, into whatever garbage the
stack happened to hold next. Same-content key builds could
yield different hashes depending on stack state. Surfaced
the moment the `map_*` rename above made map operations
real: the 1.4.0 replace-in-place test got 1 eviction
instead of 0 because the second store built a different
key from the first. Fixed by switching the per-hex-digit
append to `str_builder_add_byte(sb, hex_char)`.

### Changed — `enable()` contract relaxed

Pre-1.4.0: `sandhi_session_cache_enable(1)` returned 0 if
`tls_supports_session_resumption() == 0` (libssl didn't
have the four resumption symbols). Conflated two concerns
(sandhi-side flag vs. TLS-layer capability) and made every
gated test in alloc.tcyr skip-clean in CI environments
where libssl didn't fully resolve.

Post-1.4.0: `enable(on)` always succeeds (modulo init OOM)
— the cache initializes regardless of TLS capability, since
the cache itself is just a hashmap with no TLS dependency.
Production callers who want to short-circuit when the TLS
layer can't actually use cached sessions should call the
new **`sandhi_session_cache_supported()`** getter, which
returns `tls_supports_session_resumption()`.

The practical impact for production: in capability-missing
environments, `tls_get_session(ctx)` returns 0 and the
existing `if (sni_host == 0 || session == 0) { return 0; }`
guard on `store()` bails out — the cache stays empty in
production, same as before. The coverage win is that
tests (which use fake session pointers) now exercise the
cache logic for real instead of skip-cleaning.

Sandhi is the only consumer of these verbs (per the module
header), so the contract relax has no external migration
cost. The 1.3.1 / 1.3.3 round-trip tests' `if (rc != 1) {
skip; }` blocks are removed; they now `assert_eq(rc, 1)`.

### Tests

- **`tests/alloc.tcyr alloc/134/`** — 8 new test groups:
  - `defaults` — 256 / 86_400_000 / 0 / 0 unconditional.
  - `set_max_size_roundtrip` — set, get, clamp on `n<1`.
  - `set_max_age_ms_roundtrip` — set, get, clamp on `ms<1`.
  - `evict_counters_default_zero` — `_evict_count` /
    `_age_evict_count` start at 0; `_reset_stats()` clears.
  - `evict_oldest_at_max` — max=2, store 3 → oldest evicted,
    `evict_count == 1`.
  - `lookup_touch_promotes_lru` — max=2, store A, B, lookup A
    (touches), store C → B (now oldest) evicted, not A.
    Uses `while (clock_now_ms() <= t) { }` busy-waits to
    force monotonic clock progression between operations.
  - `replace_in_place_no_evict` — max=1, store A, store A
    again → size 1, `evict_count == 0` (no LRU charge for
    replace).
  - `age_evict_on_lookup` — `max_age = 1ms`, store, busy-wait
    5ms past, lookup → miss, `age_evict_count == 1`,
    `miss_count == 1`.
- **`tests/alloc.tcyr alloc/131/` + `alloc/133/`** — updated
  to remove the `if (rc != 1) { skip; }` blocks; the round-
  trip + cache-isolates tests now run unconditionally
  against the cache (was always skip-clean in CI before).
- Total: 938 → **979 assertions green** (+41: 8 new alloc/134
  groups carrying 22 asserts; +9 from gated tests now running
  for real; +10 from updated 131/133 tests asserting the new
  enable() contract; alloc total 289 → 330).
- All four suites unchanged structurally: 440 sandhi + 167
  h2 + 330 alloc + 42 rpc.
- `cyrius lint` 0 warnings on `src/tls_policy/session_cache.cyr`;
  `cyrfmt --check` clean. Smoke build no longer emits the
  long-standing `hashmap_*` undefined warnings.

### Why these three landed together

The three fixes are causally linked. The TTL + eviction
work needs a functioning hashmap underneath (fix 1). Once
the map works, key-build determinism matters (fix 2). And
once key builds are deterministic, tests can stop
skip-cleaning to actually exercise the logic (fix 3). Each
fix individually couldn't ship until all three landed —
each one's correctness depends on the others. Bundled per
the cyrius v5.10.0 "items sharing the same cascade" rule.

## [1.3.5] — 2026-05-22

**Cyrius pin 5.11.4 → 6.0.1 + binary-rename adaptation.**
Mechanical bump; no runtime / codegen change in sandhi sources.

Cyrius v6.0.0 (2026-05-19) renamed the two compiler binaries:
`cc5` → `cycc` (Cyrius Computer Compiler) and `cyrc` → `cybs`
(Cyrius Bootstrap). Back-compat symlinks `cc5 → cycc` and
`cc5_aarch64 → cycc_aarch64` ship in `~/.cyrius/versions/<v>/bin/`
through v6.0.x and drop at v6.1.0; `cbt/core.cyr`'s
compiler-lookup fallback handles the same direction for the
runtime. So sandhi's `cyrius build` / `cyrius test` / `cyrius
lint` / `cyrius distlib` invocations are unaffected — they go
through the `cyrius` CLI wrapper either way.

Cyrius v6.0.1 (same day) is a hotfix for two stdlib-resolution
path bugs surfaced by the v6.0.0 cycle-open (`_init_cyrius_lib`
+ `_check_cyml_pin_drift` skip-prefix off-by-one missing the
extra char in `"cycc "` vs `"cc5 "`, plus a `cmd_deps`
mkdir-before-find regression that broke `cyrius deps` for
downstream repos with both `src/main.cyr` and a non-empty
`stdlib = [...]` pin). Neither bug affected sandhi at the
intervening 5.11.4 → 6.0.0 hop, but pinning 6.0.1 is the
right floor going forward.

### Changed

- **`cyrius.cyml`** `[package].cyrius` pin: `5.11.4` → `6.0.1`.
- **`.github/workflows/ci.yml`** + **`release.yml`** —
  cross-arch aarch64 step prefers `$HOME/.cyrius/bin/cycc_aarch64`,
  falls back to `cc5_aarch64` during the v6.0.x back-compat
  window (so v5.x snapshot installs still on PATH keep
  working). Warning text updated to name `cycc_aarch64`.
- **`CLAUDE.md`** hard-constraints — "Do not bypass `cyrius
  build` with raw `cc5` invocations" → `cycc`. Same intent
  (don't reach past the build CLI); new binary name.

### Verified

- `cyrius build programs/smoke.cyr build/sandhi-smoke`: green.
- `dist/sandhi.cyr` regenerated via `cyrius distlib` at v1.3.5.
- Test counts unchanged (no source change): 938 assertions
  green (440 sandhi + 167 h2 + 289 alloc + 42 rpc).
- `cyrius lint` / `cyrfmt --check`: clean.

## [1.3.4] — 2026-05-11

**Stdlib annotation pass + cyrius pin 5.10.34 → 5.11.4.**

Every public fn across the 703-fn `src/` tree (http/, http/h2/,
tls_policy/, net/, obs/, etc.) carries a `: i64` return-type
annotation. Mechanical sed pass; 15 multi-line fn signatures
hand-fixed (`_sandhi_http_do_a` family + `_sandhi_conn_open_*`
family + `sandhi_h2_request_*` family). Parse-only, zero
runtime / codegen change.

`dist/sandhi.cyr` regenerated via `cyrius distlib` at v1.3.4
(11598 lines). Ready for next cyrius-side fold-in slot.

### Verified

- `cyrius build programs/smoke.cyr build/sandhi-smoke`: green.
- Dead-code report unchanged.

## [1.3.3] — 2026-05-10

**Cred-strip-aware session-cache keying.** The 1.3.1 session
cache was keyed on `(sni_host, hook_fp_hex)` — sufficient for
default-policy and policy-bound paths, but didn't distinguish
auth contexts. If a consumer rotated `Authorization` /
`Cookie` / `Proxy-Authorization` headers across requests to the
same authority + same hook, the cache reused the same TLS
session across both auth contexts. Not a security regression
at the TLS layer (the server still authenticates per-request
using the new HTTP-envelope headers), but a layering concern:
the 0.9.0 cred-strip rules deliberately invalidate cached state
on auth-context change at the redirect layer, and the session
cache should mirror that for symmetry.

### Added

- **`src/http/client.cyr`** — two new internal helpers:
  - `_sandhi_fnv1a_mix(h, s)` — running FNV-1a 64-bit byte-mixer.
    Same offset basis / prime as stdlib `hash_str` (see
    `lib/hashmap.cyr`). Lets the cred digest chain multiple
    header values into one accumulator without losing entropy
    across them.
  - `_sandhi_compute_cred_digest(headers)` — folds the values
    of `Authorization` / `Cookie` / `Proxy-Authorization`
    (case-insensitive lookup via `sandhi_headers_get`) into a
    64-bit digest. Per-header marker prefix (`A:` / `C:` /
    `P:`) before each value prevents same-value collisions
    across header names. Returns 0 when no cred-bearing
    headers are present — preserves the pre-1.3.3 cache-key
    shape for the common service-to-service path.
- **`src/http/conn.cyr`** — module-level `_sandhi_cred_digest`
  flag (mirrors the `_sandhi_alpn_advertise_h2` and
  `_sandhi_allow_0rtt` precedents). Set by dispatch entry-points
  for the duration of the request; read by the staged-connect
  finalize when computing the session-cache key.

### Changed

- **`src/tls_policy/session_cache.cyr`** — three signatures
  gained the `cred_digest` arg. Internal verb (sandhi is its
  own only consumer of these verbs; 1.3.1 added them, so
  signature evolution this soon stays inside sandhi):
  - `_sandhi_session_cache_key_a(a, sni_host, hook_fp, cred_digest)`
    renders the digest as a second 16-hex-digit suffix:
    `<sni>|<hook_fp_hex>|<cred_digest_hex>`.
  - `sandhi_session_cache_lookup(sni_host, hook_fp, cred_digest)`.
  - `sandhi_session_cache_store(sni_host, hook_fp, cred_digest, session)`.
- **`src/http/conn.cyr:_sandhi_conn_finalize_with_early_data_a`**
  — the lookup / store calls inside the staged-connect TLS
  branch now pass `_sandhi_cred_digest` as the third key
  component. When the dispatch hasn't set the flag (e.g.
  pool-take of an already-resumed h2 conn whose finalize ran
  earlier), the flag stays at 0 and key shape collapses to
  the 1.3.1 default-digest path.
- **`src/http/client.cyr:_sandhi_http_dispatch_a`** and
  **`src/http/h2/dispatch.cyr:sandhi_http_request_auto_a`** —
  both save+restore `_sandhi_cred_digest` around their
  internal dispatch (mirror of the 1.3.2 0-RTT-flag pattern).
  `_sandhi_compute_cred_digest(headers)` runs once at dispatch
  entry; the conn finalize reads the latched value.

### Notes

- **Default-zero-digest preserves the common path.** Sandhi
  consumers that don't rotate cred-bearing headers (the AGNOS
  service-to-service majority) see no behavior change. Cache
  hit-rate, key shape, and storage cost are identical to 1.3.2
  for that case.
- **Auth rotation now invalidates cache reuse.** When a
  consumer flips Authorization (e.g. token refresh), the
  digest changes → cache miss → fresh handshake. The old
  entry stays in cache until 1.3.4's TTL evicts it (still
  provisional).
- **Redirect-layer cred-strip integration is partial.** The
  0.9.0 cred-strip rules drop sensitive headers on
  cross-authority redirects (`_sandhi_strip_sensitive_headers_a`).
  The dispatch-level `_sandhi_compute_cred_digest` runs once
  per top-level dispatch, so a redirect from authority A to
  authority B uses the **original** digest for the B-authority
  handshake. Consumers don't typically combine cred-bearing
  headers with cross-authority redirects today (cross-origin
  cred handling is a request-level concern, not a TLS-layer
  one), so this is flagged in the dispatch comment but not
  remediated here. If a consumer ever needs per-hop digest
  rotation, the natural slot is to fold the recompute into
  `_sandhi_http_follow_a`'s hop loop alongside the existing
  cred-strip step.
- **Carry-over scope-out**: 1.3.4 (session-cache TTL +
  max-size eviction) stays provisional in the roadmap.

### Tests

- **`tests/alloc.tcyr alloc/133/`** — 7 new groups:
  - `cred_digest_empty` — null + empty headers → digest 0.
  - `cred_digest_non_cred_headers` — Accept / User-Agent /
    X-Custom don't perturb the digest.
  - `cred_digest_authorization` — different values → different
    digests; same value → same digest.
  - `cred_digest_cookie_and_proxy` — Cookie + Proxy-Authorization
    each yield non-zero digests; per-header marker prefix
    prevents same-value collisions across header names.
  - `cred_digest_case_insensitive_header_name` — lowercase /
    uppercase / mixed-case header names yield the same digest
    (mirrors `sandhi_headers_get` semantics).
  - `cache_isolates_by_cred_digest` — same `(host, hook_fp)`
    under different `cred_digest` → distinct cache slots;
    digest 0 → 3rd distinct slot. Skip-clean when libssl
    can't resume.
  - `cred_digest_flag_default` — module-level flag defaults to 0.
- **`tests/alloc.tcyr alloc/131/`** — pre-existing 4 groups
  updated to use the new 3/4-arg signatures (pass 0 for
  `cred_digest`). No assertions changed; coverage of the
  1.3.1 host/hook_fp dimensions stays identical.
- Total: 924 → 938 passing (+14 new assertions in 1.3.3
  groups; sandhi.tcyr / h2 / rpc unchanged).

## [1.3.2] — 2026-05-10

**TLS 1.3 0-RTT (early data), opt-in.** Composes the cyrius
v5.10.21 0-RTT primitives + v5.10.27 staged-connect + v5.10.34
status accessors into safe client-side 0-RTT with
rejection-detection retry. Default OFF — caller opts in per
request, and sandhi gates internally on replay-safe method +
libssl capability + session-cache hit + cached-session
`max_early_data` budget. Closes the 1.3.1 follow-up the
0-RTT-status filing was blocking on.

### Toolchain

- **cyrius pin** bumped 5.10.31 → 5.10.34. v5.10.34 closed
  the 0-RTT-status gap filed in
  `docs/issues/archive/2026-05-10-stdlib-tls-early-data-status.md`:
  added `tls_get_early_data_status(ctx)` and
  `tls_session_get_max_early_data(session)`, both with safe
  defaults (NOT_SENT / 0) when libssl lacks the underlying
  `SSL_get_early_data_status` / `SSL_SESSION_get_max_early_data`
  symbols. Without these accessors, sandhi can't tell whether
  the server processed early data — and silent failure to
  detect rejection would resend nothing on a stream where the
  request was discarded.

### Added

- **Public surface** — 2 verbs + 1 status accessor:
  - `sandhi_http_options_allow_0rtt(opts, on)` — per-request
    opt-in. Default 0 (off).
  - `sandhi_http_options_get_allow_0rtt(opts)` — query.
    Null-opts guard returns 0 (matches the rest of the
    getter family).
  - `sandhi_conn_0rtt_status(conn)` — exposes the
    `TLS_EARLY_DATA_*` value latched at handshake completion.
    `0` = NOT_SENT, `1` = REJECTED, `2` = ACCEPTED.
- **`src/http/client.cyr:_sandhi_method_is_replay_safe(method)`**
  — RFC-8446-§8 replay safety classifier. GET / HEAD /
  OPTIONS only; everything else silently refuses 0-RTT even
  when the caller opts in. Case-sensitive (per RFC 7230 §3.1.1).

### Changed

- **`src/http/conn.cyr`** — staged-connect finalize gained
  early-data parameters:
  - `_sandhi_conn_finalize_a` becomes a back-compat wrapper
    forwarding `early_data = 0, early_data_len = 0` to the
    new `_sandhi_conn_finalize_with_early_data_a`. Pre-1.3.2
    callers (h2 ALPN promotion, plain-TLS path without 0-RTT)
    see no behavior change.
  - After `tls_set_session(ctx, cached)`, the new finalize
    checks `tls_session_get_max_early_data(cached) >= early_data_len`
    and calls `tls_write_early_data(ctx, ed, ed_len)` when
    the cached session advertises the budget. Otherwise
    early-data is silently dropped and the request goes
    through the normal stream — same shape as a NOT_SENT
    outcome.
  - After `tls_connect_complete`, the finalize captures
    `tls_get_early_data_status(ctx)` into the new conn-struct
    slot `SANDHI_CONN_OFF_0RTT_STATUS`. Conn struct grew
    from 32 to 40 bytes (one extra `i64` slot).
- **`src/http/client.cyr:_sandhi_http_do_impl_a`** — request
  bytes now built BEFORE conn-open so the request can be
  passed in as `early_data`. The request build only depends
  on URL / headers / body / keep-alive, none of which change
  across conn-open paths, so this is a pure refactor for
  every non-0-RTT exchange.
- **`src/http/client.cyr:_sandhi_http_exchange_a`** and
  **`_sandhi_http_exchange_keepalive_a`** — both gained a
  status check at entry:
  - ACCEPTED (2): skip the request send (already sent as
    early data; server processed it), go straight to recv.
  - REJECTED (1): send the request normally via `tls_write`
    — handshake is complete, the early data the server
    discarded never reached the request handler, so this is
    a clean retry on the established stream.
  - NOT_SENT (0): existing path (covers all plaintext, all
    non-resumed TLS, and the disabled-0-RTT majority).
- **`src/http/client.cyr:_sandhi_http_dispatch_a`** and
  **`src/http/h2/dispatch.cyr:sandhi_http_request_auto_a`** —
  read `sandhi_http_options_get_allow_0rtt(opts)` and set
  the module-level `_sandhi_allow_0rtt` flag for the
  duration of the dispatch. Mirrors the existing
  `_sandhi_alpn_advertise_h2` pattern (set transiently,
  restored after) — keeps the per-call state out of every
  fn signature in the call tree. h2 auto-path doesn't
  enable 0-RTT for h2 today; the CONNECTION preface vs.
  early-data ordering still needs a milestone of its own.
- **cyrius.cyml** — pin bumped 5.10.31 → 5.10.34.

### Notes

- **Default-off is load-bearing.** Replay attacks on 0-RTT
  are real (RFC 8446 §8 spells out the threat model). Even
  with the method-safety filter, idempotent-on-the-wire ≠
  idempotent-in-effect (a GET that increments a counter is
  GET-shaped but not safe to replay). Default-off + per-request
  opt-in keeps the choice with the caller.
- **Three filters must all pass.** Caller opts in (`allow_0rtt = 1`)
  AND method is replay-safe (GET/HEAD/OPTIONS) AND
  `tls_supports_early_data()` returns 1 AND the session cache
  is enabled AND there's a cached session for this route AND
  the cached session's `max_early_data >= req_len`. Any
  failure silently falls back to the normal stream — no
  surprises, no error surfacing for a perf feature.
- **Carry-over scope-outs** still tracked for 1.3.3 / 1.3.4
  (cred-strip-aware cache keying / TTL + max-size eviction)
  per the roadmap.

### Tests

- **`tests/alloc.tcyr alloc/132/`** — 4 new groups:
  - `options_allow_0rtt_roundtrip` — setter/getter, default,
    null-opts guard.
  - `method_is_replay_safe` — full GET/HEAD/OPTIONS/POST/PUT/
    PATCH/DELETE coverage + case-sensitivity check.
  - `allow_0rtt_flag_default` — module-level flag defaults
    to 0.
  - `conn_0rtt_status_accessor` — accessor reads the
    correct offset for all three status values.
  - Total: 257 → 275 passing (18 new assertions).
- **`tests/sandhi.tcyr`** — 440 passing, unchanged (the
  0-RTT path adds no new public verbs to the main surface
  beyond the opts setter/getter exercised in alloc.tcyr).

## [1.3.1] — 2026-05-10

**TLS 1.3 / 1.2 client-side session-resumption cache.** First
release where sandhi composes the cyrius v5.10.21 session
primitives + v5.10.27 staged-connect API into actual
session reuse. Closes the 1.3.0 follow-up the staged-connect
filing was blocking on.

### Toolchain

- **cyrius pin** bumped 5.10.21 → 5.10.31. v5.10.27 (2026-05-09)
  shipped the staged-connect API (Option A from
  `docs/issues/archive/2026-05-09-stdlib-tls-staged-connect.md`):
  `tls_connect_alloc(sock, host, hook_fp, hook_ctx)` +
  `tls_connect_complete(ctx)`. v5.10.31 is current cyrius head;
  the typed-simd ABI work in v5.10.28–.31 is unrelated to
  sandhi but ships in the resync.
- The 5.10.27 → 5.10.31 stdlib resync brings typed return-type
  annotations across `lib/*` (no semantic change for sandhi —
  bare versions still work; typed annotations are forward-
  facing).

### Added

- **`src/tls_policy/session_cache.cyr`** (~190 lines) — process-
  wide singleton cache for `SSL_SESSION*` keyed by
  `(sni_host, hook_fp_hex)`. The hook pointer in the key
  prevents cross-policy contamination (default-ALPN hook
  vs. policy hook = different SSL_CTX config = incompatible
  session). Cache uses `default_alloc()` (sessions outlive
  any per-request arena, same shape as pool's `_hsv_req_buf`
  / HPACK static).
- **Public surface** — 7 verbs:
  - `sandhi_session_cache_enable(on)` — opt-in toggle.
    Returns 1 when libssl supports session resumption,
    0 otherwise (capability-gated; bails on first call
    if `tls_supports_session_resumption()` is 0).
  - `sandhi_session_cache_enabled()` — query current state.
  - `sandhi_session_cache_lookup(sni_host, hook_fp)` —
    returns cached session or 0; bumps hit/miss stats.
  - `sandhi_session_cache_store(sni_host, hook_fp, session)`
    — store; replaces prior entry (frees via
    `tls_session_free` if any).
  - `sandhi_session_cache_size()` — entry count.
  - `sandhi_session_cache_hit_count()` /
    `sandhi_session_cache_miss_count()` — observability.
  - `sandhi_session_cache_reset_stats()` — counter reset.

### Changed

- **`src/http/conn.cyr:_sandhi_conn_finalize_a`** — TLS path
  switched from one-shot `tls_connect_with_ctx_hook` to
  staged-connect:
  ```
  ctx = tls_connect_alloc(fd, sni, hook_fp, hook_ctx);
  cached = sandhi_session_cache_lookup(sni, hook_fp);
  if (cached != 0) { tls_set_session(ctx, cached); }
  if (tls_connect_complete(ctx) != 1) { close + return 0; }
  fresh = tls_get_session(ctx);  # refcount-bumped
  if (fresh != 0) { sandhi_session_cache_store(sni, hook_fp, fresh); }
  ```
  When the cache is disabled (default), lookup returns 0
  and store is a no-op — adds one global-load + early-
  return per call. **Zero overhead for callers who don't
  opt in.**
- **`cyrius.cyml [lib].modules`** — `src/tls_policy/session_cache.cyr`
  inserted between `src/http/url.cyr` and `src/http/conn.cyr`
  so single-pass compilation sees the cache fns at conn.cyr
  parse time.
- **25 program/test files** updated to add
  `include "src/tls_policy/session_cache.cyr"` before
  `include "src/http/conn.cyr"` (forward-ref under
  single-pass compilation).

### Tracked for follow-up slots

The cache lands functional but with two known limitations
that ride into pinned 1.3.x slots — see `roadmap.md` for
detail. Both are provisional and may shift order based on
consumer asks:

- **1.3.3 — cred-strip-aware session-cache keying** —
  cache key currently uses `(sni_host, hook_fp_hex)` only.
  Auth-bearing-header digest extension lands here.
- **1.3.4 — session-cache TTL + max-size eviction** —
  cache grows unbounded today; `last_used_ms` slot is
  reserved on the entry struct for the eviction logic.
- **1.3.2 — TLS 1.3 0-RTT** — composes the same
  primitives on top of an installed session. Stays the
  next-up TLS-arc slot since 0-RTT is the obvious value
  pair to session resumption.

### Verified

- 4 new test groups (7 assertions) under `alloc/131/`:
  `session_cache_default_off`,
  `session_cache_enable_capability_gated`,
  `session_cache_store_lookup_roundtrip`,
  `session_cache_disabled_noops`.
- 257/257 `tests/alloc.tcyr` (250 pre-existing + 7 new).
- 440/440 sandhi, 167/167 h2, 42/42 rpc — no regression.
- **Live-network gate**: `programs/_policy_runtime_probe.cyr`
  ALL GATES PASS against 1.1.1.1:443 (default policy
  round-trip / wrong-pin fail-closed / non-existent
  trust-store) — confirms the staged-connect rewrite
  preserves existing behavior.
- **906 assertions green** total (+7 over 1.3.0's 899).
- `cyrius lint` 0 warnings on `src/tls_policy/session_cache.cyr`,
  `src/http/conn.cyr`. `cyrfmt --check` clean.

### Pinned next

- **1.3.2** — TLS 1.3 0-RTT (opt-in via
  `sandhi_http_options_allow_0rtt`). Composes
  `tls_ctx_set_max_early_data` / `tls_write_early_data`
  / `tls_read_early_data` on top of an installed
  session. Replay-safe methods only per RFC 8446 §8.
- **1.3.3** — cred-strip-aware session-cache keying
  (provisional, may slip). Adds an auth-bearing-header
  digest to the cache key so requests with different
  auth contexts don't share a session.
- **1.3.4** — session-cache TTL + max-size eviction
  (provisional, may slip). Bounded cache size +
  age-based eviction; uses the `last_used_ms` slot
  reserved on the entry at 1.3.1.

## [1.3.0] — 2026-05-09

**Opens the 1.3.x TLS arc** — live-network TLS-policy gate
+ typed-wrapper migration onto cyrius v5.10.13's
`tls_set_alpn`. Pairs the two: both are sandhi-side
responses to the same `lib/tls.cyr` cascade.

### Toolchain

- **cyrius pin** bumped 5.10.0 → 5.10.21. Picks up
  v5.10.13 typed wrappers (`tls_set_alpn` /
  `tls_set_verify`) + v5.10.20 P(-1) hardening sweep +
  **v5.10.21 TLS surface completion** (full session-
  resumption + 0-RTT primitive set; the unblockers for
  1.3.1 / 1.3.2 — see "what 1.3.0 doesn't use yet"
  below). Plus cyrius v5.9.42 testing-stdlib carve-out
  (`regression_network_probe`).
- **`regression`** added to `[deps] stdlib`. Powers
  the live-gate skip-cleanly cascade.

### Typed-wrapper migration

Sandhi previously called `tls_dlsym("SSL_CTX_set_alpn_protos")
+ fncall3` directly, binding to the libssl symbol name +
ABI. Cyrius v5.10.13 added `tls_set_alpn(handle, protos,
len)` typed wrapper; v1.3.0 swaps two sites:

- **`src/http/conn.cyr`** `_sandhi_alpn_hook` →
  `tls_set_alpn` direct. Retired
  `_sandhi_alpn_set_fp` cache.
- **`src/tls_policy/apply.cyr`** `_sandhi_apply_hook`
  → same swap. Retired `_sandhi_apply_set_alpn_fp`.
  `sandhi_tls_policy_enforcement_available()` gate
  now uses `tls_available()` for the ALPN bit
  instead of the retired fp cache.

`SSL_get0_alpn_selected` and the 7 other libssl
symbols sandhi reaches stay on `tls_dlsym` — no typed
wrappers exist for them yet (per `lib/tls.cyr`'s
soft-deprecation note: typed wrappers are the
preferred surface, dlsym is escape-hatch). The
`lib/tls.cyr` hook-surface contract audit on cyrius's
v5.10.31 slot will likely surface more typed-wrapper
candidates.

### Live-network TLS-policy gate

Upgraded `programs/_policy_runtime_probe.cyr` into a
CI-grade gate. Mirrors cyrius `_tls_live_gate`
skip-cleanly cascade:

1. `tls_available()` — skip cleanly if missing.
2. `regression_network_probe(1.1.1.1, 443, 3000)` —
   skip cleanly if unreachable in 3s.
3. `sandhi_tls_policy_enforcement_available()` —
   FAIL exit 1 if libssl present but sandhi-side
   resolve gap.

Live gates against 1.1.1.1:443 / one.one.one.one SNI:

- `[2]` **default policy** must succeed end-to-end
  (exit 2 on regression).
- `[3]` **wrong SPKI pin** must fail-closed with
  `err_kind == SANDHI_CONN_OPEN_TLS` (exit 3 on
  fail-open / security regression; exit 4 on wrong
  err classification).
- `[4]` **non-existent trust_store path** — soft
  warning (some libssl builds keep system-CA
  defaults loaded; documented as environment quirk).

**mTLS intentionally NOT exercised** — needs a
self-signed-server fixture; pinned for a future slot.

Locally: ALL GATES PASS against 1.1.1.1:443.

### CI integration

`.github/workflows/ci.yml` gains a "Live-network
TLS-policy gate" step. Builds + runs the probe;
exits 0 on PASS or clean SKIP, non-zero on real
regression. CI runners with no network skip-cleanly.

### Verified

- Live gate exits 0 with ALL GATES PASS locally.
- 440/440 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr`,
  250/250 `tests/alloc.tcyr`, 42/42 `tests/rpc.tcyr` —
  no regression. **Total: 899 assertions green** (no
  delta from 1.2.8 — 1.3.0's deliverable is the live
  gate, not unit tests).
- `cyrius lint` 0 warnings on touched files;
  `cyrfmt --check` clean.

### What 1.3.0 doesn't use yet (and why 1.3.1 / 1.3.2 are still blocked)

The 5.10.21 pin pulls in cyrius's full TLS surface-completion
landing — **12 new typed wrappers / capability probes** that
1.3.1 (session resumption) and 1.3.2 (TLS 1.3 0-RTT) compose:

- Session resumption: `tls_get_session(ctx)`,
  `tls_set_session(ctx, session)`, `tls_session_free(session)`.
- Session-cache callbacks: `tls_ctx_set_session_new_cb` /
  `_remove_cb` / `_get_cb` / `_cache_mode`.
- Early data: `tls_ctx_set_max_early_data` / `tls_write_early_data`
  / `tls_read_early_data`.
- Capability probes: `tls_supports_early_data()` /
  `tls_supports_session_resumption()`.

1.3.0 itself doesn't compose any of these — its deliverable is
the live-network gate over the existing surface.

**1.3.1 / 1.3.2 surfaced an additional cyrius-side gap during
slot scoping**: `tls_set_session(ctx, session)` is documented
as "install a previously-cached session before tls_connect to
attempt resumption", but cyrius's `tls_connect_with_ctx_hook`
runs `SSL_CTX_new → hook → SSL_new → SSL_set_fd → SSL_ctrl(SNI)
→ SSL_connect` in one shot. The hook fires on `SSL_CTX*`
(pre-`SSL_new`); `tls_set_session` accesses the SSL handle from
`ctx+8`, which only exists post-handshake. **There's no timing
window between `SSL_new` and `SSL_connect`** for sandhi to
inject the cached session for client-side resumption.

The cyrius-side fix is either a staged-connect API
(`tls_connect_alloc` + `tls_connect_complete`) or a post-`SSL_new`
hook variant. Filed as
[`docs/issues/archive/2026-05-09-stdlib-tls-staged-connect.md`](docs/development/issues/archive/2026-05-09-stdlib-tls-staged-connect.md).
Sandhi 1.3.1 / 1.3.2 wait on cyrius landing it.

### Pinned next

- **WAIT** for cyrius staged-connect API
  (`docs/issues/archive/2026-05-09-stdlib-tls-staged-connect.md`).
  Sandhi 1.3.1 / 1.3.2 are blocked at the call-sequence layer
  even though all primitive fns exist.
- **1.3.1** when unblocked — compose `tls_get_session` /
  `tls_set_session` + the cache-callback set into a
  sandhi-side cache keyed by `(host, port, alpn)`. Respect
  0.9.0 cred-strip rules.
- **1.3.2** when 1.3.1 lands — TLS 1.3 0-RTT (opt-in via
  `sandhi_http_options_allow_0rtt`). Replay-safe methods only
  per RFC 8446 §8.

The `lib/tls.cyr` hook-surface contract audit (cyrius v5.10.31)
is independent of these and rides separately.

## [1.2.8] — 2026-05-08

**1.1.0-era OOM-guard audit + tests/sandhi.tcyr cap relief.**
Bundled slot per cyrius v5.10.0's "items sharing the same
cascade" rule — both are test-infrastructure / hardening
work. Final sandhi-side release before holding for cyrius-
side TLS hooks (1.3.1 / 1.3.2 unblockers).

### 1.1.0-era OOM-guard audit (extending 1.2.6 / 1.2.7)

1.2.6 closed OOM-SIGSEGV gaps in 1.2.0–1.2.4 additions;
1.2.7 closed the same shape on the server send path. This
slot extends the audit to the ~150 `_a` variants added at
1.1.0. Most leaf-level `_a`s already null-check (their
`alloc/batch1/`–`batch6/` tests cover the OOM contract).
**Three real findings**:

1. **`src/http/h2/response.cyr:239`** — SIGSEGV-on-OOM.
   `var headers = sandhi_headers_new_a(a)` returned 0,
   passed unguarded to `_h2_decode_response_headers_a`,
   which calls `sandhi_headers_add_a(a, h=null, ...)` →
   `vec_push_a(a, h=null, ...)` → SIGSEGV. **Fixed**:
   null-check, return `_sandhi_resp_err_a(a, SANDHI_ERR_INTERNAL)`.

2. **`src/http/sse.cyr:300`** — SIGSEGV-on-OOM.
   `var events = vec_new_a(a)` not guarded; subsequent
   `vec_push_a(a, events=null, ev)` at line 320 →
   SIGSEGV. **Fixed**: null-check, return 0.

3. **`src/http/client.cyr:689`** (`_sandhi_resolve_location_a`)
   — partial-arena leak. Used `str_builder_new()` (default
   alloc) for intermediate URL scratch; the final cstr
   was dup'd into `a` correctly, but the scratch builder
   leaked into the global allocator. Not a SIGSEGV, but
   a 1.1.0 arena-correctness violation. **Fixed**:
   threaded `str_builder_new_a` + `_a` variants; OOM
   null-guard added.

Other 1.1.0 paths surveyed and confirmed safe: 5
`sandhi_url_parse_a` callsites all null-check; 2
`vec_new_a` callsites in `src/http/h2/hpack.cyr` guard
at `+2`; `sandhi_headers_parse_a` guards at `+1`. **The
audit is now complete across every `_a` verb in the
codebase** — 1.1.0, 1.2.0–1.2.4, 1.2.7 server.

### tests/sandhi.tcyr cap relief

`tests/sandhi.tcyr` was at the per-program-fixup-table
cap (architecture/001). Carved the RPC test cluster out
into new `tests/rpc.tcyr`:

- 17 fns moved verbatim: 10 `test_json_*`, 3
  `test_dispatch_err_*`, 4 `test_webdriver_*`, 3
  `test_mcp_*`. Plus 20 corresponding `test_group(...)`
  calls.
- New `tests/rpc.tcyr` mirrors `tests/sandhi.tcyr`'s
  include block.
- Total assertions unchanged: 482 sandhi.tcyr split
  into 440 sandhi + 42 rpc.

### CI plumbing rides along

`.github/workflows/ci.yml` now runs `tests/alloc.tcyr`
(added at 1.1.0, never wired into CI) AND the new
`tests/rpc.tcyr`. Pre-1.2.8 CI only ran `sandhi.tcyr` +
`h2.tcyr`; the alloc suite (143 → 250 assertions across
1.1.0–1.2.8) was never CI-verified. Pre-existing gap
closed.

### Verified

- `tests/alloc.tcyr` gains 4 new test groups (7
  assertions) under `alloc/128/`:
  `h2_response_headers_alloc_oom`, `sse_parse_oom`,
  `resolve_location_arena`, `resolve_location_oom`.
- 250/250 alloc, 440/440 sandhi (post-split), 42/42 rpc
  (new), 167/167 h2 — no regression.
- **Total: 899 assertions green** (+7 over 1.2.7's 892).
- `cyrius lint` 0 warnings; `cyrfmt --check` clean.

### Pinned next

The OOM-guard audit story is now complete across the
entire codebase. The 1.2.x optimization arc that opened
at 1.2.0 closes here. **Holding for cyrius-side TLS
hooks** (1.3.1 session resumption, 1.3.2 0-RTT) before
the next sandhi-side slot. 1.3.0 (live-network TLS-
policy gate) is unblocked but pinned by user direction.

## [1.2.7] — 2026-05-08

**Batch G — server `_a` paint + OOM guards.** Closes the same
SIGSEGV-on-OOM gap that 1.2.6 found in the RPC dialect verbs,
this time on the server send-path. Four `_send_*` verbs in
`src/server/mod.cyr` were using `str_builder_new()`
(default_alloc) without null-check before the next
`str_builder_add_cstr_a` — same exact pattern as the dialect
verbs from 1.2.6. Painted `_a` variants on top + landed the
guards in the same patch, per the 1.2.6 process note ("future
`_a` verb additions should land with their OOM regression
test").

### Added (4 new public `_a` verbs)

- `sandhi_server_send_status_a(a, cfd, code, msg)`
- `sandhi_server_send_response_a(a, cfd, code, msg, content_type, body, body_len, extra_headers)`
- `sandhi_server_send_204_a(a, cfd, extra_headers)`
- `sandhi_server_send_chunked_start_a(a, cfd, code, content_type, extra_headers)`

All four thread `a` through `str_builder_new_a` /
`_add_cstr_a` / `_add_int_a` / `_build_a`. Bare versions
become back-compat wrappers passing `default_alloc()`.

### Return shape

The bare versions historically returned 0 (success only —
sock_send errors silently dropped, separate quality issue not
in scope). The `_a` variants return:
- **0** on success (str_builder built + sock_send invoked).
- **-1** on OOM (str_builder_new_a returned 0; sock_send not
  called). Matches the lib/str.cyr `_sb_grow_a` `0 - 1`
  convention.

Bare versions return whatever the `_a` returns — under
`default_alloc()` that's always 0 in practice. Arena callers
get the OOM signal.

### NOT paired (intentionally)

- **`sandhi_server_send_chunk`** / **`_send_chunked_end`**:
  use stack-local `var hexbuf[32]` for the chunk-length
  encoding; no allocation. No `_a` needed.
- **`sandhi_server_recv_request`**: reads into a caller-
  supplied buffer; no allocation. No `_a` needed.
- **`sandhi_server_run`** / **`_run_opts`**: server lifecycle,
  not per-request. The one alloc (`_hsv_req_buf` lazy
  singleton) is intentionally pinned to `default_alloc()`
  (process-wide singleton, outlives any per-request arena).
- **`sandhi_server_options_*`** getters / setters: pure
  load64/store64. No allocation.
- **Status accessors** (`sandhi_server_body_offset`,
  `_content_length`, `_request_has_dup_smuggling_header`,
  `_request_has_cl_te_conflict`): pure search/parse, return
  int. No allocation.

### Verified

- `tests/alloc.tcyr` gains 5 new test groups (7 assertions)
  under `alloc/127g/`: `send_status_oom`,
  `send_response_oom`, `send_204_oom`,
  `send_chunked_start_oom`, `send_status_arena_roundtrip`.
- Each OOM test drives `fail_after_n_allocs(0)` through
  the `_a` and asserts -1 return. Without the guards,
  these would have SIGSEGV'd identical to the rpc dialect
  cases 1.2.6 fixed.
- 243/243 alloc tests pass (236 pre-existing + 7 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 892 assertions green** (+7 over
  1.2.6's 885).
- `cyrius lint` 0 warnings on `src/server/mod.cyr`.
  `cyrfmt --check` clean.

### Pinned next

The OOM-guard audit story is now complete for every `_a`
verb shipped post-1.1.0 (1.2.0–1.2.7). The 1.1.0 era
additions remain unaudited; could open as a future slot
if a leaf-level gap surfaces.

- **1.2.8+** — open. Wait for cyrius-side TLS hooks
  (1.3.1/1.3.2 unblockers), or pick another sandhi-side
  item if one surfaces.
- **1.3.0** — live-network TLS-policy gate. **Awaiting**
  cyrius-side hook extensions.

## [1.2.6] — 2026-05-08

**OOM-guard audit on 1.2.0–1.2.4 `_a` additions.** Bug-class
fix slot. During 1.2.0 dev the OOM regression test for
`_sandhi_client_build_request_va` caught a SIGSEGV: when
`str_builder_new_a` returned 0, the next `str_builder_add_cstr_a`
dereferenced null. The fix at the time was a single guard. This
slot walks every `_a` variant added across 1.2.0–1.2.4 looking
for the same pattern and closes the systemic gaps.

### Findings — two patterns, ~14 sites

**Pattern A — recv-buffer alloc in HTTP exchange** (2 sites
in `src/http/client.cyr`):
- `_sandhi_http_exchange_a`: `var rbuf = alloc_via(a, cap+1)`
  followed by `sandhi_conn_recv_all_deadline(conn, rbuf=0, ...)`
  → SIGSEGV on rbuf dereference inside the recv loop.
- `_sandhi_http_exchange_keepalive_a`: same shape, with the
  added quirk that the request + body have already been sent
  by the time we OOM, so the conn must be closed (don't pool-
  put a mid-response conn).

Fix: null-check after `alloc_via`, close the conn, return
`_sandhi_resp_err_a(a, SANDHI_ERR_INTERNAL)`.

**Pattern B — `sandhi_json_obj_new_a` + `_add_*_a` chain in
RPC dialect verbs** (~12 sites across `src/rpc/{webdriver,
appium,mcp}.cyr`):
- `var body_obj = sandhi_json_obj_new_a(a)` returns 0 on OOM.
- Subsequent `sandhi_json_add_string_a(a, body_obj=0, ...)`
  calls `vec_push_a(a, v=0, ...)` which does `load64(v + 8)`
  unguarded → SIGSEGV.
- Stdlib `vec_push_a` doesn't null-check `v` (matches its
  contract: caller's responsibility).

Fix at every call site: null-check after `sandhi_json_obj_new_a`,
return `_sandhi_rpc_resp_new_a(a, 0, 0, 0, SANDHI_ERR_INTERNAL, 0)`.

Same shape applied to:
- `_sandhi_wd_build_path_a` and `_sandhi_wd_build_element_suffix_a`
  helpers — null-check after `str_builder_new_a`, return 0.
- `sandhi_wd_navigate_to_a`, `_find_element_a`,
  `_element_attribute_a`, `_element_send_keys_a`,
  `_execute_script_a`.
- `sandhi_ap_new_session_a` (3 nested obj_new_a — 3 guards),
  `_set_context_a`, `_install_app_a`, `_remove_app_a`,
  `_activate_app_a`, `_terminate_app_a`, `_mobile_exec_a`
  (which has both an obj_new_a and a str_builder_new_a path).
- `_sandhi_mcp_build_request_a` (returns 0 cleanly, propagated
  through callers via `sandhi_rpc_call_a`'s existing null-body
  handling).
- `sandhi_rpc_mcp_stream_a` (guards both build_request and
  headers_new; returns `_sandhi_stream_result_a(a, 0, 0,
  SANDHI_ERR_INTERNAL, 0)`).

### Verified

- `tests/alloc.tcyr` gains 9 new test groups (10 assertions)
  under `alloc/126/`: `exchange_path_arena`,
  `wd_navigate_to_oom`, `wd_find_element_oom`,
  `wd_element_attribute_oom`, `wd_build_helper_oom`,
  `ap_set_context_oom`, `ap_new_session_oom`,
  `mcp_build_request_oom`, `mcp_stream_oom`.
- Each OOM test drives a `fail_after_n_allocs(0)` allocator
  through the public verb. Without the guards, at least 7
  of these would have SIGSEGV'd (Pattern B sites). With the
  guards, every path returns gracefully — either an
  err-resp with `SANDHI_ERR_INTERNAL` or 0 if the err-resp
  alloc itself OOMs (double-OOM).
- 236/236 alloc tests pass (226 pre-existing + 10 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 885 assertions green** (+10 over
  1.2.5's 875).
- `cyrius lint` 0 warnings on touched files. `cyrfmt --check`
  clean.

### Pinned next

The OOM-class audit is closed for 1.2.0–1.2.4. Future `_a`
verb additions should land with their OOM regression test
in the same patch.

- **1.2.7+** — profile-justified optimizations once
  real-workload prof data lands (1.2.5 captures available).
- **1.3.0** — live-network TLS-policy gate. **Awaiting**
  cyrius-side hook extensions for 1.3.1 / 1.3.2.

## [1.2.5] — 2026-05-08

**Profile instrumentation — opens the next optimization arc.**
1.2.0–1.2.4 closed the hot-path allocator review with
speculation-driven candidates that mostly didn't pan out
on close inspection (HPACK Huffman tie-break is a no-op
when huff_len == raw_len; `_sandhi_resp_new` is already a
single 48-byte alloc; pool LRU waits for second consumer).
This slot adds the measurement tooling so future
optimization picks land with profile data, not guesses.
Mirrors cyrius v5.10.0's `_prof_*_end` capture pattern,
adapted for runtime (sandhi is called many times per
process; captures reset per request).

### Added

- **obs/prof** — new module `src/obs/prof.cyr` (~140
  lines). Default-off; enable via `sandhi_prof_enable(1)`.
- **Phase enum** (5 captured boundaries):
  `SANDHI_PROF_PHASE_REQUEST_START` (0),
  `_URL_PARSE_END` (1), `_DNS_END` (2),
  `_CONN_OPEN_END` (3), `_REQ_BUILD_END` (4),
  `_EXCHANGE_END` (5).
- **Public surface** (8 verbs): `sandhi_prof_enable`,
  `sandhi_prof_enabled`, `sandhi_prof_reset`,
  `sandhi_prof_capture`, `sandhi_prof_record_recv`,
  `sandhi_prof_get`, `sandhi_prof_recv_cap`,
  `sandhi_prof_recv_used`. Plus the
  `SANDHI_PROF_PHASE_*` enum constants.

### Wired into

- `_sandhi_http_do_impl_a` (`src/http/client.cyr`) —
  reset at entry; capture at each phase boundary.
  Captures fire on both success and error-path early
  returns where the exit point is informative.
- `_sandhi_http_exchange_a` and
  `_sandhi_http_exchange_keepalive_a` —
  `sandhi_prof_record_recv(cap, nread)` after the recv
  loop closes.

### Cost

- Disabled (default): one global-load + early-return per
  capture point; one branch per phase boundary. Zero
  allocations, zero syscalls.
- Enabled: one `clock_now_ns()` per capture (single
  `syscall(228, 4, &ts)` ≈ 100 ns on x86_64); five
  captures per request = ~500 ns/request overhead.
  Negligible against any real network round-trip.

### Verified

- `tests/alloc.tcyr` gains 5 new test groups (14
  assertions) under `alloc/125/`:
  `prof_disabled_default`, `prof_capture_monotonic`,
  `prof_reset_clears`, `prof_recv_buf`,
  `prof_real_request_arena`.
- 226/226 alloc tests pass (212 pre-existing + 14 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 875 assertions green** (+14
  over 1.2.4's 861).
- `cyrius lint` 0 warnings; `cyrfmt --check` clean.
- 14 program/test files updated to include
  `src/obs/prof.cyr` after `src/obs/trace.cyr`.
- `cyrius.cyml` `[lib].modules` registers
  `src/obs/prof.cyr` immediately after
  `src/obs/trace.cyr` so consumers including
  `lib/sandhi.cyr` post-fold get the prof surface
  for free.

### Why now

After 1.2.0–1.2.4 realized the 1.1.0 migration intent,
the natural next move was profile-driven optimization.
But every profile-justified candidate I'd seeded into
the roadmap turned out to be either a no-op or a
wait-for-consumer-ask. Rather than ship more speculation,
this slot installs the measurement so the next
optimization picks are concrete: when 1.2.6+ proposes a
hot-path change, the CHANGELOG will show before/after
numbers from these captures, not "profile-grade"
hand-waving.

### Pinned next

- **1.2.6+** — profile-justified optimizations once
  real-workload data lands (consumer code enables prof
  captures and reports). No pre-committed picks.
- **1.3.0** — live-network TLS-policy gate. Pure CI
  infra; no cyrius dep. **Awaiting** cyrius-side hook
  extensions for 1.3.1 (session resumption) and 1.3.2
  (TLS 1.3 0-RTT) — to be filed against `lib/tls.cyr`.

## [1.2.4] — 2026-05-08

**Batch F — RPC dialect `_a` (closes the optimization arc).**
Final batch of the hot-path allocator review opened at 1.2.0.
Paint-on-top wrappers atop `sandhi_rpc_call_a` (paired since
1.1.0). The MCP / WebDriver / Appium dialects now thread the
allocator end-to-end through URL construction, JSON envelope
build, and the RPC dispatch.

### Added (30 new public `_a` verbs)

- **rpc/mcp** (5): `sandhi_rpc_mcp_call_a`,
  `sandhi_rpc_mcp_call_with_headers_a`,
  `sandhi_rpc_mcp_result_raw_a`,
  `sandhi_rpc_mcp_error_message_a`,
  `sandhi_rpc_mcp_stream_a`. Plus internal helper
  `_sandhi_mcp_build_request_a` threading every
  `sandhi_json_*_a` call. Note: `sandhi_rpc_mcp_error_code`
  is intentionally not paired — it returns an int via
  `sandhi_json_get_int` (no allocation).
- **rpc/webdriver** (14): `sandhi_wd_new_session_a`,
  `sandhi_wd_extract_session_id_a`,
  `sandhi_wd_delete_session_a`, `sandhi_wd_navigate_to_a`,
  `sandhi_wd_get_url_a`, `sandhi_wd_get_title_a`,
  `sandhi_wd_find_element_a`,
  `sandhi_wd_extract_element_id_a`,
  `sandhi_wd_element_click_a`, `sandhi_wd_element_text_a`,
  `sandhi_wd_element_attribute_a`,
  `sandhi_wd_element_send_keys_a`, `sandhi_wd_status_a`,
  `sandhi_wd_execute_script_a`. Plus internal helpers
  `_sandhi_wd_build_path_a` and
  `_sandhi_wd_build_element_suffix_a`.
- **rpc/appium** (11): `sandhi_ap_new_session_a`,
  `sandhi_ap_get_contexts_a`, `sandhi_ap_set_context_a`,
  `sandhi_ap_current_context_a`, `sandhi_ap_install_app_a`,
  `sandhi_ap_remove_app_a`, `sandhi_ap_activate_app_a`,
  `sandhi_ap_terminate_app_a`, `sandhi_ap_mobile_exec_a`,
  `sandhi_ap_source_a`, `sandhi_ap_screenshot_a`.

All bare versions stay as back-compat wrappers passing
`default_alloc()`. Public-surface change: **+30 `_a` verbs**.

### Optimization arc summary (1.2.0 → 1.2.4)

The hot-path allocator review opened at 1.2.0 closes here.
Cumulative public-surface changes across the arc:

- **1.2.0 Batch A** — internal foundation; +0 public verbs
  (internal `_a`s only). Audit findings + buggy
  `_sandhi_client_build_request_a` fixed.
- **1.2.1 Batches B+C** — internal cascade closure
  (redirect / auto / retry / sensitive-headers); +1 public
  verb (`sandhi_http_request_auto_a`).
- **1.2.2 Batch D** — top-level public verbs;
  +6 (`sandhi_http_get_a` / `_post_a` / `_put_a` /
  `_patch_a` / `_delete_a` / `_head_a`).
- **1.2.3 Batch E** — opts / retry / auto user-facing;
  +12 (2 `_opts` + 4 `_retry` + 6 `_auto`).
- **1.2.4 Batch F** — RPC dialects; +30 (5 mcp + 14
  webdriver + 11 appium).

**Total post-1.1.0 public `_a` surface: +49 verbs** —
every public alloc-touching path now has an `_a`
counterpart letting consumers pass an arena allocator
end-to-end. The 1.1.0 migration intent is fully
realized.

### Verified

- `tests/alloc.tcyr` gains 4 new test groups (10
  assertions) under `alloc/124f/`:
  `mcp_build_request_arena`,
  `mcp_build_request_with_params_arena`,
  `wd_build_helpers_arena`, `wd_join_arena`. The dialect
  verbs themselves don't have a clean "garbage URL → arena
  err-resp" path (their `sandhi_rpc_call` invocation goes
  through `_sandhi_http_dispatch` whose error path predates
  the arena-aware shape), so coverage focuses on the JSON
  envelope build and URL helpers.
- `tests/alloc.tcyr` includes extended: pulled in
  `src/rpc/appium.cyr` and `src/rpc/mcp.cyr` so the test
  program reaches the new `_a` variants.
- 212/212 alloc tests pass (202 pre-existing + 10 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 861 assertions green** (+10
  over 1.2.3's 851).
- `cyrius lint` — 0 warnings on `src/rpc/mcp.cyr`,
  `src/rpc/webdriver.cyr`, `src/rpc/appium.cyr`.
  `cyrfmt --check` clean on touched files.

### Pinned next

The **hot-path allocator review arc is now closed**.
Further allocator work moves into the "Optimization-grade,
profile first" bucket of the roadmap — wait for profile
evidence on a real workload before evangelizing
arena-per-request adoption to AGNOS consumers.

The next active arc is **1.3.x — TLS arc** (live-network
TLS-policy gate, session-resumption cache, TLS 1.3 0-RTT)
per the post-fold roadmap.

## [1.2.3] — 2026-05-08

**Batch E — opts / retry / auto user-facing `_a`.**
Paint-on-top wrappers atop the dispatch / retry / auto paths
threaded by 1.2.0–1.2.2.

### Added (12 new public `_a` verbs)

- **http**: `_opts` family (2 verbs) — `sandhi_http_get_opts_a`,
  `sandhi_http_post_opts_a`. Thin wrappers calling
  `_sandhi_http_dispatch_a(a, ...)`.
- **http**: `_retry` family (4 verbs) — `sandhi_http_get_retry_a`,
  `sandhi_http_head_retry_a`, `sandhi_http_put_retry_a`,
  `sandhi_http_delete_retry_a`. Thin wrappers calling
  `_sandhi_http_retry_a(a, ...)`.
- **http/h2**: `_auto` family (6 verbs) —
  `sandhi_http_get_auto_a`, `sandhi_http_head_auto_a`,
  `sandhi_http_post_auto_a`, `sandhi_http_put_auto_a`,
  `sandhi_http_patch_auto_a`, `sandhi_http_delete_auto_a`.
  Thin wrappers calling `sandhi_http_request_auto_a(a, ...)`.
  Note: `sandhi_http_request_auto_a` itself shipped at 1.2.1
  as part of Batch C; the per-method paint lands here.

All bare versions stay as back-compat wrappers passing
`default_alloc()`. Public-surface change: **+12 `_a` verbs**.
Combined with Batch D (1.2.2 — 6 verbs), the total post-1.1.0
public `_a` surface for the HTTP request path is now **18 new
public verbs**, all consumer-callable end-to-end with arena
allocators.

### Verified

- `tests/alloc.tcyr` gains 4 new test groups (14
  assertions) under `alloc/123e/`: `opts_arena`,
  `retry_arena`, `auto_body_less_arena`,
  `auto_body_bearing_arena`. Each drives an unparseable
  URL so the err-resp path threads `a` end-to-end.
- 202/202 alloc tests pass (188 pre-existing + 14 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 851 assertions green** (+14
  over 1.2.2's 837).
- `cyrius lint` — 0 warnings on `src/http/client.cyr`,
  `src/http/retry.cyr`, `src/http/h2/dispatch.cyr`.
  `cyrfmt --check` clean on touched files.

### Pinned next

- **1.2.4 — Batch F**: RPC dialect entries
  (`sandhi_rpc_mcp_call_a`, `sandhi_rpc_call_a` +
  webdriver / appium / mcp-stream verbs). Closes the
  hot-path allocator review arc.

## [1.2.2] — 2026-05-08

**Batch D — top-level public verbs `_a`.** First release with
consumer-visible end-to-end arena adoption. Internal cascade
has been fully `_a`-threaded since 1.2.1; this slot just
paints the public-verb wrappers on top.

### Added

- **http**: new `_a` variants for the six top-level public
  verbs:
  - `sandhi_http_get_a(a, url, user_headers)`
  - `sandhi_http_post_a(a, url, user_headers, body, body_len)`
  - `sandhi_http_put_a(a, url, user_headers, body, body_len)`
  - `sandhi_http_patch_a(a, url, user_headers, body, body_len)`
  - `sandhi_http_delete_a(a, url, user_headers)`
  - `sandhi_http_head_a(a, url, user_headers)`

  Each is a thin wrapper calling `_sandhi_http_dispatch_a(a, ...)`.
  The bare versions become back-compat wrappers passing
  `default_alloc()`. **Net public-surface change: +6 `_a`
  verbs.** Mirrors the `sandhi_http_stream` /
  `sandhi_http_stream_a` pairing that shipped at 1.1.0 and
  the `sandhi_h2_request` / `sandhi_h2_request_a` pairing
  shipped alongside it.

### Consumer adoption pattern

A caller can now use a per-request arena end-to-end:

```cyr
var arena = arena_allocator(8192);
var headers = sandhi_headers_new_a(arena);
sandhi_headers_set_a(arena, headers, "Authorization", "Bearer ...");
var resp = sandhi_http_get_a(arena, "https://api.example.com/v1", headers);
# inspect resp here — body, headers, status all live in `arena`
reset_via(arena);
# arena is empty; reuse for the next request
```

This is the contract the 1.1.0 `_a` migration was scaffolded
for; 1.2.0–1.2.1 closed the orchestration-layer leaks; 1.2.2
exposes it through the public surface.

### Verified

- `tests/alloc.tcyr` gains 5 new test groups (13
  assertions) under `alloc/122d/`: `get_arena`,
  `post_arena`, `delete_head_arena`, `put_patch_arena`,
  `get_arena_round_trip` (multiple calls across
  `reset_via`).
- 188/188 alloc tests pass (175 pre-existing + 13 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 837 assertions green** (+13
  over 1.2.1's 824).
- `cyrius lint src/http/client.cyr` — 0 warnings.
  `cyrfmt --check` clean on touched files.

### Pinned next

- **1.2.3 — Batch E**: `_opts` / `_retry` / `_auto`
  user-facing variants (`sandhi_http_get_opts_a` etc.,
  `sandhi_http_get_retry_a`, `sandhi_http_get_auto_a`,
  per-method).
- **1.2.4 — Batch F**: RPC dialect entries
  (`sandhi_rpc_mcp_call_a` and friends).

## [1.2.1] — 2026-05-08

**Batches B + C bundled — redirect-following + auto-dispatch
+ retry threading.** Closes the 1.2.0 partial-arena leaks on
`follow=1` and the auto-dispatch / retry call paths. Batch B
(`_sandhi_http_follow_a`) and Batch C (`_sandhi_http_auto_*_a`
family + `_sandhi_http_retry_a`) bundled into one slot per
the cyrius v5.10.0 "items sharing the same cascade" rule —
retry calls auto, so they're a single cascade rather than
two independent slots.

### Changed

- **http**: new `_sandhi_http_follow_a` — redirect chain
  driver with `a` threaded through every hop. Each
  `_sandhi_http_do_a` call lands in the caller's arena;
  cross-authority cred-strip uses `_sandhi_strip_sensitive_headers_a`;
  Location resolution uses `_sandhi_resolve_location_a`.
  Closes the 1.2.0 TODO at `_sandhi_http_dispatch_a`'s
  follow=1 branch (the bare `_sandhi_http_follow` call is
  replaced by `_sandhi_http_follow_a(a, ...)`).
- **http**: new `_sandhi_strip_sensitive_headers_a` —
  cross-authority redirect cred-strip now allocates the
  filtered headers block from `a`. Bare version stays as
  back-compat. OOM on the fresh-block alloc returns 0
  cleanly (matches the 1.1.0 graceful-OOM pattern).
- **http/h2**: new `_sandhi_http_try_h2_promote_a` —
  ALPN-promotion path threads `a` through DNS resolve
  + non-blocking connect + ALPN handshake. The h2 conn
  stored in the pool keeps using `sandhi_h2_conn_new`'s
  internal allocator (h2 conn outlives any per-request
  arena, so it's intentionally pool-scoped).
- **http/h2**: new `_sandhi_http_auto_once_a` — h2 take /
  ALPN promote / 1.1 fallback all uniformly threaded:
  pool h2-take routes through `sandhi_h2_request_a(a, ...)`,
  ALPN promote via `_try_h2_promote_a`, and the 1.1 fall-
  through via `_sandhi_http_do_a(a, ...)`.
- **http/h2**: new `_sandhi_http_auto_follow_a` and
  `sandhi_http_request_auto_a` — auto-dispatch redirect
  chain + top-level dispatcher with per-hop `a` threading.
- **http**: new `_sandhi_http_retry_a` in
  `src/http/retry.cyr` — retry-with-backoff loop now
  routes each attempt through `sandhi_http_request_auto_a(a, ...)`,
  inheriting the h2 pool selection that 0.9.5 wired up
  while threading the caller's allocator through the
  full retry loop. Note: each attempt's response struct
  lives in `a`; arena callers who reuse the arena across
  attempts overwrite the previous response's bytes —
  retry callers typically only inspect the last response,
  which the back-compat shape already returns.
- All bare versions (`_follow`, `_auto_once`, `_auto_follow`,
  `request_auto`, `_retry`, `_try_h2_promote`,
  `_strip_sensitive_headers`) preserved as back-compat
  wrappers calling the `_a` variant with `default_alloc()`.
  Public surface unchanged in this slot.

### Verified

- `tests/alloc.tcyr` gains 6 new test groups (20
  assertions) under `alloc/121bc/`:
  1. `strip_sensitive_arena` — `_a` filters
     Authorization / Cookie / Proxy-Authorization, leaves
     non-reserved headers, arena round-trip + reset.
  2. `strip_sensitive_oom` — `fail_after_n_allocs(0)`
     returns 0 from the fresh-block alloc gracefully.
  3. `follow_err_resp_arena` — `_follow_a` against an
     unparseable URL exercises the per-hop `_do_a` path
     and surfaces the err-resp through the arena.
  4. `auto_once_err_resp_arena` — `_auto_once_a`
     no-pool path falls through to `_do_a` correctly.
  5. `request_auto_arena` — top-level `request_auto_a`
     routes the no-redirect case end-to-end into the
     arena; reset reclaims.
  6. `retry_non_retryable_arena` — `_retry_a` returns
     after one attempt on PARSE (non-retryable per
     `_sandhi_retry_should_retry`); arena threads through.
- `tests/alloc.tcyr` includes extended: pulled in
  `src/http/h2/request.cyr`, `_/response.cyr`,
  `_/pool_glue.cyr`, `_/dispatch.cyr` so the test
  program can reach the new `_a` variants in the
  auto-dispatch path.
- 175/175 alloc tests pass (155 pre-existing + 20 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 824 assertions green** (+20
  over 1.2.0's 804).
- `cyrius lint` 0 warnings on `src/http/client.cyr`,
  `src/http/h2/dispatch.cyr`, `src/http/retry.cyr`.
  `cyrfmt --check` clean on touched files.

### Pinned next

- **1.2.2 — Batch D**: top-level public verbs
  (`sandhi_http_get_a` / `_post_a` / `_put_a` /
  `_patch_a` / `_delete_a` / `_head_a`). First slot where
  consumer-visible end-to-end arena adoption ships
  (post-Batch-B+C, the internal cascade is fully `_a`-
  threaded; Batch D just paints the public-verb wrappers
  on top).
- **1.2.3 — Batch E**: `_opts` / `_retry` / `_auto`
  user-facing variants.
- **1.2.4 — Batch F**: RPC dialect entries
  (`sandhi_rpc_mcp_call` and friends).

## [1.2.0] — 2026-05-08

**Hot-path allocator review — Batch A: request-orchestrator
foundation + audit findings.** Opens the 1.2.x optimization
arc. Sandhi-side companion to cyrius v5.10.x's optimization
theme; ONE-thing-per-slot principle applied — each subsequent
batch lands in its own slot.

### Audit findings

The 1.1.0 leaf-level migration was clean — automated scan of
all 78 `_a` paired fns across `src/http/` + `src/rpc/` found
**zero** cases of an `_a` variant calling a bare paired
helper (i.e. no `_a` fn silently dropped its allocator into
`default_alloc()` via a paired but bare-form call).

**The real leak**: the request-orchestration layer above the
leaves was never `_a`-converted. `sandhi_http_get` / `_post`
/ `_put` / `_patch` / `_delete` / `_head` (and their
`_opts` / `_retry` / `_auto` variants) had no `_a`
counterparts, and the internal orchestrators (`_do` /
`_do_impl` / `_dispatch` / `_follow` / `_retry` /
`_try_h2_promote` / `_auto_once` / `_auto_follow`) all ran
on `default_alloc()` regardless. A consumer using the 1.1.0
`_a` leaves to build an arena-bound headers block had no way
to *use* that arena across the request: `sandhi_http_get`
dropped right back to the global allocator at the entry
point. Reference shapes that DID get the migration end-to-end:
`sandhi_http_stream` / `sandhi_h2_request` (see `_a`
counterparts).

**Quantified gap** (this CHANGELOG is the audit's permanent
record):
- Internal orchestrators needing `_a`: 7 fns
  (`_sandhi_http_do`, `_do_impl`, `_dispatch`, `_follow`,
  `_retry`, `_try_h2_promote`, `_auto_once`/`_auto_follow`).
- Public top-level verbs needing `_a`: ~26
  (HTTP GET-family + opts / retry / auto + RPC dialect entries).
- Accessors deliberately not paired (no alloc): ~30
  (`sandhi_http_status`, `_body`, `_headers`, etc. — pure
  load64/store64 on response/options/pool structs).
- Singletons that MUST stay on `default_alloc`: 4 (ALPN
  literals, HPACK static, HPACK Huffman tree, server
  `_hsv_req_buf` — all process-wide, outlive any per-
  request arena).

### Changed (Batch A — internal orchestrator foundation)

- **http**: `_sandhi_client_build_request_a` was buggy —
  accepted `a` and silently dropped it, calling the bare
  `_v` impl (which used `default_alloc()` throughout).
  Renamed the real impl to `_sandhi_client_build_request_va`
  (variadic with allocator) and fixed all four entry points
  (`_a` / bare / `_v` / `_va`) to thread `a` correctly via
  `str_builder_new_a` / `_add_cstr_a` / `_add_int_a` /
  `_build_a`. Added an OOM guard after `str_builder_new_a`
  so allocator-failure returns 0 cleanly instead of
  segfaulting on the next add (the stdlib `str_builder`
  ops don't null-check `sb`).
- **http**: new `_sandhi_http_exchange_a` and
  `_sandhi_http_exchange_keepalive_a`. Recv buffer alloc
  now goes through `alloc_via(a, cap+1)`; response parse
  uses `sandhi_http_response_parse_a(a, ...)`; every
  error-path resp construction uses `_sandhi_resp_err_a(a,
  ...)`. Pool put-back path keeps using the pool's own
  allocator (`_sandhi_pool_alloc(p)`) — pool entries
  outlive any per-request arena, so this is intentional,
  not a leak.
- **http**: new `_sandhi_http_do_a` (trace wrapper) and
  `_sandhi_http_do_impl_a` (request hot path). `_do_impl_a`
  threads `a` through every per-request alloc: URL parse,
  v4/v6 DNS resolve, conn-open (v4 + v6 paths), full-path
  build, host-header build, request-builder, and the
  exchange recv buffer.
- **http**: new `_sandhi_http_dispatch_a` — opts-aware
  entry. Routes the no-redirect path through `_do_a`
  (allocator threaded end-to-end). The redirect-follow
  path still routes through bare `_sandhi_http_follow` —
  `_follow_a` is Batch B (1.2.1). For `follow=1` callers,
  the per-request arena is bypassed across redirect hops
  for now; documented as a partial-arena leak that closes
  at 1.2.1.
- All bare orchestrator versions (`_do` / `_do_impl` /
  `_dispatch` / `_exchange` / `_exchange_keepalive`)
  preserved as back-compat wrappers calling the `_a`
  variant with `default_alloc()`. Public surface unchanged
  in this slot.

### Verified

- `tests/alloc.tcyr` gains 4 new test groups (12
  assertions) under `alloc/120a/`:
  1. `build_request_arena` — arena round-trip + reset
     reclaims everything.
  2. `build_request_va_keepalive` — keep_alive=1 omits
     `Connection: close` correctly through the threaded
     allocator.
  3. `dispatch_err_resp_arena` — `_sandhi_http_dispatch_a`
     against an unparseable URL allocates the err-resp
     in the arena; `reset_via` reclaims cleanly.
  4. `build_request_oom` — `fail_after_n_allocs(0)`
     returns 0 from the builder gracefully (this caught
     the missing OOM guard during development).
- 155/155 alloc tests pass (143 pre-existing + 12 new).
- 482/482 `tests/sandhi.tcyr`, 167/167 `tests/h2.tcyr` —
  no regression. **Total: 804 assertions green** (+12
  over 1.1.2's 792).
- `cyrius lint src/http/client.cyr` — 0 warnings.
  `cyrfmt --check` clean on touched files.

### Roadmap cleanup (rides along)

- 1.2.0 / 1.3.x split per the slot-shape decision:
  optimization arc (1.2.x) and TLS arc (1.3.x) are
  separate efforts that don't share a cascade and
  shouldn't bundle.
- `tls_connect` native-transport prep audit dropped from
  sandhi's roadmap — that's a cyrius-side issue against
  `lib/tls.cyr`, not sandhi's slot. Filed on cyrius's
  Held / pinned bug arc as
  *"`lib/tls.cyr` hook-surface contract audit"*.
- ADR 0001 + CLAUDE.md updated: the *"transitions to
  native TLS when v5.9.x ships"* framing was wrong (cyrius
  v5.9.x → v5.10.x is an optimization arc, not a transport
  swap; lib/tls.cyr stays libssl.so.3-bridged
  indefinitely per the 2026-04-24 pure-Cyrius-TLS removal).

### Pinned next

- **1.2.1 — Batch B**: `_sandhi_http_follow_a` +
  `_sandhi_http_retry_a`. Closes the partial-arena leak
  on `follow=1` and `_retry` callers.
- **1.2.2 — Batch C**: `_sandhi_http_auto_*_a` family.
- **1.2.3 — Batch D**: top-level public verbs
  (`sandhi_http_get_a` etc.) — first slot where
  consumer-visible end-to-end arena adoption ships.
- **1.2.4+ — Batch E / F**: `_opts` / `_retry` / `_auto`
  user-facing variants; RPC dialect entries.

## [1.1.2] — 2026-05-08

**Request-builder dup-prevention.** Closes the second 0.9.9
audit deferral. No public-surface change — the filter is
internal to `_sandhi_client_build_request_v` and applies to
every call site (`sandhi_http_get` / `_post` / `_put` / etc.,
plus the retry + auto + h2 paths that compose on top).

### Changed

- **http**: `_sandhi_client_build_request_v` in
  `src/http/client.cyr` now filters caller-supplied
  `Host` / `Content-Length` / `Transfer-Encoding` /
  `Connection` out of `user_headers` before serialization.
  Each of those is auto-injected by the builder above (Host
  from the URL, Content-Length from `body_len`, Connection
  from `keep_alive`); a caller's second copy would emit
  alongside the auto-injected version and create a dup-
  header smuggling vector on the wire (CL.CL / TE.CL /
  dup-Host / Connection-override).
- New static helper `_sandhi_client_user_header_is_reserved`
  defined just above the builder. Uses
  `_sandhi_resp_streq_ci` (response.cyr is bundled before
  client.cyr); client.cyr's own `_sandhi_streq_ci` sits
  later in the file and isn't reachable from the builder
  under single-pass compilation. Reuses the existing CI
  helper rather than adding a third copy.
- **Symmetry with the server-side detector**:
  `sandhi_headers_smuggle_dup` (0.9.1) flags the same four
  names as request-side dups in headers parsed off the
  wire. The 1.1.2 builder-side filter is the matching
  client-side guard at request-build time — closes the
  loop at both ends.

### Verified

- New `programs/_dup_prevention_probe.cyr` covers six
  scenarios across 21 assertions:
  1. Caller Host filtered, auto Host wins, non-reserved
     X-Trace passes through (4 asserts).
  2. Caller Content-Length filtered on POST; auto value
     from `body_len` wins (3 asserts).
  3. Caller Transfer-Encoding filtered (CL.TE smuggling
     vector blocked at build time; 2 asserts).
  4. Caller Connection filtered; auto `Connection: close`
     wins (3 asserts).
  5. Case-insensitive matcher: lowercase / UPPER-CASE /
     mixed-case caller names all dropped (4 asserts).
  6. Non-reserved names (Authorization, Accept, X-Custom)
     pass through unchanged — regression guard against the
     filter accidentally suppressing benign headers
     (3 asserts).
- 21/21 PASS in the probe.
- **792 assertions green** (482 sandhi + 167 h2 + 143
  alloc; no regression). Filter has no unit test in
  `tests/sandhi.tcyr` — coverage stays in the probe per
  the per-program fixup cap (architecture/001).
- `cyrius lint` 0 warnings on `src/http/client.cyr` and
  `programs/_dup_prevention_probe.cyr`. `cyrfmt --check`
  clean.

## [1.1.1] — 2026-05-08

**`Proxy-Authenticate` trailer-forbidden + cyrius 5.10.0 pin.**
First post-fold patch from the 1.1.x small-fixes lane. Single
audit deferral landing — no public-surface change.

### Changed

- **http**: `_sandhi_resp_trailer_forbidden` in
  `src/http/response.cyr` adds `Proxy-Authenticate` to the
  forbidden-name list, rounding out the proxy-auth pair after
  the 0.9.9 audit landed `Proxy-Authorization` /
  `Connection` / `Cookie`. RFC 7230 §4.1.2 trailer-filter
  parity for the proxy-auth challenge; consumers' auth
  machinery typically ignores trailer-side challenges, but
  filtering closes the symmetric position in the
  forbidden-name lists across client and server paths and
  prevents a malicious server from injecting an unexpected
  `Proxy-Authenticate` post-body via the trailer block.
  Originally deferred from the 0.9.9 audit on per-program-
  fixup-cap grounds (architecture/001); the cap re-baselined
  post-fold once consumers stopped re-concatenating sandhi's
  `src/`, so the addition lands cleanly here.
- **Toolchain pin** bumped 5.8.36 → 5.10.0 (`cyrius.cyml
  [package]`). v5.10.0 ships compile-time profile
  instrumentation only (`api-surface: unchanged`,
  byte-identical self-host); mechanical bump. The v5.9.x
  stdlib accumulation lands here too via `cyrius deps`
  resync: `lib/args.cyr`, `lib/fnptr.cyr`, `lib/fs.cyr`,
  `lib/hashmap.cyr`, `lib/sigil.cyr`, `lib/str.cyr` (~540
  net lines added, mostly `_a`-variant fill-in symmetric
  to the 1.1.0 migration). 792 assertions still green
  across the resync — no sandhi behavior change.

### Verified

- `programs/_trailers_probe.cyr` extended: section [4]
  asserts the full forbidden-list coverage end-to-end —
  `Content-Length` (0.9.4), `Authorization` (0.9.4),
  `Connection` (0.9.9), `Cookie` (0.9.9),
  `Proxy-Authorization` (0.9.9), and the new
  `Proxy-Authenticate` (1.1.1). 11 PASS / 11 total. The
  0.9.9 audit additions (Connection / Cookie /
  Proxy-Authorization) were never asserted in the probe;
  this fills that gap symmetrically.
- **792 assertions green** (482 sandhi + 167 h2 + 143
  alloc; no regression). Forbidden-list helper has no unit
  test in `tests/sandhi.tcyr` — coverage stays in the
  probe per the per-program fixup cap.

## [1.1.0] — 2026-05-03

**Allocator-as-first-arg migration.** Threads the cyrius v5.8.33
`Allocator` vtable through every alloc-touching public + internal
fn in `src/`. Adds `_a` variants that take the Allocator as the
first parameter (Zig-style); back-compat wrappers preserve the
existing API by passing `default_alloc()`. The headline win is the
**per-request-arena pattern** for HTTP servers: a handler can
`arena_allocator(N)` at the top of a request, build the parsed URL,
header block, RPC call, response struct, and body all into the
same arena, then `reset_via(a)` between requests — zero leakage,
deterministic memory ceiling, failing-allocator coverage of every
path. Closes the deferral noted in cyrius v5.8.36's stdlib pass 2.

**Toolchain pin** bumped 5.6.41 → 5.8.36 (`cyrius.cyml [package]`).
`lib/alloc.cyr` resynced and now ships the v5.8.33 `Allocator`
vtable + 3 default impls (`bump`/`arena`/`test`) + dispatch helpers
(`alloc_via`/`realloc_via`/`free_via`/`reset_via`) +
`default_alloc()` lazy-init singleton; `lib/assert.cyr` ships
`fail_after_n_allocs(n)` for OOM-handling test coverage.

**792 assertions green** (482 sandhi + 167 h2 + 143 alloc; +143
over 1.0.0's 649). The new alloc-coverage suite lives in
`tests/alloc.tcyr` (separate program — sandhi.tcyr is at the
per-program fixup-table cap per architecture/001).

### Migration shape

The proposal at `docs/proposals/2026-05-03-allocator-migration.md`
specifies the contract: every alloc-touching public fn gains an
`_a` variant taking the Allocator as the first arg; internal
helpers thread the allocator through; back-compat wrappers preserve
the pre-migration API by passing `default_alloc()`. OOM propagates
as a 0 return rather than aborting. Doc comments lead every new
public fn (cyrdoc gate).

Process-wide singletons MUST keep using `default_alloc()` regardless
of which `_a` variant called them, because they outlive any per-
request arena: the ALPN wire literals (`_sandhi_alpn_h11_wire` /
`_sandhi_alpn_h2h11_wire` in `src/http/conn.cyr`), the HPACK static
table (`_hpack_static_init` in `src/http/h2/hpack.cyr`), the HPACK
Huffman decode tree (`_hpack_huffman_init` in
`src/http/h2/huffman.cyr`), and the server-side per-process request
buffer (`_hsv_req_buf` in `src/server/mod.cyr`). An arena reset in
one request would corrupt these for every other in-flight request.

For resolver-fn-pointer callbacks whose `(ctx, name)` shape can't
take an extra Allocator argument, the allocator is stored on the
ctx struct: daimon's ctx grew from 16 → 24 bytes
(`src/discovery/daimon.cyr`); local mDNS gained an 8-byte ctx
(`src/discovery/local.cyr`).

For the connection pool, the Allocator handle lives on the pool
struct (slot +40) so put/take operations route allocator-aware
churn through the same arena the pool was built from. The pool
struct grew from 40 → 48 bytes (`src/http/pool.cyr`).

### Batches

Migration landed in 6 commit-sized bites, bottom-up (leaves first,
aggregators last).

**Batch 1 — leaves** (6 files, 17 alloc sites):
`src/http/url.cyr`, `src/http/headers.cyr`,
`src/discovery/service.cyr`, `src/discovery/daimon.cyr`,
`src/http/pool.cyr`, `src/http/h2/frame.cyr`. Pool struct +
daimon ctx grew. `headers_add_a` returns `0 - 2` on OOM (distinct
from the existing `0 - 1` byte-rejection). +33 assertions.

**Batch 2 — TLS + h2 leaves** (5 files, 24 alloc sites):
`src/tls_policy/fingerprint.cyr`, `src/tls_policy/policy.cyr`,
`src/tls_policy/apply.cyr`, `src/http/h2/huffman.cyr`,
`src/http/h2/hpack.cyr`. SPKI check (DER buffer + digest + hex
encode + constant-time compare) all flow through `a`. HPACK static
table + Huffman tree pinned to default_alloc as singletons. +24
assertions.

**Batch 3 — discovery + rpc** (4 files, 14 alloc sites):
`src/discovery/local.cyr`, `src/rpc/dispatch.cyr`,
`src/rpc/webdriver.cyr`, `src/rpc/json.cyr`. The full JSON
builder + dotted-path extractor + RPC call/wrap surface gained
`_a` variants. +23 assertions.

**Batch 4 — HTTP response/request foundation** (3 files, 15
alloc sites): `src/http/response.cyr`, `src/http/h2/response.cyr`,
`src/http/h2/request.cyr`. THE central `_sandhi_resp_new` is now
allocator-aware — every HTTP response (1.1 OR h2, success OR error,
plain OR chunked) flows through one Allocator. The h2 recv path
(16 KB hblock + 1 MB body + 16-byte result cell per frame) is now
arena-resettable. Heaviest semantic win of the migration. +18
assertions.

**Batch 5 — connection layer** (3 files, 37 alloc sites — largest
by count): `src/http/conn.cyr`, `src/http/h2/conn.cyr`,
`src/net/resolve.cyr`. ALPN-selected cstr inherits conn lifetime;
h2 conn struct + enc/dec hpack tables + per-frame send/recv all
allocator-aware; DNS resolver's `_name_eq` (8 transient cells +
2 64-byte label bufs — heaviest alloc site in the resolver) +
v4/v6 query buffers all flow through `a`. The `var a` loop
counter in `_resolve_parse_response_a*` was renamed to `a_idx` to
dodge the Allocator-parameter shadow. +19 assertions.

**Batch 6 — client + streaming + server** (6 files, 34 alloc
sites): `src/http/client.cyr`, `src/http/stream.cyr`,
`src/http/sse.cyr`, `src/http/retry.cyr`,
`src/http/h2/dispatch.cyr`, `src/server/mod.cyr`. The full SSE
parser surface (events vec, ctx struct, per-event dups + structs)
flows through `a` — re-entrant streams that nest SSE callbacks
within callbacks each get their own ctx in their own allocator.
Streaming buffers (`_sandhi_sb_new` allocates `cap+1` bytes per
buffer) arena-resettable. Server-side request-parsing helpers
(`get_method`/`get_path`/`find_header`/`url_decode`/`get_param`/
`path_segment`) all gained `_a` variants — handlers can wire one
arena through the entire request-handling chain. +26 assertions.

### Fold-into-stdlib note

The `_a` variants are ADR 0005 freeze deviations: ~150 new public
verbs land in this release. ADR 0005's freeze applied "between
0.9.2 and the v5.7.0 fold (1.0.0)" — post-fold maintenance patches
were always going to land as 1.0.x / 1.x.x stdlib patches. This
release is the first such patch. The cyrius-side update
(refreshing `cyrius/lib/sandhi.cyr` from this repo's regenerated
`dist/sandhi.cyr`) is its own small cyrius slot — probably
v5.8.37 or whichever cyrius version is current at sandhi 1.1.0
ship.

### Stdlib

- Toolchain pin 5.6.41 → 5.8.36. Brings in v5.8.33-v5.8.36 stdlib
  changes: `Allocator` vtable, `fail_after_n_allocs` test harness,
  `vec_new_a` / `vec_push_a` / `map_new_a` / `map_set_a` /
  `map_grow_a`, `str_from_a` / `str_new_a` / `str_clone_a` /
  `str_from_int_a`, `default_alloc()` lazy-init.
- `lib/str.cyr` `str_builder_*` lacks `_a` variants in the pinned
  stdlib — sandhi's `_a` paths still use the global bump for
  builder scratch and dup the final cstr into `a` so the returned
  cstr matches arena lifetime (e.g.,
  `_sandhi_client_host_header_a`, `_sandhi_wd_session_url_a`,
  `sandhi_json_build_a`). When a future cyrius release adds
  `str_builder_new_a` etc., these dups can drop in a follow-up.

## [1.0.0] — 2026-04-25

**Fold-ready release.** Final sandhi-side tag before the cyrius
v5.7.0 release vendors this repo's `dist/sandhi.cyr` as stdlib's
`lib/sandhi.cyr`. After the fold, sandhi enters maintenance mode —
patches land via the Cyrius release cycle, not this repo.

**649 assertions green** (482 sandhi + 167 h2). Public surface =
278 `sandhi_*` verbs.

The 0.9.x sequence (0.9.3 → 0.9.10, 8 hardening releases between
the 0.9.2 freeze and 1.0.0) was internal wire-up + audit pass —
TLS runtime enablement, h2 redirect-following + retry-through-auto,
ALPN auto-promotion, `TE: trailers` on both protocols, HPACK
Huffman encode, internal P1 self-audit, pool stale-skip hardening.
ADR 0005 surface freeze respected throughout (with one documented
exception: see "Public surface" below).

### http/server — transitional aliases dropped

Per the 0.9.2 plan: 19 `http_*` tail-call wrappers in
`src/server/mod.cyr` were retained through the 0.9.x window to
give downstream consumers an upgrade path from the M1 lift-and-
shift originals. They retire at 1.0.0 so they don't ship as
permanent stdlib API at v5.7.0 fold.

Migration path for any remaining consumers: rename references
from `http_*` to `sandhi_server_*`. The mapping is one-to-one
(every `http_X` was a tail-call to `sandhi_server_X` already).
`tests/sandhi.tcyr` and `programs/smoke.cyr` updated in this
release; downstream repos that still use the old names need the
same mechanical rename before bumping to a v5.7.0-compatible tag.

### Public surface — confirmed against 0.9.2 freeze

Diffed `fn sandhi_*` declarations between the 0.9.2 release commit
and 1.0.0 to verify the freeze:

- **Removed (35)**: per-module `*_version` accessors
  (`sandhi_alpn_version`, `sandhi_ap_version`, ...,
  `sandhi_wd_version`). Retired in 0.9.3's versioning refactor —
  the only version accessor any consumer ever called was
  `sandhi_version()`, and the 35 module-level ones existed only
  because the early scaffolding generator emitted them per-module.
  Removal was logged in the 0.9.3 changelog with full notice.
- **Added (2)**: `sandhi_hpack_huffman_encode` and
  `sandhi_hpack_huffman_encoded_len`, landed in 0.9.8 as the
  encoder counterpart of the public decoder
  (`sandhi_hpack_huffman_decode`, public since 0.8.0 Bite 2b).
  Strictly an ADR 0005 deviation; the rationale was that having
  a public decoder and a private encoder would have been worse
  asymmetry than the freeze deviation. Both are HPACK internals
  consumers don't typically call directly — `_hpack_string_encode`
  is the actual integration point.

Net: **278 `sandhi_*` verbs** at fold time. This is the permanent
stdlib API.

### Documentation

- `README.md` — Status section updated for 1.0.0; quick-start and
  module map unchanged.
- `CLAUDE.md` — fold-target line updated from "before v5.6.x
  closeout" (the original plan, superseded by ADR 0002) to "v5.7.0
  clean-break fold."
- `docs/development/state.md` — 1.0.0 entry framing the fold;
  Next-list closes with "Post-1.0.0: maintenance mode."
- `docs/development/roadmap.md` — already cleaned up post-0.9.9 to
  be forward-looking; shipped log carries the 0.x sequence.
- ADRs — no edits; ADRs 0001–0005 all still accurate and load-bearing.

### `dist/sandhi.cyr`

Regenerated via `cyrius distlib` from the 1.0.0 source tree. This
bundle is what the cyrius v5.7.0 release vendors as
`lib/sandhi.cyr` — byte-identity of the two at the fold commit is
one of the v5.7.0 acceptance criteria.

### Acceptance criteria (checked at the v5.7.0 release gate, not in this repo)

- Consumer repos (yantra, hoosh, ifran, daimon, mela, vidya,
  sit-remote, ark-remote) build against 5.7.0 stdlib without
  `[deps.sandhi]` pins.
- `dist/sandhi.cyr` is byte-identical to `lib/sandhi.cyr` at the
  fold commit.
- No `include "lib/http_server.cyr"` survives anywhere in AGNOS.

Post-fold patches happen on the cyrius-side via the regular
release cycle. The two 0.9.9-deferred items (trailer
`Proxy-Authenticate`, request-builder dup-prevention for
caller-supplied `Host` / `Content-Length` / `Transfer-Encoding` /
`Connection`) land as 1.0.x stdlib patches once the per-program
fixup cap re-baselines after fold.

## [0.9.10] — 2026-04-25

**Pool stale-skip hardening.** Closes the only "audited and noted,
optimization-grade only" finding from the 0.9.9 audit. Promoting
the fix into a hardening release because deterministic h2 selection
across long client uptimes is the threshold for "worth the patch
before fold." ADR 0005 surface freeze respected (no public-surface
change).

**649 assertions green** (482 sandhi + 167 h2; same coverage as
0.9.9, no regression).

### http/pool

- `src/http/pool.cyr::_sandhi_pool_has_idle` — non-consuming peek
  now walks the per-route 1.1 vec and returns 1 only if at least
  one entry is within `idle_timeout_ms` (default 90 s) of
  `clock_now_ms()`. Previously it returned 1 whenever the vec
  had any entry, regardless of staleness.

### Why this matters

`_sandhi_pool_has_idle` is the gate the 0.9.6 ALPN auto-promoter
uses to decide whether to attempt h2 promotion or just take the
existing 1.1 conn. The 0.9.6 contract was *"if the route has 1.1
conns, the previous request already learned the server speaks
1.1; don't re-ALPN."* That's correct — except when "has 1.1 conns"
in the bookkeeping doesn't match "has *usable* 1.1 conns" because
the entries are all stale.

Concretely: a process that talked to `https://api.example.com/`
once, then sat idle for >90 s, then made a second request — under
the old peek logic, the second request would skip ALPN promotion
entirely, fall through to `_sandhi_http_do` (which correctly
discards the stale conn and opens a fresh 1.1 one), and never
attempt h2 negotiation. The fresh 1.1 conn lands in the pool, so
the third request (still <90 s after the second) sees a *non-
stale* idle entry and again skips promotion. The route is locked
to 1.1 forever from one bad timing.

After this fix, the second request's peek correctly reports "no
non-stale idle conns" → ALPN promotion fires → if the server
speaks h2, we get h2 from this point on, just as if the original
request had hit a server-supports-h2 path.

### Implementation notes

- Walk is non-destructive — `_sandhi_pool_take` already does
  stale-skip on its take path, so reaping happens naturally
  on next take. No need to mutate the vec inside the peek.
- Cost: one `clock_now_ms()` per peek + a vec walk bounded by
  `max_per_host` (default 8). Negligible vs the saved TLS
  handshake on h2 promotion.
- The peek is only called from
  `_sandhi_http_auto_once` in `src/http/h2/dispatch.cyr` —
  no other callers, no API surface change.

## [0.9.9] — 2026-04-25

**Internal P1 self-audit.** Final security pass before the v5.7.0
fold makes the public surface permanent. Audited every code path
added since the 0.9.0/0.9.1 P0/P1 sweeps. ADR 0005 freeze respected
(no new public verbs). One fix landed; two findings deferred to the
1.0.x stdlib-patch window for fixup-cap reasons (architecture/001);
the rest of the audit surface is sound.

**649 assertions green** (482 sandhi + 167 h2; no regression — same
coverage as 0.9.8).

### Fix — chunked trailer forbidden list

`src/http/response.cyr::_sandhi_resp_trailer_forbidden` gains three
names: `Connection`, `Cookie`, `Proxy-Authorization`.

- `Connection` is connection-management metadata per RFC 7230 §6.1
  and MUST NOT appear in trailers. Without filtering, a malicious
  server could inject `Connection: close` in the trailer block
  after the body has been consumed; the response parser would
  surface it via `sandhi_http_headers(r)`, and the keep-alive /
  pool put-back logic that consults the response's Connection
  value would mis-classify a perfectly reusable conn as "must
  close." Real-world exploit: a spec-deviating CDN could induce
  TLS-handshake churn on every keep-alive batch.
- `Cookie` and `Proxy-Authorization` are auth-bearing request
  headers; they're now treated symmetrically with `Authorization`
  and `Set-Cookie` (which were already on the list). Closes the
  trailer-side equivalent of the 0.9.0 redirect cred-strip
  filter (`_sandhi_strip_sensitive_headers`), which strips the
  same three on cross-authority hops.

### Audited and sound

- **ALPN advertise-toggle restoration** — `_sandhi_alpn_advertise_h2`
  is reset to 0 on every exit path of `_sandhi_http_try_h2_promote`
  including the connect-failure case. Single-threaded model means
  the toggle can never persist across a request boundary.
- **Huffman encoder bit-handling** — traced multi-byte cases
  (3+3+3-bit codes filling and emitting across 8-bit boundaries)
  plus padding (1..7 unemitted bits with EOS-prefix all-1s pad).
  Bit accumulator stays within i64 (max 30-bit code + ≤7 leftover
  = 37 bits). Encoder produces byte-exact RFC 7541 C.4.1 reference
  output (verified by `test_hpack_huffman_encode_www_example`).
- **h2 forbidden-headers filter** — `_h2_header_is_forbidden`
  matches RFC 7540 §8.1.2.2 exactly: connection / keep-alive /
  proxy-connection / transfer-encoding / upgrade dropped; te
  conditionally allowed iff value is "trailers" (the one spec
  exception, validated whitespace-tolerantly).
- **Redirect cred-strip filter** — `_sandhi_strip_sensitive_headers`
  drops Authorization / Cookie / Proxy-Authorization on cross-
  authority hops. Matches the auth-header set RFC 7235 + 6265
  define; the pair is now also reflected in the trailer filter
  above.

### Audited, optimization-grade only

- `_sandhi_pool_has_idle` (shipped 0.9.6) doesn't skip stale
  (>idle_timeout_ms-old) conns when deciding whether to attempt
  ALPN promotion. If a route's only idle 1.1 conns are stale,
  promotion is skipped and `_sandhi_http_do` opens a fresh conn
  via the 1.1 path — missing the h2-promotion opportunity until
  the stale conns are reaped. Not a security issue; deferred as
  a 1.0.x optimization patch if a consumer measures the hit.

### Deferred to 1.0.x stdlib-patch window

The per-program fixup cap (architecture/001) makes the
following two finishing strokes unfit for 0.9.9 — they would push
`tests/sandhi.tcyr` over the 32768 limit.

1. **Trailer filter `Proxy-Authenticate`** — would round out the
   proxy-auth pair by analogy with the new `Proxy-Authorization`
   entry. Lower priority than the three landed names: it's a
   response challenge to the client, not an injectable
   credential vector. Single name = single string-literal fixup
   away from landing.
2. **Request-builder dup-prevention** — caller-supplied `Host` /
   `Content-Length` / `Transfer-Encoding` / `Connection` in
   `user_headers` currently emit alongside the auto-injected
   versions, creating dup-header smuggling vectors. The
   server-side counterpart (`sandhi_headers_smuggle_dup`)
   landed at 0.9.1; the client-side filter applies the same
   idea to the build path. Implementation was prototyped as a
   hand-rolled byte compare in `_sandhi_client_name_is_reserved`
   to avoid string-literal pressure, but the per-character bit
   ops (~50 of them across four name checks) tipped the cap.
   Caller currently owns the contract — the builder accepts
   the user's headers as given.

Both deferrals are tracked for the post-fold patch sequence; once
sandhi is folded into stdlib at v5.7.0, the per-program cap
re-baselines (`tests/sandhi.tcyr` no longer concatenates all of
src/), and the headroom returns.

## [0.9.8] — 2026-04-25

**HPACK Huffman encode.** Wire-size optimization for outgoing h2
header blocks — text-heavy headers (cookies, JSON Authorization
tokens, ASCII paths) now ship 25-30% smaller. Deferred from 0.8.x
on the "wait for bandwidth-pressure evidence" rule; landing now as
part of the pre-fold completeness pass since fold timing precludes
landing it later as a 1.0.x patch. ADR 0005 surface freeze
respected (no new public verbs; the new encoder symbols are HPACK
internals consumers never touch directly).

**649 assertions green** (482 sandhi + 167 h2 — +14 from the new
encoder reference test). Two existing literal-encode tests had
their wire-byte counts updated from raw to Huffman.

### http/h2/huffman

- `src/http/h2/huffman.cyr` — encode landed alongside the existing
  decode (Bite 2b of 0.8.0). Init now also builds a parallel
  `_hpack_huffman_codes` lookup table — 257 × 16-byte entries
  indexed by symbol, populated from the same hex blob the decode
  tree reads. New helpers `_hpack_huffman_code_of` /
  `_hpack_huffman_bits_of` for symbol → (code, bit-length).
- New `sandhi_hpack_huffman_encoded_len(s)` — walks `s`, sums
  each byte's bit-length from the table, returns `(bits + 7) >> 3`.
  Used by the size-vs-raw choice in `_hpack_string_encode`.
- New `sandhi_hpack_huffman_encode(out, off, s)` — packs codes
  MSB-first into a bit accumulator, drains 8-bit chunks to
  `out`, pads the final partial byte with EOS-prefix 1-bits per
  RFC 7541 §5.2 so the existing decoder's padding check accepts
  the output. Accumulator is i64 (max code 30 bits + ≤7 leftover
  → 37 bits, well within bounds).

### http/h2/hpack

- `src/http/h2/hpack.cyr::_hpack_string_encode` — probes
  `sandhi_hpack_huffman_encoded_len(s)` first, picks Huffman
  (H=1 in the length prefix) when strictly shorter than raw.
  Tie → raw, since the savings are zero and raw is simpler. The
  decoder side already supported H=1 (Bite 2b), so the wire is
  fully roundtrip-correct without any other change.

### Verification

- New `test_hpack_huffman_encode_www_example` (h2.tcyr) asserts
  byte-exact output against the RFC 7541 C.4.1 reference vector:
  `"www.example.com"` → `f1 e3 c2 e5 f2 3a 6b a0 ab 90 f4 ff`
  (12 bytes, vs. 15 raw). All 12 bytes match plus the
  `sandhi_hpack_huffman_encoded_len` probe.
- `test_hpack_encode_decode_literal_inline` updated: `("x-foo",
  "bar")` now ships in 10 bytes (Huffman 4 + raw 3) instead of
  the previous 11 (raw 5 + raw 3). Roundtrip-decode still asserts
  the original strings come back unchanged.
- `test_hpack_encode_decode_no_index` updated: `("x-no", "ok")`
  now ships in 8 bytes (Huffman 3 + raw 2) instead of 9 (raw 4 +
  raw 2). Same roundtrip property.

## [0.9.7] — 2026-04-25

**`TE: trailers` request signaling.** Outgoing-side counterpart to
the response-trailer parser that landed at 0.9.4. ADR 0005 surface
freeze respected (no new public verbs). RFC 7230 §4.4 says servers
SHOULD NOT generate trailer fields unless the request includes a
TE header field indicating "trailers" is acceptable; this release
sends that signal by default on both the 1.1 and h2 paths.

**635 assertions green** (482 sandhi + 153 h2; no regression).
Five existing 1.1 builder-test expected strings updated to reflect
the new TE line in the wire bytes.

### http (1.1)

- `src/http/client.cyr` — `_sandhi_client_build_request_v`
  auto-injects `TE: trailers\r\n` after `Accept-Encoding:
  identity\r\n` and before user headers. Override-preserving:
  `sandhi_headers_has(user_headers, "TE") == 1` skips the auto-
  inject and lets the caller's value through unchanged. Same
  shape as the existing User-Agent / Accept-Encoding defaults
  (0.7.1).

### http/h2

- `src/http/h2/request.cyr` — `_h2_header_is_forbidden(name)` →
  `_h2_header_is_forbidden(name, value)`. The `te` header is now
  conditionally allowed: `te: trailers` (whitespace-tolerant,
  case-insensitive) passes the filter; any other TE value
  (`te: gzip`, `te: deflate;q=0.5`, etc.) is dropped per RFC 7540
  §8.1.2.2 — the spec says a request with TE != "trailers" is
  malformed; we drop instead of erroring so the request still
  ships.
- `sandhi_h2_request_encode_headers` — auto-emits `te: trailers`
  after the four pseudo-headers and before user headers, when
  the caller didn't set TE. Mirrors the 1.1 builder's behavior;
  same `sandhi_headers_has`-based override gate.
- New `_h2_te_value_is_trailers(value)` — strict matcher used by
  the forbidden filter for the te-conditional rule. Skips
  leading whitespace, requires the literal "trailers" (ci),
  allows trailing whitespace.

### Verification

- 1.1 wire bytes: five existing tests in `tests/sandhi.tcyr`
  (`test_client_build_request_get` / `_post` / `_post_empty_body`
  / `_user_headers` / `_override_ua_and_ae`) now assert the
  presence of `TE: trailers\r\n` in the expected output. Default
  injection + correct ordering (after AE, before user headers,
  before Connection-close) verified.
- 1.1 override + h2 paths: standalone
  `programs/_te_trailers_probe.cyr` covers the four cases the
  test suite has no fixup-table room for (per architecture/001):
  caller TE suppresses 1.1 default; h2 drops `te: gzip`; h2
  auto-emits `te: trailers` by default; h2 lets caller-set
  `te: trailers` flow through. All four PASS.

## [0.9.6] — 2026-04-25

**ALPN-driven HTTP/2 auto-promotion.** First release where live h2
fires end-to-end via the auto-dispatcher with no consumer code
change. ADR 0005 surface freeze respected (no new public verbs).

The auto-dispatcher (`sandhi_http_request_auto`, shipped 0.8.1) was
the natural home for h2 selection but until now only used h2 if the
caller had pre-cached an h2 conn in the pool. ALPN's runtime wire-up
landed at 0.9.3, redirect-and-retry routing through the auto path
landed at 0.9.5 — this release closes the loop by having the auto
path itself open conns advertising both protocols and promote based
on what the server picks.

**635 assertions green** (482 sandhi + 153 h2; no regression).

### http/h2

- `src/http/h2/dispatch.cyr` — new `_sandhi_http_try_h2_promote`.
  Triggered from `_sandhi_http_auto_once` only when:
  - URL is HTTPS (ALPN is TLS-only)
  - A pool is attached (`opts.pool != 0`)
  - The pool's h2 slot for this route is empty
  - The pool's 1.1 slot for this route is also empty (peeked
    non-consumingly via the new `_sandhi_pool_has_idle`)
  Resolves the host (v4 then v6 fallback), flips
  `_sandhi_alpn_advertise_h2 = 1` for the open call only, calls
  `sandhi_conn_open_fully_timed` (or the v6 variant) with the
  caller's `connect_ms` / `read_ms` / `write_ms`, restores the
  flag. After handshake:
  - `sandhi_conn_alpn_is_h2 == 1` → `sandhi_h2_conn_new` +
    `sandhi_h2_conn_send_preface_and_settings` +
    `sandhi_h2_conn_recv_peer_settings`. On success, the h2 conn
    is cached via `sandhi_http_pool_put_h2` and returned; caller
    dispatches via `sandhi_h2_request`. Handshake failure closes
    the conn and falls through.
  - http/1.1 (or no ALPN) → the bare TLS conn is donated to the
    pool's 1.1 slot via `_sandhi_pool_put`. The immediately-
    following `_sandhi_http_do` takes it via `_sandhi_pool_take`,
    so the handshake is not wasted.
- `_sandhi_http_auto_once` — h2-promote check inserted between
  the existing pool-take and the 1.1 fallback. Behavior unchanged
  for non-TLS routes, no-pool requests, and routes where the pool
  already has h2 or 1.1 conns.

### http/pool

- `src/http/pool.cyr` — new `_sandhi_pool_has_idle(pool, host,
  port, tls)`. Non-consuming peek into the per-route 1.1 vec —
  returns 1 if at least one idle conn is stored. Used by the
  auto-promoter to skip ALPN promotion when the route has known
  1.1 conns. Without this gate, a server that picks http/1.1
  during ALPN would cause every subsequent request to open a
  fresh TLS conn instead of reusing the idle one (the old conns
  would only get reaped via the 90 s stale-eviction path).

### Operational notes

- ALPN promotion happens at most once per route per process when
  the server picks http/1.1 — the `_sandhi_pool_has_idle` gate
  short-circuits the second attempt. When the server picks h2,
  promotion happens once; subsequent requests take the cached
  h2 conn directly via `sandhi_http_pool_take_h2`.
- No-pool requests skip the promotion path entirely. h2's
  preface + SETTINGS + ACK roundtrips don't pay back on a single
  request — without a pool to cache the conn for the next
  request, advertising h2 is strictly slower than 1.1.
- Promotion is best-effort. DNS / connect / TLS handshake
  failures during promotion return 0 from
  `_sandhi_http_try_h2_promote`; the auto path then falls
  through to `_sandhi_http_do`, which re-attempts the open and
  surfaces the appropriate error kind to the caller.

## [0.9.5] — 2026-04-25

**HTTP/2 redirect-following + retry-through-auto.** Two internal
wire-up commits, ADR 0005 surface freeze respected (no new public
verbs). The auto-dispatcher (`sandhi_http_request_auto`, shipped
0.8.1) gains redirect-following on the h2 path and re-evaluates h2
selection per hop; the retry wrappers gain h2 selection by routing
through the same auto-dispatcher.

**635 assertions green** (482 sandhi + 153 h2; no regression
against 0.9.4).

### http/h2

- `src/http/h2/dispatch.cyr` — redirect-following hoisted to the
  auto layer. New `_sandhi_http_auto_once` is the per-hop
  dispatcher: takes h2 from the pool when available, otherwise
  calls `_sandhi_http_do` directly (1.1 single-shot — bypassing
  `_sandhi_http_dispatch`'s built-in follow loop so the auto
  follower owns the chain). New `_sandhi_http_auto_follow` mirrors
  `_sandhi_http_follow`'s security semantics (https→http refusal
  with err=TLS surfaced, Authorization / Cookie /
  Proxy-Authorization stripped on cross-authority hops, 303
  rewrites to GET and drops body) and bounds via `opts.max_hops`.
  Each hop re-enters `_sandhi_http_auto_once`, so a redirect from
  authority A (no h2 in pool) to authority B (h2 in pool) takes
  the h2 path for hop 2. `sandhi_http_request_auto` now branches
  on `opts.follow`: 1 → follower, 0 → single hop.
- Side effect: under 0.9.4 and prior, `sandhi_http_request_auto`
  with `opts.follow=1` worked only when the pool didn't have an h2
  conn (h2 wins → silent drop of the redirect; 1.1 wins → follow
  inside `_sandhi_http_dispatch`). Now both branches follow.

### http/retry

- `src/http/retry.cyr` — `_sandhi_http_retry` calls
  `sandhi_http_request_auto` instead of `_sandhi_http_dispatch`.
  `sandhi_http_get_retry` / `_head_retry` / `_put_retry` /
  `_delete_retry` now inherit h2 selection: when the attached
  pool has an h2 conn for the route, retries use h2; otherwise
  they fall back to 1.1. Pre-0.9.5 retries were 1.1-only
  regardless of pool state. Backoff + jitter behavior unchanged.

### Verification

The redirect helpers used by the new code (`_sandhi_is_redirect`,
`_sandhi_resolve_location`, `_sandhi_url_same_authority`,
`_sandhi_url_is_https_downgrade`, `_sandhi_strip_sensitive_headers`)
are already covered by the 0.9.0 P0 redirect tests in
`tests/sandhi.tcyr` (lines 548–880). End-to-end h2 redirect
verification follows the precedent set when 0.8.1 shipped
`sandhi_http_request_auto` itself — gated on a consumer
integration ask, since synthetic h2 round-trip plumbing isn't in
the test infra today.

## [0.9.4] — 2026-04-25

**Versioning refactor + chunked response trailers.** No new public
verbs (ADR 0005 freeze respected); existing accessors gain new data,
nothing changes shape.

**635 assertions green** (482 sandhi + 153 h2). Trailer-parser
verification lives in `programs/_trailers_probe.cyr` rather than
the test suite — `tests/sandhi.tcyr` is at the per-program fixup
cap (architecture/001).

### Versioning — single source of truth via auto-generated file

Mirrors the cyrius repo's own pattern (`cyrius/src/version_str.cyr`
+ `cyrius/scripts/version-bump.sh`). Before this release, the
version literal was duplicated: once in `VERSION`, once in
`src/main.cyr` as `var SANDHI_VERSION = "..."`. A shell-level CI
check was the only thing keeping them in sync.

- **`scripts/version-bump.sh`** — new. Reads VERSION; regenerates
  `src/version_str.cyr` (which contains exactly one line:
  `var SANDHI_VERSION = "X.Y.Z"`); inserts a CHANGELOG section
  header on a real bump. Same-version invocation is the documented
  "regenerate without bumping" path used by CI for drift detection.
- **`src/version_str.cyr`** — new, auto-generated, committed. The
  ONLY place `SANDHI_VERSION` is declared. Registered first in
  `cyrius.cyml [lib].modules` so every later module sees it.
- **`src/main.cyr`** — `var SANDHI_VERSION = ...` removed.
  `sandhi_version()` still delegates to `SANDHI_VERSION` (defined
  upstream in the build order).
- **CI / release** — `Verify version sync` step now re-runs
  `scripts/version-bump.sh "$(cat VERSION)"` and `git diff --quiet
  src/version_str.cyr` instead of grep+sed-ing the literal out of
  source. Same drift detection, less brittle parsing.
- All probe programs and test files updated to `include
  "src/version_str.cyr"` ahead of `src/error.cyr` so they pick up
  the var.

Bump flow now: `sh scripts/version-bump.sh 0.9.5` → regen dist
(`cyrius distlib`) → fill in CHANGELOG entries → commit.

### http
- `src/http/response.cyr` — chunked-body decoder parses RFC 7230
  §4.1.2 trailers after the terminal 0-chunk and merges allowed
  fields into the response headers (visible via the existing
  `sandhi_http_headers(r)` accessor — no new public verb). The
  RFC's forbidden-trailer list is filtered: `Transfer-Encoding`,
  `Content-Length`, `Host`, `Authorization`, `Set-Cookie`,
  `Cache-Control`, `Expect`, `Max-Forwards`, `Pragma`, `Range`,
  `TE`, `Trailer` — those are smuggling vectors. Allowed trailers
  (`Server-Timing`, custom `X-*` etc.) appear in headers naturally.
- Stale "no consumer asks" framing removed from
  `src/http/pool.cyr` and `src/http/h2/request.cyr`.

### Verification
- `programs/_trailers_probe.cyr` — confirms allowed trailers
  surface in headers, forbidden trailers are filtered, plain
  chunked (no trailer block) still works. All five scenarios PASS.

## [0.9.3] — 2026-04-25

**Stub-elimination pass** — every runtime stub in `src/` shipped in
prior 0.x releases has been replaced with a working implementation.
Internal wire-up only; no new public verbs (ADR 0005 freeze
respected). Existing accessors stop returning 0 and start returning
real values.

**634 assertions still green** (481 sandhi + 153 h2). Three existing
tests (`test_p0_tls_policy_fail_closed`, `test_tls_enforcement_flag`,
`test_discovery_local_stub_always_misses`) were rewritten to reflect
the wired-up state — they had baked in the stub contracts they were
guarding.

### Toolchain pin
- `cyrius.cyml [package].cyrius` 5.6.30 → 5.6.41 across the day.
  Fix sequence: 5.6.39 cleared `libssl-pthread-deadlock`, 5.6.40
  shipped the SSL_CTX hook (`tls_connect_with_ctx_hook` + `tls_dlsym`),
  5.6.41 fixed a SysV-ABI calling-convention regression that broke
  `tls_connect` when invoked from a 7-param Cyrius frame. All three
  issue docs now live in `docs/issues/archive/`.

### http
- `src/http/conn.cyr` — ALPN runtime wired. HTTPS connections call
  stdlib's `tls_connect_with_ctx_hook` with a hook that runs
  `SSL_CTX_set_alpn_protos`; post-handshake, `SSL_get0_alpn_selected`
  copies the negotiated protocol into a new `SANDHI_CONN_OFF_ALPN_DATA`
  slot on the conn struct (struct grows 24 → 32 bytes). Default
  advertise is `http/1.1` only — matches what the 1.1 client path
  can speak. A module-level `_sandhi_alpn_advertise_h2` toggle lets
  a future h2 auto-dispatcher claim h2 capability without a public
  API change. Hook-override pair (`_sandhi_tls_hook_override` /
  `_sandhi_tls_hook_override_ctx`) lets `tls_policy/apply.cyr` swap
  in a richer policy-aware hook for the same open path.

### tls_policy
- `src/tls_policy/alpn.cyr` — `sandhi_conn_alpn_selected` and
  `sandhi_conn_alpn_is_h2` now read the new conn-struct slot.
  Previously `return 0` stubs.
- `src/tls_policy/apply.cyr` — `sandhi_tls_policy_enforcement_available`
  resolves nine libssl/libcrypto symbols via `tls_dlsym`
  (`SSL_CTX_set_alpn_protos`, `SSL_CTX_load_verify_locations`,
  `SSL_CTX_use_certificate_file`, `SSL_CTX_use_PrivateKey_file`,
  `SSL_get(1)_peer_certificate`, `X509_get_pubkey`, `i2d_PUBKEY`,
  `X509_free`, `EVP_PKEY_free`) and returns 1 when all load. The
  policy-aware hook layers trust-store override + mTLS cert/key load
  on top of ALPN advertise; post-handshake SPKI pinning extracts the
  peer SPKI DER, hashes via stdlib `sigil`'s SHA-256, and compares
  via `sandhi_fp_eq` (constant-time). Mismatch closes the conn and
  fails the open with err=TLS (ADR 0004).

### discovery
- `src/discovery/local.cyr` — mDNS resolver implemented (RFC 6762).
  Builds an A-record query for `<name>.local` with the QU bit set
  (so responders unicast back, no IP_ADD_MEMBERSHIP needed), sends
  to 224.0.0.251:5353, recvs with SO_RCVTIMEO=500 ms, parses via the
  unicast resolver's `_sandhi_resolve_parse_response`. Returns a
  `sandhi_service` on hit, 0 on miss. `sandhi_discovery_local_available()`
  flipped from 0 to 1.

### http
- `src/http/conn.cyr` — IPv6 connect path added.
  `_sandhi_conn_open_v6_fully_timed(addr16, port, ...)` opens a
  `socket(AF_INET6) + connect(sockaddr_in6)` via raw syscalls,
  reuses the existing TLS/ALPN/policy plumbing through a new
  `_sandhi_conn_finalize` helper shared with the v4 path.
  `_sandhi_conn_connect_sa_nb` factors the non-blocking
  connect+poll dance so v4 and v6 share the connect_ms logic.
- `src/http/client.cyr` — `_sandhi_http_do_impl` now falls back to
  v6 when `_sandhi_client_resolve` misses on v4. v6-only hosts are
  reachable through `sandhi_http_get` without any consumer change
  (ADR 0005 freeze means no new public open verb — internal helper
  only).

### Verification (programs/_*.cyr — disposable probes, not in suite)
- `_alpn_runtime_probe.cyr` — advertise toggle round-trips:
  default → `http/1.1`; flip-flag → `h2`. Real wire negotiation.
- `_policy_runtime_probe.cyr` — enforcement_available=1, default
  policy opens, wrong-pin closes with err=TLS, bad-trust-store
  closes with err=TLS.
- `_mdns_probe.cyr` — sends real multicast UDP to 224.0.0.251:5353,
  recv-timeout fires cleanly when no responder is present (~500 ms);
  qname builder preserves `.local` suffix correctly (case-insensitive).
- `_v6_probe.cyr` — `_sandhi_conn_open_v6_fully_timed` connects to
  a Python listener bound on `::1`, full HTTP request/response
  roundtrip via `socket(AF_INET6)` + `connect(sockaddr_in6)`.
- `_https_oneshot.cyr` (canonical) — `sandhi_http_get("https://example.com/")`
  returns 200 / 528 bytes through the full sandhi stack.

### Stdlib deps
- Added `sigil` already in 0.7.x; this release exercises `sha256` for
  SPKI hashing.

## [0.9.2] — 2026-04-24

**Pre-fold closeout** — last sandhi-side release before the v5.7.0
fold lands sandhi into Cyrius stdlib as `lib/sandhi.cyr`. Three
focused changes: server-symbol rename for prefix consistency,
first formal `dist/sandhi.cyr` bundle generated, surface-freeze
policy documented in CLAUDE.md.

**634 total assertions** (481 sandhi + 153 h2; +2 server-rename
regression).

### Server symbol rename
`src/server/mod.cyr` — every public function renamed from `http_*`
to `sandhi_server_*` for consistency with the rest of the sandhi
public surface. The original names came from the M1 (v0.2.0) lift-
and-shift of stdlib `lib/http_server.cyr`; that prefix was a
historical artifact.

Affected functions (all 21 public + 2 helpers):

- `http_get_method` → `sandhi_server_get_method`
- `http_get_path` → `sandhi_server_get_path`
- `http_body_offset` → `sandhi_server_body_offset`
- `http_find_header` → `sandhi_server_find_header`
- `http_content_length` → `sandhi_server_content_length`
- `http_request_has_dup_smuggling_header` → `sandhi_server_*` (matching)
- `http_request_has_cl_te_conflict` → `sandhi_server_*`
- `http_path_only` → `sandhi_server_path_only`
- `http_url_decode` → `sandhi_server_url_decode`
- `http_get_param` → `sandhi_server_get_param`
- `http_path_segment` → `sandhi_server_path_segment`
- `http_send_status` → `sandhi_server_send_status`
- `http_send_response` → `sandhi_server_send_response`
- `http_send_204` → `sandhi_server_send_204`
- `http_send_chunked_start` → `sandhi_server_send_chunked_start`
- `http_send_chunk` → `sandhi_server_send_chunk`
- `http_send_chunked_end` → `sandhi_server_send_chunked_end`
- `http_recv_request` → `sandhi_server_recv_request`
- `http_server_run` → `sandhi_server_run`
- `http_server_run_opts` → `sandhi_server_run_opts`
- `_http_count_header_occurrences` → `_sandhi_server_count_header_occurrences`

**Transitional `http_*` aliases retained** through 0.9.x — every
old name is preserved as a thin wrapper that tail-calls the new
name. Existing consumers (smoke program, tests, downstream crates)
keep working unchanged. The aliases retire at 1.0.0 — the v5.7.0
fold ships `lib/sandhi.cyr` with `sandhi_server_*` only, and
consumers update their `include` line in the same release.

`sandhi_server_version()` bumped from 0.2.0 (M1 landing) to 0.9.2
(this rename's first usable form).

### `dist/sandhi.cyr` first formal bundle
`cyrius distlib` produces the standalone bundle:
- 8564 lines, 335 KB
- Concatenates every module in `cyrius.cyml [lib].modules` in
  build-order
- Header marks the `# Version: 0.9.2` and `# Generated by: cyrius
  distlib` so consumers can probe what they're including
- Stdlib references stay unresolved in the bundle (expected —
  consumer supplies stdlib via their own `[deps] stdlib` list)

This is what stdlib will vendor at v5.7.0 to produce the new
`lib/sandhi.cyr`. From here through 1.0.0, every release
regenerates the bundle so consumer-pinned bundles always reflect
the latest fixes.

### Surface freeze policy
CLAUDE.md gains a new hard-constraint line:

> Public surface frozen at 0.9.2. No new public verbs land between
> 0.9.2 and the v5.7.0 fold (1.0.0). The fold ships sandhi into
> stdlib's `lib/sandhi.cyr` permanently — every name in the public
> surface at fold-time becomes a permanent stdlib API. Bug fixes
> and internal refactors are fine; new verbs are not. If a
> consumer asks for something post-0.9.2, it lands as a 1.0.x
> stdlib patch after fold, not as 0.9.x.

This is the operational discipline that makes the clean-break
fold (per ADR 0002) safe. Anything that ships at 1.0.0 lives in
stdlib forever.

### Tests
- New `server/rename_canonical` test in `sandhi.tcyr` exercising
  the new `sandhi_server_*` names directly. The existing 25+
  tests using `http_*` names continue to pass through the alias
  layer, providing implicit regression coverage of the alias
  wrappers.

### Notes
- No new code paths or behavior changes — pure rename + alias +
  bundling + policy. Every existing test passes; only the version
  string in `test_sandhi_identity` updated to match the bumped
  `sandhi_server_version()`.
- 1.0.0 = fold event @ Cyrius v5.7.0. External gate, checked at
  the Cyrius release. From here, sandhi enters maintenance mode;
  follow-on patches ship via the Cyrius release cycle.

## [0.9.1] — 2026-04-24

**Phase 2 security sweep** — P1 hardening / defense-in-depth from
the 0.7.0 audit. **632 total assertions green** (479 sandhi + 153
h2; +17 over 0.9.0's 615). All hardening; no behavior change to
well-formed callers.

### Hardening

#### URL port overflow guard
`src/http/url.cyr` — explicit 5-digit cap on the port-parse loop.
The existing post-multiply `port > 65535` check already aborted
before the i64 multiply could wrap (port grows at most 5 digits
before exceeding 65535), but the digit-count guard is more
defensive and rejects pathological inputs (`http://h:0000000000080/`)
that any other parser might handle differently.

#### Header CRLF / NUL validation
`src/http/headers.cyr` — `sandhi_headers_add` and `_set` now
reject CR / LF in name or value. New `_sandhi_hdr_has_unsafe_byte`
helper. Without this, `sandhi_headers_set(h, "X", "v\r\nInjected:
yes")` could smuggle a new header onto the wire when the entry
serializes. Returns `0 - 1` on rejection.

#### Content-Length strict parse
`src/http/response.cyr::_sandhi_resp_parse_clen` and
`src/server/mod.cyr::http_content_length` — pure decimal digits
only (with optional leading/trailing whitespace) per RFC 7230
§3.3.2. Previously `"10, 20"` parsed as 1020 — different from
any sane parser, the CL.CL leg of the smuggling triad. Returns
`0 - 1` (response side) / `0` (server side) on malformed values;
`_sandhi_resp_frame` propagates the response error as
`SANDHI_ERR_PROTOCOL`.

#### SPKI constant-time compare
`src/tls_policy/fingerprint.cyr::sandhi_fp_eq` — replaced
`streq`'s short-circuit with a length-aware constant-time XOR
accumulator. Cert-pinning is auth-adjacent; defensive compares
should always be constant-time, full stop.

#### SSE id-with-NUL ignored
`src/http/sse.cyr` — new `_sandhi_sse_value_has_nul` helper
scans the raw value bytes (cstr operations don't see embedded
NULs) and the `id` field handler skips assignment per WHATWG
EventSource spec. An `id: a\x00b` field used to store the
attacker-controlled prefix that strlen consumers would truncate
to "a", causing reconnect-with-Last-Event-ID drift.

#### Header duplicate detection
`src/http/headers.cyr` — new `sandhi_headers_smuggle_dup`
counts `Host` / `Content-Length` / `Transfer-Encoding`
occurrences via the existing `_sandhi_hdr_ieq` case-insensitive
match. `_sandhi_resp_frame` rejects the response if any of
those three appear more than once. Server side (in `mod.cyr`)
gets parallel `_http_count_header_occurrences` +
`http_request_has_dup_smuggling_header`; the accept loop
replies 400 before user-handler dispatch. Closes CL.CL /
Host.Host / TE.TE smuggling vectors per RFC 7230 §3.3.2 + §5.4.

#### SSE re-entrance fix (the biggest of the P1s)
`src/http/sse.cyr` — parser state moved off module-scope
globals (`_sandhi_sse_cur_*`) into a 40-byte ctx struct
allocated per `sandhi_sse_parse` call. New
`_sandhi_sse_ctx_new` / `_reset` / accessors via offset
constants. `_sandhi_sse_apply_line` now takes a ctx parameter.
The previous module-scope vars made the parser non-reentrant —
a callback fired during stream dispatch that itself parsed SSE
(e.g., chained MCP-over-SSE) would clobber the outer parse's
state. With per-call ctx, nested calls are independent.

### Considered and verified — no fix needed

#### JSON escape state
The 0.7.0 audit's P2 #21 flagged `_sandhi_json_skip_object`'s
`prev_backslash` tracking as broken on `\\\"`. After tracing the
state machine through `\\\\` (escaped-backslash + escaped-quote)
+ `\\\"` (escaped-backslash + escaped-quote) + `\\` (escaped-
backslash) + `\\\\\\\\` (4 escaped-backslashes) + the closing-
quote disambiguation case, the existing logic handles every
combination correctly. Documented the trace in this CHANGELOG
entry rather than refactor for no behavior change.

### Tests added (8 in `tests/sandhi.tcyr`)

`p1/url_port_valid`, `p1/url_port_overflow`,
`p1/header_crlf_rejected`, `p1/clen_strict_comma`,
`p1/clen_strict_plus`, `p1/spki_compare`, `p1/header_dup`,
`p1/sse_reentrant`. Each exercises the precise bug class the fix
addresses.

### Notes

- `sandhi_headers_version()` bumped to 0.9.1 to mark the new
  smuggle-dup accessor.
- Server-side SSE id-NUL test deferred — synthetic byte buffer
  with embedded NUL needs an alloc-pattern that didn't fit one
  test cleanly; behavior verified by reading code + helper test
  for `_sandhi_sse_value_has_nul`.
- 0.9.2 picks up the closeout: server `http_*` →
  `sandhi_server_*` rename, surface freeze, first
  `dist/sandhi.cyr` via `cyrius distlib`, consumer pin uplift
  coordination. 1.0.0 = fold event @ Cyrius v5.7.0.

## [0.9.0] — 2026-04-24

**Phase 1 security sweep** — five P0 fixes from the 0.7.0 external
audit. Every fix has a focused regression test. **615 total
assertions green** (462 sandhi + 153 h2; +16 over 0.8.1's 599).

Minor-version bump rather than patch because two of the fixes
change observable behavior:

- Redirects across origins **now strip** `Authorization` /
  `Cookie` / `Proxy-Authorization` (curl CVE-2025-0167 / 14524
  cluster). Existing callers that relied on credentials following
  cross-origin redirects need to re-architect (per-domain auth or
  refuse-and-re-issue).
- Pinned / mTLS / custom-trust-store policies **now fail-closed**
  when enforcement isn't actually wired (which it isn't yet —
  libssl + stdlib hook blockers). Previously the silent downgrade
  to default verify gave a false sense the pinned policy was
  enforced. Use `sandhi_tls_policy_new_default()` for the previous
  best-effort behavior; that has no enforcement requirements.

The other three fixes are protocol-correctness — visible only to
malformed peers (servers + smuggling-relayed traffic). Behavior
changes only relative to the previously-too-lenient parser.

### P0 #1 — Chunked decoder hardening

`src/http/response.cyr`. `_sandhi_resp_chunk_size` returns a
`_SANDHI_RESP_CHUNK_BAD = -1` sentinel when no hex digit is present
(previously fell through with `size=0` and got treated as the
terminal chunk — silent body truncation). `_sandhi_resp_decode_chunked`
tracks `saw_terminal`; missing terminal 0-chunk → `SANDHI_ERR_PROTOCOL`.

### P0 #2 — CL + TE coexistence rejected

`src/http/response.cyr::_sandhi_resp_frame` returns `SANDHI_ERR_PROTOCOL`
when both `Content-Length` and `Transfer-Encoding: chunked` are
present. New `src/server/mod.cyr::http_request_has_cl_te_conflict`
detects the same on requests; the accept loop replies 400 before
the user handler runs. Closes the classic CL.TE / TE.CL request /
response smuggling vector per RFC 7230 §3.3.3.

### P0 #3 — Chunk-size overflow guard

`_sandhi_resp_chunk_size` rejects sizes > `_SANDHI_RESP_CHUNK_MAX
= 0x7FFFFFFF` (i31). Previously a 17-hex-char chunk-size could
overflow the signed-64-bit accumulator into a negative value that
bypassed the `off + size > blen` bounds check.

### P0 #4 — Redirect credential strip + downgrade refusal

`src/http/client.cyr::_sandhi_http_follow`. Three new helpers:
`_sandhi_url_same_authority` (scheme + host + port match),
`_sandhi_url_is_https_downgrade` (https→http detection),
`_sandhi_strip_sensitive_headers` (drops Authorization / Cookie /
Proxy-Authorization). Plus `_sandhi_streq_ci` for case-insensitive
header-name match.

On each redirect hop:
- HTTPS→HTTP downgrade refused — return the redirect response with
  `err_kind = SANDHI_ERR_TLS`, don't follow.
- Cross-authority hop strips sensitive headers from the request on
  the next hop. Per-hop semantics — bouncing back to the original
  authority restores full headers.

Private-IP / link-local SSRF guard stays opt-in for a future
option. This fix focuses on always-on credential / scheme protection.

### P0 #5 — TLS-policy fail-closed

`src/tls_policy/apply.cyr::sandhi_conn_open_with_policy`. When the
supplied policy demands enforcement (any of `pinned_hash` /
`mtls_cert` / `trust_store` set) AND
`sandhi_tls_policy_enforcement_available() == 0`, refuse the
connection — return 0 with `_sandhi_conn_last_err =
SANDHI_CONN_OPEN_TLS`. Previous silent downgrade is gone.

### Tests added (9 in `tests/sandhi.tcyr`)

`p0/chunked_complete`, `p0/chunked_no_terminal`, `p0/chunked_no_digit`,
`p0/cl_te_rejected`, `p0/chunk_overflow`, `p0/redirect_authority`,
`p0/redirect_downgrade`, `p0/redirect_strip`, `p0/tls_fail_closed`.
Each exercises the precise bug class the fix addresses.

### Notes

- Server-side P0 #2 reuses the existing `http_send_status(cfd, 400,
  ...)` helper; no new server response surface.
- The 400 dispatch happens before the user-handler call so smuggled
  requests can't slip past via custom routing logic.
- 0.9.1 picks up the P1 sweep (~7 items: SSE re-entrance, header
  dup-detect, SPKI constant-time, CL strict parse, URL port
  overflow, JSON escape state, header CRLF validation). 0.9.2 is
  closeout (server rename + surface freeze + first
  `dist/sandhi.cyr`). 1.0.0 = fold event at Cyrius v5.7.0.

## [0.8.1] — 2026-04-24

Auto-selection wiring + upstream-ask filed for the ALPN advertise
side. Strictly additive — no existing call-site behavior changes.

### Added
- **http/h2/dispatch**: `sandhi_http_request_auto(method, url,
  user_headers, body, body_len, opts)` — checks the attached pool
  for an h2 conn matching the URL's route; if found, dispatches via
  `sandhi_h2_request`; otherwise falls through to the existing
  `_sandhi_http_dispatch` (HTTP/1.1 path with all its features —
  redirects, retry, timeouts, etc.).
- **http/h2/dispatch**: convenience verbs `sandhi_http_get_auto` /
  `_head_auto` / `_post_auto` / `_put_auto` / `_patch_auto` /
  `_delete_auto`. Same signature shape as the 1.1 verbs; just
  routes through the auto-selecting dispatch.

### Limitations carried (still gated on stdlib + libssl)
- The h2 dispatch path **does not** support redirect-following or
  retry-with-backoff today. Both stay 1.1-only because no consumer
  has reported needing them on h2 yet, and they require state
  machine tweaks. Auto-selection naturally falls through to 1.1
  when redirects or retries are needed via the existing `*_opts`
  path.
- Live ALPN negotiation still doesn't fire — sandhi cannot set the
  advertise list because stdlib `tls.cyr` hides the SSL_CTX. Filed
  as `docs/issues/2026-04-24-stdlib-tls-alpn-hook.md` proposing a
  function-pointer hook variant of `tls_connect`. When the hook
  lands + libssl-pthread-deadlock clears, `sandhi_http_request_auto`
  starts auto-negotiating without consumer code change.

### Changed
- `src/main.cyr`: `sandhi_version()` → `0.8.1`.
- `src/http/h2/dispatch.cyr`: `sandhi_h2_dispatch_version()` → `0.8.1`.
- 4 expected-wire-bytes UA strings in `tests/sandhi.tcyr` bumped
  `0.8.0` → `0.8.1`.

### Notes
- No new tests in this patch. The auto-dispatch verb is a 3-line
  orchestration over pool h2 take + `sandhi_h2_request` (both
  tested in Bite 6 / 5b-c respectively) + `_sandhi_http_dispatch`
  (covered by existing sandhi.tcyr tests). Adding a dedicated
  integration test would require pulling `client.cyr` into
  `h2.tcyr`, which risks tripping the per-program fixup cap.
- 599 total assertions remain green (no regression).
- Huffman encode (currently raw-only — RFC 7541 permits this; spec
  requires servers to accept) stays deferred. Encode is wire-size
  optimization; no consumer asks for it yet.

## [0.8.0] — 2026-04-24

HTTP/2 + connection pool. Eight commit-sized "bites" landed in this
release: pool + 1.1 keep-alive (Bite 1), HPACK + Huffman decode
(Bites 2 + 2b), h2 frames (Bite 3), ALPN surface (Bite 4), h2
connection lifecycle split into request send + response decode
(Bites 5a/5b/5c), pool h2 glue (Bite 6), and the public h2 dispatch
verb (Bite 7).

**599 total test assertions** across two files (446 sandhi + 153 h2)
— up from 0.7.3's 411. The h2 protocol stack is functionally
complete (HEADERS/DATA/SETTINGS/PING/GOAWAY/RST_STREAM/CONTINUATION,
HPACK encode + decode including Huffman, full RFC 7541 Appendix
C.3.1 + C.4.1 round-trips verified).

#### Two known limitations called out

1. **Live h2 talk is blocked on libssl-pthread-deadlock**
   (`docs/issues/2026-04-24-libssl-pthread-deadlock.md`). Until that
   clears, the `sandhi_http_get` etc. public verbs continue to use
   the HTTP/1.1 path. Consumers that want h2 today open the conn
   themselves and call `sandhi_h2_request(h2c, method, url, ...)`
   directly — full lifecycle covered, just no auto-negotiation.
2. **ALPN runtime is stubbed** (`src/tls_policy/alpn.cyr` —
   `sandhi_conn_alpn_selected` always returns 0). The wire-format
   encoder is fully tested; the OpenSSL hookup
   (`SSL_CTX_set_alpn_protos` + `SSL_get0_alpn_selected`) is ~30
   lines and lands when the libssl blocker is gone. Bite 7's
   `sandhi_http_get` auto-selection wiring lands at that same
   moment, in a 0.8.1 patch.

#### What's actually new since 0.7.3

##### Connection pool + HTTP/1.1 keep-alive (Bite 1, 769 lines)
- New `src/http/pool.cyr`. Pool struct keyed by `host:port:tls` →
  vec of `idle_conn{conn, last_used_ms}`. LIFO take with stale-
  skip; FIFO eviction at `max_per_host`. Default 8 conns/route,
  90 s idle timeout (matches Go).
- New `_sandhi_http_recv_framed` parses Content-Length / chunked
  incrementally so the socket survives the request.
- `sandhi_http_options_pool(opts, pool)` — opt-in attachment.
  Caller flow unchanged; `Connection: close` is replaced with
  HTTP/1.1 default keep-alive when a pool is attached.
- Per-hop pool reuse for redirects.

##### HPACK (Bite 2, ~530 lines)
- Static table — RFC 7541 Appendix A, all 61 entries (split into
  4 helper-fn chunks to dodge Cyrius's per-fn fixup cap).
- Dynamic table with size-based tail eviction; oversized entries
  empty the table per §4.4.
- Integer encoder/decoder (§5.1, configurable prefix bits).
- String encoder/decoder (§5.2 — encode always raw; decode handles
  raw or Huffman-via-Bite-2b).
- All 5 header-field representations (§6.1–§6.3).

##### HPACK Huffman decode (Bite 2b, ~150 lines + 2570-char data blob)
- Full RFC 7541 Appendix B 257-entry code table embedded as a
  single hex blob (one fixup) and parsed at first use into a
  binary decode tree.
- Padding-rule enforcement per §5.2 (≤7 bits, all-1s, no EOS in
  payload).
- RFC C.4.1 `www.example.com` round-trips correctly.

##### HTTP/2 frame layer (Bite 3, ~280 lines)
- 32-byte frame-header struct + encode/decode honoring §4.1
  (length cap 2^24-1, stream-id reserved-bit stripped).
- Per-frame payload codecs for SETTINGS (§6.5), PING (§6.7),
  WINDOW_UPDATE (§6.9), RST_STREAM (§6.4), GOAWAY (§6.8).
- All 14 error codes (§7), all 6 SETTINGS parameters (§6.5.2),
  flag constants for END_STREAM / ACK / END_HEADERS / PADDED /
  PRIORITY.

##### ALPN surface (Bite 4, ~75 lines)
- Wire-format encoder for ProtocolNameList (RFC 7301 §3.1).
- Default `h2,http/1.1` advertise list.
- `sandhi_conn_alpn_selected` / `_is_h2` accessors (stubbed pending
  libssl).

##### h2 connection lifecycle (Bites 5a/5b/5c, ~590 lines combined)
- 5a: 80-byte conn struct (HPACK enc/dec tables, peer settings,
  stream-id counter, GOAWAY flag); frame send/recv plumbing;
  preface + SETTINGS handshake.
- 5b: HEADERS encoding via HPACK (4 pseudo-headers in spec order +
  user headers, lowercased and forbidden-list filtered per
  §8.1.2.2); HEADERS+optional-DATA frame send.
- 5c: frame loop dispatching by type and stream-id, response decode
  (HEADERS+CONTINUATION reassembly + HPACK decode, DATA accumulation
  with PADDED handling, RST_STREAM/GOAWAY surface as REMOTE error),
  returns `sandhi_response` shape.

##### Pool h2 glue (Bite 6, ~60 lines)
- New `src/http/h2/pool_glue.cyr` adds `sandhi_http_pool_take_h2` /
  `_put_h2` / `_close_h2_conns`. h2 conns are shared per route (one
  conn, many streams) — take is non-exclusive. GOAWAY conns are
  evicted on next take.

##### Public h2 dispatch verb (Bite 7, ~70 lines)
- New `src/http/h2/dispatch.cyr`'s `sandhi_h2_request(h2c, method,
  url, headers, body, body_len)` runs one full request/response
  cycle on a caller-supplied h2 conn. Returns the same
  `sandhi_response` shape as the HTTP/1.1 path.

#### Test infrastructure (Bite 2.5)

- Split `tests/sandhi.tcyr` (existing 446 assertions) and added
  `tests/h2.tcyr` (153 h2-specific assertions). The Cyrius compiler
  caps the per-program fixup table at 32768 — single-file tests
  hit the cap once HPACK landed. CI runs both.
- Filed `docs/proposals/2026-04-24-cyrius-fixup-table-cap.md` for
  the upstream-investigation question.
- Fixed `.github/workflows/ci.yml` (referenced a nonexistent
  `src/test.cyr`; CI never actually tested anything until this fix).

#### Notes / follow-ups

- The libssl-pthread-deadlock + ALPN stubs together mean the
  `sandhi_http_get` public verbs continue to use 1.1 even when h2
  is fully ready in protocol code. This is the right state to ship
  — no consumer is currently surprised by it because no consumer
  is making live HTTPS calls anyway.
- 0.8.1 will land auto-selection wiring + Huffman encode (currently
  raw-only — RFC 7541 permits this; servers must accept).
- Performance work (e.g., stream-multiplex flow-control tracking,
  HPACK encode-side static table optimization beyond pseudo-headers)
  is post-fold and only when a consumer reports a real bottleneck.

## [0.7.3] — 2026-04-24

Closes the two timeout knobs deferred from 0.7.2: `connect_ms` (non-
blocking connect + poll) and `total_ms` (monotonic-deadline threading
through every I/O phase). With both shipped, sandhi's HTTP client has
the full timeout surface — connect, read, write, and end-to-end — that
production consumers expect from a curl/reqwest-class library.

411 assertions green (+16 on the 0.7.2 baseline of 395), including
two live-network tests that fire connect against a TEST-NET-1
(192.0.2.0/24, RFC 5737) blackhole and verify the timeout returns
within budget.

### Added
- **http/conn**: `_sandhi_conn_connect_nb(fd, addr, port, timeout_ms)`
  — non-blocking connect via `O_NONBLOCK` + `connect()` (expects
  `EINPROGRESS`) + `poll(POLLOUT, timeout_ms)` + `getsockopt(SO_ERROR)`
  to distinguish connected from refused/unreachable. Restores
  blocking mode on every exit path. Local syscall constants
  `_SANDHI_SYS_POLL=7`, `_SANDHI_SYS_GETSOCKOPT=55`, `_SANDHI_F_GETFL=3`,
  `_SANDHI_F_SETFL=4`, `_SANDHI_O_NONBLOCK=2048`, `_SANDHI_EINPROGRESS=115`,
  `_SANDHI_SO_ERROR=4`, `_SANDHI_POLLOUT=4` (Linux x86_64; matches
  the existing `SYS_SETSOCKOPT=54` in stdlib `net.cyr` — aarch64
  needs a cross-cutting pass when it becomes a goal).
- **http/conn**: `sandhi_conn_open_fully_timed(addr, port, use_tls,
  sni, connect_ms, read_ms, write_ms)` — supersedes
  `sandhi_conn_open_timed` (now a 0-connect-ms wrapper). Uses
  `_sandhi_conn_connect_nb` when `connect_ms > 0`.
- **http/conn**: module-level `_sandhi_conn_last_err` + accessor
  `sandhi_conn_last_open_err()` — classifies the last open failure as
  `SANDHI_CONN_OPEN_OK` / `_CONNECT` / `_TIMEOUT` / `_TLS`. Single-
  threaded only; revisit if multi-threaded client model ever lands.
- **http/conn**: `sandhi_conn_recv_all_deadline(conn, buf, max,
  deadline_ms)` variant for `total_ms` enforcement. Loop-checks
  `clock_now_ms() >= deadline_ms` before each next-recv. SO_RCVTIMEO
  still bounds individual recv calls; the deadline is the outer
  ceiling. `sandhi_conn_recv_all` is now a `deadline_ms=0` wrapper.
- **http/client**: `sandhi_http_options_connect_ms(opts, ms)` /
  `sandhi_http_options_total_ms(opts, ms)` setters + matching
  getters. Options struct 40→56 bytes.
- **http/client**: `_sandhi_http_clamp_ms(raw_ms, deadline_ms)`
  helper — returns `raw_ms` if no deadline, the lesser of `raw_ms`
  and `(deadline - now)` if both, or `-1` sentinel if the deadline
  has elapsed. Used at every phase boundary in `_sandhi_http_do_impl`
  to bound the next operation against `total_ms`.

### Changed
- **http/client `_sandhi_http_do_impl`** computes `deadline_ms` at
  entry from `total_ms`, threads it to `_sandhi_http_exchange`, and
  uses `_sandhi_http_clamp_ms` to bound `connect_ms`. On
  `_sandhi_conn_open_fully_timed` failure, reads
  `sandhi_conn_last_open_err()` to map to `SANDHI_ERR_TIMEOUT` /
  `_TLS` / `_CONNECT` precisely (was: collapsed everything to
  CONNECT or TLS based on `use_tls`).
- **http/client `_sandhi_http_follow`** + `_sandhi_http_dispatch`
  thread the new `connect_ms` / `total_ms` through. Per-hop semantics
  for redirect chains: each hop gets its own `total_ms` budget — the
  total across all hops is bounded by `max_hops × total_ms`. If a
  consumer needs end-to-end-across-redirects, lower max_hops or
  shorten per-hop total_ms accordingly.
- **http/client `_sandhi_http_exchange`** gains a `deadline_ms` param;
  checks it at entry and uses the new
  `sandhi_conn_recv_all_deadline` for the body read.
- **http/stream `sandhi_http_stream_opts`** computes the same
  deadline + clamp + open-with-classification flow as the client.
  Body-loop checks `deadline_ms` before each next-recv — long-lived
  SSE streams now honor `total_ms` as an overall lifetime ceiling
  rather than a per-event timeout.
- **http/client / conn / stream**: `*_version()` strings → 0.7.3.
- **src/main.cyr**: `sandhi_version()` → 0.7.3.
- **tests**: bumped 4 expected-wire-bytes UA strings 0.7.2 → 0.7.3.

### Tests
- New: options coverage for `connect_ms` / `total_ms` defaults +
  mutators (4 new assertions in defaults + 2 in mutators).
- New: `_sandhi_http_clamp_ms` unit coverage — no-deadline / future-
  deadline / elapsed (~6 assertions across 3 cases).
- New: live-network connect_ms blackhole test against TEST-NET-1
  192.0.2.1:80 with 200 ms timeout, asserts `SANDHI_ERR_TIMEOUT`
  raised within a 5 s budget.
- New: live-network total_ms blackhole — same target, no connect_ms,
  total_ms=300 ms; verifies the deadline clamp closes the connect
  phase even when connect_ms isn't set explicitly.

### Notes
- Per-hop total_ms semantics are documented in the redirect-follower
  comment. End-to-end-across-redirects could be added later as a
  separate option (`overall_ms`) if a consumer asks; the shape is
  one extra field + threading the deadline across hops instead of
  recomputing.
- The non-blocking connect helper restores the fd to blocking mode
  before returning so subsequent recv/send don't get EAGAIN'd
  unexpectedly. SO_RCVTIMEO/SO_SNDTIMEO still apply post-connect.
- `_sandhi_conn_last_err` is module-level state. Today's callers
  (single-threaded HTTP client + stream) read it immediately after
  the open call returns 0, so there's no race window. A
  multi-threaded client would need this lifted to a per-call ctx;
  flagged for the 0.8.0 connection-pool work where multiple opens
  may interleave.

## [0.7.2] — 2026-04-24

Reliability + observability patch. Per-phase timeouts, retry wrappers
for idempotent methods, DNS hardening (TXID randomization + answer-
name verification + compression-pointer loop-guard), AAAA resolver
primitive, opt-in sakshi tracing, server-side idle-timeout. All
composed on stdlib (`syscalls` / `net` / `sakshi` / `chrono`); no
new external dependencies, no FFI, no stdlib patches required.

Pulled in four P1 security items while we were in `net/resolve.cyr`
(TXID randomness, answer-name match, compression-loop guard, source-
port leveraged implicitly via kernel ephemeral-port assignment). These
were on the 0.9.x P1 list; landing them together with the reliability
work is cheaper than a second read of the same file.

395 assertions green (+61 on the 0.7.1 baseline of 334).

### Added
- **http/client**: `sandhi_http_options_read_ms(opts, ms)` /
  `sandhi_http_options_write_ms(opts, ms)` setters + matching getters.
  Wired via direct `SYS_SETSOCKOPT` (`SO_RCVTIMEO=20` / `SO_SNDTIMEO=21`
  defined locally; stdlib `net.cyr` exposes the syscall + `SOL_SOCKET`
  but not the per-direction constants). Options struct 24→40 bytes.
  `SANDHI_ERR_TIMEOUT` (defined but never raised through 0.7.1) now
  fires when the SO_*TIMEO kernel deadline elapses.
- **http/conn**: `sandhi_conn_open_timed(addr, port, use_tls, sni,
  read_ms, write_ms)` variant. `sandhi_conn_open(...)` remains as a
  0-timeout wrapper. `sandhi_conn_send` / `_recv` / `_send_all` /
  `_recv_all` now return `0 - _SANDHI_EAGAIN` (= -11) on kernel
  timeout, letting callers distinguish timeout from other errors.
- **http/retry** (new `src/http/retry.cyr`): `sandhi_retry_new()` +
  `sandhi_retry_max_attempts(r, n)` / `_initial_backoff_ms(r, ms)` /
  `_max_backoff_ms(r, ms)`. Public verbs `sandhi_http_get_retry` /
  `_head_retry` / `_put_retry` / `_delete_retry` for idempotent
  methods only — POST/PATCH retry stays explicit. Retries on
  `CONNECT` / `TIMEOUT` / `DISCOVERY` / 5xx; not on 4xx / `PARSE` /
  `TLS` / `PROTOCOL`. Exponential backoff (2×) capped at max. Defaults:
  3 attempts, initial 50 ms, max 2000 ms. Sleeps via `sleep_ms` from
  stdlib `chrono`.
- **net/resolve**: `sandhi_resolve_ipv6(host)` — AAAA resolver
  returning a 16-byte net-byte-order buffer (or 0 on failure). Shares
  the hardened parse path (TXID echo + answer-name match). Client-side
  v6 connect integration deferred (no consumer has asked) — callers
  that need v6 dialing today use `sandhi_resolve_ipv6` + a future
  `sandhi_conn_open_v6_timed(...)` verb when it lands.
- **net/resolve hardening**: random 16-bit TXID per query via
  `/dev/urandom` (closes the Kaminsky cache-poisoning window). New
  `_sandhi_resolve_name_eq(buf, blen, off_a, off_b)` follows wire-
  format names with compression pointers, case-insensitive per RFC
  1035 §2.3.3, capped at 32 hops per name (`_SANDHI_RESOLVE_MAX_PTR_HOPS`).
  `_sandhi_resolve_parse_response` now verifies TXID echo + answer
  name matches question name — RRs for other hosts are scanned past,
  not trusted. Response qdcount forced to 1 (we only ever send 1
  question; anything else is malformed). All checks in one patch
  rather than spread across 0.9.x; the review finding is closed.
- **obs/trace** (new `src/obs/trace.cyr`): thin opt-in wrapper around
  stdlib sakshi's span API. `sandhi_trace_enable(on)` gates emission
  (default off — silent). `sandhi_trace_begin(name)` / `_end()` wrap
  the three boundary calls: `_sandhi_http_do` emits `sandhi.http`,
  `sandhi_resolve_ipv4` / `_ipv6` emit `sandhi.dns.v4` / `.v6`,
  `sandhi_rpc_call` / `_with_headers` emit `sandhi.rpc`. Nesting
  depth works as expected — the HTTP span appears inside the RPC span
  naturally. Attribute support deferred until sakshi grows span-attrs.
- **server**: `sandhi_server_options_new()` + `_idle_ms(opts, ms)` /
  `_max_conns(opts, n)` + getters. New `http_server_run_opts(addr,
  port, handler_fp, ctx, opts)` applies `SO_RCVTIMEO` to each accepted
  connection (slowloris guard; default 30 000 ms matches Go
  `net/http.Server.IdleTimeout`). `http_server_run(...)` remains as a
  0-opts wrapper. `max_conns` accepted but **not enforced** in 0.7.2 —
  server is single-thread accept/serve; concurrent model lands with
  0.8.0's thread-pool or epoll work.

### Changed
- **http/client** redirect follower + dispatch thread `read_ms` /
  `write_ms` through. `_sandhi_http_do`, `_sandhi_http_exchange`,
  and `_sandhi_http_follow` grew the two new parameters.
- **http/stream**: opts-aware variant honors `read_ms` / `write_ms`
  on the streaming connection. Read-loop + body-loop now map
  `0 - _SANDHI_EAGAIN` to `SANDHI_ERR_TIMEOUT` (was `SANDHI_ERR_CONNECT`
  collapse).
- **net/resolve**: `_sandhi_resolve_parse_response(buf, blen, expected_id)`
  signature changed — third parameter required. Callers inside the
  module + the synthetic-parse test updated.
- **src/main.cyr**: `sandhi_version()` → `0.7.2`.
- **cyrius.cyml `[lib].modules`**: added `src/obs/trace.cyr` (right
  after `error.cyr` — earliest, so all downstream modules can call
  into it) and `src/http/retry.cyr` (after `client.cyr`, before
  `sse.cyr`).

### Deferred from 0.7.2 at planning time
- **connect_ms** option + non-blocking connect path — requires either
  local syscall-number constants for `SYS_POLL` / `SYS_GETSOCKOPT`
  or a stdlib ask. Scheduled for 0.7.3.
- **total_ms** option — needs monotonic-deadline threading through
  every I/O phase. 0.7.3 alongside connect_ms.
- **Happy Eyeballs (RFC 6555)** — parallel v4+v6 connect race. Post-v1.
- **Connection pool / keep-alive** — shifted to 0.8.0 alongside HTTP/2
  since h2 multiplexing changes the pool checkout shape. Roadmap
  0.7.2 entry updated with rationale.
- **Client-side IPv6 connect path** (`sandhi_conn_open_v6_timed`) —
  resolver shipped; connect verb awaits a consumer ask.
- **Server concurrent connections** (`max_conns` enforcement) — 0.8.0.

### Notes
- No live-network tests added for timeout / retry — both require a
  blackhole fixture. Unit tests cover options getters/setters,
  retry-should-retry decision logic, and the EAGAIN-on-socket code
  path via synthetic response structs.
- sakshi is always-compiled-in (it's a stdlib dep anyway); the trace
  layer just gates emission. Zero runtime cost when disabled — every
  `sandhi_trace_begin`/`_end` short-circuits on the `_sandhi_trace_enabled`
  check before touching sakshi.
- DNS hardening bumps parse cost marginally (extra name-walk per
  answer RR). For typical 1-answer responses the overhead is <1 μs;
  CNAME-chain responses scale linearly with chain length but those
  are rare in the A-record path.

## [0.7.1] — 2026-04-24

Quick-wins patch. No behavior change for existing callers; new default
request headers + new response / options fields. Motivated by the 0.7.0
external security + gaps review (`docs/development/review-2026-04-24.md`
planning context captured in `roadmap.md` 0.7.1 entry).

### Added
- **http/client**: default `User-Agent: sandhi/<version>` and
  `Accept-Encoding: identity` request headers. Both are only emitted
  when the caller hasn't set their own — preserves override semantics.
  Explicit `identity` guards against servers that would otherwise
  return `Content-Encoding: gzip` sandhi cannot decode.
- **http/client**: `sandhi_http_options_max_response_bytes(opts, n)` +
  `sandhi_http_options_bytes(opts)`. Caps the buffered client's scratch
  buffer (previously a hard-coded 256 KB that silently truncated larger
  responses). Default unchanged at 262144.
- **http/stream**: `sandhi_http_stream_opts(url, method, headers, body,
  body_len, cb, ctx, opts)` — opts-aware variant honoring
  `max_response_bytes` for the header drain, body accumulator, and
  chunked-decode output buffer. `sandhi_http_stream(...)` unchanged —
  now a wrapper delegating with opts=0.
- **http/response**: `err_message` slot (cstr, +40 offset; struct size
  48) + `sandhi_http_err_message(r)` accessor + `_sandhi_resp_err_msg`
  private constructor. Reserved for the 0.8.x security pass — today's
  parser still populates only `err_kind`. ABI-breaking now so the
  security pass doesn't break it later.

### Changed
- **src/main.cyr** docstring corrected. Previously claimed the client
  shipped keepalive + conn pooling (0.7.2 roadmap items) and that the
  server module added routing + middleware (deferred). Now accurate.
- **src/main.cyr** `sandhi_version()` → `0.7.1`; per-submodule
  `*_version()` pointers aligned.

### Fixed
- **CI workflow**: `.github/workflows/ci.yml` gained an `on:
  workflow_call:` trigger. The 0.7.0 tag release failed because
  `release.yml` called `ci.yml` as a reusable workflow but `ci.yml`
  declared only `push` / `pull_request` triggers. Fix ships in 0.7.1
  for future release-tag workflows; the 0.7.0 release stands without
  a build-artifact upload.

### Notes
- The `User-Agent` string embeds `sandhi_version()` dynamically so it
  stays current across future patch bumps with no extra churn.
- No test regressions — all 333 existing assertions remain valid.
- New security-review surface findings are scoped to later releases
  (0.8.x P0 sweep, 0.9.x P1 + closeout) per `roadmap.md`.

## [0.7.0] — 2026-04-24

M3.5 close — SSE streaming + incremental chunked decode. Also carries the deps-stdlib audit + toolchain bump that unstuck the HTTPS investigation. 333 assertions green (+42 for sse + stream).

### Added
- **http/sse** (`src/http/sse.cyr`): WHATWG SSE/EventSource parser. Event struct `{name, data, id, retry_ms}` + `sandhi_sse_parse(buf, blen, remaining_out) -> vec<event>`. Handles multi-line `data:` concatenation (lines joined with `\n`), comment skipping (`: keepalive`), CRLF / LF / CR line endings, default event name `"message"`, proper field reset between events, empty-data-field dispatch.
- **http/stream** (`src/http/stream.cyr`): streaming HTTP dispatcher. `sandhi_http_stream(url, method, headers, body, body_len, cb, ctx)` sends the request, drains response headers, then feeds body bytes through an incremental chunked decoder (state-machine, not the buffer-the-whole-thing decoder in response.cyr) and into the SSE parser. Callback fires once per event; returning 0 stops the stream cleanly. Returns a stream-result struct `{http_status, events_dispatched, err_kind, stopped_by_cb}`.
- **rpc/mcp**: `sandhi_rpc_mcp_stream(endpoint, method, params, cb, ctx)` — JSON-RPC envelope build + SSE response streaming. Useful for MCP servers that stream tools/progress or resources/change notifications.

### Fixed
- **`cyrius.cyml [deps.stdlib]`** — added `mmap`, `dynlib`, `fdlopen`, `bigint`, `freelist`. These were transitive requirements of `tls` / `sigil` that sandhi's main manifest never listed, so `cyrius build` (non-strict default) patched undef-fn call-sites with a placeholder disp32 that silently looped back into `_cyrius_init` at runtime. All sandhi builds since scaffold had this latent issue — surfaced only when M2 HTTPS exercised `tls_connect`. Root-cause postmortem at `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` (closed at cyrius v5.6.29-1; cyrius shipped a `ud2` fixup so future missing-includes SIGILL instead of looping).

### Changed
- **Toolchain pin** — `cyrius.cyml [package].cyrius` bumped from `5.6.22` to `5.6.30` (via 5.6.29-1). Gains: the `_tls_init` bootstrap sequence (`dynlib_bootstrap_cpu_features/tls/stack_end` before `dynlib_open`) + the undef-fn `ud2` safety net (5.6.29-1) + stale-comment cleanup in `fdlopen.cyr` (5.6.30, doc-only). Residual HTTPS blocker is now at the libssl layer, not the cyrius layer — tracked in `docs/issues/2026-04-24-libssl-pthread-deadlock.md`.
- **cyrius.cyml `[lib].modules`**: http/sse + http/stream added in order (sse first — stream composes on top).
- **Source-comment retro** — `src/http/response.cyr` + `src/http/client.cyr` notes about "Cyrius 5.6.22 stack-slot aliasing" re-framed: the symptom was almost certainly the same undef-fn silent-stomp as the HTTPS loop. Kept the small-function shape because it reads better; dropped the "compiler quirk" framing.
- **src/main.cyr**: `sandhi_version()` → 0.7.0.

### Notes
- SSE works over plain HTTP (verified via unit tests against synthetic byte streams for parser correctness + chunked-decode roundtrip). Live HTTPS SSE waits on the libssl-pthread-deadlock blocker — same block as every other HTTPS path.
- No automatic reconnect on SSE disconnect per the spec's `retry:` field — callers handle it by re-calling `sandhi_http_stream`. Can add an opt-in reconnect wrapper when a consumer asks.
- The `_sandhi_sse_cur_*` dispatcher state lives at module scope because Cyrius has no closures and threading it through the loop via out-params gets unreadable. Parser is single-threaded by design — SSE consumers should drive from one thread.

## [0.6.0] — 2026-04-24

M5 close. TLS-policy surface — SPKI cert pinning, mTLS client certs, custom trust store, policy composition. Surface fully shipped + unit-tested; runtime enforcement stubbed pending the stdlib TLS-init fix. 291 assertions green (+41 for tls_policy).

### Added
- **tls_policy/policy** (`src/tls_policy/policy.cyr`): policy struct `{flags, pinned_spki_hex, mtls_cert, mtls_key, trust_store_path}` + constructors (`new_default` / `new_pinned` / `new_mtls` / `new_trust_store`) + `combine` (additive, right-wins on field conflict, null-safe). Flags are a bitmask (`PINNED | MTLS | CUSTOM_TRUST`) so composition just ORs them together.
- **tls_policy/fingerprint** (`src/tls_policy/fingerprint.cyr`): SPKI hash format helpers. `sandhi_fp_normalize` (strip `:`/space/tab + lowercase), `sandhi_fp_eq` (null-safe case + delimiter-insensitive compare), `sandhi_fp_byte_length` (returns 32 for SHA-256, 20 for SHA-1), `sandhi_fp_encode_bytes` (raw → hex). Accepts all the common SPKI string shapes callers will plausibly hand us.
- **tls_policy/apply** (`src/tls_policy/apply.cyr`): `sandhi_conn_open_with_policy(addr, port, use_tls, sni_host, policy)` — public surface ready, enforcement stubbed. Delegates to `sandhi_conn_open` today while reading policy fields so the call-site shape is stable. `sandhi_tls_policy_enforcement_available() == 0` signals stub state; callers requiring hard enforcement can refuse to run.

### Changed
- **tls_policy/mod.cyr**: scaffold → real dialect-index with a complete usage example and the "enforcement pending" pointer to the issues doc.
- **cyrius.cyml `[lib].modules`**: tls_policy modules moved after http/client so `apply.cyr` can reference `sandhi_conn_open`. Composition order now foundation → http/net → tls_policy → rpc → discovery → server → main.
- **src/main.cyr**: `sandhi_version()` → 0.6.0.

### Deferred with explicit path forward
- **Live enforcement** — the TODO list in `apply.cyr` enumerates exactly the OpenSSL calls needed (`SSL_CTX_load_verify_locations`, `SSL_CTX_use_certificate_file`, `SSL_CTX_use_PrivateKey_file`, `SSL_get_peer_certificate`, `X509_get_pubkey`, `i2d_PUBKEY`). When stdlib TLS-init stabilizes (issue doc `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` — closed post-release at v5.6.29-1; follow-on blocker now tracked at `docs/issues/2026-04-24-libssl-pthread-deadlock.md`), wiring these is a ~50-line follow-up with no API shape change.
- **SPKI extraction from peer certificate** — same gate. `sandhi_fp_encode_bytes` already handles the output-side formatting, so the fill-in is: resolve the two additional OpenSSL symbols, call them, hash with `sha256_hex`, compare via `sandhi_fp_eq`.

## [0.5.0] — 2026-04-24

M4 close. Service discovery — daimon-backed resolver, chain-resolver with fallthrough, mDNS interface stub, register/deregister. 250 assertions green (+35 for discovery).

### Added
- **discovery/service** (`src/discovery/service.cyr`): service struct `{name, host, port, ipv4}` + resolver struct `{lookup_fn, ctx}` + `sandhi_resolver_lookup(r, name)` dispatcher. The type vocabulary every resolver shares.
- **discovery/chain** (`src/discovery/chain.cyr`): `sandhi_discovery_chain_new` / `_add` / `_count` / `_resolve` / `_as_resolver`. Iterates resolvers in insertion order, returns first non-null hit. Supports nesting a chain as a resolver inside another chain.
- **discovery/daimon** (`src/discovery/daimon.cyr`): HTTP-backed resolver against daimon's registry. Contract documented inline (`GET /services/{name}` → `{"host","port","address"?}`). Missing daimon = miss = chain fallthrough; no crash on outage.
- **discovery/local** (`src/discovery/local.cyr`): **mDNS interface only** — resolver struct constructs cleanly and integrates with the chain, but lookup always misses today. Reason documented: stdlib `net.cyr` doesn't expose the multicast-UDP socket primitives (`IP_ADD_MEMBERSHIP`, `IP_MULTICAST_TTL`) needed for the 224.0.0.251:5353 query path. `sandhi_discovery_local_available() == 0` signals the stub state. Real impl lands when `net.cyr` gains multicast helpers or a consumer asks.
- **discovery/register** (`src/discovery/register.cyr`): `sandhi_discovery_register(base, name, host, port)` + `_deregister(base, name)`. Daimon-backed publish/withdraw; mDNS publishing deferred with the local resolver.

### Changed
- **discovery/mod.cyr**: scaffold → real dialect-index comment with typical consumer usage + `sandhi_discovery_version() → "0.5.0"`.
- **cyrius.cyml `[lib].modules`**: discovery submodules added in dependency order (service → chain → daimon → local → register → mod).
- **src/main.cyr**: `sandhi_version()` → 0.5.0.

### Deferred (documented in code + roadmap)
- **mDNS lookup**. Stub resolver shipped today; real impl blocked on multicast primitives in stdlib `net.cyr`.
- **mDNS publishing** (continuous responder loop). Not in scope until multicast + thread-lifecycle story firms up.

## [0.4.0] — 2026-04-24

M3 close. JSON-RPC dialect layer — WebDriver, Appium, MCP-over-HTTP. 215 assertions green.

### Added
- **rpc/json** (`src/rpc/json.cyr`): nested JSON builder + dotted-path extractor. `sandhi_json_obj_new` / `add_string` / `add_int` / `add_bool` / `add_null` / `add_object` / `add_raw` / `escape` / `build`; `sandhi_json_get_string` / `get_int` / `has_path` with `value.sessionId`-style dotted paths. stdlib json.cyr is flat-only, so sandhi owns this surface for RPC use.
- **rpc/dispatch** (`src/rpc/dispatch.cyr`): JSON-over-HTTP transport with dialect-aware error envelope extraction. `sandhi_rpc_call(url, http_method, body_json, dialect)` returns a unified rpc-response (http_status + body + err_kind + err_message). Dialects: `GENERIC`, `WEBDRIVER` (W3C `value.error`/`value.message`), `JSONRPC` (`error.code`/`error.message`).
- **rpc/webdriver** (`src/rpc/webdriver.cyr`): W3C WebDriver dialect. Session lifecycle (`new_session` / `delete_session`), navigation (`navigate_to` / `get_url` / `get_title`), element interaction (`find_element` / `element_click` / `element_text` / `element_attribute` / `element_send_keys`), JS execution (`execute_script`), status probe (`status`). W3C element-reference key (`element-6066-11e4-a52e-4f735466cecf`) + pre-W3C `ELEMENT` fallback in `sandhi_wd_extract_element_id`.
- **rpc/appium** (`src/rpc/appium.cyr`): Appium extensions on top of WebDriver — `new_session` with `appium:automationName` capability, `set_context` / `get_contexts` / `current_context`, app lifecycle (`install_app` / `remove_app` / `activate_app` / `terminate_app`), `mobile_exec` / `source` / `screenshot`.
- **rpc/mcp** (`src/rpc/mcp.cyr`): MCP-over-HTTP transport. JSON-RPC 2.0 envelope build with monotonic per-process request IDs. **Transport only** per ADR 0001 — tool discovery / prompt schemas / sampling semantics stay in bote + t-ron.

### Changed
- **rpc/mod.cyr**: scaffold replaced with a real dialect-index comment + `sandhi_rpc_version() → "0.4.0"`.
- **cyrius.cyml `[lib].modules`**: new ordering routes `rpc/json` → `rpc/dispatch` → each dialect → `rpc/mod`.
- **src/main.cyr**: `sandhi_version()` → 0.4.0.

### Deferred
- **SSE / streaming response** for long-lived RPC calls. Roadmap M3 listed this but chunked framing is already handled in `src/http/response.cyr`; SSE-as-iterator is a callback/async shape that no current consumer needs. Lands as M3.5 when a consumer asks.

## [0.3.0] — 2026-04-24

M2 close. Full HTTP client surface — POST/PUT/DELETE/PATCH/HEAD/GET over HTTP and HTTPS, custom headers, chunked decoding, opt-in redirect following, native DNS resolver. 173 assertions green; live HTTP round-trip to `example.com` verified end-to-end via `programs/http-probe.cyr`.

### Added
- **http/headers** (`src/http/headers.cyr`): real key-value store — `sandhi_headers_new` / `set` / `add` / `get` / `remove` / `has` / `count` / `name_at` / `value_at` / `serialize` / `parse`. Case-insensitive lookup, multi-value support (Set-Cookie etc.), wire-format CRLF serialization.
- **http/url** (`src/http/url.cyr`): URL parser for `http://` and `https://` — returns 40-byte struct with scheme, host, port, path, query. CRLF-injection hardening from the stdlib http.cyr pattern. Default ports inferred (80 / 443).
- **http/conn** (`src/http/conn.cyr`): tagged `{kind, fd, tls_ctx}` connection abstraction. `sandhi_conn_open` wraps plain TCP via net.cyr or TLS via tls.cyr; unified `_send` / `_send_all` / `_recv` / `_recv_all` / `_close`.
- **http/response** (`src/http/response.cyr`): response parser handling Content-Length, Transfer-Encoding: chunked, and connection-close framings. Response struct `{status, body_ptr, body_len, headers, err_kind}`.
- **http/client** (`src/http/client.cyr`): `sandhi_http_get` / `post` / `put` / `delete` / `patch` / `head`. Request builder with HTTP/1.1 request line, Host header, auto Content-Length for body-bearing methods, `Connection: close`. Opt-in redirect following via `sandhi_http_options_new` + `_opts` variants (RFC 7231 §6.4 method rewrite: 303 → GET, 301/302/307/308 preserve). Absolute + relative Location resolution.
- **net/resolve** (`src/net/resolve.cyr`): native UDP DNS resolver. RFC 1035 query build + response parse, `/etc/resolv.conf` nameserver discovery with 8.8.8.8 fallback, A-records only, Linux-first. Includes `sandhi_net_parse_ipv4` for numeric literals. Written because `fdlopen_getaddrinfo` is blocked at 5.6.22 (tracked in `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md`).
- **programs/dns-probe.cyr** + **programs/http-probe.cyr**: ad-hoc live-probe tools (not part of test suite; require network).

### Changed
- **programs/smoke.cyr**: include list expanded for the new http/* + net/* modules.
- **cyrius.cyml `[lib].modules`**: new order enforces the dependency chain (headers → url → conn → response → resolve → client).
- **src/main.cyr**: `sandhi_version()` bumped to 0.3.0.

### Known issues
- **HTTPS runtime via `lib/tls.cyr` is unstable.** Compilation is clean and `tls_policy` surface is intact, but live HTTPS round-trips trigger a re-entrant-execution symptom (`programs/http-probe.cyr https://...` prints "GET ..." hundreds of times before being killed). Candidate cause: `_tls_init` calls `dynlib_open` without the `dynlib_bootstrap_*` sequence that `lib/dynlib.cyr` documents as required for libc-dependent sidecars. Logged in `docs/issues/archive/2026-04-24-fdlopen-getaddrinfo-blocked.md` (P8 entry). Plain HTTP works end-to-end against hostname and IP-literal URLs.
- **Stack-slot aliasing on crowded frames.** Cyrius 5.6.22 silently zeroes a caller's local after a function call if the caller has ~15+ locals. Worked around by keeping individual sandhi functions below that threshold (see `src/http/response.cyr` comment). Logged in the same issue file.

## [0.2.0] — 2026-04-24

### Added
- **server**: lift-and-shift of `lib/http_server.cyr` into `src/server/mod.cyr`. Status codes, request parsing (`http_get_method` / `http_get_path` / `http_find_header` / `http_content_length`), path + query helpers (`http_path_only` / `http_url_decode` / `http_get_param` / `http_path_segment`), response builders (`http_send_status` / `http_send_response` / `http_send_204`), chunked / SSE (`http_send_chunked_start` / `http_send_chunk` / `http_send_chunked_end`), request reader (`http_recv_request`), and accept-loop (`http_server_run`) — all moved verbatim from the interim stdlib file. No behavior change.
- **tests**: pure-helper unit tests exercising the migrated server symbols (url decoding, path segmentation, query param extraction, request parsing) — 28 assertions green.
- **smoke**: `programs/smoke.cyr` now exercises `http_url_decode` so the linker actually pulls the migrated code in.

### Changed
- **cyrius.cyml**: `http_server` removed from `[deps.stdlib]`; sandhi is now self-sufficient for the HTTP server surface. Stdlib-side stays unchanged through the 5.6.x window and is resolved in one event at Cyrius v5.7.0 per [ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — `lib/http_server.cyr` is deleted and `lib/sandhi.cyr` is added as a clean-break fold. 5.6.YY releases carry a deprecation warning on include.

### Decisions
- **[ADR 0002](docs/adr/0002-clean-break-fold-at-cyrius-v5-7-0.md) — Clean-break fold at Cyrius v5.7.0.** Supersedes the alias-window migration plan from ADR 0001 / roadmap M1 / M6. One event at v5.7.0 instead of a two-copy window; 5.6.YY deprecation warning as the notice period.

## [0.1.0]

### Added
- Initial project scaffold
