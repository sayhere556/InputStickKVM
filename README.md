# InputStick KVM

Use your Mac’s keyboard and trackpad to control another computer through an InputStick USB receiver. Native macOS app, **vibe-coded with OpenAI Codex**.

**Hardware required: [Buy an InputStick from the official shop](https://www.inputstick.com/shop/).** Plug it into the computer you want to control. The Mac connects over Bluetooth. This app sends keyboard and mouse input—it does not stream video.

## Get started

Requires **macOS 14+**, Xcode to build, and an InputStick receiver.

1. Open `InputStickKVM.xcodeproj` in Xcode, select **InputStickKVM → My Mac**, and press **Run**.
2. Allow Bluetooth access. Select your receiver and connect the first time; the app can discover devices and reconnect automatically afterward.
3. Click the control area to start forwarding your keyboard and trackpad.

## Controls

- **Escape:** release control immediately.
- **Hold Right Command:** pause forwarding and reveal the mouse-lock button. Release Command to apply the lock.
- **Left Control / Option / Command:** send **Ctrl / Alt / Win**.
- **Macros:** type `hello`, move the pointer, or **Type clipboard**. Clipboard text is read only when clicked. **Stop** or **Escape** cancels typing.
- **Disconnect:** pause automatic reconnection; click **Resume** when you want it back.

There is no timed auto-release. Switching apps, closing the window, or losing the connection releases capture. Reconnecting never automatically captures input or replays clipboard text.

## Current limits

Clipboard typing supports US-layout text, tabs, and line breaks; Unicode/emoji typing and password entry for protected receivers are not implemented. macOS system shortcuts may still act locally. Builds are not notarized. Basic hardware tests passed, but exhaustive recovery testing is still pending—see [validation notes](VALIDATION.md).

## Public domain

The original app code, artwork, and documentation are dedicated to the **public domain under [CC0 1.0](LICENSE)**. Use, modify, and share them freely, including commercially.

**Exception:** the bundled [official InputStick SDK](https://github.com/inputstick/InputStickAPI-iOS) and other material under `Vendor/` retain their original terms, including the SDK’s [MIT license](Vendor/LICENSE). They are not covered by this public-domain dedication. See [NOTICE](NOTICE).
