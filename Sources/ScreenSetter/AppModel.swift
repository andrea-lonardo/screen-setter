import AppKit
import Observation
import ServiceManagement

// The single main-actor source of truth shared by the menu bar and the SwiftUI
// Settings/Onboarding windows. Display operations run serially on a background
// queue; while one runs `isBusy` is true and further operations are ignored.
// Failures are presented by the model as native alerts — views never need to.

@MainActor
@Observable
final class AppModel {
    let store: LayoutStore
    /// True for `--preview-settings` / `--render-settings`: sample data, no display changes.
    let isPreview: Bool
    @ObservationIgnored let updates: UpdateController

    private(set) var library = LayoutLibrary()
    private(set) var currentSnapshot: LayoutSnapshot?
    private(set) var activeLayoutID: UUID?
    private(set) var isBusy = false
    /// Set when an automatic restore needs the user's attention.
    private(set) var reviewMessage: String?
    /// While true, global hotkeys are suspended so a recorder can capture keys.
    var isRecordingHotkey = false

    // MARK: Shell state (not part of the Settings contract)

    /// Set by the hotkey center when a shortcut could not be registered.
    private(set) var hotkeyIssue: String?
    /// Called on main after a display operation succeeds (the menu bar flashes).
    @ObservationIgnored var operationDidSucceed: (() -> Void)?

    @ObservationIgnored private let displayQueue = DispatchQueue(
        label: "io.github.andrea-lonardo.screen-setter.display", qos: .userInitiated)
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var lastAutomaticTopology: String?
    @ObservationIgnored private var pendingRefresh: DispatchWorkItem?
    @ObservationIgnored private var settingsController: SettingsWindowController?
    @ObservationIgnored private var onboardingController: OnboardingWindowController?
    @ObservationIgnored private var hasEvaluatedOnboarding = false
    @ObservationIgnored private var whatsNewController: WhatsNewWindowController?
    /// Bumped when the login item changes so `launchAtLogin` readers re-render.
    private var loginItemRevision = 0
    @ObservationIgnored private var previewLaunchAtLogin = false

    init(store: LayoutStore, isPreview: Bool = false) {
        self.store = store
        self.isPreview = isPreview
        updates = UpdateController(enabled: !isPreview)
        library = store.library
    }

    // MARK: Queries

    var groups: [DisplayGroup] { library.groups }

    /// The display set that is connected right now, if any layout uses it.
    var connectedGroupID: String? {
        guard let key = currentSnapshot?.topologyKey,
              library.layouts.contains(where: { $0.groupID == key }) else { return nil }
        return key
    }

    func layouts(inGroup groupID: String) -> [Layout] {
        library.layouts.filter { $0.groupID == groupID }
    }

    func name(of group: DisplayGroup) -> String {
        _ = library // Register observation; the store derives names from the same data.
        return store.name(of: group)
    }

    func isConnected(_ group: DisplayGroup) -> Bool {
        group.id == currentSnapshot?.topologyKey
    }

    func summary(for layout: Layout) -> String {
        _ = library
        return store.summary(for: layout)
    }

    func automaticLayoutID(inGroup groupID: String) -> UUID? {
        _ = library
        return store.automaticLayoutID(inGroup: groupID)
    }

    /// Name for a display UUID from the library cache, else "Display".
    func displayName(for displayID: String) -> String {
        _ = library
        return store.displayName(for: displayID)
    }

    // MARK: Display operations (asynchronous, serialized)

    func apply(_ id: UUID) {
        perform({ try $0.apply(id) })
    }

    /// `completion` receives the new layout, or nil on failure.
    func saveCurrentArrangement(named name: String? = nil, completion: ((Layout?) -> Void)? = nil) {
        let accepted = perform({ try $0.saveCurrent(named: name) }) { result in
            completion?(try? result.get())
        }
        if !accepted { completion?(nil) }
    }

    func replaceWithCurrentArrangement(_ id: UUID) {
        perform({ try $0.replaceWithCurrent(id) })
    }

    func refresh() {
        refreshState(allowAutomatic: false)
    }

    // MARK: Edits (synchronous; failures are shown as alerts and return false)

    @discardableResult func rename(_ id: UUID, to name: String) -> Bool {
        edit { try store.rename(id, to: name) }
    }

    /// Saves editor changes; when `apply` is true and the display set is connected,
    /// applies the layout afterwards.
    @discardableResult func update(_ layout: Layout, apply: Bool) -> Bool {
        guard edit({ try store.update(layout) }) else { return false }
        if apply, currentSnapshot?.topologyKey == layout.groupID {
            self.apply(layout.id)
        }
        return true
    }

    func duplicate(_ id: UUID) {
        edit { _ = try store.duplicate(id) }
    }

    func delete(_ id: UUID) {
        edit { try store.delete(id) }
    }

    func moveLayouts(inGroup groupID: String, from source: IndexSet, to destination: Int) {
        edit { try store.moveLayouts(inGroup: groupID, from: source, to: destination) }
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        edit { try store.moveGroups(from: source, to: destination) }
    }

    func renameGroup(_ groupID: String, to name: String) {
        edit { try store.renameGroup(groupID, to: name) }
    }

    func setAutomaticLayout(inGroup groupID: String, layoutID: UUID?) {
        edit { try store.setAutomaticLayout(inGroup: groupID, layoutID: layoutID) }
    }

    @discardableResult func setHotkey(_ hotkey: Hotkey?, for id: UUID) -> Bool {
        edit { try store.setHotkey(hotkey, for: id) }
    }

    func completeOnboarding() {
        edit { try store.setOnboardingCompleted() }
    }

    // MARK: App

    var launchAtLogin: Bool {
        get {
            _ = loginItemRevision
            if isPreview { return previewLaunchAtLogin }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            defer { loginItemRevision += 1 }
            if isPreview { previewLaunchAtLogin = newValue; return }
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    if SMAppService.mainApp.status == .requiresApproval {
                        presentAlert(
                            title: "Allow Screen Setter to Open at Login",
                            message: "Turn on Screen Setter in System Settings › General › Login Items & Extensions.",
                            style: .informational)
                        SMAppService.openSystemSettingsLoginItems()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                presentAlert(title: "Open at Login Couldn’t Be Changed", message: error.localizedDescription)
            }
        }
    }

    func openSettings(selectingLayout layoutID: UUID? = nil) {
        let controller = settingsController ?? SettingsWindowController(model: self)
        settingsController = controller
        NSApp.activate()
        controller.show(selectingLayout: layoutID)
    }

    func openDisplaySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func showError(_ message: String) {
        presentAlert(title: "Screen Setter", message: message)
    }
}

// MARK: - Shell support

extension AppModel {
    /// Called once by the app delegate after launch: reads the displays, restores
    /// an automatic layout if one matches, then decides whether to onboard.
    func start() {
        refreshState(allowAutomatic: !isPreview) { [weak self] in
            guard let self else { return }
            if let issue = self.store.loadIssue {
                self.presentAlert(title: "Your Layouts Couldn’t Be Loaded", message: issue, style: .informational)
            }
            self.showOnboardingIfNeeded()
        }
    }

    /// Debounced refresh after display reconfiguration (may restore automatically).
    func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshState(allowAutomatic: true) }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// After wake the same display set may need its automatic layout again.
    func systemDidWake() {
        lastAutomaticTopology = nil
        scheduleRefresh()
    }

    func layout(id: UUID) -> Layout? {
        library.layouts.first { $0.id == id }
    }

    /// Layouts of the connected display set, in user order.
    var connectedLayouts: [Layout] {
        guard let key = connectedGroupID else { return [] }
        return layouts(inGroup: key)
    }

    var connectedGroup: DisplayGroup? {
        guard let key = connectedGroupID else { return nil }
        return library.groups.first { $0.id == key }
    }

    /// Applies a layout requested by a hotkey, URL, or Shortcut, explaining why
    /// it can't run instead of failing silently. The connected displays are
    /// checked when the layout is applied, not against the cached snapshot,
    /// which is still empty right after launch and lags display changes.
    func requestApply(_ layout: Layout) {
        guard !isBusy else {
            presentAlert(title: "Screen Setter",
                         message: "A display change is already in progress. Try again when it finishes.",
                         style: .informational)
            return
        }
        apply(layout.id)
    }

    /// A unique name describing the connected arrangement, such as "Studio Display Above".
    func suggestedArrangementName() -> String {
        let base = currentSnapshot.flatMap(describe) ?? "Layout \(connectedLayouts.count + 1)"
        let taken = Set(library.layouts.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    func setHotkeyIssue(_ message: String?) {
        if hotkeyIssue != message { hotkeyIssue = message }
    }

    func showReviewDetails() {
        let message = [reviewMessage, hotkeyIssue].compactMap { $0 }.joined(separator: "\n\n")
        guard !message.isEmpty else { return }
        let alert = makeAlert(title: reviewMessage == nil ? "Review Keyboard Shortcuts" : "Review Display Layout",
                              message: message, style: .informational)
        alert.addButton(withTitle: "Screen Setter Settings…")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { openSettings() }
    }

    private static let lastSeenWhatsNewKey = "LastSeenWhatsNewVersion"

    /// Shows What's New once per feature release, after an update.
    func showWhatsNewIfNeeded() {
        guard !isPreview, WhatsNew.currentFeatures != nil,
              UserDefaults.standard.string(forKey: Self.lastSeenWhatsNewKey) != WhatsNew.currentKey else { return }
        markWhatsNewSeen()
        showWhatsNew()
    }

    func showWhatsNew() {
        guard let features = WhatsNew.currentFeatures else { return }
        let controller = whatsNewController ?? WhatsNewWindowController(features: features)
        whatsNewController = controller
        controller.show()
    }

    private func markWhatsNewSeen() {
        guard !isPreview else { return }
        UserDefaults.standard.set(WhatsNew.currentKey, forKey: Self.lastSeenWhatsNewKey)
    }

    func showOnboarding() {
        let controller = onboardingController ?? OnboardingWindowController(model: self)
        onboardingController = controller
        NSApp.activate()
        controller.show()
    }

    func presentAlert(title: String, message: String, style: NSAlert.Style = .warning) {
        let alert = makeAlert(title: title, message: message, style: style)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func makeAlert(title: String, message: String, style: NSAlert.Style) -> NSAlert {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        return alert
    }
}

// MARK: - Orchestration

private extension AppModel {
    /// Runs one display operation on the serial queue, then refreshes. Returns
    /// false when it was ignored because another operation is running.
    @discardableResult
    func perform<T: Sendable>(
        automatic: Bool = false,
        _ operation: @escaping @Sendable (LayoutStore) throws -> T,
        completion: ((Result<T, Error>) -> Void)? = nil
    ) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        revision += 1
        pendingRefresh?.cancel()
        if reviewMessage != nil { reviewMessage = nil }
        displayQueue.async { [store] in
            let result = Result { try operation(store) }
            let snapshot = try? store.refresh()
            // The model lives for the whole app session, so a strong capture is fine.
            DispatchQueue.main.async {
                self.isBusy = false
                self.lastAutomaticTopology = snapshot?.topologyKey
                self.setCurrent(snapshot)
                switch result {
                case .success:
                    self.operationDidSucceed?()
                case .failure(let error):
                    if automatic {
                        self.reviewMessage = error.localizedDescription
                    } else {
                        self.present(error)
                    }
                }
                completion?(result)
            }
        }
        return true
    }

    func refreshState(allowAutomatic: Bool, completion: (() -> Void)? = nil) {
        guard !isBusy, !isRefreshing else {
            if allowAutomatic { scheduleRefresh() }
            completion?()
            return
        }
        isRefreshing = true
        let requestedRevision = revision
        displayQueue.async { [store] in
            let result = Result { try store.refresh() }
            DispatchQueue.main.async {
                self.isRefreshing = false
                defer { completion?() }
                guard !self.isBusy, self.revision == requestedRevision else { return }
                switch result {
                case .failure(let error):
                    self.setCurrent(nil)
                    self.reviewMessage = error.localizedDescription
                case .success(let snapshot):
                    self.setCurrent(snapshot)
                    guard allowAutomatic, self.lastAutomaticTopology != snapshot.topologyKey else { return }
                    self.lastAutomaticTopology = snapshot.topologyKey
                    guard let layout = self.store.automaticLayout(for: snapshot),
                          self.activeLayoutID != layout.id else { return }
                    guard self.store.canAutomaticallyApply(layout, to: snapshot) else {
                        self.reviewMessage = "The display modes or mirroring changed since “\(layout.name)” was saved. Review it in Settings before applying it manually."
                        return
                    }
                    let id = layout.id
                    self.perform(automatic: true, { try $0.apply(id, automatic: true) })
                }
            }
        }
    }

    /// Runs a synchronous store edit and mirrors the result.
    @discardableResult
    func edit(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            reloadFromStore()
            return true
        } catch {
            reloadFromStore()
            showError(error.localizedDescription)
            return false
        }
    }

    func setCurrent(_ snapshot: LayoutSnapshot?) {
        if currentSnapshot != snapshot { currentSnapshot = snapshot }
        reloadFromStore()
    }

    func reloadFromStore() {
        let newLibrary = store.library
        if library != newLibrary { library = newLibrary }
        let active = currentSnapshot.flatMap { store.activeLayoutID(in: $0) }
        if activeLayoutID != active { activeLayoutID = active }
    }

    func present(_ error: Error) {
        if case let .displayNotConnected(name)? = error as? LayoutError {
            let alert = makeAlert(
                title: "Displays Not Connected",
                message: "Connect the displays used by “\(name)” to apply it. Your saved layout is unchanged.",
                style: .informational)
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "macOS Display Settings…")
            if alert.runModal() == .alertSecondButtonReturn { openDisplaySettings() }
            return
        }
        showError(error.localizedDescription)
    }

    func showOnboardingIfNeeded() {
        guard !hasEvaluatedOnboarding else { return }
        hasEvaluatedOnboarding = true
        let current = store.library // Includes any 1.x profiles migrated by the first refresh.
        guard !current.hasCompletedOnboarding else {
            showWhatsNewIfNeeded()
            return
        }
        // New and migrated people get the welcome window instead of What's New.
        markWhatsNewSeen()
        if current.layouts.isEmpty {
            showOnboarding()
        } else {
            // Migrated 1.x users already know the app; don't welcome them again.
            try? store.setOnboardingCompleted()
            reloadFromStore()
        }
    }

    /// "Studio Display Above", "LG UltraFine Left", or "Mirrored" for two displays.
    func describe(_ snapshot: LayoutSnapshot) -> String? {
        guard snapshot.displays.count == 2 else { return nil }
        if snapshot.displays.contains(where: { $0.mirrorSourceID != nil }) { return "Mirrored" }
        let anchor = snapshot.displays.first(where: \.builtIn)
            ?? snapshot.displays.first { $0.x == 0 && $0.y == 0 }
            ?? snapshot.displays[0]
        guard let other = snapshot.displays.first(where: { $0.id != anchor.id }) else { return nil }
        let reference = snapshot.frame(of: anchor)
        let frame = snapshot.frame(of: other)
        let position: String
        if frame.maxY <= reference.minY { position = "Above" }
        else if frame.minY >= reference.maxY { position = "Below" }
        else if frame.maxX <= reference.minX { position = "Left" }
        else { position = "Right" }
        let name = library.displayNames[other.id.uppercased()] ?? other.name
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "external display" else { return "External \(position)" }
        return "\(trimmed) \(position)"
    }
}
