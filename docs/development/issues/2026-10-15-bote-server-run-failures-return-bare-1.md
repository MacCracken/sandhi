# The serve entry points return a bare `1` for every failure, and two of them leak the listen socket

**Filed:** 2026-10-15
**Reporter:** bote 3.4.0
**Affected:** `src/server/mod.cyr`, all five serve entry points (`sandhi_server_run_opts`, via
`sandhi_server_run`; `_run_async`; `_run_pooled`; `_run_tls`; `_run_pooled_tls`)
**Version checked:** sandhi 1.10.9, the version cyrius 6.7.9 folds into `lib/sandhi.cyr`. Line
numbers below are `src/server/mod.cyr` at `7ef9715`.
**Severity:** Medium (operability). There are two defects:
- **Diagnostics.** A caller cannot tell a port in use from a failed allocation or a fatal accept.
- **An fd leak**, on its own Low: one socket per failed start in `_run_opts` and `_run_async`. It
  matters to any caller that retries, such as a supervisor loop or a fallback to the next port.

No data exposure.
**Status:** open.

## What is wrong

### 1. Every failure is `return 1`, and the errno is thrown away

Each entry point returns `0` when it is stopped and `1` for anything else. `sandhi_server_run_opts`
alone has seven distinct `return 1` causes:

| Line | Cause |
|---|---|
| 1464 | request buffer could not be allocated (`_hsv_ensure_req_buf`) |
| 1465 | reject arena could not be allocated (`_hsv_ensure_reject_arena`) |
| 1471 | `tcp_socket()` failed |
| 1475 | `sock_bind()` failed |
| 1478 | `sock_listen()` failed |
| 1485 | accept state could not be allocated |
| 1497 | `_sandhi_server_accept` classified an errno as `SANDHI_ACCEPT_FATAL` |

On Linux, `tcp_socket`, `sock_bind` and `sock_listen` all return `Err(errno)`
(`lib/net.cyr`: `return Err(0 - r)`). So at lines 1471 / 1475 / 1478 the errno sits in
`sfd` / `br` / `lr` and is never read. At 1497 the errno was in hand a moment earlier; it is what
`_sandhi_server_accept_action` (line 1430) classified. The other four entry points have the same
shape:
- `_run_async`: 1661 / 1663 / 1664, accept 1719;
- `_run_pooled`: 2248, accept 2300, and 2158 in its inline-serving path
  `_sandhi_server_pool_run_inline`;
- `_run_tls`: 2810, accept 2836;
- `_run_pooled_tls`: 2994, accept 3045, and 2921 in `_sandhi_server_pool_tls_run_inline`.

The two TLS entries also return `1` for a missing TLS option or certificate/key, before any
socket exists. sandhi logs nothing at any of these sites: the server module's only sakshi calls
are the opt-in `sandhi_trace_*` spans.

### 2. `_run_opts` and `_run_async` leak the listen socket when bind or listen fails

`_run_pooled` (2250–2251), `_run_tls` and `_run_pooled_tls` close `sfd` before returning from a
failed bind or listen. `_run_opts` (1475, 1478) and `_run_async` (1663, 1664) do not.

## Reproduction

### What a consumer sees (bote 3.4.0)

bote's HTTP, bridge, Streamable HTTP and WebSocket transports are each one call to
`sandhi_server_run`. Start a second instance on a port the first one holds:

```sh
cd ~/Repos/bote && ./scripts/build-all.sh
./build/bote http 18391 &       # holds the port
./build/bote http 18391         # second instance
echo $?                         # 1
```

stderr of the second instance (bote 3.4.0 logs every transport failure through sakshi):

```
[1129085290544435] [INFO] bote starting version=3.4.0 transport=http addr=127.0.0.1 port=18391 auth=none log=info
[1129085290579862] [ERROR] transport failed transport=http rc=1 cause="socket, bind, listen or accept failed (is the port in use?)"
```

bote has to guess. Its own Unix transport, which runs its own accept loop, logs
`unix transport failed step=bind path=… errno=98` for the same class of failure.

### What sandhi drops, and the leak (probe)

The probe holds a port, binds it directly, then calls three entry points five times each and
watches the number the next socket receives. Built in bote's tree (cyrius 6.7.9, sandhi 1.10.9
fold) and run on x86_64 Linux:

```
holder bind is_err=0
direct sock_bind on the held port: is_err=1
direct sock_bind errno (98 = EADDRINUSE): 98
next fd before run_opts x5: 4
  sandhi_server_run_opts rc=1
  sandhi_server_run_opts rc=1
  sandhi_server_run_opts rc=1
  sandhi_server_run_opts rc=1
  sandhi_server_run_opts rc=1
next fd after  run_opts x5: 9
next fd before run_pooled x5: 9
next fd after  run_pooled x5: 9
next fd before run_async x5: 9
  sandhi_server_run_async rc=1
  sandhi_server_run_async rc=1
  sandhi_server_run_async rc=1
  sandhi_server_run_async rc=1
  sandhi_server_run_async rc=1
next fd after  run_async x5: 14
```

- The stdlib reports `EADDRINUSE` (98). sandhi reports `1`.
- `_run_opts` and `_run_async` each leak one socket per failed start (4 → 9, 9 → 14).
  `_run_pooled` does not (9 → 9).

Probe source:

```cyr
fn _noop_handler(ctx, cfd, buf, n) { return 0; }

fn _say(label, n) {
    print(label, strlen(label));
    fmt_int(n);
    print("\n", 1);
    return 0;
}

fn _next_fd() {
    var t, fd = tcp_socket();
    sock_close(fd);
    return fd;
}

fn main() {
    alloc_init();
    var port = 18392;
    var lo = INADDR_LOOPBACK();
    var ht, hfd = tcp_socket();
    var hbt, hbv = sock_bind(hfd, lo, port);
    var hlt, hlv = sock_listen(hfd, 4);
    _say("holder bind is_err=", is_err_result(hbt));
    var t2, f2 = tcp_socket();
    var bt, bv = sock_bind(f2, lo, port);
    _say("direct sock_bind on the held port: is_err=", is_err_result(bt));
    _say("direct sock_bind errno (98 = EADDRINUSE): ", bv);
    sock_close(f2);
    _say("next fd before run_opts x5: ", _next_fd());
    var i = 0;
    while (i < 5) {
        _say("  sandhi_server_run_opts rc=", sandhi_server_run_opts(lo, port, &_noop_handler, 0, 0));
        i = i + 1;
    }
    _say("next fd after  run_opts x5: ", _next_fd());
    _say("next fd before run_pooled x5: ", _next_fd());
    i = 0;
    while (i < 5) { sandhi_server_run_pooled(lo, port, &_noop_handler, 0, 0); i = i + 1; }
    _say("next fd after  run_pooled x5: ", _next_fd());
    _say("next fd before run_async x5: ", _next_fd());
    i = 0;
    while (i < 5) {
        _say("  sandhi_server_run_async rc=", sandhi_server_run_async(lo, port, &_noop_handler, 0, 0));
        i = i + 1;
    }
    _say("next fd after  run_async x5: ", _next_fd());
    return 0;
}
var r = main();
sys_exit(r);
```

## Proposed fix

1. **The leak, at once (four lines).** `sock_close(sfd)` before `return` at 1475 / 1478 and
   1663 / 1664, as `_run_pooled` does at 2250–2251. Regression: the probe's next-fd check, which
   fails today (4 → 9).
2. **Say why, without changing the `0` / `1` contract.** Every caller today, bote included,
   treats any non-zero return as failure. A negative-errno return would be the most direct fix,
   but it changes that contract for every caller that compares against `1`. An additive shape
   keeps it:

   ```
   # The step and errno of the most recent failed serve start on this thread.
   # step: SANDHI_SERVER_FAIL_{NONE, CONFIG, ALLOC, SOCKET, BIND, LISTEN, ACCEPT}; errno 0 when the
   # step has none (CONFIG / ALLOC). Reset to NONE when a serve loop starts accepting.
   fn sandhi_server_last_failure(out_step, out_errno): i64
   ```

   Set it at each `return 1` above. It has to be per thread, or per server handle, so that two
   servers starting on two threads do not overwrite each other.
3. **Optionally, a sakshi line at the failing step**: for example
   `sakshi_error("sandhi server: bind failed", …)` with the errno, through sandhi's existing sakshi
   dependency. This is a visible behaviour change, because sandhi would start writing to stderr at
   sakshi's default level where today it writes nothing. So if wanted it belongs behind the same
   opt-in as `sandhi_trace_enable`, or at DEBUG. (2) is what bote would consume. It already logs the
   transport failure and needs only the step and errno to say which one.

## Consumer-side workaround

None that is clean. bote could re-bind the port itself before calling `sandhi_server_run`, to learn
the errno. That duplicates sandhi's socket setup and races sandhi's own bind, so bote does not do
it. bote 3.4.0 ships the four-way "socket, bind, listen or accept failed (is the port in use?)"
line and records this filing in its roadmap (Housekeeping → Upstream filings). bote has no retry
loop, so the leak costs it one fd at exit, not a growing count.

## Severity rationale

Medium for the pair, as listed above. The diagnostics gap affects every consumer of the five
entry points. The commonest failure, a port already in use, is the one an operator most needs
named, and the errno is already in a local variable at the failing line. The leak is Low on its
own and rises with retries: a supervisor retrying `sandhi_server_run` every second against a held
port leaks 3,600 sockets an hour, and in the end turns that failure into `EMFILE` everywhere else
in the process.

## Related

- [`archive/2026-07-30-accept-loop-unguarded-spin.md`](archive/2026-07-30-accept-loop-unguarded-spin.md):
  bote's earlier report against these accept sites, which added `_sandhi_server_accept_action`,
  the classifier whose errno this filing asks sandhi to keep.
- bote `CHANGELOG.md` [3.4.0] (operational logging through sakshi) and
  `docs/development/roadmap.md` (Housekeeping → Upstream filings).

## Log

- 2026-10-15: filed by bote 3.4.0 with the probe output above (sandhi 1.10.9 as folded by
  cyrius 6.7.9).
