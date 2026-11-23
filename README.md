# InputStick KVM — initial macOS build

A native SwiftUI macOS app using the official Objective-C InputStick SDK. Open **InputStickKVM.xcodeproj**, choose **InputStickKVM → My Mac**, and press **Run**. Minimum deployment target: macOS 14. Local development signing is configured; no paid developer account or third-party package manager is needed.

## What is implemented

- **Auto-discover** and **Reconnect** are enabled by default and saved between launches. Bluetooth starts on launch when either is enabled. Discovery uses 15-second scans with a short pause between scans.
- Scan for nearby receivers, select a device, connect, cancel, and disconnect. Automatically reconnect to the last successfully used receiver, with retries spaced at 2, 4, 8, 16, then 30 seconds. New/unknown receivers require manual selection.
- **Disconnect** or **Cancel connection** pauses automatic actions for the current session. Use **Resume** or manually connect to resume. Automatic recovery never reactivates capture or replays macros.
- Separate Bluetooth, connection, initialization, USB-waiting, and USB-suspended states.
- **Macros** contains **Type “hello”**, **Move pointer →**, and **Type clipboard**. Clipboard text is read only on a button click; its content is never logged, persisted, or polled.
- Clipboard macros accept printable US-layout ASCII text, tabs, and line breaks, up to 100,000 characters. CRLF/CR are normalized to LF. Unsupported characters are rejected before any text is sent. Text is queued in 32-character chunks, waiting for both local and receiver keyboard buffers to drain. **Stop**, **Escape**, focus loss, and connection loss cancel the queue without replay after reconnect.
- A window-based interceptor area forwarding physical keyboard keys, left/right/middle mouse buttons, relative trackpad/mouse movement, and vertical scroll.
- Six-key HID reports with sided Control, Shift, Option/Alt, and left Command/Windows modifiers.
- **Right Command** is reserved locally: holding it pauses remote input, releases held keys/buttons, restores the Mac pointer, and reveals a mouse-lock button. Requested lock starts when Command is released. Hold Right Command again to unlock.
- **Escape** releases capture. Leaving the control area when unlocked, app/window focus loss, window closure, sleep/session changes, and loss of device readiness release capture. There is no timed capture limit.
- Neutral reports and buffer-clearing requests on release; neutral state on reconnect. Disconnect allows 150 ms for release reports before closing the connection. Remote delivery is best effort and cannot be confirmed after link loss.
- Mouse deltas are coalesced at up to 60 Hz with bounded backlog. A congested key/button queue releases capture instead of accumulating unbounded input.

## First hardware test

1. Plug InputStick into the receiving computer. Keep that computer's physical keyboard/mouse available.
2. Open an empty text document there. This app does not stream its display.
3. Start the app and respond to macOS's Bluetooth permission prompt if shown. It automatically discovers receivers and reconnects to the last successful receiver. On first use, select your intended device manually.
4. Select the intended device and click **Connect**. Wait for **Ready to send input**.
5. Click **Type “hello”** and **Move pointer →**. Confirm both results on the receiving computer.
6. Click the control area. That first click activates forwarding and is not forwarded as a remote press. Check typing, modifier release, dragging, and scrolling.
7. Press **Escape**. Confirm the Mac pointer is free and no remote key/button remains held.
8. Start another session, hold **Right Command**, click **Lock mouse on ⌘ release**, then release Command. Verify pause/unlock and Escape before longer use.
9. Test focus switching, window closure, disconnect recovery. If a remote key remains held after a lost link, reconnect and use **Release all input**, or unplug/replug InputStick.

## Scope and limits

**Initial hardware checks are user-confirmed:** the app reached Ready, the pointer moved using the test button, and `hello` appeared correctly on the receiving computer on November 23, 2026. The user also reported that the three basic forwarding, mouse-lock, and release/recovery checks worked. The requested control key has since changed to Right Command; that updated binding has software-test coverage but still needs a physical-key check. Exhaustive failure handling remains unverified. See `VALIDATION.md` for details.

This version uses AppKit's local event monitor. It captures within this app; it does not install a global event tap, request Accessibility/Input Monitoring, or guarantee suppression of macOS-reserved shortcuts. Focus switching intentionally releases control. A global interceptor with explicit permission handling is a later milestone.

Escape is reserved for release and cannot yet be forwarded to the host. Right Command never becomes a Windows key; Left Command does. Holding Right Command clears held remote input; repress other held keys afterward. Host keyboard layout determines characters. Fn, media keys, multitouch gestures, horizontal scrolling, and layout selection are not implemented. Caps Lock synchronization with the host has not been validated.

Password-protected receivers fail safely if a key is needed: a password-entry/key-storage screen is not implemented, and device protection is not modified. Firmware updates are left to InputStickUtility. Automatic reconnection is implemented; automatic resumption of capture is intentionally disabled.

Release behavior on crashes, Bluetooth loss, unusual window arrangements, multiple displays, and USB suspension requires hardware validation. This is a development build, not a notarized distribution.

## SDK audit

Official source: https://github.com/inputstick/InputStickAPI-iOS

Pinned commit: `ea487920c271368ac0f29c31b306f2905da18bec`.

The repository already provides macOS-compatible CoreBluetooth/Foundation code. `Vendor/InputStickCore` is the unchanged `InputStickAPI/Core` directory; the UIKit-specific `iOS` directory is excluded. MIT license and provenance are included. No network dependency is required to build this copy.

The upstream umbrella `InputStickAPI.h` imports a missing `InputStickKeyboardUtils.h`. Our bridge imports the required individual headers instead. The vendor sources build with a legacy `CC_MD5` deprecation warning in the SDK's password-key derivation; this protocol behavior has not been changed. Encryption support is retained.

`Bridge/KVMTransport` owns the SDK and handles notifications, raw HID reports, readiness checks, and buffer release. `App/KVMModel.swift` manages UI state and the local event monitor. `App/InputState.swift` contains independently testable input and capture logic.

## Build and checks

From this directory:

```sh
xcodebuild -project InputStickKVM.xcodeproj -scheme InputStickKVM \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build build

mkdir -p .build
xcrun swiftc -module-cache-path .build/ModuleCache \
  App/InputState.swift Tests/main.swift -o .build/input-state-tests
.build/input-state-tests
```

The state checks do not access Bluetooth, install event hooks, move the cursor, or send input. For an Intel Mac, change the build destination architecture to `x86_64`.

## Next milestones

1. Validate discovery, USB readiness, `hello`, and neutral reports with the actual receiver.
2. Validate real trackpad deltas, scrolling direction, caps lock, modifier combinations, and all capture/release paths.
3. Add password/key handling using Keychain and explicit user entry.
4. Add optional global event interception, permission flow, stronger watchdog/recovery, and more keyboard-layout controls after the basic hardware path is proven.

## Clipboard and automatic connection checks

Copy a short harmless plain-text phrase yourself, focus an empty document on the receiving computer, then click **Type clipboard**. Tabs and newlines are sent as actual keypresses. Press Escape to stop a longer macro. The current build does not support arbitrary Unicode/emoji typing.

To test reconnect, unplug/replug the receiver or temporarily take it out of range. The app should reconnect to the remembered receiver and remain in **Mac control**. A deliberate **Disconnect** must stay disconnected until **Resume** or a manual connection. The clipboard contents and any partially typed macro are never automatically restored.
