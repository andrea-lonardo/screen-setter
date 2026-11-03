import AppKit
import SwiftUI

/// Records a global keyboard shortcut. While recording, global hotkeys are
/// suspended through `model.isRecordingHotkey`.
struct HotkeyRecorder: View {
    @Binding var hotkey: Hotkey?
    let model: AppModel

    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []

    var body: some View {
        HStack(spacing: 6) {
            recordButton
                .background(
                    KeyCaptureBridge(
                        isRecording: $isRecording,
                        onModifiersChanged: { liveModifiers = $0 },
                        onCapture: { captured in
                            hotkey = captured
                            isRecording = false
                        }
                    )
                )
            if hotkey != nil, !isRecording {
                Button {
                    hotkey = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear Shortcut")
                .accessibilityLabel("Clear Shortcut")
            }
        }
        .onChange(of: isRecording) { _, recording in
            liveModifiers = []
            model.isRecordingHotkey = recording
        }
        .onDisappear {
            isRecording = false
            model.isRecordingHotkey = false
        }
    }

    @ViewBuilder private var recordButton: some View {
        let button = Button {
            isRecording.toggle()
        } label: {
            Text(title)
                .monospacedDigit()
                .frame(minWidth: 132)
        }
        .accessibilityLabel("Keyboard shortcut")
        .accessibilityValue(isRecording ? "Recording" : (hotkey?.displayString ?? "None"))
        .accessibilityHint(isRecording
            ? "Type a key combination, press Escape to cancel, or Delete to remove the shortcut."
            : "Records a new shortcut.")
        .help(isRecording ? "Type a shortcut, or press Escape to cancel" : "Click to record a shortcut")

        if isRecording {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var title: String {
        if isRecording {
            let modifiers = HotkeyCapture.modifierSymbols(liveModifiers)
            return modifiers.isEmpty ? "Type Shortcut…" : modifiers + "…"
        }
        return hotkey?.displayString ?? "Record Shortcut"
    }
}

/// Converts key events into `Hotkey` values.
enum HotkeyCapture {
    static let functionKeyCodes: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static let specialKeyNames: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        49: "Space", 36: "↩", 76: "⌤", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 114: "Help",
    ]

    static let escapeKeyCode: UInt16 = 53
    static let deleteKeyCodes: Set<UInt16> = [51, 117]
    static let tabKeyCode: UInt16 = 48

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= Hotkey.command }
        if flags.contains(.shift) { result |= Hotkey.shift }
        if flags.contains(.option) { result |= Hotkey.option }
        if flags.contains(.control) { result |= Hotkey.control }
        return result
    }

    static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    static func keyName(for event: NSEvent) -> String {
        if let name = functionKeyCodes[event.keyCode] ?? specialKeyNames[event.keyCode] {
            return name
        }
        let characters = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? "Key \(event.keyCode)" : trimmed.uppercased()
    }

    enum Outcome {
        case capture(Hotkey)
        case clear
        case cancel
        case passThrough
        case reject
    }

    static func outcome(for event: NSEvent) -> Outcome {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let hasPrimaryModifier = !flags.intersection([.command, .option, .control]).isEmpty
        let isFunctionKey = functionKeyCodes[event.keyCode] != nil

        if !hasPrimaryModifier {
            if event.keyCode == escapeKeyCode, flags.isEmpty { return .cancel }
            if deleteKeyCodes.contains(event.keyCode), flags.isEmpty { return .clear }
            if event.keyCode == tabKeyCode { return .passThrough }
            if !isFunctionKey { return .reject }
        }
        return .capture(Hotkey(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(flags),
            key: keyName(for: event)
        ))
    }
}

/// An invisible view placed behind the record button. While recording it becomes
/// first responder and captures key events with a local monitor, so shortcuts
/// that would otherwise trigger menus or buttons are recorded instead.
private struct KeyCaptureBridge: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onModifiersChanged: (NSEvent.ModifierFlags) -> Void
    var onCapture: (Hotkey?) -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        KeyCaptureView()
    }

    func updateNSView(_ view: KeyCaptureView, context: Context) {
        view.onModifiersChanged = onModifiersChanged
        view.onCapture = onCapture
        view.onEnd = { isRecording = false }
        view.setRecording(isRecording)
    }

    static func dismantleNSView(_ view: KeyCaptureView, coordinator: ()) {
        view.setRecording(false)
    }
}

private final class KeyCaptureView: NSView {
    var onModifiersChanged: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onCapture: (Hotkey?) -> Void = { _ in }
    var onEnd: () -> Void = {}

    private var monitor: Any?

    override var acceptsFirstResponder: Bool { monitor != nil }

    override func resignFirstResponder() -> Bool {
        if monitor != nil {
            stopMonitoring()
            onEnd()
        }
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, monitor != nil { end() }
    }

    func setRecording(_ recording: Bool) {
        if recording, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                // Local monitors run on the main thread.
                let box = EventBox(event: event)
                let passThrough = MainActor.assumeIsolated { self?.handle(box.event) ?? true }
                return passThrough ? event : nil
            }
            window?.makeFirstResponder(self)
            NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
        } else if !recording, monitor != nil {
            stopMonitoring()
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func end() {
        setRecording(false)
        onEnd()
    }

    /// Returns true when the event should continue to the app.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .flagsChanged:
            onModifiersChanged(event.modifierFlags.intersection([.command, .option, .control, .shift]))
            return true
        case .leftMouseDown, .rightMouseDown:
            // Any click ends recording. A click on the record button itself is
            // consumed so it does not start recording again.
            let location = convert(event.locationInWindow, from: nil)
            let onButton = event.window === window && bounds.contains(location)
            end()
            return !onButton
        case .keyDown:
            guard event.window === window else { return true }
            if event.isARepeat { return false }
            switch HotkeyCapture.outcome(for: event) {
            case .capture(let hotkey):
                setRecording(false)
                onCapture(hotkey)
            case .clear:
                setRecording(false)
                onCapture(nil)
            case .cancel:
                end()
            case .passThrough:
                end()
                return true
            case .reject:
                NSSound.beep()
            }
            return false
        default:
            return true
        }
    }
}

private struct EventBox: @unchecked Sendable {
    let event: NSEvent
}
