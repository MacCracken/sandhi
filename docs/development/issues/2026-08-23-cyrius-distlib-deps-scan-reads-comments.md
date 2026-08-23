# 2026-08-23 — `cyrius distlib` derives `.deps` leaf requirements from COMMENT text

**Status:** open (cyrius-side).
**Severity:** low — the scanner **over**-declares, never under-declares, so nothing
fails to link. The cost is noise: a profile consumer is told to bring a module it
does not need, and the `.deps` sidecars churn on prose edits, which weakens the
CI drift gate that watches them.
**Repo:** cyrius (toolchain, `cyrius distlib`).
**Surfaced by:** sandhi 1.9.14, adding the client resolve hook.

## Symptom

Adding a comment to `src/http/conn.cyr` — no code change — added `assert` to the
leaf-requirement sidecars of the two profile bundles that include that module:

```
 dist/sandhi-tls.deps    | +assert
 dist/sandhi-server.deps | +assert
```

Neither slice uses `assert` anywhere. The module is a test helper.

## Reproduction (exact, from the 1.9.14 tree)

The comment documenting `sandhi_client_resolver_installed` read:

```
# hook can assert this at startup and refuse to serve without it, rather than
```

Changing the single word `assert` → `check`, with no other edit anywhere, and
re-running `cyrius distlib --all`, removes the entry from both sidecars:

```
$ sed -i 's/can assert this at startup/can check this at startup/' src/http/conn.cyr
$ cyrius distlib --all && git diff dist/sandhi-tls.deps dist/sandhi-server.deps
(no output)
```

So the scan is matching bare identifiers in comment text, not call sites.

## Why it is easy to miss

Most stdlib module names that appear in prose — `io`, `net`, `str`, `http`,
`tls`, `vec` — are modules the slice genuinely uses, so a spurious hit is
invisible. `assert` is the tell precisely because a shipping library never uses
it. Any other test-only or rarely-used module name would behave the same way.

## Suggested fix (cyrius-side)

Strip comments before the identifier scan. A `#` to end-of-line strip is enough;
Cyrius has no block comments and no `#` inside string literals on these paths.

## sandhi-side disposition

None required, and none taken beyond avoiding the trip word in that one comment.
The sidecars are correct today. Filed so that (a) a future `.deps` diff that
looks inexplicable has an explanation to hand, and (b) nobody "fixes" a spurious
entry by adding the module to `[deps].stdlib`, which would make the
over-declaration permanent and real.

## Log

- **2026-08-23 (sandhi 1.9.14 / cyrius `6.5.35`)** — Filed. Reproduced by
  toggling one word in one comment, both directions.
