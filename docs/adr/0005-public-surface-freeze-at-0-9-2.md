# 0005 — Public surface freeze at 0.9.2

**Status**: Accepted
**Date**: 2026-04-24

> **Thesis**: sandhi's public surface is frozen at 0.9.2. Between
> 0.9.2 and the v5.7.0 fold (shipped as sandhi 1.0.0), no new
> public verbs land. Bug fixes and internal refactors are
> unaffected. This is the operational corollary of ADR 0002's
> clean-break fold: every name in the public surface at fold-time
> becomes a permanent stdlib API.

## Context

[ADR 0002](0002-clean-break-fold-at-cyrius-v5-7-0.md) established
that sandhi folds into stdlib in one event at Cyrius v5.7.0 with
no alias window. The consequence section of that ADR flagged it:

> Timeline pressure on M2–M5 concentrates: anything sandhi plans
> to ship must land pre-5.7.0 since the public surface freezes at
> fold. Speculative surface is doubly discouraged.

0.9.2 is the closeout release. Every planned sandhi-side item has
landed:

- M2 full HTTP client (0.3.0)
- M3 JSON-RPC dialects (0.4.0)
- M3.5 SSE streaming (0.7.0)
- M4 service discovery (0.5.0)
- M5 TLS policy surface (0.6.0)
- 0.7.x reliability (timeouts, retry, DNS hardening, tracing)
- 0.8.x HTTP/2 + connection pool
- 0.9.x security sweep

From here, the only release-shaped work that remains is **the
fold itself**: `cyrius distlib` generates `dist/sandhi.cyr`,
stdlib vendors it as `lib/sandhi.cyr`, sandhi's 1.0.0 tag marks
the fold event. Any sandhi-side change between 0.9.2 and 1.0.0
ships permanently — there is no window where sandhi exists as a
sibling crate with an unstable surface waiting to be stabilized.

## Decision

**Between 0.9.2 and 1.0.0, no new public verbs land in sandhi.**

What counts as "new public verb":

- Any new `sandhi_*` name callable from outside the crate.
- Any new field added to a public struct observable via an
  accessor.
- Any new error-code constant in `src/error.cyr`.
- Any new option getter/setter (`sandhi_http_options_*`).

What doesn't count (and is still fine to land):

- Bug fixes to existing verbs — behavior-preserving (parses
  more input correctly, fixes a boundary bug) or
  behavior-changing to fix a security issue (per
  [ADR 0004](0004-security-first-refusal-model.md)).
- Internal refactors that don't change the public surface (e.g.,
  splitting a module, changing a private helper's signature).
- Documentation updates, CHANGELOG entries, test additions.
- Version-string bumps in `*_version()` accessors.

The CLAUDE.md hard-constraint line added at 0.9.2 captures the
policy:

> Public surface frozen at 0.9.2. No new public verbs land between
> 0.9.2 and the v5.7.0 fold (1.0.0). The fold ships sandhi into
> stdlib's `lib/sandhi.cyr` permanently — every name in the public
> surface at fold-time becomes a permanent stdlib API. Bug fixes
> and internal refactors are fine; new verbs are not. If a
> consumer asks for something post-0.9.2, it lands as a 1.0.x
> stdlib patch after fold, not as 0.9.x.

### What "1.0.x stdlib patch after fold" means in practice

Post-fold, sandhi-shape changes flow through the Cyrius release
process, not this repo. A consumer who needs a new verb in
`lib/sandhi.cyr` files against Cyrius, the change lands as a
1.0.x stdlib patch (e.g., Cyrius v5.7.3 ships `lib/sandhi.cyr`
with one new verb), consumers pick it up via their Cyrius
toolchain bump. sandhi-the-repo is expected to enter maintenance
mode after the fold — no further releases, with the retirement
tracked in `docs/development/state.md`.

## Consequences

- **Positive**
  - Every name at 1.0.0 has been live through 0.3.0–0.9.2. No
    name ships to permanent stdlib surface without production
    exposure in the sibling-crate phase.
  - Surface-review discipline aligns cleanly with release
    process. Between 0.9.2 and 1.0.0, any PR introducing a new
    `sandhi_*` name gets rejected on that basis alone, without
    needing to argue the merits of the specific verb. The
    question is settled.
  - Removes the temptation to land "just one more thing" before
    fold. The sibling-crate phase is over; further shape changes
    need stdlib-level review anyway, and might as well ride the
    Cyrius release process.
- **Negative**
  - Consumer asks that surface between 0.9.2 and 1.0.0 land later
    than they otherwise would — one stdlib release cycle of
    latency. Acceptable because 1.0.0 is already imminent (tied
    to Cyrius v5.7.0) and the Cyrius release cycle is fast.
  - sandhi's current public surface is effectively the permanent
    one. Any shape we got wrong in the sibling-crate phase lives
    forever (or takes a stdlib-side deprecation to retire).
- **Neutral**
  - Surface review at 0.9.2 becomes the permanent-API review.
    Consumer pins that have been riding 0.8.x / 0.9.x already
    encode the "what's actually used" signal — anything no
    consumer is using is a candidate for quiet removal pre-fold.

## Alternatives considered

- **Freeze earlier (e.g., at 0.9.0).** Considered. Rejected
  because 0.9.1 + 0.9.2 together carried meaningful additions
  (header dup-detection accessor, server symbol rename with
  transitional aliases, `dist/sandhi.cyr` first formal bundle).
  Freezing at 0.9.0 would have forced those into 0.9.0 proper,
  making 0.9.0 a larger release without benefit.
- **Freeze later (e.g., at 0.9.5).** Would give more room for
  late-arriving consumer asks. Rejected because the fold is
  imminent and further sibling-crate churn delays it without
  corresponding value — the right home for post-0.9.2 asks is
  1.0.x stdlib patches.
- **No explicit freeze; rely on "the fold is soon, so be
  careful".** The status before 0.9.2's CLAUDE.md update. Rejected
  because "be careful" is not a review criterion. An explicit
  freeze gives every PR author + reviewer a clear question to
  answer: does this add a new public name? If yes → post-fold.
  If no → fine.
- **Freeze only the server module (where the fold's include
  rewrite is most visible).** Rejected — the clean-break fold
  puts everything into `lib/sandhi.cyr` at once, not just the
  server module. Partial freezes don't match the shipping shape.
