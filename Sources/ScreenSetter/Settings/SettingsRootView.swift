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
        // The sidebar is the window's navigation, so it never collapses.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(model: model, selection: $navigation.selection) {
                navigation.isSavingCurrentArrangement = true
            }
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
        } detail: {
            detail
                .navigationTitle(title)
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
                GroupDetailView(model: model, group: group) {
                    navigation.isSavingCurrentArrangement = true
                }
                .id(group.id)
            } else {
                emptyLibrary
            }
        case nil:
            emptyLibrary
        }
    }

    private var title: String {
        switch navigation.selection {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .automation: "Automation"
        case .about: "About"
        case .group(let id): model.groups.first { $0.id == id }.map { model.name(of: $0) } ?? "Screen Setter"
        case nil: "Screen Setter"
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
            Button("macOS Display Settings…") { model.openDisplaySettings() }
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
    /// Starts saving the current arrangement as a new layout.
    let onNewLayout: () -> Void

    @State private var renamingGroup: DisplayGroup?
    @State private var renameText = ""

    var body: some View {
        List(selection: $selection) {
            displaySets

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

            // Always here, even with no layouts: saving works for any displays.
            Button(action: onNewLayout) {
                Label {
                    Text("New Layout…")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "plus")
                        .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy)
            .help("Save how your displays are set up now as a new layout")
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
            Text(model.name(of: group))
                .lineLimit(1)
        } icon: {
            // The connected set is the one marked in colour.
            if connected {
                Image(systemName: count > 1 ? "display.2" : "display")
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: count > 1 ? "display.2" : "display")
            }
        }
        .help(connected ? "Connected" : (count == 1 ? "1 display" : "\(count) displays"))
        .accessibilityElement(children: .combine)
        .accessibilityValue(connected ? "Connected" : "Not connected")
    }
}
