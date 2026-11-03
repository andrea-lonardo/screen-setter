import AppKit

/// The status item and its native menu. The menu is rebuilt from the model when
/// it opens and whenever the model changes, so it stays current while open.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let idleSymbol = "rectangle.2.swap"
    private static let busySymbol = "arrow.triangle.2.circlepath"
    private static let successSymbol = "checkmark.circle"

    private let model: AppModel
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var isFlashing = false

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 240
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "Screen Setter"
        item.menu = menu
        statusItem = item

        model.operationDidSucceed = { [weak self] in self?.flashSuccess() }
        observeChanges(of: { [weak self] in self?.observedState() }) { [weak self] in
            self?.rebuildMenu()
            self?.updateStatusIcon()
        }
    }

    /// Opens the menu programmatically (`--show-menu`).
    func showMenu() {
        statusItem?.button?.performClick(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        model.refresh()
    }

    // MARK: Menu

    /// Reads everything the menu shows, registering observation.
    private func observedState() {
        _ = (model.library, model.currentSnapshot, model.activeLayoutID, model.isBusy,
             model.reviewMessage, model.hotkeyIssue, model.undoActionTitle)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let busy = model.isBusy

        if model.reviewMessage != nil || model.hotkeyIssue != nil {
            let title = model.reviewMessage == nil ? "Review Keyboard Shortcuts…" : "Review Display Layout…"
            let review = item(title, action: #selector(showReview), symbol: "exclamationmark.triangle")
            review.toolTip = model.reviewMessage ?? model.hotkeyIssue
            menu.addItem(review)
            menu.addItem(.separator())
        }

        let layouts = model.connectedLayouts
        if let group = model.connectedGroup, !layouts.isEmpty {
            menu.addItem(.sectionHeader(title: model.name(of: group)))
            for (index, layout) in layouts.enumerated() {
                let entry = NSMenuItem(title: layout.name, action: #selector(applyLayout(_:)),
                                       keyEquivalent: index < 9 ? String(index + 1) : "")
                entry.target = self
                entry.representedObject = layout.id
                entry.image = LayoutThumbnail.menuImage(for: layout.snapshot)
                entry.state = layout.id == model.activeLayoutID ? .on : .off
                entry.isEnabled = !busy
                entry.toolTip = model.summary(for: layout)
                menu.addItem(entry)
            }
        } else {
            let empty = NSMenuItem(title: "No Layouts for These Displays", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        menu.addItem(.separator())
        let save = item("Save Current Arrangement…", action: #selector(saveCurrentArrangement), symbol: "plus.rectangle.on.rectangle")
        save.isEnabled = !busy
        menu.addItem(save)

        if let undoTitle = model.undoActionTitle {
            let undo = item(undoTitle, action: #selector(undo), symbol: "arrow.uturn.backward", key: "z")
            undo.isEnabled = !busy
            menu.addItem(undo)
        }

        menu.addItem(.separator())
        menu.addItem(item("Display Settings…", action: #selector(openDisplaySettings), symbol: "display"))
        menu.addItem(item("Settings…", action: #selector(openSettings), symbol: "gearshape", key: ","))
        menu.addItem(.separator())
        let quit = item("Quit Screen Setter", action: #selector(quit), symbol: "power", key: "q")
        quit.isEnabled = !busy
        menu.addItem(quit)
    }

    private func item(_ title: String, action: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        item.image = image
        return item
    }

    // MARK: Status icon

    private func updateStatusIcon() {
        guard !isFlashing || model.isBusy else { return }
        isFlashing = false
        setStatusSymbol(model.isBusy ? Self.busySymbol : Self.idleSymbol)
        let tooltip = model.isBusy ? "Screen Setter — Changing displays…" : (model.reviewMessage ?? "Screen Setter")
        statusItem?.button?.toolTip = tooltip
    }

    private func setStatusSymbol(_ name: String) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Screen Setter")
            ?? NSImage(systemSymbolName: Self.idleSymbol, accessibilityDescription: "Screen Setter")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func flashSuccess() {
        isFlashing = true
        setStatusSymbol(Self.successSymbol)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.isFlashing else { return }
            self.isFlashing = false
            self.updateStatusIcon()
        }
    }

    // MARK: Actions

    @objc private func applyLayout(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.apply(id)
    }

    @objc private func saveCurrentArrangement() {
        let suggestion = model.suggestedArrangementName()
        let alert = model.makeAlert(
            title: "Save Current Arrangement",
            message: "Save how the connected displays are arranged now as a new layout.",
            style: .informational)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggestion
        field.placeholderString = suggestion
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("Layout name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.layout()
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveCurrentArrangement(named: name.isEmpty ? nil : name)
    }

    @objc private func undo() { model.undo() }
    @objc private func showReview() { model.showReviewDetails() }
    @objc private func openDisplaySettings() { model.openDisplaySettings() }
    @objc private func openSettings() { model.openSettings() }

    @objc private func quit() {
        guard !model.isBusy else { return }
        NSApp.terminate(nil)
    }
}
