import AppKit
import SwiftUI

/// Automatic layouts for every display set, and the URLs that apply layouts.
struct AutomationPane: View {
    let model: AppModel

    @State private var copiedLayoutID: UUID?

    var body: some View {
        if model.library.layouts.isEmpty {
            ContentUnavailableView(
                "No Layouts",
                systemImage: "bolt",
                description: Text("Save a layout, then choose here when it’s applied automatically.")
            )
        } else {
            Form {
                connectSection
                urlSection
            }
            .formStyle(.grouped)
        }
    }

    private var connectSection: some View {
        Section {
            ForEach(model.groups) { group in
                Picker(selection: automaticBinding(for: group)) {
                    Text("Do Nothing").tag(UUID?.none)
                    Divider()
                    ForEach(model.layouts(inGroup: group.id)) { layout in
                        Text(layout.name).tag(UUID?.some(layout.id))
                    }
                } label: {
                    GroupSectionHeader(model: model, group: group)
                }
            }
        } header: {
            Text("When Displays Connect")
        } footer: {
            Text("The layout is applied when that exact set of displays connects, as long as their resolution, mirroring and rotation still match it.")
                .foregroundStyle(.secondary)
        }
    }

    private var urlSection: some View {
        Section {
            ForEach(model.groups) { group in
                ForEach(model.layouts(inGroup: group.id)) { layout in
                    urlRow(for: layout)
                }
            }
        } header: {
            Text("Apply with a URL")
        } footer: {
            Text("Open these links from Shortcuts, scripts or other apps to switch layouts.")
                .foregroundStyle(.secondary)
        }
    }

    private func urlRow(for layout: Layout) -> some View {
        let url = AppInfo.applyURL(forLayoutNamed: layout.name)
        let copied = copiedLayoutID == layout.id
        return LabeledContent {
            Button(copied ? "Copied" : "Copy") { copy(url, for: layout.id) }
                .help("Copy the URL")
        } label: {
            Text(layout.name)
            Text(url)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
    }

    private func automaticBinding(for group: DisplayGroup) -> Binding<UUID?> {
        Binding(
            get: { model.automaticLayoutID(inGroup: group.id) },
            set: { model.setAutomaticLayout(inGroup: group.id, layoutID: $0) }
        )
    }

    private func copy(_ string: String, for id: UUID) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copiedLayoutID = id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedLayoutID == id { copiedLayoutID = nil }
        }
    }
}
