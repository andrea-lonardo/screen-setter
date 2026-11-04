import SwiftUI

enum SidebarItem: Hashable {
    case group(String)
    case general
    case shortcuts
    case automation
    case about

    /// The settings panes, in sidebar order.
    static let settingsPanes: [SidebarItem] = [.general, .shortcuts, .automation, .about]

    var isSettingsPane: Bool { Self.settingsPanes.contains(self) }

    /// Pane names accepted by `--render-settings … --pane <name>`.
    init?(paneName: String) {
        switch paneName.lowercased() {
        case "general": self = .general
        case "shortcuts": self = .shortcuts
        case "automation": self = .automation
        case "about": self = .about
        default: return nil
        }
    }
}

/// Navigation state shared between the window controller and the SwiftUI views.
@MainActor
@Observable
final class SettingsNavigation {
    var selection: SidebarItem?
    var isSavingCurrentArrangement = false
}

struct SettingsRootView: View {
    let model: AppModel
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(model: model, selection: $navigation.selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
        }
        .navigationTitle("Screen Setter")
        .toolbar {
            // Saving belongs to the layout library, not to the settings panes.
            if navigation.selection?.isSettingsPane != true {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        navigation.isSavingCurrentArrangement = true
                    } label: {
                        Label("Save Current Arrangement…", systemImage: "plus")
                    }
                    .help("Save Current Arrangement…")
                    .disabled(model.isBusy)
                }
            }
        }
        .sheet(isPresented: $navigation.isSavingCurrentArrangement) {
            SaveArrangementSheet(model: model) { layout in
                navigation.selection = .group(layout.groupID)
            }
        }
        .onAppear(perform: validateSelection)
        .onChange(of: model.groups.map(\.id)) { validateSelection() }
    }

    @ViewBuilder private var detail: some View {
        switch navigation.selection {
        case .general:
            GeneralPane(model: model)
        case .shortcuts:
            ShortcutsPane(model: model)
        case .automation:
            AutomationPane(model: model)
        case .about:
            AboutPane(model: model)
        case .group(let id):
            if let group = model.groups.first(where: { $0.id == id }) {
                GroupDetailView(model: model, group: group)
                    .id(group.id)
            } else {
                emptyLibrary
            }
        case nil:
            emptyLibrary
        }
    }

    private var emptyLibrary: some View {
        ContentUnavailableView {
            Label("No Layouts", systemImage: "display.2")
        } description: {
            Text("Arrange your displays in System Settings, then save the arrangement as a layout. You can switch back to it anytime from the menu bar.")
        } actions: {
            Button("Save Current Arrangement…") {
                navigation.isSavingCurrentArrangement = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
            Button("Display Settings…") { model.openDisplaySettings() }
        }
    }

    /// Keeps the selection pointing at something that exists: the connected
    /// display set, else the first one, else nothing (the empty state).
    private func validateSelection() {
        switch navigation.selection {
        case let item? where item.isSettingsPane:
            return
        case .group(let id) where model.groups.contains(where: { $0.id == id }):
            return
        default:
            let preferred = model.connectedGroupID.flatMap { id in model.groups.first { $0.id == id } }
                ?? model.groups.first
            navigation.selection = preferred.map { .group($0.id) }
        }
    }
}

struct SettingsSidebar: View {
    let model: AppModel
    @Binding var selection: SidebarItem?

    @State private var renamingGroup: DisplayGroup?
    @State private var renameText = ""

    var body: some View {
        List(selection: $selection) {
            if !model.groups.isEmpty {
                displaySets
            }

            Section("Settings") {
                Label("General", systemImage: "gearshape")
                    .tag(SidebarItem.general)
                Label("Shortcuts", systemImage: "command")
                    .tag(SidebarItem.shortcuts)
                Label("Automation", systemImage: "bolt")
                    .tag(SidebarItem.automation)
                Label("About", systemImage: "info.circle")
                    .tag(SidebarItem.about)
            }
        }
        .listStyle(.sidebar)
        .alert("Rename Display Set", isPresented: renameBinding, presenting: renamingGroup) { group in
            TextField("Name", text: $renameText, prompt: Text(derivedName(group)))
            Button("Rename") {
                model.renameGroup(group.id, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Leave the name empty to name the set after its displays.")
        }
    }

    private var displaySets: some View {
        Section("Layouts") {
            ForEach(model.groups) { group in
                GroupSidebarRow(model: model, group: group)
                    .tag(SidebarItem.group(group.id))
                    .contextMenu {
                        Button("Rename…") { beginRename(group) }
                    }
            }
            .onMove { source, destination in
                model.moveGroups(from: source, to: destination)
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingGroup != nil }, set: { if !$0 { renamingGroup = nil } })
    }

    private func beginRename(_ group: DisplayGroup) {
        renameText = group.customName ?? ""
        renamingGroup = group
    }

    private func derivedName(_ group: DisplayGroup) -> String {
        model.displays(inGroup: group.id).map { model.displayLabel(for: $0) }.joined(separator: " + ")
    }
}

private struct GroupSidebarRow: View {
    let model: AppModel
    let group: DisplayGroup

    var body: some View {
        let connected = model.isConnected(group)
        let count = group.id.split(separator: "+").count
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.name(of: group))
                    .lineLimit(1)
                if connected {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .imageScale(.small)
                        Text("Connected")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    Text(count == 1 ? "1 display" : "\(count) displays")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: count > 1 ? "display.2" : "display")
        }
        .accessibilityElement(children: .combine)
    }
}
