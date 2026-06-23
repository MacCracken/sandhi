# 2026-05-10 — `lib/tls.cyr` needs `SSL_get_early_data_status` + `SSL_SESSION_get_max_early_data` for safe client-side 0-RTT

**Status**: Filed (open). Cyrius v5.10.31 ships the
write/read early-data primitives but not the
acceptance-status surface required to do 0-RTT safely on
the client side.

**Filed**: sandhi 1.3.2 entry (early-data status gap
surfaced after the v5.10.31 pin verification, before any
1.3.2 implementation).
**Side**: Upstream (cyrius stdlib).
**Sandhi-side surface**: `src/tls_policy/session_cache.cyr`
+ `src/http/conn.cyr` + new `sandhi_http_options_allow_0rtt`
flag — 1.3.2 work blocked on this filing.

## What v5.10.21 + v5.10.27 + v5.10.31 shipped

- v5.10.21: session resumption + early-data primitives:
  `tls_get_session` / `tls_set_session` / `tls_session_free`,
  the 4 session-cache callbacks, `tls_ctx_set_max_early_data`,
  `tls_write_early_data`, `tls_read_early_data`,
  `tls_supports_early_data` capability probe.
- v5.10.27: staged-connect API
  (`tls_connect_alloc` + `tls_connect_complete`) — closed
  the timing-window gap for client-side resumption. Sandhi
  1.3.1 landed using this.
- v5.10.31: typed-simd ABI work (unrelated to TLS).

## What's missing

OpenSSL's documented client-side 0-RTT contract requires
two more accessors that cyrius v5.10.31 doesn't expose:

### 1. `SSL_get_early_data_status(ssl)` — post-handshake acceptance check

After the handshake completes, the client MUST check
whether the server accepted or rejected the 0-RTT data:

```c
status = SSL_get_early_data_status(ssl);
// SSL_EARLY_DATA_NOT_SENT     (0)
// SSL_EARLY_DATA_REJECTED     (1) → caller must resend over normal stream
// SSL_EARLY_DATA_ACCEPTED     (2) → request landed, response will follow
```

Without this, sandhi has no way to know whether
`tls_write_early_data` actually delivered. Failure mode:
client thinks request sent, server rejected (replay
mitigation, bad ticket, etc.), recv stalls / returns
unexpected bytes. Worse UX than the no-0-RTT path.

### 2. `SSL_SESSION_get_max_early_data(session)` — pre-attempt eligibility

Before attempting 0-RTT, the client should check whether
the cached session even advertises early-data support:

```c
max = SSL_SESSION_get_max_early_data(sess);
if (max > 0) { /* attempt 0-RTT up to `max` bytes */ }
```

Without this, sandhi attempts 0-RTT on every cached
session — wasting cycles on sessions where the server
explicitly disabled it. Also there's no way to bound the
write size against the server's advertised capacity (a
write larger than `max` will be rejected wholesale).

## Proposed cyrius surface

Two thin wrappers, mirroring the v5.10.21/.27 typed-wrapper
pattern:

```cyr
# Returns one of TLS_EARLY_DATA_NOT_SENT / _REJECTED /
# _ACCEPTED. Constants live in TlsConst alongside the
# existing SSL_READ_EARLY_DATA_* enum.
fn tls_get_early_data_status(ctx): i64;

# Returns max early-data bytes the cached session permits.
# 0 means session doesn't advertise 0-RTT support.
fn tls_session_get_max_early_data(session): i64;
```

Plus an enum (in TlsConst):

```cyr
enum TlsConst {
    # ...existing entries...
    TLS_EARLY_DATA_NOT_SENT = 0;
    TLS_EARLY_DATA_REJECTED = 1;
    TLS_EARLY_DATA_ACCEPTED = 2;
}
```

Wraps libssl's `SSL_get_early_data_status(ssl)` and
`SSL_SESSION_get_max_early_data(sess)` respectively. Both
return-only (no state mutation). Same defensive shape as
existing wrappers (null-check inputs, return safe defaults
when libssl symbol unresolved).

## Why this matters for sandhi

Sandhi 1.3.2 (TLS 1.3 0-RTT, opt-in via
`sandhi_http_options_allow_0rtt`) needs both:

- **Pre-attempt gate** (`tls_session_get_max_early_data`):
  sandhi only attempts 0-RTT when the cached session
  advertises support AND the request fits within the
  server's max. Avoids wasting bandwidth on sessions
  that won't accept it.
- **Post-handshake retry** (`tls_get_early_data_status`):
  on REJECTED, sandhi must resend the request over
  normal `tls_write` to complete the round-trip. Without
  this, the request is silently lost.

Without either, sandhi 1.3.2 either ships unsafe (silent
failures) or doesn't ship at all. We picked "doesn't ship"
per the user-direction memory pin
`feedback_no_silent_scope_outs`.

## Acceptance from sandhi side

Both wrappers + the enum land → sandhi 1.3.2 implements
client-side 0-RTT with proper rejection handling:

```cyr
# Inside the 0-RTT-eligible path after tls_set_session:
var max_early = tls_session_get_max_early_data(cached_sess);
if (max_early >= req_len) {
    tls_write_early_data(ctx, req_bytes, req_len);
}
tls_connect_complete(ctx);

# Post-handshake — if rejected, fall back.
if (tls_get_early_data_status(ctx) == TLS_EARLY_DATA_REJECTED) {
    tls_write(ctx, req_bytes, req_len);  # resend over normal stream
}
# else: 0-RTT accepted, response is on the way via tls_read
```

No further sandhi-side ask after this lands.

## Related

- [`archive/2026-05-09-stdlib-tls-staged-connect.md`](2026-05-09-stdlib-tls-staged-connect.md)
  — yesterday's staged-connect filing. Same shape: cyrius
  shipped primitives but not the full safety surface;
  resolved at v5.10.27.
- Cyrius v5.10.21 CHANGELOG framed itself as
  "sandhi 1.3.x unblocking" — primitives at the
  write/read level are there. v5.10.27 added the
  connect-flow timing window. This filing closes the
  client-side correctness gap.
