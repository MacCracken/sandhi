# 2026-04-24 — Daimon service-registry endpoints (cross-repo coordination)

**Status**: **OPEN — confirmed not implemented** (re-checked 2026-09-23 against
`~/Repos/daimon` @ 2.4.2; first confirmed 2026-08-23 @ 2.0.2). This is no longer an
assumption: daimon serves a `/v1/*` API (`/v1/agents`, `/v1/edge/*`, `/v1/mcp/*`,
`/v1/rag/*`, `/v1/scheduler/*`, `/v1/health`, `/v1/metrics`) and there is **no
`/services/` route anywhere in its source**. daimon *is* a sandhi consumer (25 verbs,
`"sandhi"` in `[deps] stdlib`) — on the MCP-client side, not this producer side.

⚠ **Namespace mismatch, not just an absence.** sandhi's `src/discovery/daimon.cyr`
resolver calls `GET {base}/services/{name}` and registers with
`POST {base}/services/{name}` — against real daimon both 404. Whoever lands this must
decide which side moves: daimon adds `/services/{name}`, or sandhi's resolver is
re-pointed at a `/v1/`-namespaced route. sandhi's side is a small, contained change
(one module, one URL builder) if the API lands under `/v1/`.
**Reporter**: sandhi M4 close
**Affects**: live round-trip testing of sandhi's daimon discovery backend (unit-tested
against synthetic bodies only). The v5.7.0 fold this originally raced has shipped.
**Target**: daimon-scheduled — no sandhi-side date
**Blast radius**: any consumer that puts `sandhi_discovery_daimon_resolver` in its resolver chain
(via stdlib's `lib/sandhi.cyr`); today that backend can only ever miss and fall through

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

- Resolver: [`src/discovery/daimon.cyr`](../../../src/discovery/daimon.cyr) — the URL builder and the JSON parser that reads daimon's responses are the source of truth for the wire shape.
- Register/deregister: [`src/discovery/register.cyr`](../../../src/discovery/register.cyr).
- Chain integration: [`src/discovery/chain.cyr`](../../../src/discovery/chain.cyr) — daimon is designed as one backend among many; outages fall through.

## Changing the contract post-fold

The pre-fold urgency this section used to argue — land it before the v5.7.0 fold freezes
the surface — no longer applies: the fold shipped at sandhi 1.0.0, and ADR 0005's freeze
lapsed with it. A contract change is now an ordinary sandhi patch plus a cyrius release
that re-vendors `lib/sandhi.cyr`. If daimon prefers to keep everything under `/v1/`,
sandhi re-points the single URL builder (`_sandhi_daimon_url_a`,
`src/discovery/daimon.cyr:62`; `register.cyr` reuses it) — say which in the daimon-side
filing so both halves land together.

## Proposed roadmap entry for daimon

> **Service registry endpoints for sandhi discovery.** Implement `GET/POST/DELETE /services/{name}` (or `/v1/services/{name}` — coordinate with sandhi, which re-points one URL builder) per the contract at `sandhi/docs/development/issues/2026-04-24-daimon-registry-endpoints.md`. Acceptance: sandhi's discovery chain resolver round-trips end-to-end against a local daimon (`sandhi_discovery_register("http://127.0.0.1:9000", "test-svc", "127.0.0.1", 8080)` followed by `sandhi_discovery_chain_resolve(chain, "test-svc")` returns the same host/port). Consumers reach sandhi through stdlib's `lib/sandhi.cyr` — no sandhi pin to bump.

## Log

- **2026-04-24** — Filed during sandhi M4 close. Trigger: user noted the "daimon will implement" claim in sandhi's v0.5.0 state was an assumption rather than a committed cross-repo action. Base-OS modernization pass is the target scheduling window.
- **2026-09-23** (sandhi 1.10.0 issue sweep) — Re-checked against daimon 2.4.2: still
  `/v1/*` only, no `/services/` route; stays open. Repaired the pre-fold framing (the
  "land before the v5.7.0 surface freeze" rationale, the "concurrent with the v1.0 fold"
  target, `[deps.sandhi]`-pinning blast radius) — the fold shipped at 1.0.0, so a contract
  change is now an ordinary patch + re-vendor, and the proposed roadmap entry offers
  `/v1/services/{name}` as the alternative to the namespace mismatch.
