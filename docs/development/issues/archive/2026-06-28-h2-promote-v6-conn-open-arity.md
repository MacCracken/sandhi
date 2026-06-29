# 2026-06-28 — h2-promote IPv6 path calls `_sandhi_conn_open_v6_fully_timed_a` with 8 args (needs 9)

**Status:** RESOLVED at sandhi 1.7.0 (2026-06-29) — `dispatch.cyr`'s IPv6 branch
now passes `0` as the 9th `ctx` arg (the ctx==0 fallback; h2-promote threads no
request context). `dist/sandhi.cyr` regenerated warning-clean. Archived.
**Severity:** medium — a build warning today (`'_sandhi_conn_open_v6_fully_timed_a'
expects 9 arguments, got 8`); a latent wrong-arg on the IPv6 + h2-promote client
path at runtime (the missing trailing `ctx` is read as garbage).
**Reported via:** `yeo-cy-test` consumer (SecureYeoman → Cyrius probe), building
against folded sandhi 1.6.13 in cyrius 6.3.0. The probe is server-side, so it
doesn't execute this path — it just surfaces the warning at compile time.

## Symptom

Any consumer that builds with sandhi emits, from the folded `dist/sandhi.cyr`:

```
warning: '_sandhi_conn_open_v6_fully_timed_a' expects 9 arguments, got 8
```

## Root cause

`_sandhi_conn_open_v6_fully_timed_a` gained a trailing `ctx` parameter in the
**1.6.9** per-call request-context change (it is now 9-arg:
`(a, addr16, port, use_tls, sni_host, connect_ms, read_ms, write_ms, ctx)` —
`src/http/conn.cyr:609`). The IPv4 call sites and `src/http/client.cyr`'s IPv6
call (`client.cyr:459`, passes `ctx`) were updated, but the **h2-promote IPv6
branch was missed**:

```
# src/http/h2/dispatch.cyr:144-146
if (addr6 != 0) {
    conn = _sandhi_conn_open_v6_fully_timed_a(a, addr6, port, 1, host,
    connect_ms, read_ms, write_ms);          # <-- 8 args; missing trailing ctx
}
```

The sibling IPv4 branch two lines down calls the public
`sandhi_conn_open_fully_timed_a` (which defaults `ctx` internally), so only the
IPv6 branch warns. At runtime, an IPv6 h2 promotion reads whatever is in the 9th
arg slot as the per-request `ctx` pointer.

## Scope

Client-side, IPv6 + h2-promote only (requires a pool + h2 advertised + an
AAAA-resolved host). The common IPv4 path and all server paths are unaffected.

## Fix

Pass the `ctx` the dispatch path is already holding (or `0` if none) as the 9th
arg on the `dispatch.cyr` IPv6 branch — mirroring `client.cyr:459`:

```
conn = _sandhi_conn_open_v6_fully_timed_a(a, addr6, port, 1, host,
connect_ms, read_ms, write_ms, ctx);
```

Then re-fold `dist/sandhi.cyr` so the folded snapshot consumers build against is
warning-clean.
