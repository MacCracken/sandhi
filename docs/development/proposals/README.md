# sandhi — proposals

Home for **enhancement proposals**: new capability sandhi could grow, written up
before it is built. Bugs and "a consumer needs sandhi to do X" coordination docs go
in [`../issues/`](../issues/README.md); the release plan is
[`../roadmap.md`](../roadmap.md); shipped history lives in
[`../../../CHANGELOG.md`](../../../CHANGELOG.md).

Naming: `YYYY-MM-DD-kebab-case.md`, like `issues/` and `adr/`. Never renumber;
append-only. Proposals moved here from `docs/proposals/` (the shipped ones, now in
`archive/`) and `docs/development/requests/` (the open ones) at 1.10.11.

## Lifecycle

- **New proposal** → a dated file here: the ask, the file(s) it would touch, the
  smallest shape that serves the known use, and the design risks to settle first.
- **Scheduled** → the roadmap names the release line it ships on, and the file's
  **Status** line says so. Every open proposal below is scheduled.
- **Shipped** → set **Status** to shipped with the release, and move the file to
  [`archive/`](archive/).
- **Turns out to be a bug or a producer/consumer contract** → move it to
  `issues/` instead.

## Open proposals

| Proposal | Touches | Scheduled |
|----------|---------|-----------|
| [`2026-06-23-json-merge-patch-and-rpc-batch.md`](2026-06-23-json-merge-patch-and-rpc-batch.md) | `src/rpc/` | **1.14.x** (batch first at 1.14.0, then merge patch) |
| [`2026-06-23-tls-alpn-extensions.md`](2026-06-23-tls-alpn-extensions.md) | `src/http/conn.cyr` ALPN wire | **1.14.x** (after the 1.13 request-context slot) |
| [`2026-06-23-connect-proxy-tunneling.md`](2026-06-23-connect-proxy-tunneling.md) | `src/http/conn.cyr` + client | **1.15.0** |
| [`2026-06-23-cookie-jar.md`](2026-06-23-cookie-jar.md) | `src/http/` (new) | **1.15.x** |

## Archive (shipped or resolved)

| Proposal | Outcome |
|----------|---------|
| [`archive/2026-05-03-allocator-migration.md`](archive/2026-05-03-allocator-migration.md) | Shipped at 1.1.0 and across the 1.2.x arc: the Allocator-as-first-arg `_a` variants. |
| [`archive/2026-04-24-cyrius-fixup-table-cap.md`](archive/2026-04-24-cyrius-fixup-table-cap.md) | Resolved sandhi-side by splitting the test suites (0.8.0, 1.2.8); never filed upstream. The cap-drift watch is in the roadmap's standing watches. |
