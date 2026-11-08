import AppKit
import SwiftUI

// Public API fixed by the app shell: SettingsWindowController(model:),
// .show(selectingLayout:), .render(to:); OnboardingWindowController(model:), .show();
// LayoutThumbnail.menuImage(for:) (in LayoutThumbnail.swift).

enum SettingsRenderError: LocalizedError {
    case unavailable

    var errorDescription: String? { "The window could not be rendered." }
}

/// Shared bounds keep AppKit resizing and SwiftUI’s split-view layout in agreement.
enum SettingsWindowMetrics {
    static let minimumSize = NSSize(width: 760, height: 640)
    static let minimumDetailWidth: CGFloat = 440
}

/// Hosts the SwiftUI Settings window. Created once by the app shell and reused.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: AppModel
    private let navigation = SettingsNavigation()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let root = SettingsRootView(model: model, navigation: navigation)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.minSize]
        hosting.sceneBridgingOptions = [.toolbars, .title]
        window.contentViewController = hosting

        window.title = "Screen Setter"
        window.toolbarStyle = .unified
        // Tall enough for the 680×600 layout editor sheet to fit inside the window.
        window.contentMinSize = SettingsWindowMetrics.minimumSize
        window.setContentSize(NSSize(width: 860, height: 680))
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.center()
        // Sample windows must not restore or save the real Settings window’s frame.
        if !model.isPreview { window.setFrameAutosaveName("ScreenSetterSettings") }
        // Repair a narrow frame saved before these bounds were enforced.
        let restoredSize = window.contentRect(forFrameRect: window.frame).size
        window.setContentSize(NSSize(
            width: max(restoredSize.width, SettingsWindowMetrics.minimumSize.width),
            height: max(restoredSize.height, SettingsWindowMetrics.minimumSize.height)
        ))
    }

    required init?(coder: NSCoder) { nil }

    /// Shows and focuses the window, optionally selecting a layout's display set.
    func show(selectingLayout layoutID: UUID? = nil) {
        if let layoutID, let layout = model.library.layouts.first(where: { $0.id == layoutID }) {
            navigation.selection = .group(layout.groupID)
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Renders the window content to a PNG (used by `--render-settings` for docs).
    func render(to url: URL, selecting item: SidebarItem? = nil) throws {
        guard let window else { throw SettingsRenderError.unavailable }
        if let item { navigation.selection = item }
        try WindowRenderer.render(window, to: url)
    }
}

/// Draws a window, including its titlebar and Liquid Glass content, to a PNG
/// without showing it on screen.
@MainActor
enum WindowRenderer {
    static func render(_ window: NSWindow, to url: URL) throws {
        guard let content = window.contentView else { throw SettingsRenderError.unavailable }
        if !window.isVisible {
            // Lay the window out off screen so the toolbar and split view exist.
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            window.orderFrontRegardless()
        }
        window.appearance = NSApp.appearance
        // Let SwiftUI finish its layout passes before capturing.
        for _ in 0..<4 {
            content.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        // Capture the whole frame, including the titlebar and toolbar.
        let frameView = content.superview ?? content
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            throw SettingsRenderError.unavailable
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        compositeGlassContent(of: frameView, into: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SettingsRenderError.unavailable
        }
        try png.write(to: url)
    }

    /// `cacheDisplay` skips content hosted inside Liquid Glass views (such as the
    /// sidebar). Draw a plain stand-in for each large glass view, the scrolling
    /// content inside it, and then the titlebar again on top.
    private static func compositeGlassContent(of root: NSView, into bitmap: NSBitmapImageRep) {
        func views<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
            if let match = view as? T { return [match] }
            return view.subviews.flatMap { views(of: type, in: $0) }
        }
        func draw(_ view: NSView, rect: NSRect, tint: NSColor? = nil) {
            guard rect.width > 0, rect.height > 0,
                  let image = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
            view.cacheDisplay(in: rect, to: image)
            let destination = view.convert(rect, to: root)
            guard let tint else {
                image.draw(in: destination, from: .zero, operation: .sourceOver,
                           fraction: 1, respectFlipped: true, hints: nil)
                return
            }
            let tinted = NSImage(size: rect.size, flipped: false) { bounds in
                image.draw(in: bounds)
                tint.set()
                bounds.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: nil)
        }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            let glasses = views(of: NSGlassEffectView.self, in: root)
                .filter { $0.bounds.width > 100 && $0.bounds.height > 100 }
            guard !glasses.isEmpty else { return }
            for glass in glasses {
                let frame = glass.convert(glass.bounds, to: root)
                let shape = NSBezierPath(roundedRect: frame, xRadius: glass.cornerRadius, yRadius: glass.cornerRadius)
                NSColor.windowBackgroundColor.setFill()
                shape.fill()
                NSColor.quaternarySystemFill.setFill()
                shape.fill()

                for scrollView in views(of: NSScrollView.self, in: glass) {
                    guard let document = scrollView.documentView else { continue }
                    // Selection materials capture as black and the row text keeps its
                    // inactive colour, so draw the inactive-window highlight instead.
                    let selections = views(of: NSVisualEffectView.self, in: document)
                        .filter { $0.material == .selection && !$0.isHidden }
                    for selection in selections {
                        let rect = selection.convert(selection.bounds, to: root)
                        NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
                        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                        selection.isHidden = true
                    }
                    // In dark mode vibrant sidebar content captures as a black mask.
                    let isDark = root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    draw(document, rect: document.visibleRect, tint: isDark ? .labelColor : nil)
                    selections.forEach { $0.isHidden = false }
                }
            }
            // The window controls and toolbar sit above the sidebar.
            let titlebar = root.subviews.first { String(describing: type(of: $0)).contains("Titlebar") }
            if let titlebar {
                draw(titlebar, rect: titlebar.bounds)
                // Vibrant title text also captures as a black mask in dark mode.
                if root.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                    for label in views(of: NSTextField.self, in: titlebar)
                    where !label.isEditable && !label.isHidden {
                        draw(label, rect: label.bounds, tint: .labelColor)
                    }
                }
            }
        }
    }
}

/// First-run welcome window. The app shell shows it when
/// `library.hasCompletedOnboarding` is false and the library has no layouts.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var hasCompleted = false

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let root = OnboardingView(model: model) { [weak self] in self?.finish() }
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 560, height: 470))
        window.title = "Welcome to Screen Setter"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        hasCompleted = false
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Renders the welcome window to a PNG (used by `--render-onboarding` for docs).
    func render(to url: URL) throws {
        guard let window else { throw SettingsRenderError.unavailable }
        try WindowRenderer.render(window, to: url)
    }

    func windowWillClose(_ notification: Notification) {
        complete()
    }

    private func finish() {
        complete()
        window?.close()
    }

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        model.completeOnboarding()
    }
}

/// Shows the highlights of the current feature release.
@MainActor
final class WhatsNewWindowController: NSWindowController {
    init(features: [WhatsNew.Feature]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        let root = WhatsNewView(features: features) { [weak window] in window?.close() }
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        window.title = "What’s New in Screen Setter"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenNone)
        window.layoutIfNeeded()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Renders the window to a PNG (used by `--render-whats-new`).
    func render(to url: URL) throws {
        guard let window else { throw SettingsRenderError.unavailable }
        window.layoutIfNeeded()
        try WindowRenderer.render(window, to: url)
    }
}
