import Foundation

private struct LinkTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func requireLink(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw LinkTestFailure(description: message) }
}

/// Exercises the generated link through Foundation URL parsing and the app's
/// real identifier resolver, without launching the app or applying a layout.
private func linkTarget(_ link: String, in store: LayoutStore) throws -> UUID? {
    guard let url = URL(string: link),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme == "screensetter", components.host == "apply",
          components.query == nil, components.fragment == nil,
          url.pathComponents.count == 2 else {
        throw LinkTestFailure(description: "Generated layout link must contain one apply identifier")
    }
    return store.layout(matchingIdentifier: url.lastPathComponent)?.id
}

private final class LinkTestEngine: DisplayControlling {
    func capture() throws -> LayoutSnapshot {
        let mode = DisplayModeSpec(width: 1512, height: 982, pixelWidth: 3024,
                                   pixelHeight: 1964, refreshRate: 60)
        return LayoutSnapshot(displays: [
            DisplaySpec(id: "00000000-0000-0000-0000-000000000001", name: "Built-in Display",
                        vendor: 1, model: 1, serial: 0, builtIn: true, mode: mode,
                        x: 0, y: 0, rotation: 0, mirrorSourceID: nil)
        ])
    }

    func validate(_ target: LayoutSnapshot) throws {
        throw LinkTestFailure(description: "Link tests must not request display validation")
    }

    func apply(_ target: LayoutSnapshot) throws {
        throw LinkTestFailure(description: "Link tests must not apply displays")
    }
}

func runLinkTests() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("screen-setter-link-tests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let engine = LinkTestEngine()
    let legacy = SavedLayout(presetID: "monitor-right", title: "Migrated Desk", savedAt: Date(),
                             snapshot: try engine.capture())
    try ProfileRepository(directory: directory.appendingPathComponent("Profiles")).save(legacy)
    let store = LayoutStore(directory: directory, engine: engine)
    guard let migrated = store.layout(matchingIdentifier: "monitor-right") else {
        throw LinkTestFailure(description: "Legacy fixture must migrate")
    }

    let original = try store.saveCurrent(named: "Desk")
    let copied = original.applyURL
    try requireLink(try linkTarget(copied, in: store) == original.id, "Copied link targets its layout")

    try store.rename(original.id, to: "Travel / 100% Café 🖥? #")
    try requireLink(store.layout(id: original.id)?.applyURL == copied, "Rename preserves copied link")
    try requireLink(try linkTarget(copied, in: store) == original.id, "Copied link survives rename")

    let reused = try store.saveCurrent(named: "Desk")
    try requireLink(try linkTarget(copied, in: store) == original.id, "Reusing a name cannot retarget an old link")
    let duplicate = try store.saveCurrent(named: "Desk")
    try requireLink(store.layout(matchingIdentifier: "Desk") == nil, "Name lookup still rejects ambiguity")
    try requireLink(reused.applyURL != duplicate.applyURL, "Duplicate names have distinct links")
    try requireLink(try linkTarget(reused.applyURL, in: store) == reused.id, "First duplicate link resolves")
    try requireLink(try linkTarget(duplicate.applyURL, in: store) == duplicate.id, "Second duplicate link resolves")

    let uuidName = try store.saveCurrent(named: original.id.uuidString)
    let legacyName = try store.saveCurrent(named: "monitor-right")
    try requireLink(try linkTarget(uuidName.applyURL, in: store) == uuidName.id, "A UUID name cannot hijack its copied link")
    try requireLink(try linkTarget(legacyName.applyURL, in: store) == legacyName.id, "A legacy ID name cannot hijack its copied link")
    try requireLink(store.layout(matchingIdentifier: "MONITOR-RIGHT")?.id == migrated.id, "Legacy identifier compatibility is preserved")
    try requireLink(store.layout(matchingIdentifier: "Migrated Desk")?.id == migrated.id, "Name-based lookup remains supported")

    let reloaded = LayoutStore(directory: directory, engine: engine)
    for layout in store.library.layouts {
        try requireLink(reloaded.layout(id: layout.id)?.applyURL == layout.applyURL, "Reload preserves links")
        try requireLink(try linkTarget(layout.applyURL, in: reloaded) == layout.id, "Copied link resolves after reload")
    }

    try reloaded.delete(original.id)
    try requireLink(try linkTarget(copied, in: reloaded) == nil, "Deleting a target makes its link unresolved")
    try requireLink(try linkTarget(uuidName.applyURL, in: reloaded) == uuidName.id, "UUID-named layout keeps its own link after the namesake target is deleted")
    try requireLink(try linkTarget(reused.applyURL, in: reloaded) == reused.id, "Deleting one layout preserves other links")
    let afterDeletion = LayoutStore(directory: directory, engine: engine)
    try requireLink(try linkTarget(copied, in: afterDeletion) == nil, "A deleted target stays unresolved after reload")
}
