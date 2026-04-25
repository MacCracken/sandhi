# 0004 — Refuse-don't-interpret on ambiguous protocol input

**Status**: Accepted
**Date**: 2026-04-24

> **Thesis**: when sandhi sees a malformed or ambiguous HTTP
> message, the answer is to refuse the message and surface an error
> — not to apply defensive heuristics. For every smuggling vector,
> an upstream proxy or origin may interpret the ambiguity
> differently; the only safe disagreement-handling is to not be a
> party to the disagreement.

## Context

The 0.7.0 external review identified a cluster of HTTP-parser
bugs in sandhi that traced back to the same shape: the parser
accepted input that was technically malformed but "looked close
enough", and downstream behavior then depended on which lenient
interpretation the parser picked. The well-known smuggling triad
(CL.CL / CL.TE / TE.TE per RFC 7230 §3.3.3) is the canonical
example, but the shape generalizes — any parser that tries to
"fix" malformed input is opting itself into a disagreement with
some other parser somewhere in the request/response path.

0.9.0 and 0.9.1 together closed this cluster in two phases:

- **0.9.0** — five P0 items (protocol-correctness fixes whose
  disagreement window is an active exploit class).
- **0.9.1** — seven P1 items (defense-in-depth where disagreement
  is plausible but no in-the-wild exploit is known).

Every fix took the same shape: **detect the ambiguity, emit a
specific error code, refuse the message**. No fix added
heuristics, "most likely intended" interpretations, or
silent-fallback paths.

## Decision

sandhi's protocol parsers refuse ambiguous or malformed input.
The error taxonomy in `src/error.cyr` already carries the codes
needed: `SANDHI_ERR_PROTOCOL` for framing ambiguity,
`SANDHI_ERR_PARSE` for structural malformation, `SANDHI_ERR_TLS`
for security-policy refusal. Every fix in 0.9.0/0.9.1 routes
through one of those, with a specific regression test proving
the refusal fires on exactly the bug class.

### Concrete fixes by category

**Framing ambiguity** (the smuggling cluster):

- **Chunked decoder requires terminal 0-chunk** (0.9.0 P0 #1,
  `src/http/response.cyr`). `_sandhi_resp_chunk_size` returns
  `_SANDHI_RESP_CHUNK_BAD = -1` when no hex digit is present
  (was: fell through as size=0 and got treated as the terminal
  chunk — silent body truncation). Missing terminal chunk →
  `SANDHI_ERR_PROTOCOL`.
- **CL + TE coexistence rejected on both sides** (0.9.0 P0 #2).
  `src/http/response.cyr::_sandhi_resp_frame` and
  `src/server/mod.cyr::http_request_has_cl_te_conflict` both
  reject. Server dispatch replies 400 before the user handler
  runs, so custom routing can't accidentally route a smuggled
  request.
- **Chunk-size overflow capped at 2^31** (0.9.0 P0 #3).
  `_sandhi_resp_chunk_size` rejects sizes >
  `_SANDHI_RESP_CHUNK_MAX = 0x7FFFFFFF`. 17-hex-char chunk-size
  could have overflowed the signed accumulator negative, bypassing
  the `off + size > blen` bounds check.
- **Header duplicate detection — Host / CL / TE** (0.9.1 P1 #6).
  `src/http/headers.cyr::sandhi_headers_smuggle_dup` counts
  occurrences case-insensitively. Both `_sandhi_resp_frame`
  (response side) and server accept-loop reject. Closes CL.CL /
  Host.Host / TE.TE per RFC 7230 §3.3.2 + §5.4.
- **Strict CL parse** (0.9.1 P1 #3). `_sandhi_resp_parse_clen` +
  `src/server/mod.cyr::http_content_length` accept decimal digits
  only with optional surrounding whitespace per RFC 7230 §3.3.2.
  `"10, 20"` used to parse as `1020` — that's the disagreement
  any sane parser would be appalled by, and the vehicle for
  CL.CL smuggling.

**Credential / scheme protection**:

- **Cross-origin redirects strip sensitive headers** (0.9.0 P0 #4,
  `src/http/client.cyr::_sandhi_http_follow`). Per-hop
  `Authorization` / `Cookie` / `Proxy-Authorization` strip when
  scheme+host+port don't match the previous hop. Curl
  CVE-2025-0167 / 14524 cluster.
- **HTTPS→HTTP downgrade refused outright** (same fix). The
  redirect is returned to the caller as an HTTPS response with
  `err_kind = SANDHI_ERR_TLS` — not followed. There is no
  "permissive mode" switch; if a caller wants to downgrade, they
  re-issue the request explicitly with the new URL.

**Policy enforcement fail-closed**:

- **TLS policy fail-closed** (0.9.0 P0 #5,
  `src/tls_policy/apply.cyr`). When the caller demands pinning /
  mTLS / custom trust store AND
  `sandhi_tls_policy_enforcement_available()` is 0, the connection
  is refused — return 0, set `_sandhi_conn_last_err =
  SANDHI_CONN_OPEN_TLS`. Previous behavior silently downgraded to
  default verify; that gave false confidence the pin was enforced.
  Callers wanting best-effort semantics must pass
  `sandhi_tls_policy_new_default()` explicitly.

**Injection-through-normalization**:

- **Header CRLF / NUL rejected on add/set** (0.9.1 P1 #2,
  `src/http/headers.cyr`). `sandhi_headers_add` and
  `sandhi_headers_set` reject CR / LF / NUL in name or value.
  Without this, `set(h, "X", "v\r\nInjected: yes")` would smuggle
  a second header onto the wire at serialization time.
- **SSE id-with-NUL ignored** (0.9.1 P1 #5, `src/http/sse.cyr`).
  `_sandhi_sse_value_has_nul` scans raw value bytes (cstr ops stop
  at NUL); the `id` field handler skips assignment per WHATWG
  EventSource spec. `id: a\x00b` used to store the
  attacker-controlled prefix; strlen consumers would then see
  `"a"`, corrupting the reconnect `Last-Event-ID`.

## Consequences

- **Positive**
  - No smuggling vector sandhi is a party to. Every known shape is
    refused with a specific error; every refusal has a regression
    test under `p0/` or `p1/` in `tests/sandhi.tcyr`.
  - Consumer-facing error taxonomy carries the signal — a
    `SANDHI_ERR_PROTOCOL` return tells the caller "the wire
    input was malformed", and they can log, retry against a
    different endpoint, or surface a specific user-facing error.
    No need to inspect body bytes to distinguish truncation from
    malformation.
  - Behavior is stable across intermediaries. A 2-hop CL.TE
    smuggle that worked against a lenient parser chained with
    sandhi upstream now 400s at sandhi; the downstream origin
    never sees the ambiguous bytes.
  - Fail-closed TLS policy makes `sandhi_tls_policy_enforcement_available()`
    the single query point for consumers needing hard guarantees.
- **Negative**
  - Previously-working callers that relied on the lenient parser
    will see new errors. Two fixes are observably behavior-changing
    and triggered the minor-version bump for 0.9.0:
    - Credentials no longer follow cross-origin redirects.
    - Pinned / mTLS / trust-store policies without wired
      enforcement now refuse rather than silently downgrade.
  - Terminal-0-chunk requirement rejects some servers that produce
    connection-close-framed "chunked" streams. Those servers were
    already malformed; sandhi now surfaces it instead of truncating.
- **Neutral**
  - Establishes the shape for future security work. When a new
    vector surfaces, the fix pattern is already documented: detect,
    error-code, refuse, test. Don't add a "lenient mode" switch.

## Alternatives considered

- **Lenient mode behind a flag** (accept ambiguous input when
  caller sets `sandhi_http_options_permissive(opts, 1)`).
  Rejected — the permissive path is by definition the unsafe
  path, and every call-site would have to reason about whether
  to enable it. A config flag that makes you vulnerable if you
  flip it is worse than no flag, because the flag says "this is
  a valid choice" when it isn't.
- **Heuristics for the smuggling cluster** (e.g., "prefer TE over
  CL" per RFC 7230 §3.3.3 when both are present). RFC-permitted
  but foolhardy — the upstream proxy is under no obligation to
  agree, and any implementation mismatch becomes smuggling.
  Refusing is the only posture that doesn't depend on every
  other parser in the chain matching ours.
- **Only fix the P0s, leave P1 for later.** Considered. Rejected
  because the P0/P1 split is about exploit-pressure, not
  correctness — P1 header dup-detection and CRLF rejection
  close adjacent vectors, and 0.9.1 was cheap (same files, same
  testing rig, same release cycle). Leaving them for 1.0.x
  would mean shipping sandhi-in-stdlib with known-soft spots.
- **Wait to fix until an in-the-wild exploit is filed.** Rejected
  — the audit already mapped the vectors, the fixes are small
  and well-scoped, and sandhi is about to ship permanently into
  stdlib at v5.7.0. Shipping the soft version permanently is
  the wrong tradeoff.
