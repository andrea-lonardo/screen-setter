import AppKit
import SwiftUI

struct GeneralPane: View {
    let model: AppModel

    @State private var copied = false

    private var exampleURL: String {
        AppInfo.applyURL(forLayoutNamed: model.library.layouts.first?.name ?? "Desk")
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
                LabeledContent {
                    Button("Show Welcome Window…") { model.showOnboarding() }
                } label: {
                    Text("Welcome window")
                    Text("A quick introduction to saving and switching layouts.")
                }
            }

            Section("Displays") {
                LabeledContent {
                    Button("Display Settings…") { model.openDisplaySettings() }
                } label: {
                    Text("Arrangement, resolution and mirroring")
                    Text("Set up your displays in System Settings, then save the arrangement as a layout.")
                }
            }

            Section {
                LabeledContent {
                    EmptyView()
                } label: {
                    Text("Keyboard shortcuts")
                    Text("Give any layout a shortcut in its editor. Shortcuts work in every app.")
                }
                LabeledContent {
                    Button(copied ? "Copied" : "Copy") { copy(exampleURL) }
                        .help("Copy the URL")
                } label: {
                    Text("Apply with a URL")
                    Text("Open a link like this from Shortcuts, scripts or other apps to switch layouts:")
                    Text(exampleURL)
                        .font(.callout.monospaced())
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Shortcuts & Automation")
            } footer: {
                Text("In the URL, use the layout’s name with spaces and special characters percent-encoded, as in the example.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version", value: AppInfo.version.replacingOccurrences(of: "Version ", with: ""))
                LabeledContent("Source code") {
                    Link("GitHub", destination: AppInfo.repositoryURL)
                }
                LabeledContent("License") {
                    if let licenseURL = AppInfo.licenseURL {
                        Button("MIT License…") { NSWorkspace.shared.open(licenseURL) }
                    } else {
                        Text("MIT License")
                    }
                }
            } header: {
                Text("About")
            } footer: {
                Text("Screen Setter is free and open source, provided as is, without warranty of any kind. Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
