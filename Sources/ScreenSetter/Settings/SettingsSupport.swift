import AppKit
import SwiftUI

// Small helpers shared by the Settings and Onboarding views.

extension AppModel {
    /// The remembered name for a display, falling back to the name stored in the layout.
    func displayLabel(for display: DisplaySpec) -> String {
        let remembered = displayName(for: display.id)
        if remembered == "Display", !display.name.isEmpty { return display.name }
        return remembered
    }

    /// The displays of a display set, built-in first, from its first layout.
    func displays(inGroup groupID: String) -> [DisplaySpec] {
        guard let layout = library.layouts.first(where: { $0.groupID == groupID }) else { return [] }
        return layout.snapshot.displays.sorted { lhs, rhs in
            if lhs.builtIn != rhs.builtIn { return lhs.builtIn }
            return displayLabel(for: lhs).localizedStandardCompare(displayLabel(for: rhs)) == .orderedAscending
        }
    }

    /// Another layout that already uses `hotkey`, if any.
    func layout(using hotkey: Hotkey, except id: UUID) -> Layout? {
        library.layouts.first {
            $0.id != id && $0.hotkey?.isSameShortcut(as: hotkey) == true
        }
    }
}

extension DisplayModeSpec {
    var isHiDPI: Bool { pixelWidth > width }

    var refreshRateLabel: String? {
        guard refreshRate > 0, refreshRate.isFinite else { return nil }
        let rounded = refreshRate.rounded()
        if abs(refreshRate - rounded) < 0.01 { return "\(Int(rounded)) Hz" }
        return String(format: "%.2f Hz", refreshRate)
    }

    var resolutionLabel: String { "\(width) × \(height)" }

    /// "1512 × 982 (HiDPI) · 120 Hz"
    var menuLabel: String {
        var label = resolutionLabel
        if isHiDPI { label += " (HiDPI)" }
        if let refreshRateLabel { label += " · " + refreshRateLabel }
        return label
    }

    /// Sorting for resolution menus: HiDPI first, then larger, then faster.
    static func menuOrder(_ lhs: DisplayModeSpec, _ rhs: DisplayModeSpec) -> Bool {
        if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
        if lhs.width != rhs.width { return lhs.width > rhs.width }
        if lhs.height != rhs.height { return lhs.height > rhs.height }
        return lhs.refreshRate > rhs.refreshRate
    }
}

extension DisplaySpec {
    /// The modes offered in the editor. The current mode is always included; old
    /// profiles without `availableModes` offer only the current mode.
    var selectableModes: [DisplayModeSpec] {
        var modes: [DisplayModeSpec] = []
        for candidate in availableModes ?? [] {
            let equivalent = candidate.width == mode.width && candidate.height == mode.height
                && candidate.pixelWidth == mode.pixelWidth && candidate.pixelHeight == mode.pixelHeight
                && abs(candidate.refreshRate - mode.refreshRate) <= 0.1
            let entry = equivalent ? mode : candidate
            if !modes.contains(entry) { modes.append(entry) }
        }
        if !modes.contains(mode) { modes.append(mode) }
        return modes.sorted(by: DisplayModeSpec.menuOrder)
    }
}

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/andrea-lonardo/screen-setter")!
    static let releasesURL = URL(string: "https://github.com/andrea-lonardo/screen-setter/releases")!
    static let privacyURL = URL(string: "https://andrea-lonardo.github.io/screen-setter/privacy/")!

    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "—"
        let build = info["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    /// The MIT license text bundled in Contents/Resources by build.sh.
    static var licenseURL: URL? { Bundle.main.url(forResource: "LICENSE", withExtension: nil) }

    /// The URL schemes the app handles: its own, then the one used before the rename.
    static let urlSchemes = ["screensetter", "displaylayouts"]

    /// `screensetter://apply/<name>` with the name percent-encoded.
    static func applyURL(forLayoutNamed name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
        return "screensetter://apply/" + encoded
    }
}

/// Asks for a name and saves the current display arrangement as a new layout.
struct SaveArrangementSheet: View {
    let model: AppModel
    var onSaved: (Layout) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var suggestedName = ""
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(suggestedName))
                        .focused($nameFocused)
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save Current Arrangement")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Saves how your displays are set up right now — their arrangement, main display, mirroring and resolution — as a new layout.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textCase(nil)
                    .padding(.bottom, 6)
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Arrange your displays in System Settings first.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("macOS Display Settings…") { model.openDisplaySettings() }
                            .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                if isSaving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || model.isBusy)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            suggestedName = model.suggestedArrangementName()
            name = suggestedName
            nameFocused = true
        }
    }

    private func save() {
        isSaving = true
        let requested = trimmedName.isEmpty ? nil : trimmedName
        model.saveCurrentArrangement(named: requested) { layout in
            isSaving = false
            guard let layout else { return }
            onSaved(layout)
            dismiss()
        }
    }
}
