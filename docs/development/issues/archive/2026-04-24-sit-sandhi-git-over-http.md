# 2026-04-24 — sit adopts `sandhi::http` for git-over-HTTP remote ops

**Status**: **RESOLVED / moot (2026-06-15)** — sit shipped its remote ops without
adopting `sandhi::http`. The hypothesis this doc captured (sit consumes sandhi's
HTTP *client* for the git smart-HTTP protocol) was definitively answered **no**:
sit chose its own `/sit/v1/...` REST wire protocol and a hand-rolled HTTP client.
This is a closed question, not a blocked or in-progress one. See the 2026-06-15
log entry for the evidence. (sit *does* consume sandhi's **server** surface
`sandhi_server_*` for `sit serve` — that relationship is live and unaffected.)
**Reporter**: sandhi post-M3 coordination sweep
**Target**: ~~sit's remote-ops milestone~~ — shipped (sit v1.0.0, 2026-06-13) via a non-sandhi-client path
**Depends on**: sandhi v0.3.0 (shipped) for the HTTP client surface — never consumed by sit

## What's assumed vs. actual

ADR 0001 lists sit as a planned sandhi consumer for "remote clone/push/pull once the local VCS is done". Whether sit's roadmap has this scheduled yet is **not confirmed from this repo** — sit's local VCS work is the first dependency, and "remote ops" is a later milestone that'll pick up sandhi when it's ready to start.

This doc captures the sandhi-side contract so sit's remote-ops milestone has a paste-ready migration plan when the time comes, rather than a retrofit conversation.

## What sandhi now provides (ready for sit)

- **`sandhi::http::client`** — the methods sit needs for git-over-HTTP smart protocol: `sandhi_http_get` for `$repo/info/refs?service=git-upload-pack` (ref advertisement), `sandhi_http_post` for `$repo/git-upload-pack` (fetch) and `$repo/git-receive-pack` (push).
- **Chunked response decoding** handled in the response parser. Packfile responses that stream via `Transfer-Encoding: chunked` surface as a single decoded body to the caller.
- **`sandhi::http::headers`** for the git-specific headers: `Content-Type: application/x-git-upload-pack-request`, `Accept: application/x-git-upload-pack-result`, plus `Authorization` for authenticated remotes.
- **Redirect following** is off by default but opt-in via `sandhi_http_options_new()`. Git's HTTP spec allows 301/302/307/308 for repo relocations; sit can enable this per-request.

## Minimal migration shape (ref advertisement)

```cyr
include "dist/sandhi.cyr"

var h = sandhi_headers_new();
sandhi_headers_set(h, "User-Agent", "sit/1.x git/2.0");

var url = "https://git.example.com/repo.git/info/refs?service=git-upload-pack";
var r = sandhi_http_get(url, h);
if (sandhi_http_err_kind(r) != SANDHI_OK) { /* network failure */ }
if (sandhi_http_status(r) != 200) { /* remote refused */ }
# sandhi_http_body(r) is the pkt-line ref advertisement.
# Pass to sit's git-protocol parser.
```

## Minimal migration shape (push / fetch)

```cyr
var h = sandhi_headers_new();
sandhi_headers_set(h, "Content-Type", "application/x-git-upload-pack-request");
sandhi_headers_set(h, "Accept", "application/x-git-upload-pack-result");

# packfile_req_bytes + packfile_req_len come from sit's protocol layer.
var r = sandhi_http_post("https://git.example.com/repo.git/git-upload-pack",
                        h, packfile_req_bytes, packfile_req_len);
# sandhi_http_body(r) / sandhi_http_body_len(r) is the packfile payload.
```

## Known caveats

- **HTTPS works end-to-end** — the original libssl-pthread / stdlib-TLS-init blocker resolved upstream (cyrius v5.6.39; native TLS is the no-flag default since 6.1.21), so HTTPS git remotes (GitHub, GitLab, self-hosted with TLS) work today (see [`archive/2026-04-24-libssl-pthread-deadlock.md`](2026-04-24-libssl-pthread-deadlock.md)). sit's remote milestone is now gated **only** on sit's local-VCS completion.
- **Large packfile responses** — sandhi's HTTP client reads into a 256 KB default buffer (`_SANDHI_HTTP_RESP_BUF_SIZE`). Real packfiles can be MB to GB. sit's remote milestone needs either (a) a larger buffer configurable per-request, or (b) a streaming callback surface. This is a sandhi-side enhancement sit can drive when its milestone opens — file as "sandhi extension: streaming / configurable response buffer" at that point.
- **SSH remotes** are out of scope. sandhi doesn't speak SSH; sit's SSH transport stays as sit-owned code (or via a separate crate).

## Proposed sit roadmap entry

> **Remote clone / push / pull via `sandhi::http`.** Use `sandhi_http_get` for ref advertisement and `sandhi_http_post` for pack transfer. Pin sandhi via `[deps.sandhi]` until the v5.7.0 fold. Flag `sandhi` streaming / large-response surface as a follow-up if packfile size exceeds the default 256 KB buffer in practice. Reference: `sandhi/docs/issues/2026-04-24-sit-sandhi-git-over-http.md`. **Blocked by**: sit local-VCS work (the stdlib TLS-init prerequisite has landed).

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Carries two gating dependencies (sit's own local VCS + stdlib TLS), so expected to land later than other consumer migrations.
- **2026-06-15** — **RESOLVED / moot.** Reviewed against sit's actual repo state
  (sit v1.0.0 / v1.0.1, 2026-06-13). Findings:
  - **sit's remote sync shipped** — clone / fetch / push over
    `file://` / `http://` / `https://` / `ssh://` (sit CHANGELOG v1.0.0). The
    gating dependency (sit's local VCS) is done.
  - **sit did NOT adopt git smart-HTTP, nor sandhi's HTTP client.** It speaks its
    own `/sit/v1/...` REST protocol (`src/wire_http.cyr` — endpoints
    `/sit/v1/refs`, `/sit/v1/objects/`, `/sit/v1/want`, `/sit/v1/capabilities`;
    no `info/refs?service=git-upload-pack` / `git-upload-pack` / `git-receive-pack`
    anywhere) over a hand-rolled HTTP/1.0 client (`wire_http.cyr`, not
    `sandhi_http_get` / `_post`). So the migration shapes in this doc were never
    needed.
  - **The 256 KB-buffer caveat never triggered from sit.** sit's own client uses a
    dynamic 64 KiB→16 MiB buffer (`WIRE_HTTP_INITIAL_BUF` / `WIRE_HTTP_MAX_BODY`),
    so the "sandhi streaming / configurable response buffer" follow-up this doc
    flagged has **no sit-driven demand** — it stays a wait-for-a-real-ask item, not
    a sit obligation. (Per `project_sit_adoption_drives_roadmap`: sit surfaced no
    HTTP-client friction because it isn't a client consumer.)
  - **sit DOES consume sandhi's server surface** (`sandhi_server_*` in
    `src/serve.cyr` for `sit serve`) — sit's roadmap marks the sandhi dependency
    "on hold — keep sandhi" pending an easier cyrius `stdlib`/`lib` consumption
    path. That server-side relationship is live and orthogonal to this (client-side)
    doc.
  - **Action**: archived. The client-adoption question is closed; no sandhi-side
    work pending. sit's *server*-surface consumption is tracked separately (it's
    the live sit↔sandhi coupling).
