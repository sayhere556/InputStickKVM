# Validation record — November 23, 2026

## Build and software checks

- Xcode 27.2 (27B52), macOS 26.6.2 on the user's Mac.
- Debug macOS build succeeded with the official SDK core compiled into the app.
- Built and launched through Xcode using Computer.
- 36 pure input-state checks passed after changing the control key to Right Command: disconnected gating, pause/lock transitions, release state, sided modifiers, multi-key reports, rollover recovery, unsupported keys, and bounded fractional mouse deltas. Additional cases cover both Command keys held, each side released independently, a control key already held on activation, and release during a paused lock.
- SDK sources were left unchanged. The bridge avoids an upstream umbrella-header import of a nonexistent header.
- Known SDK compiler warning: deprecated `CC_MD5` in upstream password-key derivation. No protocol/cryptography changes made.

## Hardware evidence

- App's **Ready to send input** state observed directly in the running UI.
- User reported **“it moved.”** after using the app's mouse test.
- User confirmed **“Yes, hello appeared correctly”** for the text test.
- User subsequently reported **“everythings works”** after the three requested live forwarding, mouse lock, and release/recovery checks. This report applies to the previous Left Command binding; the user then corrected the desired binding to Right Command.
- Direct UI observation also showed **Control released with Escape** with the app back in Mac control.

These confirm the first Bluetooth/USB input path with the user's hardware; they do not establish reliability or validate every capture feature.

## Right Command update and review

- Right Command now pauses capture and reveals lock controls. Left Command maps to the host's left Windows/GUI modifier.
- The reserved right-side modifier is excluded from all host keyboard reports, including when both Command keys are held.
- Modifier state is read from every event, so holding Right Command before entering the app cannot be missed on the activation click.
- Reconnection replaces any stale connection-error notice with a ready message.
- Build passed after these changes. The new right-side binding has software coverage; its physical-key behavior has not been independently observed yet.

## Still requires deeper hardware testing

- Continuous keyboard forwarding, six-key combinations, sided modifiers, host layout, caps lock, and repeat behavior.
- Trackpad movement, scrolling direction/sensitivity, button drags, and Bluetooth backpressure.
- Updated Right Command binding, including both Command keys held together.
- Exhaustive focus/window loss, sleep, USB suspend, disconnect, reconnect neutralization, and 60-second capture deadline cases beyond the user's basic checks.
- Release behavior during link loss or an app crash. Remote release cannot be guaranteed once disconnected.
- Password-protected devices: password entry is intentionally not implemented yet.

## Macros and automatic connection update

- The user confirmed the Right Command build works before this update.
- Renamed Test input to Macros and added Type clipboard with chunked typing, Stop/Escape cancellation, no clipboard-content logging, and upfront unsupported-character rejection.
- Added persistent Auto-discover/Reconnect options, remembered-receiver startup connection, capped retry backoff, manual-disconnect pause/Resume, and sleep gating.
- 70 pure software checks pass, including automatic connection decisions, throttling, unknown-device behavior, clipboard normalization/validation, chunking, cancellation, and no replay on reconnect.
- Debug build succeeds. Live clipboard delivery and physical link-loss recovery require validation with the receiver; no private clipboard was read during development.

## Release build without timed capture expiry

Removed the 60-second capture deadline and countdown. Escape, Right Command pause, focus/sleep loss, connection-loss release, and macro cancellation remain. All 70 checks pass; Release build succeeded. Earlier references to a 60-second timer describe older builds.
