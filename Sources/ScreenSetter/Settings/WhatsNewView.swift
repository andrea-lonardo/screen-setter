import AppKit
import SwiftUI

/// The highlights of a feature release, shown once after an update installs.
/// Keyed by major.minor, so patch releases don't show it again.
enum WhatsNew {
    struct Feature: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let releases: [String: [Feature]] = [
        "2.2": [
            Feature(
                symbol: "square.grid.2x2",
                title: "Layouts at a glance",
                detail: "Each display set shows its layouts as cards with the arrangement drawn large. Click one to switch to it."
            ),
            Feature(
                symbol: "plus",
                title: "New Layout, always in reach",
                detail: "Save the current arrangement from the sidebar, whichever displays are connected."
            ),
            Feature(
                symbol: "display.2",
                title: "A calmer sidebar",
                detail: "One line per display set. The connected set has a blue icon."
            ),
        ],
        "2.1": [
            Feature(
                symbol: "sidebar.left",
                title: "Settings, reorganized",
                detail: "Your display sets come first, followed by General, Shortcuts, Automation and About."
            ),
            Feature(
                symbol: "command",
                title: "Every shortcut in one place",
                detail: "Record or clear a keyboard shortcut for any layout from the Shortcuts pane."
            ),
            Feature(
                symbol: "bolt.fill",
                title: "Automation",
                detail: "Choose what happens when each set of displays connects, and copy a link that applies any layout."
            ),
            Feature(
                symbol: "checkmark.seal.fill",
                title: "Updates at a glance",
                detail: "About shows whether Screen Setter is up to date, and this window appears after each feature update."
            ),
        ],
    ]

    /// "2.1" for version 2.1.1.
    static var currentKey: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.split(separator: ".").prefix(2).joined(separator: ".")
    }

    static var currentFeatures: [Feature]? { releases[currentKey] }
}

struct WhatsNewView: View {
    let features: [WhatsNew.Feature]
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("What’s New in Screen Setter")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Version \(WhatsNew.currentKey)")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(features) { feature in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(.tint)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 52)
            .padding(.top, 30)

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                Button(action: onContinue) {
                    Text("Continue")
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)

                Link("All Release Notes", destination: AppInfo.releasesURL)
                    .font(.callout)
            }
            .padding(.bottom, 28)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}
