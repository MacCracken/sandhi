# 2026-10-03 — the chunked-response verbs discard every send result: a streaming handler cannot tell its client has gone

**Status:** Resolved in sandhi **1.10.5** (2026-10-04). Reaches agnosai, bote and agnostic only when a cyrius release re-vendors `lib/sandhi.cyr` from `dist/sandhi.cyr`; there is no sandhi pin to bump.
**Severity:** **P2** — nothing crashes or corrupts inside sandhi. A server streaming to a client that has
disconnected keeps streaming, and keeps the connection and whatever feeds it, until its own source ends.
A short write silently breaks the chunk framing.
**Reporter:** agnostic, whose roadmap (0.1.9) records this as the prerequisite for any SSE route there. The same
pattern is live in agnosai and bote today (see *Who is affected*).
**Sandhi version:** 1.10.4 (`88115b3`, the tag), folded at cyrius 6.6.12 and carried unchanged by 6.6.14's
`lib/sandhi.cyr`.
**Affects:** every caller of `sandhi_server_send_chunked_start{,_a}`, `sandhi_server_send_chunk` and
`sandhi_server_send_chunked_end`.

## What happens

`src/server/mod.cyr`:

- `sandhi_server_send_chunk` (:558) writes the hex length line, the payload and the trailing CRLF with three
  `sock_send` calls (:582–584) and returns `0` whatever they returned (:585).
- `sandhi_server_send_chunked_end` (:590) sends `0\r\n\r\n` (:591) and returns `0` (:592).
- `sandhi_server_send_chunked_start_a` (:534) returns `0 - 1` only when building the header fails. Its
  `sock_send` of the head (:547) is discarded as well.

Each discarded result hides one of two failures:

1. **A peer that has gone.** The serve loops ignore SIGPIPE (1.6.6, `_sandhi_server_ignore_sigpipe`), so a write
   to a closed connection fails with `EPIPE` instead of killing the process. That failure is the only signal a
   streaming handler gets, and these verbs swallow it.
2. **A short write.** A blocking stream write may return fewer bytes than asked (a signal, or `SO_SNDTIMEO`).
   cyrius 6.6.8 added `sock_send_all` for this case: its comment in `lib/net.cyr` notes that every caller that
   dropped `sock_send`'s count silently truncated its frame. A chunk cut short leaves its length line promising
   bytes that never arrive, so the client reads the next chunk's header as payload.

## Reproduction (run 2026-10-03, cyrius 6.6.14)

An AF_UNIX socketpair. The client end is closed before the server writes.

```cyrius
fn main() {
    _sandhi_server_ignore_sigpipe();       # what every sandhi serve loop does at startup (1.6.6)
    var fds[8];
    var r = sys_socketpair(1, 1, 0, &fds);  # AF_UNIX, SOCK_STREAM
    if (r != 0) { println("socketpair failed"); return 1; }
    var pair = load64(&fds);
    var srv = pair & 0xFFFFFFFF;
    var cli = (pair >> 32) & 0xFFFFFFFF;
    sys_close(cli);                         # the client leaves
    println("sandhi_server_send_chunk ->");
    fmt_int(sandhi_server_send_chunk(srv, "data: x\n\n", 9));
    println("");
    println("sandhi_server_send_chunked_end ->");
    fmt_int(sandhi_server_send_chunked_end(srv));
    println("");
    println("sock_send_all on the same fd ->");
    fmt_int(sock_send_all(srv, "data: x\n\n", 9));
    println("");
    return 0;
}
var rc = main();
syscall(60, rc);
```

Built with `cyrius build` from a manifest whose `[deps] stdlib` is agnosai's set (it includes `sandhi`, `tls`,
`net` and their dependencies). `cyrius build` prepends the declared stdlib; a bare `cycc < repro.cyr` gets no
auto-prepend and fails on undefined names. Output:

```
sandhi_server_send_chunk ->
0
sandhi_server_send_chunked_end ->
0
sock_send_all on the same fd ->
-32
```

## Who is affected (read 2026-10-03)

- **agnosai**, `src/server/routes/sse.cyr`: the crew event stream (`agnosai_sse_crew_stream`, loop at :198)
  ends only when the subscriber lags or the subscription closes. Every event frame (:94) and the keep-alive
  (:249) go through `sandhi_server_send_chunk` without checking its result. A client that disconnects therefore
  holds the loop, its event-bus subscription and its connection until the crew finishes.
- **bote**, `src/transport_streamable.cyr`: the MCP streamable-HTTP SSE paths (:431–442, :462, :508–516).
- **agnostic** has no SSE route yet. Its roadmap names this as the prerequisite.

## Proposed fix

Send through `sock_send_all` and return its result: `0` on success, `-errno` on failure (`-EPIPE` for a peer
that has gone). `sandhi_server_send_chunk` stops at the first failure rather than sending the payload after a
failed length line. `sandhi_server_send_chunked_end` and `sandhi_server_send_chunked_start_a` do the same.

Callers that ignore the return are unaffected. Callers that check it can stop streaming.

Post-fold, consumers receive the fix only when a cyrius release re-vendors `lib/sandhi.cyr` from
`dist/sandhi.cyr`; there is no sandhi pin to bump.

## Acceptance

- A test that closes the peer of a socketpair and asserts that `sandhi_server_send_chunked_start`,
  `sandhi_server_send_chunk` and `sandhi_server_send_chunked_end` each return a negative errno.
- The guide's SSE example (`docs/guides/server.md`, "Chunked / streaming") checks the result and stops on a
  negative one.

## Resolution (sandhi 1.10.5)

Fixed as proposed. `sandhi_server_send_chunked_start{,_a}`, `sandhi_server_send_chunk` and
`sandhi_server_send_chunked_end` write through `sock_send_all` and return `0` once every byte is
written, or its negative result: `-errno` (`-EPIPE` for a peer that has gone), or `-1` when building
the head runs out of memory, as before. `sandhi_server_send_chunk` stops at the first failed write, so
no payload follows a failed length line. A short write is finished instead of truncating the frame.

Acceptance:

- `tests/sandhi.tcyr` `server/chunked_send_results`: on an AF_UNIX pair whose peer has closed, all three
  verbs return a negative value. Mutation: restoring the discarded results fails exactly those three
  rows. A live-pair row checks they return 0 and the exact wire bytes. The test ignores SIGPIPE through
  the stdlib's `signal_ignore`, so it also runs on the macOS CI job.
- `docs/guides/server.md` "Chunked / streaming" checks each result and stops on a negative one.

**macOS caveat.** The serve loops still ignore SIGPIPE on Linux only (`_sandhi_server_ignore_sigpipe`),
so on macOS a write to a client that has gone raises SIGPIPE and kills the process before the handler
sees `-EPIPE`. The stdlib prerequisite for closing that (`signal_ignore`, portable to macOS) has
landed in the toolchain; the roadmap's *macOS server SIGPIPE guard* entry tracks the switch.

**Not changed:** the one-shot verbs (`sandhi_server_send_response{,_a}`, `_send_status{,_a}`,
`_send_204{,_a}`) still discard their `sock_send` results. That is outside this filing; it is tracked
in the roadmap.

