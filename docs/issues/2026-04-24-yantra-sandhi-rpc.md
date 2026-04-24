# 2026-04-24 — yantra adopts `sandhi::rpc` for WebDriver + Appium backends

**Status**: Awaiting yantra roadmap entry
**Reporter**: sandhi post-M3 coordination sweep
**Target**: yantra's base-OS modernization pass (pre-sandhi-fold at Cyrius v5.7.0)
**Depends on**: sandhi v0.4.0 (shipped)

## What's assumed vs. actual

sandhi's M3 (v0.4.0) landed `sandhi::rpc::webdriver` and `sandhi::rpc::appium` specifically to unblock yantra's M2+ backend work (Firefox/WebKit via geckodriver, Android via UiAutomator2, iOS via XCUITest). Whether yantra has "pin sandhi" on its own roadmap is **not confirmed from this repo** — the sandhi-side surface is ready and unit-tested; cross-repo scheduling is the item to land.

## What sandhi now provides (ready for yantra)

- **`sandhi::rpc::webdriver`** — W3C WebDriver wire format. Session lifecycle (`sandhi_wd_new_session` / `sandhi_wd_delete_session`), navigation (`sandhi_wd_navigate_to` / `_get_url` / `_get_title`), element interaction (`find_element`, `element_click`, `element_text`, `element_attribute`, `element_send_keys`), JavaScript (`sandhi_wd_execute_script`), readiness probe (`sandhi_wd_status`).
- **`sandhi::rpc::appium`** — extensions on top of WebDriver. `sandhi_ap_new_session` with `appium:automationName` capability, context switching (`set_context` / `get_contexts`), app lifecycle (`install_app` / `remove_app` / `activate_app` / `terminate_app`), `mobile_exec`, `source`, `screenshot`.
- **`sandhi::rpc::json`** — nested JSON build (`sandhi_json_obj_new` + `add_string` / `add_int` / `add_bool` / `add_object` / `add_raw`) and dotted-path extract (`sandhi_json_get_string("value.sessionId")`). stdlib `json.cyr` is flat-only; yantra needs the nested version.
- **Error envelopes** — `SANDHI_RPC_DIALECT_WEBDRIVER` auto-extracts `value.error` / `value.message` from responses into `sandhi_rpc_err_message`. No per-verb error decoding at the consumer.

All of the above reuse sandhi's HTTP client + DNS resolver under the hood, so yantra doesn't pay a separate transport cost.

## Minimal migration shape

Before sandhi (yantra would hand-roll the wire format):
```cyr
# Build JSON manually, POST via stdlib http, parse response by hand.
# Roughly ~200 lines of per-backend boilerplate × each of Firefox,
# WebKit, UiAutomator2, XCUITest.
```

After sandhi:
```cyr
include "dist/sandhi.cyr"  # pre-fold; lib/sandhi.cyr post-fold

var base = "http://127.0.0.1:4444";
var caps = sandhi_json_obj_new();
sandhi_json_add_string(caps, "browserName", "firefox");
var root = sandhi_json_obj_new();
sandhi_json_add_object(root, "capabilities", caps);

var r = sandhi_wd_new_session(base, sandhi_json_build(root));
if (sandhi_rpc_ok(r) == 0) { /* surface sandhi_rpc_err_message(r) */ }
var sid = sandhi_wd_extract_session_id(r);
sandhi_wd_navigate_to(base, sid, "https://example.com/");
```

That's the same shape for every WebDriver / Appium backend. Per-backend code is ~20 lines of capability building + dispatch.

## Known caveats

- **HTTPS runtime currently blocked** (see `2026-04-24-libssl-pthread-deadlock.md`). Plain HTTP works end-to-end. Local drivers (geckodriver on 127.0.0.1:4444) are the default anyway — HTTPS isn't on yantra's critical path for the acceptance line.
- **Streaming responses (SSE)** deferred to sandhi M3.5. WebDriver BiDi events will land when a yantra backend actually needs them.

## Proposed yantra roadmap entry

> **Adopt `sandhi::rpc` for WebDriver + Appium backends.** Drop any hand-rolled JSON-wire-format code in favor of `sandhi_wd_*` and `sandhi_ap_*` verbs. Pin sandhi via `[deps.sandhi]` during the 5.6.x window; the pin retires at the v5.7.0 fold (sandhi becomes `lib/sandhi.cyr`). Acceptance: `yantra_web_open("firefox")` / `yantra_web_open("webkit")` / `yantra_android_open(...)` all route through sandhi. Reference: `sandhi/docs/issues/2026-04-24-yantra-sandhi-rpc.md`.

## Log

- **2026-04-24** — Filed as part of the sandhi post-M3 coordination sweep.
