# 2026-05-09 — `lib/tls.cyr` needs a pre-handshake timing window for client-side session resumption

**Status**: ✅ Resolved upstream — cyrius v5.10.27 (2026-05-09).
Implemented Option A from this filing: `tls_connect_alloc(sock,
host, hook_fp, hook_ctx)` + `tls_connect_complete(ctx)` split
the connect flow at the timing window required for client-side
resumption. Existing `tls_connect_with_ctx_hook` collapsed to a
3-line wrapper for back-compat; sandhi callers updated at 1.3.1
to use the new staged-connect API. Sandhi pinned 5.10.31 for
1.3.1 (5.10.27 was the actual fix; 5.10.31 is the current
cyrius head).

**Filed**: sandhi 1.3.1 entry (timing-window gap surfaced after
v5.10.21 pin bump, before any 1.3.1 implementation).
**Side**: Upstream (cyrius stdlib).
**Sandhi-side surface**: `src/tls_policy/` — 1.3.1 session-cache
implementation is blocked on this.

## What v5.10.21 shipped

22 fns in `lib/tls.cyr`. The new ones (12 fns + 2 capability probes):

- `tls_get_session(ctx)` — refcount-bumping getter.
- `tls_set_session(ctx, session)` — installs a session.
- `tls_session_free(session)` — caller-owned cleanup.
- `tls_ctx_set_session_new_cb` / `_remove_cb` / `_get_cb` /
  `_cache_mode` — cache-callback set.
- `tls_ctx_set_max_early_data` / `tls_write_early_data` /
  `tls_read_early_data` — 0-RTT primitives.
- `tls_supports_session_resumption()` /
  `tls_supports_early_data()` — capability probes.

These are correct primitives. Thank you. The CHANGELOG framing of
"sandhi 1.3.x unblocking" is right at the primitive level.

## What's missing

`tls_set_session` is documented as "install a previously-cached
session **before tls_connect to attempt resumption**." Per OpenSSL,
`SSL_set_session(ssl, sess)` must fire **before** `SSL_connect(ssl)`
to enable resumption — calling it after handshake is a no-op for
the resumption purpose.

But cyrius's `tls_connect_with_ctx_hook` does the full flow in one
call:

```cyr
fn tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx) {
    var ssl_ctx = fncall1(_fn_SSL_CTX_new, method);
    # ... defaults ...
    if (hook_fp != 0) { fncall2(hook_fp, hook_ctx, ssl_ctx); }
    var ssl = fncall1(_fn_SSL_new, ssl_ctx);   # <— SSL handle created here
    fncall2(_fn_SSL_set_fd, ssl, sock);
    fncall4(_fn_SSL_ctrl, ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, ..., host);
    var r = fncall1(_fn_SSL_connect, ssl);     # <— handshake runs here
    # ... allocate ctx struct, return ...
}
```

The hook fires on `SSL_CTX*`, before `SSL_new`. So inside the
hook there's no `SSL*` to `tls_set_session` against. And
`tls_set_session(ctx, session)` only works on the ctx
returned post-handshake — at which point the handshake already
either resumed (using whatever session libssl found internally,
which is none for a fresh SSL_CTX) or did a full handshake.

**There's no timing window between `SSL_new` and `SSL_connect`
exposed to sandhi.**

The 4 cache callbacks help capture sessions out of successful
handshakes via `_new_cb` (sandhi can store), but the **resume**
direction needs the timing window.

## Two reasonable shapes for the fix

### Option A — staged-connect API (preferred)

Split `tls_connect_with_ctx_hook` into allocate + complete:

```cyr
# Allocate ctx through SSL_new + SSL_set_fd + SNI, but DON'T run
# SSL_connect yet. Returns ctx with handshake in "ready to start"
# state. Hook fires as today (on SSL_CTX*, pre-SSL_new).
fn tls_connect_alloc(sock, host, hook_fp, hook_ctx);

# Run SSL_connect on a staged ctx. Returns 1 on success, 0 on
# failure (caller should tls_close to release).
fn tls_connect_complete(ctx);
```

Sandhi flow:

```cyr
var ctx = tls_connect_alloc(sock, host, hook_fp, hook_ctx);
if (ctx == 0) { return 0; }
var cached = sandhi_session_cache_lookup(host, port, alpn);
if (cached != 0) { tls_set_session(ctx, cached); }
if (tls_connect_complete(ctx) != 1) { tls_close(ctx); return 0; }
# resumption either took or didn't; sandhi caches a fresh session
# via tls_get_session for next time.
```

Existing `tls_connect_with_ctx_hook(sock, host, hook_fp, hook_ctx)`
becomes a 3-line wrapper:

```cyr
var ctx = tls_connect_alloc(sock, host, hook_fp, hook_ctx);
if (ctx == 0) { return 0; }
if (tls_connect_complete(ctx) != 1) { tls_close(ctx); return 0; }
return ctx;
```

Byte-identical for existing callers. Sandhi's `_sandhi_alpn_hook`
+ `_sandhi_apply_hook` continue working as today.

### Option B — post-SSL_new hook variant

Add a second hook that fires after `SSL_new` / `SSL_set_fd` /
`SSL_ctrl(SNI)` but before `SSL_connect`:

```cyr
# Handshake-time hook: `ssl_hook_fp(ssl_hook_ctx, ssl_handle)`
# fires AFTER ssl is allocated + bound + SNI set, BEFORE SSL_connect.
# Both hooks may be 0 (skip).
fn tls_connect_with_hooks(sock, host, ctx_hook_fp, ctx_hook_ctx,
                           ssl_hook_fp, ssl_hook_ctx);
```

`tls_set_session(ssl_handle, session)` would then work directly
inside `ssl_hook_fp`, since `ssl_handle` is the SSL* pre-handshake.

Existing `tls_connect_with_ctx_hook` becomes a wrapper.

---

Option A is cleaner — composes with the existing hook surface
naturally (existing hook doesn't change shape; new fns split
the connect-flow timing). Option B adds a second hook surface
which doubles the parameter explosion.

## Why this matters for sandhi

Without one of the above, sandhi 1.3.1 can:

- ✅ Capture sessions out of successful handshakes (via
  `_new_cb` with `SSL_SESS_CACHE_CLIENT` mode set in the hook).
- ❌ **NOT actually resume** — every connect runs a full
  handshake regardless of cache state, because there's no
  way to inject the cached session pre-`SSL_connect`.

That's "half a feature" — the cache fills but never pays off.
1.3.2 (0-RTT) is also affected since 0-RTT requires a session
installed pre-handshake.

## Acceptance from sandhi side

Either option lands → sandhi 1.3.1 implements client-side
session resumption, ships, and 1.3.2 0-RTT follows naturally.

No code change required from sandhi's existing tls_policy /
conn / hook usage — Options A and B both preserve the existing
`tls_connect_with_ctx_hook` shape.

## Related

- `2026-04-24-stdlib-tls-alpn-hook.md` (archived) — the original
  hook ask, resolved at cyrius v5.6.40. Same shape: sandhi
  needed a TLS surface stdlib didn't expose, cyrius added it.
- Cyrius v5.10.21 CHANGELOG explicitly framed itself as
  "sandhi 1.3.x unblocking — closes v5.10.13 partial-fix gap"
  — primitives are there, just the call-sequence surface
  isn't yet.
