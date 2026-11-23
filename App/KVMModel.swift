import SwiftUI
import AppKit
import CoreGraphics

struct NearbyDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let rssi: Int
}

final class KVMModel: ObservableObject {
    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var ready = false
    @Published private(set) var scanning = false
    @Published private(set) var bluetoothState = 0
    @Published private(set) var connectionState = 0
    @Published private(set) var started = false
    @Published private(set) var session = CaptureSession()
    @Published private(set) var notice = "Start with an empty document on the receiving computer. Right Command reveals mouse-lock controls."
    @Published private(set) var history: [String] = []
    @Published var selection: String?
    @Published private(set) var disconnecting = false
    @Published var autoDiscover = UserDefaults.standard.object(forKey: "autoDiscover") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoDiscover, forKey: "autoDiscover"); if autoDiscover { resumeAutomatic() } }
    }
    @Published var autoReconnect = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoReconnect, forKey: "autoReconnect"); if autoReconnect { resumeAutomatic() } }
    }
    @Published private(set) var automaticPaused = false
    @Published private(set) var macroRunning = false
    @Published private(set) var macroProgress = ""
    weak var pad: NSView?
    private let transport = KVMTransport()
    private var keyboard = HIDKeyboardState()
    private var mouse = MouseAccumulator()
    private var buttons: UInt8 = 0
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var pollingTimer: Timer?
    private var cursorDetached = false
    private var automation = ConnectionAutomation()
    private var macro = TextMacroQueue()
    private var sleeping = false
    private var macroLastProgress = Date()

    init() {
        transport.onChange = { [weak self] in self?.refresh() }
        transport.onMessage = { [weak self] message in self?.log(message) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged,
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        let nc = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification,
                     NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if let window = notification.object as? NSWindow, window !== self.pad?.window { return }
                self.release("Control released: window or app focus changed.")
                self.session.rightCommandDown = false
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.release("Control released: Mac is sleeping or switching sessions.")
                self?.session.rightCommandDown = false
                self?.sleeping = true
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = false
            })
        }
        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tick, forMode: .common); timer = tick
        let poll = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh(); self?.runAutomatic()
        }
        RunLoop.main.add(poll, forMode: .common); pollingTimer = poll
        // User-requested automatic discovery starts Bluetooth on launch.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.autoDiscover || self.autoReconnect else { return }
            self.startBluetooth()
        }
    }

    deinit {
        timer?.invalidate(); pollingTimer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        if cursorDetached { CGAssociateMouseAndMouseCursorPosition(1) }
    }

    var status: String {
        guard started else { return "Bluetooth not started" }
        if bluetoothState != 5 {
            return [0:"Checking Bluetooth…", 1:"Bluetooth resetting", 2:"Bluetooth unavailable",
                    3:"Bluetooth permission required", 4:"Bluetooth is off"][bluetoothState] ?? "Bluetooth unavailable"
        }
        return [0:"Disconnected", 1:"Connecting…", 2:"Initializing InputStick…",
                3:"Waiting for USB host", 4:"USB host asleep", 5:"Ready to send input"][connectionState] ?? "Unknown state"
    }
    var captureLabel: String {
        if session.rightCommandDown && session.active { return "Paused · Mac controls available" }
        if session.cursorLocked { return "Mouse locked · forwarding input" }
        return session.active ? "Forwarding inside this area" : "Mac control"
    }
    func log(_ message: String) {
        notice = message
        history.insert(message, at: 0)
        history = Array(history.prefix(8))
    }
    func refresh() {
        started = transport.started
        bluetoothState = transport.bluetoothState
        connectionState = transport.connectionState
        scanning = transport.scanning
        let nowReady = transport.ready && !disconnecting
        if ready && !nowReady { release("Control released: device is no longer ready.") }
        if !ready && nowReady { log("Connected and ready. Click the control area to begin forwarding.") }
        ready = nowReady
        var discovered: [NearbyDevice] = transport.devices.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return NearbyDevice(id: id, name: name, rssi: (item["rssi"] as? NSNumber)?.intValue ?? 0)
        }
        if let remembered = transport.lastDevice, let id = remembered["id"],
           !discovered.contains(where: { $0.id == id }) {
            discovered.append(NearbyDevice(id: id, name: remembered["name"] ?? "InputStick", rssi: 0))
        }
        // The SDK expires scan results after connecting. Keep the selected receiver
        // visible while connected so SwiftUI's Picker never points at a missing tag.
        if connectionState != 0, let selected = devices.first(where: { $0.id == selection }),
           !discovered.contains(where: { $0.id == selected.id }) {
            discovered.append(selected)
        }
        if !discovered.contains(where: { $0.id == selection }) { selection = discovered.first?.id }
        devices = discovered
    }
    func startBluetooth() { transport.start(); refresh() }
    func scan() { transport.scan(); log("Scanning for nearby InputStick devices for up to 15 seconds.") }
    func stopScan() { autoDiscover = false; transport.stopScan() }
    func resumeAutomatic() {
        automation.resume(); automaticPaused = false
        if !started { startBluetooth() }
    }
    private func runAutomatic() {
        guard started, !sleeping, !disconnecting else { return }
        let action = automation.next(now: Date.timeIntervalSinceReferenceDate,
            bluetoothOn: bluetoothState == 5, connectionState: connectionState,
            scanning: scanning, discover: autoDiscover, reconnect: autoReconnect,
            rememberedID: transport.lastDevice?["id"])
        // Only the poll timer drives actions. SDK notification refreshes cannot
        // recursively initiate another scan or connection attempt.
        switch action {
        case .scan: transport.scan()
        case .connect(let id):
            selection = id
            log("Reconnecting to your last InputStick…")
            transport.connect(id)
        case nil: break
        }
    }
    func connect() {
        guard let selection, devices.contains(where: { $0.id == selection }), !disconnecting else { return }
        automation.resume(); automaticPaused = false
        release(); transport.connect(selection); refresh()
    }
    func disconnect() {
        automation.paused = true; automaticPaused = true
        release(); disconnecting = true; ready = false
        transport.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.disconnecting = false; self?.refresh()
        }
    }
    func testHello() {
        guard ready, !session.active, !macroRunning else { return }
        startMacro("hello")
    }
    func typeClipboard() {
        guard ready, !session.active, !macroRunning else { return }
        // No clipboard polling, preview, persistence, or content in logs.
        guard let text = NSPasteboard.general.string(forType: .string) else {
            log("The clipboard does not contain text."); return
        }
        switch ClipboardMacro.prepare(text) {
        case .success(let text): startMacro(text)
        case .failure(.empty): log("The clipboard is empty.")
        case .failure(.tooLong): log("Clipboard typing supports up to 100,000 characters at once.")
        case .failure(.unsupportedCharacters):
            log("This US-layout macro supports English letters, numbers, punctuation, tabs, and line breaks. Nothing was sent; the clipboard contains unsupported characters.")
        }
    }
    private func startMacro(_ text: String) {
        macro.start(text); macroRunning = macro.active; macroLastProgress = Date()
        macroProgress = "Typing \(macro.total) characters…"
        log("Typing text on the receiving computer. Escape or Release all input stops it.")
    }
    func testMouse() {
        guard ready, !session.active, !macroRunning else { return }
        transport.sendMouse(0, x: 40, y: 0, wheel: 0)
        log("Queued a 40-unit movement to the right. Check the receiving computer; delivery is unverified.")
    }
    func begin() {
        guard ready, !macroRunning, NSApp.isActive, pad?.window?.isKeyWindow == true else { return }
        session.begin(ready: ready)
        guard session.active else { return }
        neutralize()
        log("Control started. Escape releases immediately. Hold Right Command for mouse lock.")
    }
    func toggleLock() {
        session.toggleLock(ready: ready)
        reconcileCursor()
    }
    func release(_ reason: String? = nil) {
        let wasActive = session.active || cursorDetached || macroRunning
        session.release()
        reconcileCursor(); neutralize()
        if wasActive, let reason { log(reason) }
    }
    private func neutralize() {
        macro.cancel(); macroRunning = false; macroProgress = ""
        keyboard.reset(); buttons = 0; mouse = MouseAccumulator()
        transport.releaseInputs()
    }
    private func reconcileCursor() {
        let shouldDetach = session.cursorLocked && ready && NSApp.isActive && pad?.window?.isKeyWindow == true
        guard shouldDetach != cursorDetached else { return }
        let result = CGAssociateMouseAndMouseCursorPosition(shouldDetach ? 0 : 1)
        if result == .success { cursorDetached = shouldDetach }
        else if shouldDetach {
            session.release(); neutralize()
            log("macOS refused mouse lock. Control was released.")
        } else {
            // Retry recoupling on every tick until macOS confirms success.
            log("Mouse release is awaiting macOS. Press Escape again if needed.")
        }
    }
    private func insidePad(_ event: NSEvent) -> Bool {
        guard let pad, event.window === pad.window else { return false }
        return pad.bounds.contains(pad.convert(event.locationInWindow, from: nil))
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard NSApp.isActive, event.window == nil || event.window === pad?.window else { return event }
        if event.type == .keyDown, event.keyCode == 53, session.active || macroRunning {
            release("Control released with Escape."); return nil
        }
        // Read every event, including the first click after focus returns, so a
        // Command key already held before activation cannot start capture.
        if session.updateControlKey(deviceFlags: event.modifierFlags.rawValue) {
            if session.active { neutralize() }
            reconcileCursor()
            if session.active && event.type == .flagsChanged { return nil }
        }
        if event.type == .leftMouseDown, !session.active, !macroRunning, !session.rightCommandDown, insidePad(event), ready {
            begin(); return nil // The activation click is never sent to the host.
        }
        guard session.forwarding, ready else { return event }
        let isPointer = ![NSEvent.EventType.keyDown, .keyUp, .flagsChanged].contains(event.type)
        if isPointer && !session.cursorLocked && !insidePad(event) {
            release("Control released: pointer left the control area."); return event
        }
        switch event.type {
        case .keyDown, .keyUp:
            guard !event.isARepeat else { return nil }
            keyboard.updateModifiers(deviceFlags: event.modifierFlags.rawValue)
            keyboard.update(keyCode: event.keyCode, down: event.type == .keyDown)
            sendKeyboard()
        case .flagsChanged:
            keyboard.updateModifiers(deviceFlags: event.modifierFlags.rawValue)
            if event.keyCode == 57 {
                // Caps Lock is a physical HID key, not a modifier bit.
                keyboard.update(keyCode: 57, down: true); sendKeyboard()
                keyboard.update(keyCode: 57, down: false)
            }
            sendKeyboard()
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            mouse.add(x: event.deltaX, y: event.deltaY)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown,
             .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard event.buttonNumber < 8 else { return nil }
            guard transport.mouseCanAccept else {
                release("Control released: Bluetooth mouse queue is busy."); return nil
            }
            // Never replay old movement as a drag after a new button edge.
            mouse = MouseAccumulator()
            let bit = UInt8(1 << event.buttonNumber)
            let down = [NSEvent.EventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
            if down { buttons |= bit } else { buttons &= ~bit }
            // Button edges are sent immediately; motion is paced by tick().
            transport.sendMouse(buttons, x: 0, y: 0, wheel: 0)
        case .scrollWheel:
            mouse.add(wheel: event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? 8 : 1))
        default: return event
        }
        return nil
    }
    private func sendKeyboard() {
        guard transport.keyboardCanAccept else {
            release("Control released: Bluetooth keyboard queue is busy."); return
        }
        transport.sendKeyboard(keyboard.report)
    }
    private func tick() {
        reconcileCursor()
        if macroRunning {
            guard transport.ready, ready, NSApp.isActive, !sleeping else {
                release("Text macro stopped: connection or focus changed."); return
            }
            if Date().timeIntervalSince(macroLastProgress) > 15 {
                release("Text macro stopped: the receiver stopped accepting text."); return
            }
            if let chunk = macro.next(ready: ready, keyboardIdle: transport.keyboardIdle) {
                transport.typeText(chunk)
                macroLastProgress = Date()
                macroProgress = "Typing text · \(macro.queued)/\(macro.total) queued"
            }
            if !macro.active {
                macroRunning = false; macroProgress = ""
                log("Text macro finished sending. Check the receiving computer for the result.")
            }
        }
        guard session.active else { return }
        guard transport.ready, NSApp.isActive, pad?.window?.isKeyWindow == true else {
            release("Control released: connection or focus changed."); return
        }
        guard session.forwarding, transport.mouseCanAccept else { return }
        let (x, y, wheel) = mouse.take()
        if x != 0 || y != 0 || wheel != 0 { transport.sendMouse(buttons, x: x, y: y, wheel: wheel) }
    }
}
