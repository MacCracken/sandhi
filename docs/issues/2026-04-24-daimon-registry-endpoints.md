# 2026-04-24 — Daimon service-registry endpoints (cross-repo coordination)

**Status**: Awaiting daimon roadmap entry
**Reporter**: sandhi M4 close
**Affects**: sandhi v0.5.0+ live testing; sandhi fold-into-stdlib at Cyrius v5.7.0 (ADR 0002)
**Target**: land during the in-progress base-OS modernization pass toward latest Cyrius
**Blast radius**: downstream consumers pinning sandhi for service discovery (hoosh, ifran, mela, sit-remote, ark-remote, vidya)

## What's assumed vs. actual

sandhi's M4 (v0.5.0) **assumes** daimon will expose a service-registry HTTP API that sandhi's `discovery/daimon.cyr` resolver calls against. The contract is fully defined on sandhi's side; daimon-side implementation has not been formally committed on daimon's roadmap as of the date above.

This doc makes the assumption explicit and provides a paste-ready spec so the daimon modernization pass can schedule it alongside other latest-Cyrius rework.

**Acceptance on sandhi's side is already met** — the resolver is written, unit-tested against synthetic response bodies (10 assertions in `tests/sandhi.tcyr` under `discovery/daimon/*`), and integrates with the chain resolver. Live round-trip testing waits on daimon's implementation landing.

## Contract (daimon-side must implement)

Base URL: whatever daimon's local HTTP listener serves on (conventionally `http://127.0.0.1:9000`, but sandhi doesn't assume this — consumers pass the base URL at resolver construction).

### `GET {base}/services/{name}`

Resolve a service by logical name.

**Responses:**
- `200 OK` with JSON body when the service is registered:
  ```json
  {
    "host": "10.0.0.42",
    "port": 9100,
    "address": "10.0.0.42"
  }
  ```
  - `host` (required, string): hostname or dotted-quad. Used as the `Host:` header when sandhi's HTTP client connects.
  - `port` (required, integer 1..65535): listening port.
  - `address` (optional, string, dotted-quad IPv4): pre-resolved IPv4 when daimon already knows it. sandhi's resolver uses this to skip a DNS round-trip.
- `404 Not Found`: the name is not registered. Body ignored.
- Any other status or transport failure: treated as a miss; the sandhi chain resolver falls through to the next backend (e.g. mDNS, static config). **Daimon should NOT 500 for routine "service is down" cases** — 404 keeps the miss path clean.

### `POST {base}/services/{name}`

Register a service. Request body:
```json
{"host": "10.0.0.42", "port": 9100}
```

- `host` (required, string).
- `port` (required, integer 1..65535).

**Responses:**
- `2xx`: registered. Response body ignored by sandhi today (may be added later).
- Any non-2xx: sandhi's `sandhi_discovery_register` returns `SANDHI_ERR_REMOTE` to the caller.

### `DELETE {base}/services/{name}`

Withdraw a previously-registered service.

**Responses:**
- `2xx`: deregistered (or idempotent if already absent).
- Any non-2xx: `SANDHI_ERR_REMOTE` to the caller.

## sandhi-side reference

- Resolver: [`src/discovery/daimon.cyr`](../../src/discovery/daimon.cyr) — the URL builder and the JSON parser that reads daimon's responses are the source of truth for the wire shape.
- Register/deregister: [`src/discovery/register.cyr`](../../src/discovery/register.cyr).
- Chain integration: [`src/discovery/chain.cyr`](../../src/discovery/chain.cyr) — daimon is designed as one backend among many; outages fall through.

## Why now

Two reasons to schedule daimon's side during the base-OS modernization pass:

1. **sandhi's v1.0 fold target (ADR 0002) is Cyrius v5.7.0.** At fold, sandhi's public surface freezes and `lib/sandhi.cyr` ships as part of stdlib. The discovery/daimon surface is part of that frozen surface. If daimon's actual endpoints diverge from the contract above after fold, it's a stdlib-release event to fix. Landing daimon's endpoints pre-fold gives us a chance to update the contract on both sides while the sandhi API is still mutable.

2. **Modernization alignment.** The base-OS rework toward latest Cyrius is the natural moment to add new HTTP surface — the daimon HTTP listener is presumably getting touched anyway for the dep / toolchain bumps.

## Proposed roadmap entry for daimon

> **Service registry endpoints for sandhi discovery.** Implement `GET/POST/DELETE /services/{name}` per the contract at `sandhi/docs/issues/2026-04-24-daimon-registry-endpoints.md`. Acceptance: sandhi's discovery chain resolver round-trips end-to-end against a local daimon (`sandhi_discovery_register("http://127.0.0.1:9000", "test-svc", "127.0.0.1", 8080)` followed by `sandhi_discovery_chain_resolve(chain, "test-svc")` returns the same host/port). Target: concurrent with sandhi v1.0 fold.

## Log

- **2026-04-24** — Filed during sandhi M4 close. Trigger: user noted the "daimon will implement" claim in sandhi's v0.5.0 state was an assumption rather than a committed cross-repo action. Base-OS modernization pass is the target scheduling window.
