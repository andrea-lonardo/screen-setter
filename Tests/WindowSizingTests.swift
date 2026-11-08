import AppKit
import SwiftUI

private struct WindowSizingFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct WindowSizingTests {
    @MainActor
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: .darkAqua)
        application.finishLaunching()

        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(store: PreviewLibrary.makeStore(), isPreview: true)
        model.start()
        let deadline = Date().addingTimeInterval(5)
        while model.currentSnapshot == nil && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        guard model.currentSnapshot != nil else {
            throw WindowSizingFailure(description: "Isolated preview displays did not load")
        }

        let controller = SettingsWindowController(model: model)
        guard let window = controller.window else {
            throw WindowSizingFailure(description: "Settings window was not created")
        }
        // The regression happened after SwiftUI attached its split-view controller,
        // so checking only the values immediately after initialization misses it.
        try controller.render(to: directory.appendingPathComponent("gallery-default.png"))
        try checkMinimum(window, pane: "initial gallery")

        window.setContentSize(NSSize(width: 760, height: 640))
        guard let split = window.contentView.flatMap(findSplitView) else {
            throw WindowSizingFailure(description: "Settings split view was not attached")
        }
        // Stress the content pane with the sidebar at its widest supported size.
        split.setPosition(320, ofDividerAt: 0)
        split.adjustSubviews()
        try controller.render(to: directory.appendingPathComponent("gallery-wide-sidebar.png"))
        try checkMinimum(window, pane: "widest sidebar")
        let panes: [(String, SidebarItem?)] = [
            ("gallery", model.groups.first.map { .group($0.id) }),
            ("disconnected", model.groups.last.map { .group($0.id) }),
            ("general", .general), ("shortcuts", .shortcuts),
            ("automation", .automation), ("about", .about)
        ]
        for (name, pane) in panes {
            try controller.render(to: directory.appendingPathComponent("\(name)-minimum.png"), selecting: pane)
            try checkMinimum(window, pane: name)
        }
        guard window.frameAutosaveName.isEmpty else {
            throw WindowSizingFailure(description: "Sizing tests must not use the real Settings frame preference")
        }
        print("PASS: Settings minimum survives layout, widest sidebar, minimum-size resizing and all panes")
    }

    @MainActor
    private static func checkMinimum(_ window: NSWindow, pane: String) throws {
        guard window.contentMinSize.width >= 760, window.contentMinSize.height >= 640 else {
            throw WindowSizingFailure(description: "\(pane): native minimum collapsed to \(window.contentMinSize)")
        }
        let actual = window.contentRect(forFrameRect: window.frame).size
        guard actual.width >= 760, actual.height >= 640 else {
            throw WindowSizingFailure(description: "\(pane): content shrank to \(actual)")
        }
        guard let split = window.contentView.flatMap(findSplitView),
              let detail = split.arrangedSubviews.last, detail.bounds.width >= 440 else {
            throw WindowSizingFailure(description: "\(pane): detail pane shrank below 440 points")
        }
    }

    @MainActor
    private static func findSplitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count >= 2 {
            return split
        }
        return view.subviews.lazy.compactMap { findSplitView(in: $0) }.first
    }
}
