# 005 — aarch64 cross-build: upstream `cycc_aarch64` choked on stdlib `bayan` (1.4.11–1.4.x; resolved 1.5.0)

> **RESOLVED at sandhi 1.5.0 / cyrius 6.2.6 (2026-06-14).** The
> `cycc_aarch64` `error: unexpected enum` abort is fixed upstream in
> 6.2.6. `CYRIUS_DCE=1 cyrius build --aarch64 programs/smoke.cyr
> build/sandhi-smoke-aarch64` now produces a valid `ELF 64-bit … ARM
> aarch64` binary with zero sandhi-side change — exactly as the filing
> predicted (a purely cyrius-side dep-assembly fix). The CI / release
> "Cross-build aarch64" step is a **gating step** again (the 1.4.11
> warn-and-skip-on-failure tolerance is removed; the only tolerated skip
> is the toolchain genuinely lacking `cycc_aarch64`). The history below is
> retained for the record. Issue archived at
> [`docs/issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`](../development/issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md).

## History (1.4.11 — best-effort window)

The CI / release **"Cross-build aarch64 (best-effort)"** step did not
gate a sandhi release. As of **1.4.11** it could not succeed on any
installed cyrius toolchain **6.0.21–6.2.1**, because `cycc_aarch64`
aborted with `error: unexpected enum` while assembling the stdlib `bayan`
dependency.

## What happens

`cyrius build --aarch64 programs/smoke.cyr …` fails at parse time:

```
compile programs/smoke.cyr -> build/sandhi-smoke-aarch64 [aarch64] error: unexpected enum
```

The x86_64 build of the *identical* source is clean. The trigger is
the stdlib `bayan` module: drop it from `[deps]` and aarch64 builds
clean; the minimal repro needs no sandhi code at all
(`deps = [syscalls, alloc, bayan]` + a three-line `main`).

## Why it's upstream, not sandhi

- `bayan` arrives transitively via `sigil` (its 6.1.25 carve-out
  re-exports `u256_*` / `base64_*` for the SPKI-pin digest path). It
  entered sandhi's `[deps]` at the **1.4.11** 6.2.1 pin sweep, which
  is why the break surfaced then — but every installed `cycc_aarch64`
  from **6.0.21 through 6.2.1** reproduces it, so it is a long-standing
  aarch64-backend defect, not a 6.2.1 regression.
- `bayan.cyr` parses fine on aarch64 when *included as a source file*;
  it only fails when pulled in as a `[deps]` entry. The fault is in
  the aarch64 **dependency-assembly / concatenation order**, where a
  preceding module's trailing top-level statement flips the parser
  into init-body mode ahead of bayan's first `enum` — the documented
  cyrius "top-level init breaks later declarations" quirk, exposed
  only on the aarch64 path.
- Per ADR 0001 and CLAUDE.md (compose-don't-reimplement, **No FFI**),
  sandhi neither forks stdlib `bayan` nor touches the compiler binary.
  The fix is purely cyrius-side.

## Consequence for releases

The aarch64 binary is a convenience link-shape proof shipped beside
the x86_64 binary, the source tarball, and `dist/sandhi.cyr`. The
authoritative release gates — x86_64 build, the `.tcyr` suite, lint,
`cyrius distlib` — are all green on 6.2.1. The aarch64 step in
`ci.yml` / `release.yml` therefore **warns and skips the artifact**
on failure instead of failing the job; the Archive step already
guards on file presence. When cyrius fixes `cycc_aarch64`, the step
resumes emitting the artifact with no sandhi-side change.

Originally tracked as a cross-repo dependency in
[`docs/development/roadmap.md`](../development/roadmap.md); filed (now archived,
resolved at 1.5.0) at
[`docs/issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`](../development/issues/archive/2026-06-12-cyrius-aarch64-bayan-enum-parse.md).
