import SwiftUI

/// Edits a copy of a layout; changes are committed with `model.update(_:apply:)`.
struct LayoutEditorView: View {
    let model: AppModel
    let isConnected: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Layout
    @State private var selectedDisplayID: String?

    init(model: AppModel, layout: Layout, isConnected: Bool) {
        self.model = model
        self.isConnected = isConnected
        _draft = State(initialValue: layout)
        _selectedDisplayID = State(initialValue: layout.snapshot.mainDisplayID)
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var issue: String? { draft.snapshot.arrangementIssue }
    private var canSave: Bool { !trimmedName.isEmpty && issue == nil && !model.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }
                arrangementSection
                if let display = selectedDisplay {
                    DisplayInspector(
                        model: model,
                        snapshot: $draft.snapshot,
                        selectedDisplayID: $selectedDisplayID,
                        display: display
                    )
                }
                shortcutSection
            }
            .formStyle(.grouped)

            footer
        }
        .frame(width: 680, height: 600)
    }

    private var selectedDisplay: DisplaySpec? {
        selectedDisplayID.flatMap { draft.snapshot.display(withID: $0) }
            ?? draft.snapshot.mainDisplayID.flatMap { draft.snapshot.display(withID: $0) }
    }

    // MARK: Arrangement

    private enum ArrangementMode: Hashable {
        case extend, mirror, mixed
    }

    private var arrangementMode: Binding<ArrangementMode> {
        Binding(
            get: {
                if draft.snapshot.isMirroringAll { return .mirror }
                return draft.snapshot.isExtendingAll ? .extend : .mixed
            },
            set: { mode in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    switch mode {
                    case .mirror: draft.snapshot.mirrorAll()
                    case .extend: draft.snapshot.extendAll()
                    case .mixed: break
                    }
                }
            }
        )
    }

    private var arrangementSection: some View {
        Section {
            ArrangementCanvas(snapshot: $draft.snapshot, selectedID: $selectedDisplayID, model: model)
                .frame(height: 200)
        } header: {
            HStack {
                Text("Arrangement")
                Spacer()
                if draft.snapshot.displays.count > 1 {
                    Picker("Arrangement", selection: arrangementMode) {
                        Text("Extend").tag(ArrangementMode.extend)
                        Text("Mirror").tag(ArrangementMode.mirror)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    .help("Extend the desktop across all displays, or show the main display on every display")
                }
            }
        } footer: {
            if draft.snapshot.unmirroredDisplays.count > 1 {
                Text("Drag displays to arrange them, or select one and use the arrow keys. The main display has the menu bar.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Shortcut

    private var shortcutSection: some View {
        Section {
            LabeledContent("Keyboard shortcut") {
                HotkeyRecorder(hotkey: $draft.hotkey, model: model)
            }
        } footer: {
            if let hotkey = draft.hotkey, let other = model.layout(using: hotkey, except: draft.id) {
                Label("“\(other.name)” uses this shortcut. Saving moves it to this layout.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Text("Press the shortcut in any app to switch to this layout.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel("Can’t save: \(issue)")
            }
            Spacer(minLength: 0)
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save(apply: false) }
                .keyboardShortcut(isConnected ? nil : .defaultAction)
                .disabled(!canSave)
            Button("Save and Apply") { save(apply: true) }
                .keyboardShortcut(isConnected ? .defaultAction : nil)
                .disabled(!canSave || !isConnected)
                .help(isConnected ? "Save the layout and switch to it" : "Connect these displays to apply this layout")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func save(apply: Bool) {
        var layout = draft
        layout.name = trimmedName
        if model.update(layout, apply: apply) {
            dismiss()
        }
    }
}

/// Settings for the display selected on the canvas.
private struct DisplayInspector: View {
    let model: AppModel
    @Binding var snapshot: LayoutSnapshot
    @Binding var selectedDisplayID: String?
    let display: DisplaySpec

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Role: Hashable {
        case main, extended, mirror(String)
    }

    var body: some View {
        Section {
            if snapshot.displays.count > 1 {
                Picker("Display", selection: selection) {
                    ForEach(snapshot.displays, id: \.id) { candidate in
                        Text(label(for: candidate)).tag(candidate.id)
                    }
                }
                Picker("Use as", selection: role) {
                    Text("Main Display").tag(Role.main)
                    if canBeExtended {
                        Text("Extended Display").tag(Role.extended)
                    }
                    let sources = snapshot.unmirroredDisplays.filter { $0.id != display.id }
                    if !sources.isEmpty {
                        Divider()
                        ForEach(sources, id: \.id) { source in
                            Text("Mirror of \(model.displayLabel(for: source))").tag(Role.mirror(source.id))
                        }
                    }
                }
            }
            Picker("Resolution", selection: mode) {
                let modes = display.selectableModes
                let hiDPI = modes.filter(\.isHiDPI)
                let standard = modes.filter { !$0.isHiDPI }
                ForEach(hiDPI, id: \.self) { Text($0.menuLabel).tag($0) }
                if !hiDPI.isEmpty, !standard.isEmpty { Divider() }
                ForEach(standard, id: \.self) { Text($0.menuLabel).tag($0) }
            }
            .disabled(display.selectableModes.count < 2)
            if display.rotation != 0 {
                LabeledContent("Rotation", value: "\(Int(display.rotation))°")
            }
        } header: {
            Text(model.displayLabel(for: display))
        } footer: {
            if display.availableModes == nil {
                Text("Save this layout again with the display connected to choose other resolutions.")
                    .foregroundStyle(.secondary)
            } else if display.rotation != 0 {
                Text("Change rotation in System Settings, then replace the layout with the current arrangement.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(for candidate: DisplaySpec) -> String {
        let name = model.displayLabel(for: candidate)
        return candidate.mirrorSourceID == nil ? name : "\(name) (Mirrored)"
    }

    /// The only unmirrored display must stay main.
    private var canBeExtended: Bool {
        display.mirrorSourceID != nil || !snapshot.isMain(display.id)
            || snapshot.unmirroredDisplays.count > 1
    }

    private var selection: Binding<String> {
        Binding(get: { display.id }, set: { selectedDisplayID = $0 })
    }

    private var role: Binding<Role> {
        Binding(
            get: {
                if let source = display.mirrorSourceID { return .mirror(source) }
                return snapshot.isMain(display.id) ? .main : .extended
            },
            set: { role in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    switch role {
                    case .main: snapshot.makeMain(display.id)
                    case .extended: snapshot.makeExtended(display.id)
                    case .mirror(let source): snapshot.mirror(display.id, of: source)
                    }
                }
            }
        )
    }

    private var mode: Binding<DisplayModeSpec> {
        Binding(
            get: { display.mode },
            set: { mode in
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    snapshot.setMode(mode, for: display.id)
                }
            }
        )
    }
}
