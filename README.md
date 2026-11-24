# InputStick KVM

Use your Mac’s keyboard and trackpad to control another computer through an InputStick USB receiver. Native macOS app, **vibe-coded with OpenAI Codex**.

**Hardware required: [Buy an InputStick from the official shop](https://www.inputstick.com/shop/).** Plug it into the computer you want to control. The Mac connects over Bluetooth. This app sends keyboard and mouse input—it does not stream video.

## Get started

Requires **macOS 14+** and an InputStick receiver. Supports Apple Silicon and Intel Macs.

1. Download the app from [Releases](https://github.com/sayhere556/InputStickKVM/releases), unzip it, and move it to Applications. Or build `InputStickKVM.xcodeproj` in Xcode with **InputStickKVM → My Mac**.
2. Allow Bluetooth access. Select your receiver and connect the first time; discovery and reconnection can run automatically afterward.
3. Click **Enable keyboard capture**, then turn on InputStick KVM in **System Settings → Privacy & Security → Accessibility**. If missing, use **+** to add the app. Rebuilds may require granting access again or restarting the app.
4. Click **Start control** or the control area to forward your keyboard and trackpad.

## Controls

- **Escape:** release control immediately.
- **Hold Right Command:** pause forwarding and reveal the mouse-lock button. Release Command to apply the lock.
- **Left Control / Option / Command:** send **Ctrl / Alt / Win**.
- **Macros:** type `hello`, move the pointer, or **Type clipboard**. Clipboard text is read only when clicked. **Stop** or **Escape** cancels typing.
- **Disconnect:** pause automatic reconnection; click **Resume** when you want it back.

While forwarding, keyboard interception and macOS presentation mode keep app-switching shortcuts and trackpad workspace swipes from pulling you out of capture. Hold Right Command to temporarily restore Mac controls.

There is no timed auto-release. Leaving the control area with the mouse unlocked, losing focus, closing the window, sleeping, or losing the connection releases capture. Reconnecting never automatically captures input or replays clipboard text.

## Current limits

Clipboard typing supports US-layout text, tabs, and line breaks; Unicode/emoji typing and password entry for protected receivers are not implemented. This is a development build, signed locally and not notarized; macOS may require approving it in Privacy & Security before opening. Capture is not a system-wide kiosk or a security boundary. Basic forwarding, blocked swipes, and Escape release were user-tested, but exhaustive recovery testing is still pending—see [validation notes](VALIDATION.md).

## Public domain

The original app code, artwork, and documentation are dedicated to the **public domain under [CC0 1.0](LICENSE)**. Use, modify, and share them freely, including commercially.

**Exception:** the bundled [official InputStick SDK](https://github.com/inputstick/InputStickAPI-iOS) and other material under `Vendor/` retain their original terms, including the SDK’s [MIT license](Vendor/LICENSE). They are not covered by this public-domain dedication. See [NOTICE](NOTICE).
