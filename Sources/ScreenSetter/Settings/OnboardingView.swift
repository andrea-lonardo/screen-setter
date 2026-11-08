import AppKit
import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    var onGetStarted: () -> Void

    @State private var isSaving = false
    @State private var savedLayoutName: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)
                Text("Welcome to Screen Setter")
                    .font(.title.weight(.semibold))
                Text("Switch between saved display arrangements in a click.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 30)
            .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 14) {
                Step(
                    symbol: "display.2",
                    title: "Arrange your displays",
                    detail: "Set position, mirroring and resolution in System Settings."
                )
                Step(
                    symbol: "square.and.arrow.down",
                    title: "Save the arrangement as a layout",
                    detail: savedLayoutName.map { "Saved “\($0)”. Save more anytime from the menu bar." }
                        ?? "Save as many layouts as you like for each set of displays."
                )
                Step(
                    symbol: "menubar.rectangle",
                    title: "Switch layouts",
                    detail: "From the menu bar, a keyboard shortcut, or automatically."
                )
            }
            .padding(.horizontal, 56)
            .padding(.top, 22)

            Spacer(minLength: 16)

            Label {
                Text("Screen Setter lives in the menu bar and has no Dock icon. If you can’t see it there, open the app again to show its settings.")
            } icon: {
                Image(systemName: MenuBarController.idleSymbol)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 56)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Button("macOS Display Settings…") { model.openDisplaySettings() }
                Button("Save Current Arrangement…", action: saveCurrent)
                    .disabled(isSaving || model.isBusy)
                Spacer()
                Button("Get Started", action: onGetStarted)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 560, height: 470)
        .sheet(isPresented: $isSaving) {
            SaveArrangementSheet(model: model) { layout in
                savedLayoutName = layout.name
            }
        }
    }

    private func saveCurrent() {
        isSaving = true
    }
}

private struct Step: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
