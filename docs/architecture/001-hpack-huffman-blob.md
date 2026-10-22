# 001 — HPACK Huffman table is a single hex-blob literal

The HPACK Huffman decoder in `src/http/h2/huffman.cyr` embeds the
257-entry RFC 7541 Appendix B code table as a single 2570-character
hex blob (`_hpack_huffman_blob`) — not as 257 separate constants,
not as a generated lookup array, not as 257 `store64` calls in an
init function. This is the canonical "big table in one string
literal" pattern for sandhi; the same pattern is likely to recur in
future protocol modules that carry large lookup tables.

## What the module actually ships

`src/http/h2/huffman.cyr`:

    var _hpack_huffman_blob = "00001ff80d007fffd817..." (2570 chars)

Format per entry (10 hex chars × 257 entries):

- 8 hex chars for the code value, left-zero-padded to fit the
  30-bit RFC 7541 maximum (`0x3fffffff` for EOS).
- 2 hex chars for the code's bit length (3–30).
- The symbol is implicit from the entry's index (0..256).

At first use of the decoder or encoder, `_hpack_huffman_get()` has
`_hpack_huffman_build_a` walk the blob, parse each entry with
`_hpack_parse_hex`, and insert it into a binary tree via
`_hpack_huffman_add_a`. Tree nodes are 24 bytes
`{left_ptr, right_ptr, symbol_or_minus_1}`; internal nodes carry
`symbol = _SANDHI_HPACK_HUFFMAN_INTERNAL = -1`, leaves carry
`0..256`. The tree's root and the symbol→code encode table share one
block, published by a single store after a fence once it is complete
(1.13.4; through 1.13.3 the build wrote straight into globals behind a
"built" flag, and two threads' first uses raced).

Decode (`sandhi_hpack_huffman_decode_a`) walks the tree bit-by-bit. On a
leaf, it emits the symbol (or rejects if EOS). Padding rule per
§5.2: after consuming all input bits, if not at root, the partial
path must be ≤ 7 bits and all-1s (the MSBs of the EOS code); any
other partial path is malformed and decode fails.

## Why one literal, not 257 constants

Cyrius's per-program fixup table is capped at 32768 entries
(investigated in [`docs/development/proposals/archive/2026-04-24-cyrius-fixup-table-cap.md`](../development/proposals/archive/2026-04-24-cyrius-fixup-table-cap.md)).
String literals consume fixups. 257 separate literals would
consume 257 fixups *just for this table*, before the rest of the
HPACK / h2 / client code gets any. Adding the Huffman table as
257 separate constants pushed `tests/sandhi.tcyr` over the cap
and broke compilation during 0.8.0 Bite 2b.

One hex-blob literal consumes one fixup, regardless of table
size. The parse cost at first use is a few microseconds; the
decode tree is built once per process.

The related constraint (per-*function* fixup allowance, distinct
from the per-program cap) is what split the HPACK static table
fill into `_hpack_static_fill_1` .. `_4` at `src/http/h2/hpack.cyr`
— each function under the allowance, four functions under the
program-level cap. Same shape, at a different granularity.

## Tradeoffs this pattern makes

- **Accepts**: a runtime parse cost at first use (hex-digit walks in
  `_hpack_parse_hex`, tree node allocations). For HPACK Huffman this is ~257 tree inserts ×
  ~15 bits average depth ≈ 4000 tree walks + ~300 allocs. Sub-ms
  in practice.
- **Accepts**: the table is encoded as a literal string, which
  means a typo in the hex goes through the compiler and surfaces
  at runtime as a wrong-symbol decode. Guard: one
  known-correct-answer test (RFC 7541 Appendix C.4.1
  `www.example.com` round-trip) in `tests/h2.tcyr`.
- **Gains**: one fixup instead of N. Critical when N is ≥ ~100
  and the file is already near the per-program cap.
- **Gains**: the table encoding is legible — one line per 16
  symbols in the source (see the comment block above the blob in
  `src/http/h2/huffman.cyr`), inspectable by anyone who can
  read RFC 7541 Appendix B.

## When to reach for this pattern

- Protocol modules with lookup tables ≥ 100 entries.
- Character-class tables, status-code tables, error-code name
  tables — anywhere a generator would emit N `store*` calls.
- Tables where runtime mutation isn't needed (the blob is
  read-only; the parsed structure is built once and shared).

Not needed when:

- Table has < ~30 entries. The fixup savings don't justify the
  parse code.
- Table entries vary in shape per entry. Hex-blob format wants
  fixed-width entries; variable-width pushes the parse
  complexity up fast.

## References

- `src/http/h2/huffman.cyr` — the module this note describes.
- [`docs/development/proposals/archive/2026-04-24-cyrius-fixup-table-cap.md`](../development/proposals/archive/2026-04-24-cyrius-fixup-table-cap.md)
  — the upstream investigation question about the fixup cap.
- `src/http/h2/hpack.cyr` — `_hpack_static_fill_1` .. `_4`, the
  per-*function*-allowance variant of the same shape (four
  functions each under the allowance).
- 0.8.0 Bite 2b (CHANGELOG entry) — when this pattern first
  landed.
