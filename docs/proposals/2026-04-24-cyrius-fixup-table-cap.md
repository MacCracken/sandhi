# 2026-04-24 — Cyrius compiler fixup-table cap (32768)

**Status**: Internal note. Not yet filed against cyrius. Captured at
0.8.0 Bite 2 (HPACK) when it first hit sandhi.

**Type**: Toolchain limitation worth raising / investigating upstream
when a future bite hits the wall again.

## Symptom

```
warning:lib/syscalls_x86_64_linux.cyr:358: syscall arity mismatch
error: fixup table full (32768)
  FAIL: tests/sandhi.tcyr (compile error)
```

The cyrius compiler's per-program fixup table is hard-capped at
32768 entries. String literals appear to consume one fixup each (or
possibly two — the cap is reached faster than the literal count
alone would suggest). When the compilation unit's literal count
exceeds the cap, compile fails.

The cap was first observed during 0.8.0 Bite 2 (HPACK):

- `src/http/h2/hpack.cyr` adds 122 string-literal pushes for the
  RFC 7541 Appendix A static table — already had to be split into
  4 helper fns to dodge a *per-fn* fixup allowance (separate from
  the per-program cap).
- `tests/sandhi.tcyr` then exceeded the per-program cap when
  HPACK's targeted unit tests piled assertion-message string
  literals on top of the existing 461 assertions in the file.

## What we did instead

- **Split static-table init** into `_hpack_static_init_a/b/c/d` (4 fns
  of ~16 entries each). This handled the per-fn allowance.
- **Trimmed HPACK targeted tests** from sandhi.tcyr down to 3
  (static-table spotcheck, Huffman-rejection, RFC C.3.1 end-to-end
  decode). Coverage of integer-encoding / dynamic-table eviction /
  per-rep encoders is preserved through the C.3.1 round-trip but
  not through targeted unit tests.
- **Split test files** at Bite 2.5 (this proposal landing): HPACK
  tests now live in `tests/h2.tcyr`. CI runs both files.
  `tests/sandhi.tcyr` continues to hold the existing core tests.

## What this proposal asks for

When sandhi (or another cyrius-stdlib consumer) bumps into the cap
again, two paths to consider:

### Option 1 — Raise the cap

The 32768 number looks like an `i16`-width (signed 16-bit) array
index. If the cap is enforced by a static-sized buffer, raising
it to 65536 (`u16`) or 1048576 (`i20`) doubles or triples the
program-size budget at trivial memory cost (table grows from
~256 KB to ~512 KB at 64-bit pointers).

**Risk**: low — the cap is a quantitative guard, not a correctness
boundary. Tooling tests should already cover larger programs.

**Effort**: small — likely a one-line type change in `cc5` plus
recompiling the bootstrap. Caveat: if the table is serialised into
the binary format somehow, the on-disk shape would change and
older binaries would need re-emission. Worth a quick recon before
filing.

### Option 2 — String literal interning

Today each occurrence of `"foo"` in source likely emits its own
fixup, even when the compiler could collapse identical literals
to one. Interning identical literals at the program level would:

- Cut the fixup count drastically for assertion-heavy test files
  (every `assert_*(_, _, "label")` call shares many duplicate
  short labels).
- Cut binary size proportionally.
- Cost: a hashmap lookup at fixup-emit time during compilation —
  trivial.

**Risk**: low — semantics-preserving; any literal-equality test
in user code is already pointer-equal post-intern (which is
stricter than the language guarantees).

**Effort**: medium — touches the literal-emit path and the fixup
table layout. Probably 50-150 lines of cc5 changes.

### Option 3 (combined)

Do both. The interning gives a 5-10× headroom; the cap raise gives
another 2-30×. Together that's enough headroom for sandhi's full
0.8.0 surface plus future protocol modules without revisiting.

## Sandhi-side workarounds we already use

- Lazy-init pattern with split helper fns for static tables (HPACK
  Appendix A; foreseeable that h2 frame-type tables will need the
  same).
- Test-file split per subsystem — `sandhi.tcyr` for core,
  `h2.tcyr` for h2 protocol code. Each file stays under the cap.
- Trim assertion message strings — terse messages save fixups.

These work but get noisy as sandhi's surface area grows. A real fix
(option 1 or 2) lets sandhi go back to single-file tests and
single-fn static tables.

## Cross-links

- 0.8.0 Bite 2 commit: `0dfa35f` — first sandhi-side encounter.
- 0.8.0 Bite 2.5: this proposal + `tests/h2.tcyr` extraction.
- Cyrius source: `cc5` (location of fixup-table emit) — not
  inspected from sandhi context per
  `feedback_cross_repo_boundary.md` (read-only from here).

## Log

- **2026-04-24** — Filed during 0.8.0 Bite 2 work. Three
  workarounds in place; revisit upstream when next subsystem
  (h2 frames likely) hits the same wall.
