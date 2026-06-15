# 2026-06-15 — cyrius `lib/net.cyr` lacks IPv4 multicast primitives (gates sandhi mDNS multicast)

**Status**: ⚠️ **Open — partially landed; the primitives are NOT sufficient.**
cyrius 6.2.7 shipped the join/option primitives specified below
(`net_join_multicast` / `net_drop_multicast` / `net_set_multicast_ttl` / `_loop`
/ `_if` / `sock_reuseport` + per-target `IP_MULTICAST_*` / `SO_REUSEPORT` /
`IPPROTO_IP` constants + the 8-byte `ip_mreq`; the source cites this filing). A
sandhi 1.5.4 QM-resolver adoption was written **and reverted after an adversarial
review found a blocker** (see "The missing piece" below). sandhi additionally
needs cyrius to add **unconnected `sock_sendto` / `sock_recvfrom`** to
`lib/net.cyr` (or to use a two-socket send/recv split), plus a loopback
live-multicast test, before a QM resolver can actually receive answers.

## The missing piece (found in the 1.5.4 review — corrects this filing)

`lib/net.cyr`'s `sock_send` / `sock_recv` bottom out at `sys_write` / `sys_read`,
which **require a connected socket**. So sending to the mDNS group forces a
`sock_connect(fd, group, 5353)` — and on Linux, **`connect()` on a UDP socket
installs a source-address filter**: the socket then only delivers datagrams whose
*source* is the connected peer (224.0.0.251:5353). An mDNS responder sends its
answer **from its own unicast IP** (e.g. 192.168.1.42:5353), never from the group
address, so a connected socket **drops every real answer** before `recv` sees it.
The `join` / `SO_REUSEPORT` / TTL primitives are real but inert if the receiving
socket is connected.

**Two ways to fix (both must be validated with a live/loopback test):**
1. **(preferred) cyrius adds `sock_sendto` + `sock_recvfrom` to `lib/net.cyr`**
   (`sys_sendto`=44 is already used in `lib/sakshi.cyr`; `sys_recvfrom` is in
   `syscalls_linux_common.cyr:412` — just unwrapped). Then sandhi sends the query
   unconnected and receives unfiltered. Cleanest; agnos returns -1.
2. **Two-socket split (sandhi-side, no new cyrius verb):** send on a *connected*
   socket A (`sock_connect` + `sock_send`), receive on a *separate unconnected*
   socket B bound to 5353 + `SO_REUSEPORT` + group-joined (`sock_recv` = `sys_read`
   works on an unconnected bound socket). More complex.

## Pre-existing exposure in the QU resolver (separate, older — needs a live check)

The shipped unicast (QU) resolver `_sandhi_local_query_a` (`src/discovery/local.cyr`,
since 0.9.3) has the **same** shape — it `sock_connect`s to 224.0.0.251:5353 then
`sock_recv`s, expecting the QU unicast answer on that fd. The same connect()
source-filter would drop a unicast answer arriving from the responder's IP. Its
"works against most responders" claim is **unverified** (no live test — unit
tests use synthetic packets; the smoke only checks a no-responder miss). Needs a
live-network check; if confirmed, the QU path needs the same unconnected-recv fix.
**Filed**: sandhi side, against the cyrius repo.
**Side**: Upstream (cyrius stdlib `lib/net.cyr` + per-target `SockOpt` enum).
**Sandhi-side surface**: None. Per ADR 0001 / CLAUDE.md ("compose, don't
reimplement"; "No FFI"), sandhi reaches the network only through the stdlib
`net.cyr` / `sock_*` contract and does not define socket-option constants or
`setsockopt` structs itself. This filing makes the cross-repo coupling visible;
the work is purely cyrius-side.

## What sandhi does today (and why it works without these)

`src/discovery/local.cyr` resolves `<name>.local` by sending an mDNS A-record
query to the IPv4 mDNS group **224.0.0.251:5353** over UDP with **QCLASS =
IN | QU-bit (0x8001)** (RFC 6762 §5.4 — "request unicast response"). Because
the QU bit asks responders to **unicast** the answer back to our source port,
the reply arrives on the same fd we sent from — so sandhi needs **no group
membership, no multicast setsockopt** at all. It rides the existing portable
`udp_socket()` / `sock_connect` / `sock_send` / `sock_recv` / `sock_close`
surface (which already works on Linux/macOS/AGNOS). Bounded by `SO_RCVTIMEO`.

This is correct and sufficient for the common case (most responders honor QU).
The gap is the cases QU can't cover.

## What needs multicast primitives (the gap)

Two `discovery/local.cyr` enhancements are blocked on cyrius shipping IPv4
multicast primitives:

1. **QM (standard multicast-response) mode** — some responders ignore the QU
   bit and always multicast their answer to 224.0.0.251:5353. To receive that,
   sandhi must **join the group** (`IP_ADD_MEMBERSHIP`) on a socket bound to
   5353 with `SO_REUSEPORT` (so it can coexist with the host's mDNS daemon),
   and listen.
2. **RFC 6763 service-by-type browsing** (`_http._tcp.local` PTR enumeration,
   continuous discovery) — inherently a multicast-listen workflow; it cannot be
   done with one-shot QU queries.

Neither is wired today; both are "wait-for-second-consumer-ask" features in
sandhi's roadmap. This filing is the upstream prerequisite so the timing is
tracked, not the trigger to build them.

## Contract — what cyrius `lib/net.cyr` needs to expose

The generic `sys_setsockopt(fd, level, optname, optval, optlen)` wrapper
(`syscalls_linux_common.cyr`, `SYS_SETSOCKOPT=54`) already exists — the **raw
plumbing is there**. What's missing is the IP-multicast-level **constants**, the
**`ip_mreq` struct shape**, and ideally a **join helper**. Concretely:

### Socket-option constants (per-target `SockOpt` / new `IpOpt` enum in `net.cyr`)

Today `net.cyr`'s `SockOpt` enum carries only `SOL_SOCKET` / `SO_REUSEADDR` /
`SO_RCVTIMEO` / `SO_ERROR`. The multicast set (Linux x86_64/arm64 values shown;
macOS/BSD differ and belong in the macOS peer — these are protocol constants,
not syscall numbers, so they're stable across Linux arches):

| Name | Level | Linux value | Role |
|---|---|---|---|
| `IPPROTO_IP` | (level) | 0 | setsockopt level for the IP options below |
| `IP_MULTICAST_IF` | IPPROTO_IP | 32 | select outgoing interface |
| `IP_MULTICAST_TTL` | IPPROTO_IP | 33 | hop limit (mDNS: 255 send / 1 link-local) |
| `IP_MULTICAST_LOOP` | IPPROTO_IP | 34 | local loopback of sent multicast |
| `IP_ADD_MEMBERSHIP` | IPPROTO_IP | 35 | join a group |
| `IP_DROP_MEMBERSHIP` | IPPROTO_IP | 36 | leave a group |
| `SO_REUSEPORT` | SOL_SOCKET | 15 | coexist with the host mDNS daemon on 5353 |

### `ip_mreq` struct (8 bytes)

```
struct ip_mreq {
    imr_multiaddr: in_addr,   # 4 bytes, network-byte-order group (224.0.0.251)
    imr_interface: in_addr,   # 4 bytes, network-byte-order local iface (INADDR_ANY = 0)
}                              # 8 bytes total
```

### Preferred: a typed join helper (composes the above)

Smaller, more portable consumer surface than hand-rolling the struct:

```
# Join group `group` (network-byte-order uint32) on interface `iface`
# (0 = INADDR_ANY). Returns 0 / -errno. macOS/AGNOS peers provide their
# own impl (or a clean "unsupported" return).
fn net_join_multicast(fd, group, iface): i64
fn net_set_multicast_ttl(fd, ttl): i64
fn net_set_multicast_loop(fd, on): i64
```

sandhi's preference is the **helper** (option-A style, mirroring how the
1.4.2 ALPN/SPKI work retired raw `tls_dlsym` onto typed `tls_get_*` wrappers):
it keeps sandhi composing a portable verb instead of reaching for raw
constants + `setsockopt` struct layout, and lets the macOS/AGNOS peers map the
operation to their own ABI. If cyrius prefers to ship only the constants +
`ip_mreq`, sandhi can compose `sys_setsockopt` directly — either unblocks it.

## What sandhi does NOT need

- A full IGMP / source-specific multicast (`ip_mreq_source`) surface — plain
  `ip_mreq` group join covers mDNS.
- IPv6 multicast (`IPV6_JOIN_GROUP`) — sandhi's discovery is IPv4 mDNS today.
- Any change to the QU-bit unicast path — it stays as the default/fallback.

## Acceptance (sandhi side, when it lands)

- `discovery/local.cyr` gains a QM-capable listen path behind the existing
  `sandhi_discovery_local_*` surface (QU stays the default); a unit test joins
  224.0.0.251:5353 with `SO_REUSEPORT` and parses a multicast A response.
- No regression to the QU path or the four `.tcyr` suites.
- macOS / AGNOS either provide the primitive or return a clean "unsupported"
  so the bundle still compiles + the resolver degrades to QU.

## Why filed now

Verified **still-absent on cyrius 6.2.6** (2026-06-15): a whole-stdlib grep
found none of `IP_ADD_MEMBERSHIP` / `IP_MULTICAST_TTL` / `_LOOP` / `_IF` /
`SO_REUSEPORT`, no `ip_mreq` struct, and no multicast-join helper — only the
generic `sys_setsockopt` plumbing. The roadmap previously tracked this only as
an inline "Cross-repo dependencies" bullet + a `discovery/local.cyr` comment;
this file is the paste-ready spec so the cyrius side has zero ambiguity, closing
the last untracked upstream item in sandhi's Batch A.

## Related

- sandhi `docs/development/roadmap.md` "Cross-repo dependencies" → Batch A3.
- sandhi `src/discovery/local.cyr` — the QU-bit resolver these would extend
  (header comment §"Wire shape" documents why QU needs no membership today).
- ADR 0001 — sandhi composes stdlib primitives; multicast plumbing is stdlib's.

## Log

- **2026-06-15** — filed at sandhi 1.5.3 close on cyrius 6.2.6, after the
  upstream-claims verification pass confirmed the primitives are still absent
  and flagged this as the one Batch-A item lacking a proper cyrius-side
  coordination doc.
- **2026-06-15 (1.5.4)** — cyrius 6.2.7 shipped the join/option primitives from
  this filing. sandhi 1.5.4 attempted a QM-resolver adoption, but an adversarial
  code review caught a **blocker**: the resolver `sock_connect`ed the UDP socket
  to the group and `sock_recv`ed, so Linux's connect() source-filter dropped
  every answer (responders send from their own IP, not the group). The
  primitives are **necessary but not sufficient** — a working QM resolver also
  needs unconnected `sock_sendto` / `sock_recvfrom` (or a two-socket split) +
  a loopback live test. The 1.5.4 adoption was **reverted**; this filing was
  un-archived and corrected. Status downgraded RESOLVED → partially-landed. The
  same connect()-filter concern was noted in the pre-existing QU resolver.
