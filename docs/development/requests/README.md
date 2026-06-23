# sandhi — requests log

Home for **non-roadmapped enhancement requests that are not bugs or
consumer-coordination docs**. Bugs and "a consumer needs sandhi to do X"
docs go in [`../issues/`](../issues/README.md); committed / provisional open
work goes in [`../roadmap.md`](../roadmap.md); shipped history lives in
[`../../CHANGELOG.md`](../../../CHANGELOG.md). This folder holds the third
bucket: speculative capability asks with **no sandhi-side commitment yet** —
features sandhi could grow but is deliberately holding until a real consumer
need lands.

Naming: `YYYY-MM-DD-kebab-case.md`, like `issues/` and `adr/`. Never renumber;
append-only.

## Lifecycle

- **New request** → add a dated file here describing the ask, the file(s) it
  would touch, and the gate (what evidence / which consumer would justify
  building it).
- **A consumer commits** (or a second consumer asks for the same pattern, per
  CLAUDE.md) → promote the request to a slot in `roadmap.md`, and delete or
  cross-link the request file.
- **Turns out to be a bug or a producer/consumer contract** → move it to
  `issues/` instead.

## Why separate from the roadmap

The roadmap is sandhi's own plan — open work plus *anchored* deferrals (a
reserved struct slot, a documented limitation in a specific module). These
requests have no such anchor: they are protocol/feature surface that incumbents
have but AGNOS consumers have not yet needed. Keeping them here keeps the
roadmap about sandhi's actual trajectory while still tracking the asks so they
aren't silently lost (the no-silent-scope-outs rule).

## Open requests

| Request | Touches | Gate |
|---------|---------|------|
| [`2026-06-23-connect-proxy-tunneling.md`](2026-06-23-connect-proxy-tunneling.md) | `src/http/conn.cyr` + client | a documented AGNOS egress-proxy need |
| [`2026-06-23-cookie-jar.md`](2026-06-23-cookie-jar.md) | `src/http/` (new) | an AGNOS consumer using cookie-bearing APIs |
| [`2026-06-23-json-merge-patch-and-rpc-batch.md`](2026-06-23-json-merge-patch-and-rpc-batch.md) | `src/rpc/` | a consumer needing RFC 7396 or JSON-RPC 2.0 batch (MCP tool-discovery latency is the likeliest) |
| [`2026-06-23-tls-alpn-extensions.md`](2026-06-23-tls-alpn-extensions.md) | `src/http/conn.cyr` ALPN wire | a consumer needing an ALPN protocol beyond `http/1.1` + `h2` |

> Seeded 2026-06-23 by consolidating the speculative "wait for a real ask"
> feature surface out of the roadmap. Concrete, sandhi-anchored deferrals (h2
> spec-completeness, per-hop cred-digest recompute, the daimon resolver auth
> slot, the client connection-pool mutex) stayed on the roadmap as backlog —
> they name a specific code site, these don't.
