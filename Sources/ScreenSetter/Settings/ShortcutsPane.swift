import AppKit
import SwiftUI

/// Every layout's keyboard shortcut in one place, grouped by display set.
struct ShortcutsPane: View {
    let model: AppModel

    var body: some View {
        if model.library.layouts.isEmpty {
            ContentUnavailableView(
                "No Layouts",
                systemImage: "command",
                description: Text("Save a layout, then give it a keyboard shortcut here.")
            )
        } else {
            Form {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(model.layouts(inGroup: group.id)) { layout in
                            ShortcutRow(model: model, layout: layout)
                        }
                    } header: {
                        GroupSectionHeader(model: model, group: group)
                    } footer: {
                        if group.id == model.groups.last?.id {
                            Text("Press a layout’s shortcut in any app to switch to it. Giving a layout a shortcut another layout uses moves the shortcut.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct ShortcutRow: View {
    let model: AppModel
    let layout: Layout

    var body: some View {
        LabeledContent {
            HotkeyRecorder(hotkey: binding, model: model)
        } label: {
            HStack(spacing: 10) {
                LayoutThumbnailView(snapshot: layout.snapshot, isActive: model.activeLayoutID == layout.id)
                    .frame(width: 34, height: 24)
                    .accessibilityHidden(true)
                Text(layout.name)
                    .lineLimit(1)
            }
        }
    }

    private var binding: Binding<Hotkey?> {
        Binding(
            get: { layout.hotkey },
            set: { model.setHotkey($0, for: layout.id) }
        )
    }
}

/// A display set's name for section headers, marked when it is connected.
struct GroupSectionHeader: View {
    let model: AppModel
    let group: DisplayGroup

    var body: some View {
        HStack(spacing: 6) {
            Text(model.name(of: group))
            if model.isConnected(group) {
                Text("Connected")
                    .fontWeight(.regular)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
