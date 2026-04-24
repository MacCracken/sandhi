# 2026-04-24 — sit adopts `sandhi::http` for git-over-HTTP remote ops

**Status**: Awaiting sit roadmap entry (and the VCS-core work sit remote ops depend on)
**Reporter**: sandhi post-M3 coordination sweep
**Target**: sit's remote-ops milestone (timing tied to sit's local-VCS completion, not sandhi's v5.7.0 fold)
**Depends on**: sandhi v0.3.0 (shipped) for the HTTP client surface

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

- **HTTPS runtime currently blocked** (`2026-04-24-libssl-pthread-deadlock.md`). Effectively all git remotes today are HTTPS (GitHub, GitLab, self-hosted with TLS). sit's remote milestone is therefore **gated** on the libssl pthread-lock fix as well as sit's local-VCS completion. Plain-HTTP git remotes (rare, usually internal) work today.
- **Large packfile responses** — sandhi's HTTP client reads into a 256 KB default buffer (`_SANDHI_HTTP_RESP_BUF_SIZE`). Real packfiles can be MB to GB. sit's remote milestone needs either (a) a larger buffer configurable per-request, or (b) a streaming callback surface. This is a sandhi-side enhancement sit can drive when its milestone opens — file as "sandhi extension: streaming / configurable response buffer" at that point.
- **SSH remotes** are out of scope. sandhi doesn't speak SSH; sit's SSH transport stays as sit-owned code (or via a separate crate).

## Proposed sit roadmap entry

> **Remote clone / push / pull via `sandhi::http`.** Use `sandhi_http_get` for ref advertisement and `sandhi_http_post` for pack transfer. Pin sandhi via `[deps.sandhi]` until the v5.7.0 fold. Flag `sandhi` streaming / large-response surface as a follow-up if packfile size exceeds the default 256 KB buffer in practice. Reference: `sandhi/docs/issues/2026-04-24-sit-sandhi-git-over-http.md`. **Blocked by**: sit local-VCS work + stdlib TLS-init fix.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep. Carries two gating dependencies (sit's own local VCS + stdlib TLS), so expected to land later than other consumer migrations.
