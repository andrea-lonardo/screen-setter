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
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Setter")
                            .font(.title3.weight(.semibold))
                        Text(AppInfo.version)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { model.updates.checksAutomatically },
                    set: { model.updates.checksAutomatically = $0 }
                ))
                LabeledContent {
                    Button("Check Now") { model.updates.checkForUpdates() }
                        .disabled(!model.updates.canCheckForUpdates)
                } label: {
                    Text("Check for updates")
                    Text("With automatic checks on, Screen Setter asks its website once a day whether a new version exists. Only the app’s version is sent.")
                }
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
                Text("Screen Setter is free and open source, provided as is, without warranty of any kind. Updates use Sparkle, under the MIT License. Mac and macOS are trademarks of Apple Inc., registered in the U.S. and other countries and regions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
