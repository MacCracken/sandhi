# 005 — aarch64 cross-build is best-effort: upstream `cycc_aarch64` chokes on stdlib `bayan` (1.4.11)

The CI / release **"Cross-build aarch64 (best-effort)"** step does not
gate a sandhi release. As of **1.4.11** it cannot succeed on any
installed cyrius toolchain, because `cycc_aarch64` aborts with
`error: unexpected enum` while assembling the stdlib `bayan`
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

Tracked as a cross-repo dependency in
[`docs/development/roadmap.md`](../development/roadmap.md) and filed at
[`docs/issues/2026-06-12-cyrius-aarch64-bayan-enum-parse.md`](../issues/2026-06-12-cyrius-aarch64-bayan-enum-parse.md).
