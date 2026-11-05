import SwiftUI

/// The layouts of one display set, as a gallery of arrangement cards.
struct GroupDetailView: View {
    let model: AppModel
    let group: DisplayGroup
    /// Starts saving the current arrangement as a new layout.
    let onNewLayout: () -> Void

    @State private var editing: Layout?
    @State private var renaming: Layout?
    @State private var renameText = ""
    @State private var deleting: Layout?
    @State private var replacing: Layout?

    private let columns = [GridItem(.adaptive(minimum: 172, maximum: 260), spacing: 14, alignment: .top)]

    var body: some View {
        let layouts = model.layouts(inGroup: group.id)
        let connected = model.isConnected(group)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(statusText(connected: connected))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(layouts) { layout in
                        LayoutCard(model: model, layout: layout, isConnected: connected) {
                            if connected { model.apply(layout.id) } else { editing = layout }
                        } actions: {
                            actions(for: layout, in: layouts)
                        }
                    }
                    if connected {
                        NewLayoutCard(action: onNewLayout)
                            .disabled(model.isBusy)
                    }
                }

                otherDisplaysNote(connected: connected)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .sheet(item: $editing) { layout in
            LayoutEditorView(model: model, layout: layout, isConnected: connected)
        }
        .alert("Rename Layout", isPresented: $renaming.isPresented, presenting: renaming) { layout in
            TextField("Name", text: $renameText, prompt: Text(layout.name))
            Button("Rename") { commitRename(layout) }
            Button("Cancel", role: .cancel) {}
        }
        .modifier(DeleteConfirmation(model: model, deleting: $deleting, isLast: layouts.count == 1))
        .modifier(ReplaceConfirmation(model: model, replacing: $replacing))
    }

    /// Names the displays only when the set has a custom name; otherwise the title already does.
    private func statusText(connected: Bool) -> String {
        let subject: String
        if group.customName != nil {
            subject = model.displays(inGroup: group.id).map { model.displayLabel(for: $0) }
                .formatted(.list(type: .and))
        } else {
            subject = "These displays"
        }
        return connected
            ? "\(subject) are connected. Click a layout to switch to it."
            : "\(subject) aren’t connected right now. Click a layout to edit it."
    }

    /// How to make layouts for displays that have no set yet. Saving always files the
    /// layout under the displays connected now, so the button is offered only on a
    /// set that isn't connected; a connected set has its own tile for that.
    private func otherDisplaysNote(connected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layouts for other displays")
                .font(.headline)
            Text("Connect them and arrange them in Display Settings, then choose Save Current Arrangement. Each set of displays gets its own place in the sidebar.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !connected {
                    Button("Save Current Arrangement…", action: onNewLayout)
                        .disabled(model.isBusy)
                }
                Button("Display Settings…") { model.openDisplaySettings() }
            }
            .padding(.top, 2)
        }
    }

    private func commitRename(_ layout: Layout) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != layout.name { model.rename(layout.id, to: name) }
    }

    @ViewBuilder
    private func actions(for layout: Layout, in layouts: [Layout]) -> some View {
        Button("Apply") { model.apply(layout.id) }
            .disabled(!model.isConnected(group) || model.isBusy)
        Button("Edit…") { editing = layout }
        Button("Rename…") {
            renameText = layout.name
            renaming = layout
        }
        Button("Duplicate") { model.duplicate(layout.id) }
            .disabled(model.isBusy)
        if layouts.count > 1, let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            Divider()
            Button("Move Left") {
                model.moveLayouts(inGroup: group.id, from: IndexSet(integer: index), to: index - 1)
            }
            .disabled(index == 0)
            Button("Move Right") {
                model.moveLayouts(inGroup: group.id, from: IndexSet(integer: index), to: index + 2)
            }
            .disabled(index == layouts.count - 1)
        }
        Divider()
        Button("Replace with Current Arrangement…") { replacing = layout }
            .disabled(!model.isConnected(group) || model.isBusy)
        Divider()
        Button("Delete…", role: .destructive) { deleting = layout }
            .disabled(model.isBusy)
    }
}

private enum CardMetrics {
    static let height: CGFloat = 100
    static let radius: CGFloat = 12
}

/// A layout as a card: its arrangement drawn large, then its name, mode and shortcut.
private struct LayoutCard<Actions: View>: View {
    let model: AppModel
    let layout: Layout
    let isConnected: Bool
    let action: () -> Void
    @ViewBuilder let actions: () -> Actions

    @State private var isHovering = false

    var body: some View {
        let isActive = model.activeLayoutID == layout.id
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                preview(isActive: isActive)
                VStack(alignment: .leading, spacing: 1) {
                    Text(layout.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(isActive ? "Current" : (layout.isMirrored ? "Mirrored" : "Extended"))
                            .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Spacer(minLength: 4)
                        if let hotkey = layout.hotkey {
                            Text(hotkey.displayString)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Keyboard shortcut \(hotkey.displayString)")
                        }
                    }
                    .font(.callout)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isConnected && model.isBusy)
        .help(isConnected ? "Switch to this layout" : "Edit this layout")
        .contextMenu { actions() }
        .overlay(alignment: .topLeading) {
            Menu {
                actions()
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
                    .background(.regularMaterial, in: Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(7)
            .opacity(isHovering ? 1 : 0)
            .help("More Actions")
            .accessibilityLabel("More Actions")
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func preview(isActive: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            shape.fill(.quinary)
            LayoutThumbnailView(snapshot: layout.snapshot, isActive: isActive)
                .padding(.horizontal, 30)
                .padding(.vertical, 18)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: CardMetrics.height)
        .overlay {
            shape.strokeBorder(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                               lineWidth: isActive ? 2 : 1)
        }
    }
}

/// The last tile of a connected set: saves the current arrangement as a new layout.
private struct NewLayoutCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: CardMetrics.radius, style: .continuous)
                    .strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: CardMetrics.height)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Save Current Arrangement…")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("As a new layout")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Save how your displays are set up now as a new layout")
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
