import Foundation

enum ConnectionAction: Equatable {
    case scan
    case connect(String)
}

/// Pure retry policy: remembered receivers only; no automatic input capture.
struct ConnectionAutomation {
    var paused = false
    private(set) var attempts = 0
    private(set) var nextAttempt = 0.0
    private var nextScan = 0.0

    mutating func resume() { paused = false; attempts = 0; nextAttempt = 0; nextScan = 0 }
    mutating func next(now: TimeInterval, bluetoothOn: Bool, connectionState: Int,
                       scanning: Bool, discover: Bool, reconnect: Bool,
                       rememberedID: String?) -> ConnectionAction? {
        guard !paused, bluetoothOn else { return nil }
        if connectionState == 5 { attempts = 0; nextAttempt = now + 2; return nil }
        guard connectionState == 0 else { return nil }
        if reconnect, let id = rememberedID, now >= nextAttempt {
            attempts = min(attempts + 1, 5)
            nextAttempt = now + min(30, pow(2, Double(attempts)))
            return .connect(id)
        }
        if discover, !scanning, now >= nextScan {
            nextScan = now + 20
            return .scan
        }
        return nil
    }
}

enum ClipboardMacroError: Error, Equatable {
    case empty, tooLong, unsupportedCharacters
}

struct ClipboardMacro {
    static func prepare(_ text: String) -> Result<String, ClipboardMacroError> {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.isEmpty else { return .failure(.empty) }
        guard normalized.utf8.count <= 100_000 else { return .failure(.tooLong) }
        guard normalized.unicodeScalars.allSatisfy({ (32...126).contains($0.value) || $0.value == 9 || $0.value == 10 }) else {
            return .failure(.unsupportedCharacters)
        }
        return .success(normalized)
    }
}

struct TextMacroQueue {
    private var pending = ""
    private(set) var active = false
    private(set) var total = 0
    private(set) var queued = 0
    mutating func start(_ text: String) {
        pending = text; active = !text.isEmpty; total = text.count; queued = 0
    }
    mutating func cancel() { pending = ""; active = false; total = 0; queued = 0 }
    /// Wait for both local AND receiver buffers before adding each bounded chunk.
    mutating func next(ready: Bool, keyboardIdle: Bool) -> String? {
        guard ready else { cancel(); return nil }
        guard active, keyboardIdle else { return nil }
        guard !pending.isEmpty else { active = false; return nil }
        let chunk = String(pending.prefix(32))
        pending.removeFirst(chunk.count); queued += chunk.count
        return chunk
    }
}

/// Pure state: no event hooks, Bluetooth, or cursor side effects.
struct CaptureSession {
    private(set) var active = false
    private(set) var lockRequested = false
    var rightCommandDown = false
    var forwarding: Bool { active && !rightCommandDown }
    var cursorLocked: Bool { forwarding && lockRequested }

    /// IOKit NX_DEVICERCMDKEYMASK. Distinguishes Right Command even with both held.
    mutating func updateControlKey(deviceFlags: UInt) -> Bool {
        let held = deviceFlags & 0x10 != 0
        guard held != rightCommandDown else { return false }
        rightCommandDown = held
        return true
    }

    mutating func begin(ready: Bool) {
        guard ready, !rightCommandDown else { return }
        active = true
    }
    mutating func toggleLock(ready: Bool) {
        guard ready, rightCommandDown, active else { return }
        lockRequested.toggle()
    }
    mutating func release() {
        active = false
        lockRequested = false
    }
}

struct HIDKeyboardState {
    private(set) var keys = Set<UInt8>()
    private(set) var modifiers: UInt8 = 0

    mutating func reset() { keys.removeAll(); modifiers = 0 }
    mutating func update(keyCode: UInt16, down: Bool) {
        guard let usage = Self.usages[keyCode] else { return }
        if down { keys.insert(usage) } else { keys.remove(usage) }
    }
    mutating func updateModifiers(deviceFlags: UInt) {
        // IOKit IOLLEvent.h device masks. Right Command is reserved for local controls.
        let masks: [(UInt, UInt8)] = [(0x1, 0x01), (0x2, 0x02), (0x20, 0x04),
                                     (0x2000, 0x10), (0x4, 0x20), (0x40, 0x40), (0x8, 0x08)]
        modifiers = masks.reduce(0) { $0 | (deviceFlags & $1.0 != 0 ? $1.1 : 0) }
    }
    var report: Data {
        // USB boot keyboards use ErrorRollOver in all six slots when over capacity.
        let slots = keys.count > 6 ? Array(repeating: UInt8(1), count: 6) : keys.sorted() + Array(repeating: 0, count: 6 - keys.count)
        return Data([modifiers, 0] + slots)
    }
    // Physical Apple key positions -> USB HID usages (ANSI plus ISO/JIS positions).
    // The receiving computer determines the layout. Fn/media/gestures are not mapped.
    static let usages: [UInt16: UInt8] = [
        0:4, 1:22, 2:7, 3:9, 4:11, 5:10, 6:29, 7:27, 8:6, 9:25,
        10:100, 11:5, 12:20, 13:26, 14:8, 15:21, 16:28, 17:23,
        18:30, 19:31, 20:32, 21:33, 22:35, 23:34, 24:46, 25:38,
        26:36, 27:45, 28:37, 29:39, 30:48, 31:18, 32:24, 33:47,
        34:12, 35:19, 36:40, 37:15, 38:13, 39:52, 40:14, 41:51,
        42:49, 43:54, 44:56, 45:17, 46:16, 47:55, 48:43, 49:44,
        50:53, 51:42, 53:41, 57:57, 65:99, 67:85, 69:87, 71:83,
        75:84, 76:88, 78:86, 81:103, 82:98, 83:89, 84:90, 85:91,
        86:92, 87:93, 88:94, 89:95, 91:96, 92:97, 93:137, 94:135,
        95:133, 96:62, 97:63, 98:64, 99:60, 100:65, 101:66,
        103:68, 105:104, 106:107, 107:105, 109:67, 111:69, 113:106,
        114:73, 115:74, 116:75, 117:76, 118:61, 119:77, 120:59,
        121:78, 122:58, 123:80, 124:79, 125:81, 126:82
    ]
}

struct MouseAccumulator {
    private(set) var x = 0.0, y = 0.0, wheel = 0.0
    mutating func add(x: Double = 0, y: Double = 0, wheel: Double = 0) {
        // Bound delayed motion during a slow Bluetooth link.
        self.x = max(-512, min(512, self.x + x))
        self.y = max(-512, min(512, self.y + y))
        self.wheel = max(-127, min(127, self.wheel + wheel))
    }
    mutating func take() -> (Int8, Int8, Int8) {
        let dx = Int8(max(-127, min(127, x.rounded(.towardZero))))
        let dy = Int8(max(-127, min(127, y.rounded(.towardZero))))
        let dw = Int8(max(-127, min(127, wheel.rounded(.towardZero))))
        x -= Double(dx); y -= Double(dy); wheel -= Double(dw)
        return (dx, dy, dw)
    }
}
