# 2026-08-23 — bote needs a client that connects to a **pre-resolved address** (SSRF guard without a DNS-rebinding window)

**Status**: **RESOLVED — shipped in sandhi 1.9.14** (2026-08-23). Archived same day.

sandhi took **shape B**, the resolve hook: `sandhi_client_set_resolver(lookup_fn, ctx)`
+ `_clear_resolver` + `_resolver_installed`, with
`lookup_fn(ctx, host, family) -> addr`, `0` to refuse.

Shape B was chosen over shape A (`sandhi_http_get_at`) specifically because of
the redirect caveat this filing raised. A pre-resolved entry point would have had
to disable redirect-following to stay honest — the vetted address is only valid
for the first hop's host — whereas the hook fires per hop **by construction**,
since `_sandhi_http_follow_a` re-enters the dispatch path and each hop resolves
again. It also has no bypass: all four client paths (buffered, auto/h2,
streaming, download) funnel through the same two private resolve functions.

Two points beyond what was asked for:

- **IP literals go through the hook too.** It sits ahead of the
  `sandhi_net_parse_ipv4` fast path, so `http://169.254.169.254/` cannot slip
  past a policy that only sees names — bote's classifier can now cover literal
  and hostname URLs through one code path instead of two.
- **`Host:` / SNI were never at risk.** Both still derive from the URL; the hook
  replaces only the name→address step. The warning in this doc needed no
  special handling.

Gated in CI by `programs/_ssrf_resolver_gate.cyr`, which forks a real server that
302s across hosts and checks both that the hook vets every hop and that refusing
hop 2 stops the request.

⚠ **bote does not get this by bumping a pin.** Post-fold there is no sandhi pin;
consumers include stdlib's vendored `lib/sandhi.cyr`, so this reaches bote only
when a cyrius release re-vendors it from `dist/sandhi.cyr`.
**Update 2026-09-23:** that happened at cyrius **6.5.37** (the sandhi 1.9.15 fold), so the
hook is available to any consumer pinned at or above 6.5.37.

**Original filing follows, unedited.**

---

**Status (as filed)**: OPEN — confirmed not fixed in sandhi 1.9.13 (verified 2026-08-23 against `dist/sandhi.cyr` at tag `1.9.13`).
**Reporter**: bote 3.3.7 blocker re-derivation (bote audited its "Blocked on cyrius / external" table and found six of seven premises expired; this is one of only two that survived).
**Side**: bote is a **consumer**.
**Severity**: this is the last thing standing between bote and a correct SSRF guard for hostname URLs. bote ships `web_fetch` as an MCP tool, so the exposure is real, not theoretical.
**Depends on**: nothing — this is purely additive sandhi API.

---

## The ask, in one line

A public client entry point that takes an **already-resolved address** and connects to it, rather than resolving the hostname itself.

Equivalently (and possibly easier for sandhi): a **resolve hook** on the client path, so a consumer can interpose its own policy between "name" and "connect".

---

## Why bote cannot solve this on its own side

bote's `src/host.cyr` carries an IPv4/IPv6 SSRF classifier (`_ssrf_classify_ipv4` and friends) that rejects loopback, link-local, RFC 1918, CGNAT, multicast and the IPv6 equivalents. It is well tested — 113 assertions in `tests/bote_host.tcyr`.

**It can only guard URLs whose host is an IP literal.** For a hostname, bote has nowhere to stand:

- `sandhi_http_get(url, user_headers)` (`dist/sandhi.cyr:5448`) takes a URL and nothing else.
- It routes through `sandhi_http_get_a` → `_sandhi_http_dispatch_a`, which resolves internally.
- The resolution is `_sandhi_client_resolve_a` (`dist/sandhi.cyr:4333`) / `_sandhi_client_resolve` (`:4339`) — **private**, 15 call sites, no parameter and no hook.

So the only shape available to a consumer today is **resolve-then-fetch**:

```
addr = sandhi_resolve_ipv4(host)   # bote resolves, and classifies addr
...                                 # bote's SSRF check runs here
sandhi_http_get(url, hdrs)          # sandhi resolves AGAIN, independently
```

⛔ **That is not a fix, it is a DNS-rebinding vulnerability with extra steps.** Two independent resolutions with an attacker-controlled interval between them: the name resolves to a public address for bote's check, then to `169.254.169.254` for sandhi's connect. The guard would read as protective while providing nothing. bote will not ship that shape.

⚠ **This also means the ask bote originally filed was the wrong one.** The old entry (cyrius `archived/2026-05-10-bote-net-stdlib-recv-timeout-and-getaddrinfo.md`, Part B) asked for a `getaddrinfo_hosts(name, family)` stub in `lib/net.cyr`. Even if that shipped tomorrow it would not close this, because the gap is not "bote cannot resolve a name" — bote **can** already, via `sandhi_resolve_ipv4` (`dist/sandhi.cyr:4066`) / `sandhi_resolve_ipv6` (`:4022`). The gap is that it cannot make sandhi's client **use the address it just vetted**. Filing the old shape again would file the wrong thing.

---

## What 1.9.13 does and does not have (checked, not assumed)

| Surface | Where | Does it close this? |
|---|---|---|
| `sandhi_http_get` / `_post` / `_put` / `_patch` (+ `_a` variants) | `dist/sandhi.cyr:5448` ff. | ❌ URL only; no address parameter |
| `_sandhi_client_resolve` / `_a` | `:4333`, `:4339` | ❌ private, no hook, 15 internal call sites |
| `sandhi_resolve_ipv4` / `sandhi_resolve_ipv6` | `:4066` / `:4022` | ⚠️ lets bote resolve — but not tell the client what it found |
| `sandhi_resolver_new` / `_fn` / `_ctx` / `_lookup` | `:12023`-`:12039` | ❌ **Not a DNS hook.** Its contract is `lookup_fn(ctx, name) → sandhi_service`, i.e. the **service-discovery** resolver (daimon / mDNS / local backends). It cannot be used to interpose on the HTTP client's name resolution. This is the most likely thing to be mistaken for a fix — it is not one. |
| `sandhi_server_peer_ip` / `_sockaddr` / `_conn_peer_ip` | `:14972`-`:15016` | ❌ server-side accessors, wrong direction |

---

## Shapes that would work (sandhi's choice — either closes it)

**A. Pre-resolved connect** — most direct:

```
# addr is a packed network-byte-order u32 (same shape sandhi_resolve_ipv4 returns);
# `url` still carries scheme/path/query, and Host: is still derived from it so
# TLS SNI and vhosts keep working.
fn sandhi_http_get_at(url, user_headers, addr): i64
```

**B. Resolve hook on the client path** — more general, and reuses a pattern sandhi already has:

```
# lookup_fn(ctx, host) -> packed addr, or 0 to refuse the connection.
# Refusing is the important half: it is what lets a consumer's policy VETO.
fn sandhi_client_set_resolver(lookup_fn, ctx): i64
```

Either shape gives bote **one** resolution, vetted before connect, with no window.

⚠ Whichever is chosen, please keep `Host:` / SNI derived from the **URL**, not reverse-derived from the address — otherwise TLS breaks for every virtual host.

---

## Minimal migration shape (bote side, once this lands)

```
var host = _url_host(url);
var addr = sandhi_resolve_ipv4(host);
if (addr == 0) { return _err("resolve failed"); }
if (host_ssrf_check_addr(reg, addr) != 0) { return _err("blocked by SSRF policy"); }
var resp = sandhi_http_get_at(url, hdrs, addr);   # shape A
```

bote's classifier already exists and is tested; only the last line is missing.

---

## Proposed sandhi roadmap entry

> **Pre-resolved client connect (`sandhi_http_*_at`) or a client resolve hook.**
> Lets a consumer vet a resolved address against its own policy and then connect
> to *that address*, closing the DNS-rebinding window that resolve-then-fetch
> leaves open. Blocks bote's hostname SSRF guard (`web_fetch` is a shipped MCP
> tool). Additive; no existing signature changes.

---

## Known caveats

- **First-A-record only.** `_sandhi_resolve_parse_response_a` (`dist/sandhi.cyr:3870`) returns on the first `_SANDHI_RR_A` hit. A multi-homed name where only some addresses are internal would be partly unguarded. Not a blocker for this ask — worth stating so it is not discovered later and mistaken for a regression.
- **IPv6.** bote's classifier handles both families; shape A should have an IPv6 sibling (or take a family tag) or the guard is v4-only.
- **Redirects.** If the client follows redirects internally, each hop resolves again and re-opens the window. Either the hook must fire per hop, or `_at` must disable redirect-following and hand control back. ⚠ This is easy to miss and would silently defeat the whole fix.

---

## Log

- **2026-08-23** — Filed. bote re-derived its blocker table at 3.3.6/3.3.7 and found this had been mis-filed upstream since 2026-05-10 as a `getaddrinfo` request in cyrius, which was the wrong repo *and* the wrong shape. Verified against `dist/sandhi.cyr` at tag `1.9.13`: no pre-resolved entry point, no client resolve hook, `sandhi_resolver_*` is service discovery. bote's side (the address classifier) is already built and tested.

- **2026-08-23 (sandhi 1.9.14)** — **Resolved.** Shape B (resolve hook) shipped.
  The `getaddrinfo_hosts` request this had been mis-filed as in cyrius since
  2026-05-10 can be closed there as the wrong shape *and* the wrong repo, exactly
  as this filing argued. Migration on bote's side is the hook install plus its
  existing classifier — the `sandhi_http_get_at` line sketched above is not
  needed, since the hook makes the ordinary `sandhi_http_get` safe.
