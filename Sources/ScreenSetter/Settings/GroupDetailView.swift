import SwiftUI

/// The layouts of one display set, plus its automatic layout.
struct GroupDetailView: View {
    let model: AppModel
    let group: DisplayGroup

    @State private var editing: Layout?
    @State private var renaming: Layout?
    @State private var renameText = ""
    @State private var deleting: Layout?
    @State private var replacing: Layout?

    private var layouts: [Layout] { model.layouts(inGroup: group.id) }
    private var isConnected: Bool { model.isConnected(group) }

    var body: some View {
        Form {
            Section {
                GroupHeader(model: model, group: group, isConnected: isConnected)
            }
            layoutsSection
            automaticSection
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { layout in
            LayoutEditorView(model: model, layout: layout, isConnected: isConnected)
        }
        .alert("Rename Layout", isPresented: $renaming.isPresented, presenting: renaming) { layout in
            TextField("Name", text: $renameText, prompt: Text(layout.name))
            Button("Rename") { commitRename(layout) }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(DeleteConfirmation(model: model, deleting: $deleting, isLast: layouts.count == 1))
        .modifier(ReplaceConfirmation(model: model, replacing: $replacing))
    }

    private var layoutsSection: some View {
        let layouts = layouts
        let connected = isConnected
        return Section {
            ForEach(layouts) { layout in
                LayoutRow(model: model, layout: layout, isConnected: connected, onEdit: { editing = layout }) {
                    actions(for: layout, in: layouts, includeMoves: false)
                }
                .contextMenu { actions(for: layout, in: layouts, includeMoves: true) }
            }
            .onMove { source, destination in
                model.moveLayouts(inGroup: group.id, from: source, to: destination)
            }
        } header: {
            Text("Layouts")
        } footer: {
            Text(connected
                ? "Double-click a layout to edit it. Drag layouts to change their order in the menu."
                : "Connect these displays to apply their layouts. You can still edit them.")
                .foregroundStyle(.secondary)
        }
    }

    private var automaticSection: some View {
        Section {
            Picker("When these displays connect", selection: automaticBinding) {
                Text("Do Nothing").tag(UUID?.none)
                Divider()
                ForEach(layouts) { layout in
                    Text(layout.name).tag(UUID?.some(layout.id))
                }
            }
        } header: {
            Text("Automatic")
        } footer: {
            Text("The layout is applied when this exact set of displays connects, as long as their resolution, mirroring and rotation still match it.")
                .foregroundStyle(.secondary)
        }
    }

    private func commitRename(_ layout: Layout) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != layout.name { model.rename(layout.id, to: name) }
    }

    private var automaticBinding: Binding<UUID?> {
        Binding(
            get: { model.automaticLayoutID(inGroup: group.id) },
            set: { model.setAutomaticLayout(inGroup: group.id, layoutID: $0) }
        )
    }

    @ViewBuilder
    private func actions(for layout: Layout, in layouts: [Layout], includeMoves: Bool) -> some View {
        Button("Edit…") { editing = layout }
        Button("Rename…") {
            renameText = layout.name
            renaming = layout
        }
        Button("Duplicate") { model.duplicate(layout.id) }
            .disabled(model.isBusy)
        if includeMoves, layouts.count > 1, let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            Divider()
            Button("Move Up") {
                model.moveLayouts(inGroup: group.id, from: IndexSet(integer: index), to: index - 1)
            }
            .disabled(index == 0)
            Button("Move Down") {
                model.moveLayouts(inGroup: group.id, from: IndexSet(integer: index), to: index + 2)
            }
            .disabled(index == layouts.count - 1)
        }
        Divider()
        Button("Replace with Current Arrangement…") { replacing = layout }
            .disabled(!isConnected || model.isBusy)
        Divider()
        Button("Delete…", role: .destructive) { deleting = layout }
            .disabled(model.isBusy)
    }
}

private struct GroupHeader: View {
    let model: AppModel
    let group: DisplayGroup
    let isConnected: Bool

    var body: some View {
        let displays = model.displays(inGroup: group.id)
        HStack(spacing: 12) {
            Image(systemName: displays.count > 1 ? "display.2" : "display")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name(of: group))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(group.customName == nil
                    ? (displays.count == 1 ? "1 display" : "\(displays.count) displays")
                    : displays.map { model.displayLabel(for: $0) }.formatted(.list(type: .and)))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if isConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .labelStyle(ConnectedLabelStyle())
            } else {
                Text("Not Connected")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct ConnectedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.green)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

private struct LayoutRow<Actions: View>: View {
    let model: AppModel
    let layout: Layout
    let isConnected: Bool
    let onEdit: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        let isActive = model.activeLayoutID == layout.id
        HStack(spacing: 12) {
            LayoutThumbnailView(snapshot: layout.snapshot, isActive: isActive)
                .frame(width: 46, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(layout.name)
                        .lineLimit(1)
                    if isActive {
                        Label("Current", systemImage: "checkmark")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Current layout")
                    }
                }
                Text(model.summary(for: layout))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let hotkey = layout.hotkey {
                HotkeyBadge(hotkey: hotkey)
            }
            Button("Apply") { model.apply(layout.id) }
                .disabled(!isConnected || model.isBusy)
                .help(isConnected ? "Switch to this layout" : "Connect these displays to apply this layout")
            Menu {
                actions()
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More Actions")
            .accessibilityLabel("More Actions")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit") { onEdit() }
    }
}

extension Binding where Value == Layout? {
    /// True while a layout is set; setting it to false clears the layout.
    var isPresented: Binding<Bool> {
        Binding<Bool>(get: { wrappedValue != nil }, set: { if !$0 { wrappedValue = nil } })
    }
}

private struct DeleteConfirmation: ViewModifier {
    let model: AppModel
    @Binding var deleting: Layout?
    let isLast: Bool

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: $deleting.isPresented,
            titleVisibility: .visible,
            presenting: deleting
        ) { layout in
            Button("Delete", role: .destructive) { model.delete(layout.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(isLast
                ? "This is the only layout for these displays, so the display set is removed too."
                : "The layout and its keyboard shortcut are removed.")
        }
    }
}

private struct ReplaceConfirmation: ViewModifier {
    let model: AppModel
    @Binding var replacing: Layout?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Replace “\(replacing?.name ?? "")” with the current arrangement?",
            isPresented: $replacing.isPresented,
            titleVisibility: .visible,
            presenting: replacing
        ) { layout in
            Button("Replace") { model.replaceWithCurrentArrangement(layout.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The layout’s arrangement, mirroring and resolutions are replaced with how your displays are set up now. Its name and shortcut stay the same.")
        }
    }
}
