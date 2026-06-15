# 2026-06-12 — `cycc_aarch64` aborts with `unexpected enum` assembling stdlib `bayan`

**Status**: ✅ **Resolved upstream in cyrius 6.2.6** (picked up at sandhi
1.5.0, 2026-06-14). `CYRIUS_DCE=1 cyrius build --aarch64
programs/smoke.cyr build/sandhi-smoke-aarch64` now produces a valid
`ELF 64-bit … ARM aarch64` binary — the `unexpected enum` abort is gone
with **zero sandhi-side change**, exactly as the filing predicted (a
purely cyrius-side `cycc_aarch64` dep-assembly fix). The CI / release
aarch64 step was restored to a gating step at 1.5.0. See CHANGELOG
[1.5.0] and [architecture/005](../../architecture/005-aarch64-bayan-cross-build.md).
*(History below retained for the record; original status: Open — filed
upstream, blocked only the aarch64 cross-build artifact, x86_64
unaffected and authoritative.)*
**Filed**: sandhi side, against cyrius repo.
**Side**: Upstream (cyrius `cycc_aarch64` — the aarch64 cross-compiler).
**Sandhi-side surface**: None. sandhi composes stdlib `bayan` (it
arrives transitively via `sigil`); per ADR 0001 and CLAUDE.md
("compose-don't-reimplement", "No FFI") sandhi cannot fork/patch a
stdlib module or the compiler binary. This filing keeps the
cross-repo coupling visible; the fix is purely cyrius-side.

## Symptom

The release/CI "Cross-build aarch64 (best-effort)" step fails:

```
compile programs/smoke.cyr -> build/sandhi-smoke-aarch64 [aarch64] error: unexpected enum
FAIL
```

The x86_64 build of the identical source is clean. The error code
varies with token position (`29033` for the full smoke, `3283` for
the minimal repro) but the message is always `unexpected enum`.

## Minimal reproducer (zero sandhi code)

```
# cyrius.cyml
[package]
name = "proj"
version = "0.0.1"
language = "cyrius"
cyrius = "6.2.1"
[build]
entry = "programs/main.cyr"
output = "build/main"
[deps]
stdlib = [ "syscalls", "alloc", "bayan" ]
```

```
# programs/main.cyr
fn _p(): i64 { return 0; }
var _e = _p();
syscall(60, _e);
```

```
CYRIUS_DCE=1 cyrius build --aarch64 programs/main.cyr build/main   # FAIL: unexpected enum
CYRIUS_DCE=1 cyrius build          programs/main.cyr build/main   # OK (x86_64)
```

Drop `bayan` from `[deps]` (keep everything up to and including
`fdlopen`) and the aarch64 build is clean — `bayan` is the trigger.

## What it is — and isn't

- **It is** an aarch64 **dependency-assembly / parser** defect in
  `cycc_aarch64`. `bayan.cyr` *included as a source file* parses
  fine on aarch64; it only fails when pulled in as a `[deps]` entry,
  so the fault is in how the aarch64 pipeline concatenates/orders
  the dep set, not in bayan's source per se. The shape matches the
  known cyrius quirk *"a top-level statement forces the parser into
  init-body mode, and a following `enum` declaration fails"* — a
  preceding module's trailing top-level statement appears to leak
  parser state into bayan's first `enum` (`TomlError`) in the
  aarch64 concatenation order.
- **It is not** a stdlib-content drift: the vendored
  `lib/syscalls_aarch64_linux.cyr` is byte-identical to the
  version-pinned 6.2.1 snapshot, and building from a directory with
  no `cyrius.cyml` (bare prelude) is clean on aarch64.
- **It is not** version-introduced by the 6.2.1 pin: every installed
  `cycc_aarch64` from **6.0.21 through 6.2.1** reproduces it. sandhi
  only *started hitting it* at **1.4.11**, when the 6.2.1 pin sweep
  replaced `bigint` + `base64` with `bayan` in `[deps]` (`bayan` is
  the 6.1.25 carve-out that re-exports `u256_*` / `base64_*` for
  sigil's SPKI-pin digest path).

## Why it isn't a release blocker

The aarch64 binary is a *best-effort* convenience artifact — a
prebuilt link-shape proof shipped alongside the x86_64 binary and
the source tarball / `dist/sandhi.cyr`. The x86_64 build, the full
`.tcyr` suite, lint, and `cyrius distlib` are the authoritative
release gates and are all green on 6.2.1. As of 2026-06-12 the
aarch64 step in `ci.yml` / `release.yml` was made to tolerate this
failure (warn + skip the artifact) so the upstream defect cannot
gate a sandhi release. When cyrius fixes `cycc_aarch64`, the step
resumes producing the artifact with no sandhi-side change.

## Resolution path

Cyrius-side: fix the aarch64 dep-assembly so a preceding module's
top-level statement doesn't flip the parser into init-body mode
ahead of bayan's `enum` declarations (or reorder/guard the
concatenation). Tracked sandhi-side under roadmap "Cross-repo
dependencies" and architecture/005.
