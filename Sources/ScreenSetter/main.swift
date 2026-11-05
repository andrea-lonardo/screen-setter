import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let arguments = CommandLine.arguments
    private let model: AppModel
    private let menuBar: MenuBarController
    private let hotkeys: HotkeyCenter
    private var wakeObserver: NSObjectProtocol?

    override init() {
        let previewOnboarding = arguments.contains("--preview-onboarding")
        if previewOnboarding || arguments.contains("--preview-settings") {
            model = AppModel(store: PreviewLibrary.makeStore(empty: previewOnboarding), isPreview: true)
        } else {
            model = AppModel(store: LayoutStore())
        }
        menuBar = MenuBarController(model: model)
        hotkeys = HotkeyCenter(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Previews run as a regular app so their windows can be inspected and automated.
        NSApp.setActivationPolicy(model.isPreview ? .regular : .accessory)
        menuBar.start()
        hotkeys.start()
        model.start()

        if !model.isPreview {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.systemDidWake() }
            }
        }

        if arguments.contains("--preview-onboarding") {
            DispatchQueue.main.async { [model] in model.showOnboarding() }
        } else if arguments.contains("--preview-settings") || arguments.contains("--show-settings") {
            DispatchQueue.main.async { [model] in model.openSettings() }
        } else if arguments.contains("--show-menu") {
            DispatchQueue.main.async { [menuBar] in menuBar.showMenu() }
        }
    }

    /// Opening the app again (from Finder, Spotlight or Launchpad) shows
    /// Settings, so it stays reachable when macOS hides the menu bar item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        guard !model.isPreview else { return }
        model.scheduleRefresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.isBusy ? .terminateCancel : .terminateNow
    }

    // MARK: URL scheme

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    /// `screensetter://apply/<identifier>` applies a layout by UUID, 1.x ID, or
    /// name (percent-encoded); `screensetter://settings` opens Settings. Links
    /// using the pre-rename `displaylayouts://` scheme work the same way.
    private func handle(_ url: URL) {
        let usage = "Use screensetter://apply/ followed by a layout’s name or identifier, or screensetter://settings."
        guard let scheme = url.scheme?.lowercased(), AppInfo.urlSchemes.contains(scheme),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil, components.user == nil,
              components.password == nil, components.port == nil,
              let action = components.host?.lowercased() else {
            model.presentAlert(title: "Unsupported Link", message: usage)
            return
        }

        // Percent-decode only after splitting, so names may contain an encoded "/".
        var path = components.percentEncodedPath
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix("/") { path.removeLast() }

        switch action {
        case "settings" where path.isEmpty:
            model.openSettings()
        case "apply" where !path.isEmpty && !path.contains("/"):
            guard let identifier = path.removingPercentEncoding?.trimmingCharacters(in: .whitespaces),
                  !identifier.isEmpty else {
                model.presentAlert(title: "Unsupported Link", message: usage)
                return
            }
            guard let layout = model.store.layout(matchingIdentifier: identifier) else {
                model.presentAlert(
                    title: "Layout Not Found",
                    message: "No layout matches “\(identifier)”. Check the name in Settings. If several layouts share that name, rename one or use the layout’s identifier instead.")
                return
            }
            model.requestApply(layout)
        default:
            model.presentAlert(title: "Unsupported Link", message: usage)
        }
    }
}

@main
struct ScreenSetterApplication {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments

        if let index = arguments.firstIndex(of: "--render-whats-new") {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                fputs("Usage: Screen Setter --render-whats-new /path/to/output.png [--dark]\n", stderr)
                exit(2)
            }
            renderWhatsNew(to: URL(fileURLWithPath: arguments[index + 1]), dark: arguments.contains("--dark"))
            return
        }

        for flag in ["--render-settings", "--render-onboarding"] {
            guard let index = arguments.firstIndex(of: flag) else { continue }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                fputs("Usage: Screen Setter \(flag) /path/to/output.png [--dark] [--pane general|shortcuts|automation|about] [--set <n>]\n", stderr)
                exit(2)
            }
            var pane: SidebarItem?
            if let paneIndex = arguments.firstIndex(of: "--pane") {
                guard paneIndex + 1 < arguments.count, let item = SidebarItem(paneName: arguments[paneIndex + 1]) else {
                    fputs("--pane takes general, shortcuts, automation or about.\n", stderr)
                    exit(2)
                }
                pane = item
            }
            // `--set <n>` selects the n-th display set (1-based) instead of a pane.
            var setNumber: Int?
            if let setIndex = arguments.firstIndex(of: "--set") {
                guard setIndex + 1 < arguments.count, let number = Int(arguments[setIndex + 1]), number > 0 else {
                    fputs("--set takes a display set number, starting at 1.\n", stderr)
                    exit(2)
                }
                setNumber = number
            }
            render(onboarding: flag == "--render-onboarding",
                   to: URL(fileURLWithPath: arguments[index + 1]), dark: arguments.contains("--dark"),
                   pane: pane, setNumber: setNumber)
            return
        }

        if arguments.contains("--diagnose") {
            diagnose()
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    /// Renders Settings or the welcome window with isolated sample data; never
    /// reads or changes real displays.
    @MainActor
    private static func render(onboarding: Bool, to url: URL, dark: Bool, pane: SidebarItem? = nil, setNumber: Int? = nil) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        application.finishLaunching()

        let model = AppModel(store: PreviewLibrary.makeStore(empty: onboarding), isPreview: true)
        // Pick up the sample's connected display set before rendering.
        let deadline = Date().addingTimeInterval(5)
        model.start()
        while model.currentSnapshot == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        do {
            if onboarding {
                try OnboardingWindowController(model: model).render(to: url)
            } else {
                var item = pane
                if let setNumber, setNumber <= model.groups.count {
                    item = .group(model.groups[setNumber - 1].id)
                }
                try SettingsWindowController(model: model).render(to: url, selecting: item)
            }
            print("Rendered \(onboarding ? "the welcome window" : "Settings") with isolated sample data to \(url.path).")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func renderWhatsNew(to url: URL, dark: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        application.finishLaunching()
        guard let features = WhatsNew.currentFeatures else {
            fputs("This version has no What’s New.\n", stderr)
            exit(1)
        }
        do {
            try WhatsNewWindowController(features: features).render(to: url)
            print("Rendered What’s New to \(url.path).")
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    /// Prints the connected displays. Read-only: no layout is applied and no
    /// saved data is read or migrated.
    private static func diagnose() {
        do {
            let engine = DisplayEngine()
            let snapshot = try engine.capture()
            let mirrored = snapshot.displays.contains { $0.mirrorSourceID != nil }
            print("Screen Setter \(versionDescription) — \(snapshot.displays.count) display(s), \(mirrored ? "mirroring on" : "extended").")
            for display in snapshot.displays {
                let mode = display.mode
                let refresh = mode.refreshRate == 0 ? "unknown Hz" : String(format: "%.2f Hz", mode.refreshRate)
                print("")
                print("\(display.name)\(display.builtIn ? " (built-in)" : "")")
                print("  ID:          \(display.id)")
                print("  Mode:        \(mode.width)×\(mode.height) points, \(mode.pixelWidth)×\(mode.pixelHeight) pixels, \(refresh)")
                print("  Origin:      \(display.x), \(display.y)\(display.x == 0 && display.y == 0 && display.mirrorSourceID == nil ? " (main display)" : "")")
                print("  Rotation:    \(Int(display.rotation))°")
                if let source = display.mirrorSourceID {
                    let sourceName = snapshot.displays.first { $0.id.uppercased() == source.uppercased() }?.name ?? source
                    print("  Mirroring:   \(sourceName)")
                } else {
                    print("  Mirroring:   no")
                }
                print("  Modes:       \(display.availableModes.map { "\($0.count) available" } ?? "not captured")")
            }
            if let issue = snapshot.arrangementIssue {
                print("\nArrangement issue: \(issue)")
            }
            do {
                try engine.validate(snapshot)
                print("\nPreflight: the current arrangement can be restored by the native engine.")
            } catch {
                print("\nPreflight: \(error.localizedDescription)")
            }
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static var versionDescription: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "development build"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}
