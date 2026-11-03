import AppKit
import Carbon.HIToolbox
import Observation

/// Registers each layout's global keyboard shortcut with the Carbon hot key API,
/// which works without Accessibility permission. Shortcuts are suspended while
/// Settings records a new one, and re-registered whenever the library changes.
@MainActor
final class HotkeyCenter {
    private struct Registration: Equatable {
        var hotkey: Hotkey
        var layoutID: UUID
        var name: String
    }

    private static let signature: OSType = 0x444C_686B // "DLhk"
    private static weak var current: HotkeyCenter?

    private let model: AppModel
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var layoutsByHotkeyID: [UInt32: UUID] = [:]
    private var registered: [Registration] = []
    private var nextID: UInt32 = 1

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard !model.isPreview else { return }
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, &handler)
        if status != noErr {
            NSLog("Screen Setter: could not install the keyboard shortcut handler (%d).", status)
            model.setHotkeyIssue("Keyboard shortcuts are unavailable because macOS refused the shortcut handler (error \(status)).")
            return
        }
        observeChanges(of: { [weak self] in self?.desiredRegistrations() }) { [weak self] in
            self?.synchronize()
        }
    }

    /// The shortcuts that should be active right now; empty while recording.
    private func desiredRegistrations() -> [Registration] {
        guard !model.isRecordingHotkey else { return [] }
        return model.library.layouts.compactMap { layout in
            layout.hotkey.map { Registration(hotkey: $0, layoutID: layout.id, name: layout.name) }
        }
    }

    private func synchronize() {
        let desired = desiredRegistrations()
        guard desired != registered else { return }
        unregisterAll()

        var failures: [String] = []
        for registration in desired {
            let id = nextID
            nextID &+= 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                registration.hotkey.keyCode, registration.hotkey.modifiers,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[id] = ref
                layoutsByHotkeyID[id] = registration.layoutID
            } else {
                NSLog("Screen Setter: shortcut %@ for “%@” could not be registered (%d).",
                      registration.hotkey.displayString, registration.name, status)
                failures.append("\(registration.hotkey.displayString) (“\(registration.name)”)")
            }
        }
        registered = desired

        if failures.isEmpty {
            model.setHotkeyIssue(nil)
        } else {
            let list = ListFormatter.localizedString(byJoining: failures)
            model.setHotkeyIssue("macOS couldn’t register \(list). Another app may already use \(failures.count == 1 ? "this shortcut" : "these shortcuts"). Choose a different shortcut in Settings.")
        }
    }

    private func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        layoutsByHotkeyID.removeAll()
        registered.removeAll()
    }

    fileprivate static func hotkeyPressed(_ id: UInt32) {
        guard let center = current, let layoutID = center.layoutsByHotkeyID[id] else { return }
        guard let layout = center.model.layout(id: layoutID) else { return }
        guard !center.model.isBusy else { NSSound.beep(); return }
        center.model.requestApply(layout)
    }
}

private func hotKeyEventHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    // Carbon delivers hot key events on the main thread; defer past the event dispatch.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotkeyCenter.hotkeyPressed(id) }
    }
    return noErr
}

/// Calls `action` on main whenever any observable value read by `read` changes.
/// `action` also runs once immediately. Changes are coalesced: tracking resumes
/// on the next main-queue turn, then `action` runs again.
@MainActor
func observeChanges<Value>(of read: @escaping @MainActor () -> Value, perform action: @escaping @MainActor () -> Void) {
    withObservationTracking {
        _ = read()
    } onChange: {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { observeChanges(of: read, perform: action) }
        }
    }
    action()
}
