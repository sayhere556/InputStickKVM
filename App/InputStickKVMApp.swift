import SwiftUI
import AppKit

@main
struct InputStickKVMApp: App {
    @StateObject private var model = KVMModel()
    var body: some Scene {
        Window("InputStick KVM", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 850, minHeight: 680)
        }
        .defaultSize(width: 980, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Control") {
                Button("Release All Input") { model.release("Control released from menu.") }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: KVMModel
    private let accent = Color(red: 0.27, green: 0.72, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("InputStick KVM").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Your Mac’s keyboard and trackpad. Your other computer.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("DEVELOPMENT BUILD", systemImage: "hammer")
                    .font(.caption.weight(.semibold)).padding(9)
                    .background(accent.opacity(0.13), in: Capsule())
            }
            HStack(alignment: .top, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.status, systemImage: model.ready ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(model.ready ? .green : .primary)
                        if !model.started {
                            Text("Enable Bluetooth to discover your InputStick.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Enable Bluetooth") { model.startBluetooth() }.buttonStyle(.borderedProminent)
                        } else {
                            HStack {
                                Button(model.scanning ? "Stop scan" : "Scan for InputStick") {
                                    if model.scanning { model.stopScan() } else { model.scan() }
                                }.disabled(model.bluetoothState != 5 || model.connectionState != 0 || model.disconnecting)
                                if model.scanning { ProgressView().controlSize(.small) }
                                Spacer()
                            }
                            Picker("Device", selection: $model.selection) {
                                Text(model.devices.isEmpty ? "No devices discovered" : "Choose a device").tag(String?.none)
                                ForEach(model.devices) { device in
                                    Text("\(device.name) · \(device.id.prefix(8))").tag(Optional(device.id))
                                }
                            }.disabled(model.connectionState != 0)
                            HStack {
                                Button("Connect") { model.connect() }
                                    .disabled(model.selection == nil || !model.devices.contains(where: { $0.id == model.selection }) || model.bluetoothState != 5 || model.connectionState != 0 || model.disconnecting)
                                Button(model.connectionState == 1 || model.connectionState == 2 ? "Cancel connection" : "Disconnect") { model.disconnect() }
                                    .disabled(model.connectionState == 0 || model.disconnecting)
                            }
                        }
                        HStack {
                            Toggle("Auto-discover", isOn: $model.autoDiscover)
                            Toggle("Reconnect", isOn: $model.autoReconnect)
                        }.font(.caption).toggleStyle(.checkbox)
                        if model.automaticPaused {
                            HStack {
                                Text("Automatic connection paused").font(.caption).foregroundStyle(.secondary)
                                Button("Resume") { model.resumeAutomatic() }.controlSize(.small)
                            }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading).padding(8)
                } label: { Label("1  Connect", systemImage: "cable.connector") }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open an empty document on the receiving computer first.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Type “hello”") { model.testHello() }
                            Button("Move pointer →") { model.testMouse() }
                        }.disabled(!model.ready || model.session.active || model.macroRunning)
                        Button { model.typeClipboard() } label: {
                            Label("Type clipboard", systemImage: "doc.on.clipboard")
                        }.disabled(!model.ready || model.session.active || model.macroRunning)
                        if model.macroRunning {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text(model.macroProgress).font(.caption.monospacedDigit())
                                Button("Stop") { model.release("Text macro stopped.") }.controlSize(.small)
                            }
                        }
                        Text("Types text using the US layout, including tabs and line breaks. Clipboard is read only when clicked.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading).padding(8)
                } label: { Label("2  Macros", systemImage: "keyboard") }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("3  Control area", systemImage: "cursorarrow.motionlines").font(.headline)
                    Spacer()
                    Button("Release all input") { model.release("All input released.") }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                HStack {
                    Label(model.accessibilityGranted ? "Keyboard capture permission enabled" : "Accessibility permission needed for keyboard capture",
                          systemImage: model.accessibilityGranted ? "checkmark.shield" : "hand.raised")
                        .font(.caption)
                    Spacer()
                    if !model.accessibilityGranted {
                        Button("Enable keyboard capture") { model.requestKeyboardAccess() }
                    } else if !model.session.active {
                        Button("Start control") { model.begin() }.disabled(!model.ready || model.macroRunning)
                    }
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(accent.opacity(model.session.active ? 0.12 : 0.05))
                    RoundedRectangle(cornerRadius: 18).strokeBorder(accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: model.session.active ? [] : [7, 5]))
                    PadView(model: model)
                    VStack(spacing: 12) {
                        Image(systemName: model.session.cursorLocked ? "lock.fill" : "cursorarrow")
                            .font(.system(size: 38, weight: .light)).foregroundStyle(accent)
                        Text(model.captureLabel).font(.title3.weight(.medium))
                        Text(model.ready ? "Click here to begin · Escape to release" : "Connect an InputStick to begin")
                            .foregroundStyle(.secondary)
                        Text("Hold Right ⌘ to reveal mouse lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }.allowsHitTesting(false)
                    if model.session.rightCommandDown {
                        VStack {
                            Spacer()
                            Button {
                                model.toggleLock()
                            } label: {
                                Label(model.session.lockRequested ? "Unlock mouse" : "Lock mouse on ⌘ release",
                                      systemImage: model.session.lockRequested ? "lock.open" : "lock")
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.ready || !model.session.active)
                            .padding(.bottom, 16)
                        }
                    }
                }.frame(minHeight: 235)
                Text("Capture blocks app switching · Right ⌘ temporarily restores Mac controls · Escape releases all input.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(accent)
                Text(model.notice).font(.callout).textSelection(.enabled)
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Text("Check results on the receiving computer · No screen/video streaming")
                Spacer()
                Text("Escape = release").fontWeight(.medium)
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(26)
        .tint(accent)
        .onDisappear { model.release("Control released: window closed.") }
    }
}

struct PadView: NSViewRepresentable {
    let model: KVMModel
    func makeNSView(context: Context) -> NSView {
        let view = ControlPadView()
        model.pad = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { model.pad = nsView }
}

final class ControlPadView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }
}
