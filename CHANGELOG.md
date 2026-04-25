# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
