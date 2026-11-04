import AppKit
import SwiftUI

struct GeneralPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.launchAtLogin = $0 }
                ))
            }

            Section("Displays") {
                LabeledContent {
                    Button("Display Settings…") { model.openDisplaySettings() }
                } label: {
                    Text("Arrangement, resolution and mirroring")
                    Text("Set up your displays in System Settings, then save the arrangement as a layout.")
                }
            }

            Section("Help") {
                LabeledContent {
                    Button("Show Welcome Window…") { model.showOnboarding() }
                } label: {
                    Text("Welcome window")
                    Text("A quick introduction to saving and switching layouts.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutPane: View {
    let model: AppModel

    var body: some View {
        Form {
            // A header-only section: the app's identity sits on the window background, not in a card.
            Section {
            } header: {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 88, height: 88)
                        .accessibilityHidden(true)
                    Text("Screen Setter")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(AppInfo.version)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("Save display arrangements and switch between them from the menu bar.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .textCase(nil)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .accessibilityElement(children: .combine)
            }

            Section {
                UpdateStatusRow(updates: model.updates)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { model.updates.checksAutomatically },
                    set: { model.updates.checksAutomatically = $0 }
                ))
                LabeledContent("Release notes") {
                    Link("View on GitHub", destination: AppInfo.releasesURL)
                }
            } header: {
                // Matches the other panes' headers; the header-only section above changes the default.
                Text("Updates")
                    .font(.headline)
                    .foregroundStyle(.primary)
            } footer: {
                Text("Automatic checks ask Screen Setter’s website once a day whether a new version exists. Only the app’s version is sent.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Source code") {
                    Link("GitHub", destination: AppInfo.repositoryURL)
                }
                LabeledContent("Privacy") {
                    Link("No Data Collected", destination: AppInfo.privacyURL)
                }
                LabeledContent("License") {
                    if let licenseURL = AppInfo.licenseURL {
                        Button("MIT License…") { NSWorkspace.shared.open(licenseURL) }
                    } else {
                        Text("MIT License")
                    }
                }
            } footer: {
                Text("Free and open source, provided as is, without warranty of any kind. Updates use Sparkle, under the MIT License. Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Whether Screen Setter is up to date, and a button to check now.
private struct UpdateStatusRow: View {
    let updates: UpdateController

    var body: some View {
        LabeledContent {
            Button(updates.availableVersion == nil ? "Check Now" : "Update…") { updates.checkForUpdates() }
                .disabled(!updates.canCheckForUpdates)
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(updates.availableVersion == nil && updates.lastCheckDate != nil ? Color.green : Color.accentColor)
                    .font(.title2)
            }
        }
    }

    private var title: String {
        if let version = updates.availableVersion { return "Version \(version) is available" }
        return updates.lastCheckDate == nil ? "Not checked yet" : "Screen Setter is up to date"
    }

    private var detail: String {
        guard let date = updates.lastCheckDate else {
            return "Check now to see whether a new version exists."
        }
        if Date().timeIntervalSince(date) < 60 { return "Last checked just now" }
        return "Last checked " + date.formatted(.relative(presentation: .named))
    }

    private var symbol: String {
        if updates.availableVersion != nil { return "arrow.down.circle.fill" }
        return updates.lastCheckDate == nil ? "arrow.clockwise.circle.fill" : "checkmark.circle.fill"
    }
}
