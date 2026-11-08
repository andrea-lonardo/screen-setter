import Foundation
import Darwin

private struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(message: message) }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
        throw TestFailure(message: "\(message) (got \(actual), expected \(expected))")
    }
}

private func expectThrow(_ body: () throws -> Void, _ message: String) throws {
    do {
        try body()
    } catch {
        return
    }
    throw TestFailure(message: message)
}

private func mode(
    width: Int = 1728,
    height: Int = 1117,
    pixelWidth: Int = 3456,
    pixelHeight: Int = 2234,
    refreshRate: Double = 60
) -> DisplayModeSpec {
    DisplayModeSpec(width: width, height: height, pixelWidth: pixelWidth, pixelHeight: pixelHeight, refreshRate: refreshRate)
}

private func displayID(_ alias: String) -> String {
    switch alias {
    case "builtin": return "00000000-0000-0000-0000-000000000001"
    case "external": return "00000000-0000-0000-0000-000000000002"
    case "projector": return "00000000-0000-0000-0000-000000000003"
    default: return "00000000-0000-0000-0000-000000000004"
    }
}

private func display(
    id: String,
    name: String,
    x: Int32 = 0,
    y: Int32 = 0,
    displayMode: DisplayModeSpec = mode(),
    mirrorSourceID: String? = nil,
    rotation: Double = 0,
    serial: UInt32 = 100,
    availableModes: [DisplayModeSpec]? = nil
) -> DisplaySpec {
    DisplaySpec(
        id: displayID(id), name: name, vendor: 1, model: 2, serial: serial, builtIn: id == "builtin",
        mode: displayMode, x: x, y: y, rotation: rotation, mirrorSourceID: mirrorSourceID.map(displayID),
        availableModes: availableModes
    )
}

private func snapshot(
    externalName: String = "Studio Display",
    externalID: String = "external",
    externalX: Int32 = 1728,
    externalY: Int32 = 0,
    externalMode: DisplayModeSpec = mode(),
    externalMirrorSourceID: String? = nil,
    availableModes: [DisplayModeSpec]? = nil
) -> LayoutSnapshot {
    LayoutSnapshot(displays: [
        display(id: "builtin", name: "Built-in Retina Display", serial: 1, availableModes: availableModes),
        display(id: externalID, name: externalName, x: externalX, y: externalY, displayMode: externalMode,
                mirrorSourceID: externalMirrorSourceID, serial: 2, availableModes: availableModes)
    ])
}

private func saved(id: String, title: String, snapshot: LayoutSnapshot, autoApply: Bool = false) -> SavedLayout {
    SavedLayout(schemaVersion: 1, presetID: id, title: title, savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                snapshot: snapshot, autoApply: autoApply)
}

private func legacyCommand(_ state: LayoutSnapshot) -> String {
    "/opt/homebrew/bin/displayplacer " + state.displays.map {
        "\"id:\($0.id) res:\($0.mode.width)x\($0.mode.height) hz:\($0.mode.refreshRate) color_depth:8 enabled:true scaling:on origin:(\($0.x),\($0.y)) degree:\($0.rotation)\""
    }.joined(separator: " ")
}

private final class FakeEngine: DisplayControlling {
    var current = snapshot()
    var applyCount = 0
    var rejectValidation = false
    var failApply = false
    func capture() throws -> LayoutSnapshot { current }
    func validate(_ target: LayoutSnapshot) throws {
        if rejectValidation || target.topologyKey != current.topologyKey { throw TestFailure(message: "preflight failed") }
    }
    func apply(_ target: LayoutSnapshot) throws {
        applyCount += 1
        if failApply { throw TestFailure(message: "driver refused") }
        current = target
    }
}

private func withDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("screen-setter-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

private func withStore<T>(_ body: (LayoutStore, FakeEngine, URL) throws -> T) throws -> T {
    try withDirectory { directory in
        let engine = FakeEngine()
        return try body(LayoutStore(directory: directory, engine: engine), engine, directory)
    }
}

private func names(_ layouts: [Layout]) -> [String] { layouts.map(\.name) }

// MARK: Snapshot and legacy parser

private func testSemanticEquality() throws {
    let base = snapshot()
    let reorderedAndRenamed = LayoutSnapshot(displays: [
        display(id: "external", name: "A different cable label", x: 1728, serial: 2),
        display(id: "builtin", name: "Another Mac name", serial: 1)
    ])
    try check(base.matches(reorderedAndRenamed), "display order and names should not affect semantic equality")
    try checkEqual(base.topologyKey, reorderedAndRenamed.topologyKey, "topology key should ignore order and names")
    try check(!base.matches(snapshot(externalX: 1729)), "a geometry change should not match")
    try check(!base.matches(snapshot(externalMirrorSourceID: "builtin")), "a mirror change should not match")
    try check(!base.matches(snapshot(externalMode: mode(pixelWidth: 3000))), "a scaling change should not match")
    try check(base.matches(snapshot(externalMode: mode(refreshRate: 60.01))), "tiny refresh-rate noise should match")
    try check(!base.matches(snapshot(externalMode: mode(refreshRate: 60.2))), "a refresh-rate change should not match")
    try check(base.topologyKey != snapshot(externalID: "projector").topologyKey, "different displays differ in topology")
}

private func testLegacyParser() throws {
    let current = snapshot()
    let command = legacyCommand(current)
    let migrated = try LegacyLayoutParser.parse(command, presetID: "monitor-right", title: "Monitor Right", current: current)
    try check(migrated.snapshot.matches(current), "valid legacy command should preserve exact pixels and geometry")
    let malicious = [
        "/opt/homebrew/bin/displayplacer id:builtin origin:(0,0) id:external origin:(1728,0); touch /tmp/marker",
        "/opt/homebrew/bin/displayplacer id:builtin origin:(0,0) $(touch /tmp/marker)",
        command + "; touch /tmp/unwanted",
        command + " && echo nope",
        command.replacingOccurrences(of: "hz:60.0", with: "hz:$(echo 60)"),
        command.replacingOccurrences(of: "degree:0.0", with: "degree:360")
    ]
    for bad in malicious {
        try expectThrow({ _ = try LegacyLayoutParser.parse(bad, presetID: "x", title: "X", current: current) },
                        "legacy parser must reject \(bad)")
    }
    try expectThrow({
        _ = try LegacyLayoutParser.parse(command, presetID: "x", title: "X",
                                         current: snapshot(externalMode: mode(pixelWidth: 1728, pixelHeight: 1117)))
    }, "migration must reject unknown scaling")
}

// MARK: Arrangement

private func testArrangementIssues() throws {
    try checkEqual(snapshot().arrangementIssue, nil, "side-by-side arrangement is valid")
    try checkEqual(LayoutSnapshot(displays: [display(id: "builtin", name: "A")]).arrangementIssue, nil, "a single display is valid")
    try checkEqual(snapshot(externalX: 1000).arrangementIssue, "Displays overlap.", "overlap is reported")
    try checkEqual(snapshot(externalX: 1800).arrangementIssue, "Every display must touch another display.", "gap is reported")
    try checkEqual(snapshot(externalX: 1728, externalY: 1117).arrangementIssue,
                   "Every display must touch another display.", "corner-only touch is not connected")
    var noMain = snapshot()
    noMain.displays[0].x = 10
    noMain.displays[1].x = 1738
    try checkEqual(noMain.arrangementIssue, "One display must be the main display.", "missing main display is reported")
    let lShape = LayoutSnapshot(displays: [
        display(id: "builtin", name: "A"),
        display(id: "external", name: "B", x: 1728, y: 0),
        display(id: "projector", name: "C", x: 1728, y: 1117)
    ])
    try checkEqual(lShape.arrangementIssue, nil, "an L-shaped arrangement is connected through shared edges")
    let mirrored = snapshot(externalX: 5000, externalY: 5000, externalMirrorSourceID: "builtin")
    try checkEqual(mirrored.arrangementIssue, nil, "a mirrored display uses its source's frame")
    var chained = LayoutSnapshot(displays: lShape.displays)
    chained.displays[1].mirrorSourceID = displayID("builtin")
    chained.displays[2].mirrorSourceID = displayID("external")
    try check(chained.arrangementIssue != nil, "mirroring must be one level deep")
}

// MARK: Store

private func testSaveAndNames() throws {
    try withStore { store, engine, directory in
        let first = try store.saveCurrent(named: nil)
        let second = try store.saveCurrent(named: nil)
        try checkEqual([first.name, second.name], ["Layout 1", "Layout 2"], "default names count up")
        try store.rename(first.id, to: "  Desk  ")
        try checkEqual(store.layout(id: first.id)?.name, "Desk", "names are trimmed")
        try checkEqual(try store.saveCurrent(named: nil).name, "Layout 1", "default names reuse the smallest free number")
        try expectThrow({ try store.rename(first.id, to: "   ") }, "empty names are rejected")
        try expectThrow({ _ = try store.saveCurrent(named: " ") }, "empty save names are rejected")
        try checkEqual(try store.saveCurrent(named: "Desk").name, "Desk", "duplicate names are allowed")
        try expectThrow({ try store.rename(UUID(), to: "X") }, "unknown ids are rejected")

        engine.current = LayoutSnapshot(displays: [display(id: "builtin", name: "Built-in Retina Display")])
        let single = try store.saveCurrent(named: "Laptop")
        try checkEqual(store.library.groups.count, 2, "a single-display layout gets its own group")
        try checkEqual(store.summary(for: single), "1 display", "single display summary")
        try checkEqual(store.summary(for: first), "2 displays · Extended", "extended summary")

        let reloaded = LayoutStore(directory: directory, engine: engine).library
        try checkEqual(reloaded.layouts.map(\.id), store.library.layouts.map(\.id), "layouts round-trip through disk")
        try checkEqual(names(reloaded.layouts), names(store.library.layouts), "names round-trip through disk")
        try checkEqual(reloaded.groups, store.library.groups, "groups round-trip through disk")
    }
}

private func testGroups() throws {
    try withStore { store, engine, _ in
        let a = try store.saveCurrent(named: "A")
        engine.current = snapshot(externalName: "Epson", externalID: "projector")
        let p = try store.saveCurrent(named: "P")
        engine.current = snapshot()
        let b = try store.saveCurrent(named: "B")
        let c = try store.saveCurrent(named: "C")
        let monitorGroup = a.groupID, projectorGroup = p.groupID
        try checkEqual(store.library.groups.map(\.id), [monitorGroup, projectorGroup], "groups are appended in creation order")
        try checkEqual(names(store.layouts(inGroup: monitorGroup)), ["A", "B", "C"], "group layouts keep library order")

        try store.moveLayouts(inGroup: monitorGroup, from: [2], to: 0)
        try checkEqual(names(store.layouts(inGroup: monitorGroup)), ["C", "A", "B"], "move to top")
        try store.moveLayouts(inGroup: monitorGroup, from: [0], to: 3)
        try checkEqual(names(store.layouts(inGroup: monitorGroup)), ["A", "B", "C"], "move to end (onMove semantics)")
        try store.moveLayouts(inGroup: monitorGroup, from: [0, 1], to: 3)
        try checkEqual(names(store.layouts(inGroup: monitorGroup)), ["C", "A", "B"], "multi-move")
        try checkEqual(store.library.layouts[1].name, "P", "other groups keep their slots")

        try store.moveGroups(from: [1], to: 0)
        try checkEqual(store.library.groups.map(\.id), [projectorGroup, monitorGroup], "groups reorder")

        let group = store.library.groups[1]
        try checkEqual(store.name(of: group), "Built-in Retina Display + Studio Display", "derived name, built-in first")
        try store.renameGroup(monitorGroup, to: "  Desk  ")
        try checkEqual(store.name(of: store.library.groups[1]), "Desk", "custom group name")
        try store.renameGroup(monitorGroup, to: "  ")
        try checkEqual(store.library.groups[1].customName, nil, "blank name restores the derived name")
        try expectThrow({ try store.renameGroup("nope", to: "X") }, "unknown group is rejected")

        let copy = try store.duplicate(a.id)
        try checkEqual(names(store.layouts(inGroup: monitorGroup)), ["C", "A", "A copy", "B"], "duplicate follows the original")
        try check(copy.id != a.id && copy.hotkey == nil && !copy.autoApply, "duplicate is a fresh layout")

        try store.delete(p.id)
        try checkEqual(store.library.groups.map(\.id), [monitorGroup], "empty groups are removed")
        for layout in [a, b, c, copy] { try store.delete(layout.id) }
        try check(store.library.groups.isEmpty && store.library.layouts.isEmpty, "everything deleted")
        try expectThrow({ try store.delete(a.id) }, "deleting twice fails")
    }
}

private func testGroupNameFallback() throws {
    try withStore { store, engine, _ in
        engine.current = LayoutSnapshot(displays: [
            display(id: "builtin", name: "Built-in Display"),
            display(id: "external", name: "Display 2", x: 1728, mirrorSourceID: "builtin")
        ])
        let layout = try store.saveCurrent(named: nil)
        try checkEqual(store.name(of: store.library.groups[0]), "Built-in Display + Display 2", "fallback names are remembered")
        engine.current.displays[1].name = "LG UltraFine"
        _ = try store.refresh()
        try checkEqual(store.library.displayNames[displayID("external")], "LG UltraFine", "real names replace fallbacks")
        engine.current.displays[1].name = "Display 2"
        _ = try store.refresh()
        try checkEqual(store.library.displayNames[displayID("external")], "LG UltraFine", "fallbacks never replace real names")
        try checkEqual(store.summary(for: layout), "2 displays · Mirrored", "mirrored summary")
        try checkEqual(store.displayName(for: displayID("other")), "Display", "unknown display")
    }
}

private func testUpdateValidation() throws {
    try withStore { store, engine, _ in
        let available = [mode(), mode(width: 1440, height: 900, pixelWidth: 2880, pixelHeight: 1800)]
        engine.current = snapshot(availableModes: available)
        let original = try store.saveCurrent(named: "Desk")

        var edited = original
        edited.name = " Edited "
        edited.snapshot.displays[1].x = -1440
        edited.snapshot.displays[1].mode = available[1]
        edited.createdAt = Date(timeIntervalSince1970: 0)
        try store.update(edited)
        let stored = store.layout(id: original.id)!
        try checkEqual(stored.name, "Edited", "update trims the name")
        try checkEqual(stored.snapshot.displays[1].x, -1440, "update stores geometry")
        try checkEqual(stored.createdAt, original.createdAt, "update preserves createdAt")
        try check(stored.modifiedAt >= original.modifiedAt, "update sets modifiedAt")

        var topology = stored
        topology.snapshot = snapshot(externalID: "projector")
        try expectThrow({ try store.update(topology) }, "topology changes are rejected")
        var unavailable = stored
        unavailable.snapshot.displays[1].mode = mode(width: 1024, height: 768, pixelWidth: 1024, pixelHeight: 768)
        unavailable.snapshot.displays[1].x = -1024
        try expectThrow({ try store.update(unavailable) }, "unavailable modes are rejected")
        var overlap = stored
        overlap.snapshot.displays[1].x = -100
        try expectThrow({ try store.update(overlap) }, "overlapping arrangements are rejected")
        var empty = stored
        empty.name = "  "
        try expectThrow({ try store.update(empty) }, "empty names are rejected")
        var missing = stored
        missing.id = UUID()
        try expectThrow({ try store.update(missing) }, "unknown layouts are rejected")
        try checkEqual(store.layout(id: original.id), stored, "rejected updates leave the layout unchanged")

        var legacyModes = stored
        legacyModes.snapshot.displays[1].availableModes = nil
        legacyModes.snapshot.displays[1].mode = mode(width: 1024, height: 768, pixelWidth: 1024, pixelHeight: 768)
        legacyModes.snapshot.displays[1].x = -1024
        try store.update(legacyModes)
        try checkEqual(store.layout(id: original.id)?.snapshot.displays[1].mode.width, 1024, "nil mode lists are not checked")
    }
}

private func testAutomaticAndHotkeys() throws {
    try withStore { store, engine, _ in
        let a = try store.saveCurrent(named: "A")
        let b = try store.saveCurrent(named: "B")
        engine.current = snapshot(externalID: "projector")
        let p = try store.saveCurrent(named: "P")
        engine.current = snapshot()

        try store.setAutomaticLayout(inGroup: a.groupID, layoutID: a.id)
        try store.setAutomaticLayout(inGroup: p.groupID, layoutID: p.id)
        try store.setAutomaticLayout(inGroup: a.groupID, layoutID: b.id)
        try checkEqual(store.automaticLayoutID(inGroup: a.groupID), b.id, "automatic layout switches")
        try check(store.layout(id: a.id)?.autoApply == false, "only one automatic layout per group")
        try checkEqual(store.automaticLayoutID(inGroup: p.groupID), p.id, "other groups are independent")
        try checkEqual(store.automaticLayout(for: engine.current)?.id, b.id, "automatic layout matches exact topology")
        try check(store.automaticLayout(for: snapshot(externalID: "other")) == nil, "other topologies have no rule")
        try expectThrow({ try store.setAutomaticLayout(inGroup: a.groupID, layoutID: p.id) }, "layout must belong to the group")

        var edited = store.layout(id: a.id)!
        edited.autoApply = true
        try store.update(edited)
        try checkEqual(store.automaticLayoutID(inGroup: a.groupID), a.id, "update enforces exclusivity")
        try check(store.layout(id: b.id)?.autoApply == false, "update clears the previous automatic layout")
        try store.setAutomaticLayout(inGroup: a.groupID, layoutID: nil)
        try checkEqual(store.automaticLayoutID(inGroup: a.groupID), nil, "automatic restore can be turned off")

        let hotkey = Hotkey(keyCode: 18, modifiers: Hotkey.control | Hotkey.option, key: "1")
        try store.setHotkey(hotkey, for: a.id)
        try store.setHotkey(Hotkey(keyCode: 18, modifiers: Hotkey.control | Hotkey.option, key: "!"), for: b.id)
        try checkEqual(store.layout(id: a.id)?.hotkey, nil, "a reassigned hotkey moves to the new layout")
        try checkEqual(store.layout(id: b.id)?.hotkey?.keyCode, 18, "new owner keeps the hotkey")
        try checkEqual(hotkey.displayString, "⌃⌥1", "hotkey display string")
        var withHotkey = store.layout(id: p.id)!
        withHotkey.hotkey = hotkey
        try store.update(withHotkey)
        try checkEqual(store.layout(id: b.id)?.hotkey, nil, "update enforces unique hotkeys")
        try store.setHotkey(nil, for: p.id)
        try checkEqual(store.layout(id: p.id)?.hotkey, nil, "hotkeys can be cleared")
    }
}

private func testIdentifierLookup() throws {
    try withStore { store, _, _ in
        let a = try store.saveCurrent(named: "Desk")
        _ = try store.saveCurrent(named: "Twin")
        _ = try store.saveCurrent(named: "twin ")
        try checkEqual(store.layout(matchingIdentifier: a.id.uuidString.lowercased())?.id, a.id, "UUID lookup")
        try checkEqual(store.layout(matchingIdentifier: " desk ")?.id, a.id, "case-insensitive name lookup")
        try check(store.layout(matchingIdentifier: "Twin") == nil, "ambiguous names resolve to nil")
        try check(store.layout(matchingIdentifier: "nothing") == nil, "unknown names resolve to nil")
    }
    try withDirectory { directory in
        try ProfileRepository(directory: directory.appendingPathComponent("Profiles"))
            .save(saved(id: "monitor-right", title: "Monitor Right", snapshot: snapshot()))
        let store = LayoutStore(directory: directory, engine: FakeEngine())
        try checkEqual(store.layout(matchingIdentifier: "MONITOR-RIGHT")?.legacyID, "monitor-right", "legacy ID lookup")
    }
}

private func testApplyAndUndo() throws {
    try withStore { store, engine, _ in
        let target = snapshot(externalX: -1728)
        engine.current = target
        let layout = try store.saveCurrent(named: "Left")
        try store.setAutomaticLayout(inGroup: layout.groupID, layoutID: layout.id)
        engine.current = snapshot()
        try checkEqual(store.activeLayoutID(in: engine.current), nil, "no layout is active")
        try check(store.canAutomaticallyApply(layout, to: engine.current), "geometry-only automatic change is safe")
        try check(!store.canAutomaticallyApply(layout, to: snapshot(externalMode: mode(refreshRate: 120))), "mode changes need review")
        engine.current = snapshot(externalMode: mode(refreshRate: 120))
        try expectThrow({ try store.apply(layout.id, automatic: true) }, "automatic apply rechecks modes")
        try checkEqual(engine.applyCount, 0, "automatic recheck must not mutate displays")
        engine.current = snapshot()
        engine.rejectValidation = true
        try expectThrow({ try store.apply(layout.id) }, "failed preflight must reject")
        try check(engine.applyCount == 0 && store.undoActionTitle == nil, "failed preflight must not mutate or replace Undo")
        engine.rejectValidation = false
        try expectThrow({ try store.apply(UUID()) }, "unknown layouts are rejected")
        try store.apply(layout.id)
        try check(engine.current.matches(target) && engine.applyCount == 1, "apply restores the target")
        try checkEqual(store.undoActionTitle, "Undo Left", "undo title")
        try checkEqual(store.activeLayoutID(in: engine.current), layout.id, "applied layout is active")
        try store.apply(layout.id)
        try checkEqual(engine.applyCount, 1, "the current layout is a no-op")
        engine.failApply = true
        try expectThrow({ try store.undo() }, "failed Undo reports failure")
        try check(store.undoActionTitle != nil, "failed Undo remains available")
        engine.failApply = false
        try store.undo()
        try check(engine.current.matches(snapshot()) && store.undoActionTitle == nil, "Undo restores the prior configuration")

        engine.current = snapshot(externalID: "projector")
        do {
            try store.apply(layout.id)
            throw TestFailure(message: "apply with other displays must fail")
        } catch LayoutError.displayNotConnected(let name) {
            try checkEqual(name, "Left", "not-connected error names the layout")
        }

        engine.current = snapshot()
        try store.replaceWithCurrent(layout.id)
        try check(store.layout(id: layout.id)!.snapshot.matches(snapshot()), "replace stores the current arrangement")
        try checkEqual(store.layout(id: layout.id)?.autoApply, true, "replace keeps automatic restore")
        engine.current = snapshot(externalID: "projector")
        try expectThrow({ try store.replaceWithCurrent(layout.id) }, "replace requires the same displays")
    }
}

// MARK: Persistence and migration

private func testPersistenceFiles() throws {
    try withStore { store, _, directory in
        _ = try store.saveCurrent(named: "A")
        _ = try store.saveCurrent(named: "B")
        let fm = FileManager.default
        let library = directory.appendingPathComponent("library.json")
        let previous = directory.appendingPathComponent("library.previous.json")
        try check(fm.fileExists(atPath: previous.path), "the prior file is kept")
        let prior = try JSONDecoder.iso.decode(LayoutLibrary.self, from: Data(contentsOf: previous))
        try checkEqual(names(prior.layouts), ["A"], "previous copy holds the prior library")
        let permissions = try fm.attributesOfItem(atPath: library.path)[.posixPermissions] as? NSNumber
        try checkEqual(permissions?.intValue, 0o600, "library is owner-only")
        let dirPermissions = try fm.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        try checkEqual(dirPermissions?.intValue, 0o700, "directory is owner-only")
    }
}

private func testMigration() throws {
    try withDirectory { directory in
        let profiles = directory.appendingPathComponent("Profiles")
        let repository = ProfileRepository(directory: profiles)
        let projector = snapshot(externalID: "projector", externalMirrorSourceID: "builtin")
        try repository.save(saved(id: "custom-b", title: "Custom", snapshot: snapshot(externalY: -1117)))
        try repository.save(saved(id: "projector-mirror", title: "Projector Mirror", snapshot: projector, autoApply: true))
        try repository.save(saved(id: "monitor-right", title: "Monitor Right", snapshot: snapshot(), autoApply: true))
        try repository.save(saved(id: "ipad-left", title: "iPad Left", snapshot: snapshot(externalID: "other", externalX: -1728)))
        try repository.save(saved(id: "a-custom", title: "Another", snapshot: snapshot(externalX: -1728)))
        let before = try FileManager.default.contentsOfDirectory(atPath: profiles.path).sorted()

        let engine = FakeEngine()
        let store = LayoutStore(directory: directory, engine: engine)
        let library = store.library
        try checkEqual(library.layouts.compactMap(\.legacyID), ["ipad-left", "monitor-right", "projector-mirror", "a-custom", "custom-b"],
                       "known presets first, then others by id")
        try checkEqual(names(library.layouts), ["iPad Left", "Monitor Right", "Projector Mirror", "Another", "Custom"], "titles become names")
        try check(library.hasCompletedOnboarding, "migrated users skip onboarding")
        try checkEqual(library.layouts[1].createdAt, Date(timeIntervalSince1970: 1_700_000_000), "dates come from savedAt")
        try check(library.layouts[1].autoApply && library.layouts[2].autoApply, "automatic flags are kept")
        try checkEqual(library.groups.count, 3, "groups are created for each display set")
        try checkEqual(try FileManager.default.contentsOfDirectory(atPath: profiles.path).sorted(), before, "1.x files are untouched")
        try check(FileManager.default.fileExists(atPath: directory.appendingPathComponent("library.json").path), "migration is saved")

        // Migration runs once: new 1.x files are ignored once library.json exists.
        try repository.save(saved(id: "ipad-right", title: "iPad Right", snapshot: snapshot()))
        try checkEqual(LayoutStore(directory: directory, engine: engine).library.layouts.count, 5, "migration runs only once")
    }
    try withStore { store, _, _ in
        try check(!store.library.hasCompletedOnboarding && store.library.layouts.isEmpty, "fresh installs start empty")
    }
}

private func testLegacyCommandImport() throws {
    try withDirectory { directory in
        let profiles = directory.appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try legacyCommand(snapshot(externalX: 0, externalY: -1117)).write(to: profiles.appendingPathComponent("samsung-above.command"), atomically: true, encoding: .utf8)
        try legacyCommand(snapshot(externalID: "projector")).write(to: profiles.appendingPathComponent("ipad-left.command"), atomically: true, encoding: .utf8)
        let engine = FakeEngine()
        let store = LayoutStore(directory: directory, engine: engine)
        try check(store.library.layouts.isEmpty, "commands are not imported at launch")
        _ = try store.refresh()
        try checkEqual(store.library.layouts.map(\.legacyID), ["monitor-above"], "only commands matching connected hardware import")
        try checkEqual(store.library.layouts.first?.name, "Monitor Above", "legacy title")
        try store.delete(store.library.layouts[0].id)
        _ = try store.refresh()
        try check(store.library.layouts.isEmpty, "deleted legacy layouts are not reimported")
        try checkEqual(store.library.importedLegacyIDs, ["monitor-above"], "imported IDs are recorded")
        engine.current = snapshot(externalID: "projector")
        _ = try store.refresh()
        try checkEqual(store.library.layouts.map(\.legacyID), ["ipad-left"], "commands import when their displays connect")
        try check(FileManager.default.fileExists(atPath: profiles.appendingPathComponent("samsung-above.command").path), "command files are kept")
    }
}

private func testTolerantDecoding() throws {
    try withDirectory { directory in
        let json = """
        {"layouts":[{"id":"6A1E8C8E-6C2B-4C4E-9E43-2B0C3C6E7A11","name":"Minimal","snapshot":{"displays":[
        {"id":"\(displayID("builtin"))","name":"A","vendor":1,"model":2,"serial":3,"builtIn":true,
         "mode":{"width":100,"height":100,"pixelWidth":100,"pixelHeight":100,"refreshRate":60},
         "x":0,"y":0,"rotation":0}]}}]}
        """
        try json.write(to: directory.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
        let store = LayoutStore(directory: directory, engine: FakeEngine())
        let library = store.library
        try checkEqual(names(library.layouts), ["Minimal"], "minimal JSON loads")
        try checkEqual(library.groups.map(\.id), [library.layouts[0].groupID], "missing groups are rebuilt")
        try check(!library.layouts[0].autoApply && library.layouts[0].hotkey == nil, "defaults apply")
        try checkEqual(store.loadIssue, nil, "no load issue")
    }
}

private func testNewerSchemaProtection() throws {
    try withDirectory { directory in
        let url = directory.appendingPathComponent("library.json")
        let json = #"{"schemaVersion": 99, "layouts": "something new"}"#
        try json.write(to: url, atomically: true, encoding: .utf8)
        let store = LayoutStore(directory: directory, engine: FakeEngine())
        try check(store.library.layouts.isEmpty, "newer libraries load nothing")
        try check(store.loadIssue != nil, "newer libraries report an issue")
        try expectThrow({ _ = try store.saveCurrent(named: "X") }, "edits throw")
        try expectThrow({ try store.setOnboardingCompleted() }, "edits throw")
        _ = try store.refresh()
        try checkEqual(try String(contentsOf: url, encoding: .utf8), json, "the newer file is never overwritten")
    }
}

private func testCorruptBackup() throws {
    try withDirectory { directory in
        let url = directory.appendingPathComponent("library.json")
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let store = LayoutStore(directory: directory, engine: FakeEngine())
        try check(store.library.layouts.isEmpty && store.loadIssue != nil, "corrupt libraries start empty with an issue")
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("library.corrupt-") }
        try checkEqual(backups.count, 1, "corrupt file is backed up")
        try checkEqual(try String(contentsOf: directory.appendingPathComponent(backups[0]), encoding: .utf8), "{ not json", "backup is intact")
        _ = try store.saveCurrent(named: "After")
        try checkEqual(names(LayoutStore(directory: directory, engine: FakeEngine()).library.layouts), ["After"], "edits work afterwards")
    }
}

private func testRenameAdoption() throws {
    try withDirectory { root in
        let legacy = root.appendingPathComponent("Display Layouts")
        let current = root.appendingPathComponent("Screen Setter")
        let fm = FileManager.default
        _ = try LayoutStore(directory: legacy, engine: FakeEngine()).saveCurrent(named: "Before Rename")
        let store = LayoutStore(directory: current, legacyDirectory: legacy, engine: FakeEngine())
        try checkEqual(names(store.library.layouts), ["Before Rename"], "a pre-rename library is adopted")
        let permissions = try fm.attributesOfItem(atPath: current.appendingPathComponent("library.json").path)[.posixPermissions] as? NSNumber
        try checkEqual(permissions?.intValue, 0o600, "the adopted library is owner-only")
        _ = try store.saveCurrent(named: "After Rename")
        let original = try JSONDecoder.iso.decode(LayoutLibrary.self, from: Data(contentsOf: legacy.appendingPathComponent("library.json")))
        try checkEqual(names(original.layouts), ["Before Rename"], "the pre-rename library is never written")
        let reloaded = LayoutStore(directory: current, legacyDirectory: legacy, engine: FakeEngine())
        try checkEqual(names(reloaded.library.layouts), ["Before Rename", "After Rename"], "the new library wins once it exists")
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

@main
struct ProfileTests {
    static func main() {
        let tests: [(String, () throws -> Void)] = [
            ("semantic equality", testSemanticEquality),
            ("legacy parser", testLegacyParser),
            ("arrangement issues", testArrangementIssues),
            ("editor movement and snapping", testEditorMovementAndSnapping),
            ("editor main display", testEditorMainDisplay),
            ("editor mirroring", testEditorMirroring),
            ("editor resolution and rotation", testEditorResolutionAndRotation),
            ("editor keyboard movement", testEditorKeyboardMovement),
            ("editor operation sequences", testEditorOperationSequences),
            ("automation links", runLinkTests),
            ("save and names", testSaveAndNames),
            ("groups, ordering, duplicate, delete", testGroups),
            ("group name fallbacks", testGroupNameFallback),
            ("update validation", testUpdateValidation),
            ("automatic layouts and hotkeys", testAutomaticAndHotkeys),
            ("identifier lookup", testIdentifierLookup),
            ("apply and undo", testApplyAndUndo),
            ("persistence files", testPersistenceFiles),
            ("1.x migration", testMigration),
            ("legacy command import", testLegacyCommandImport),
            ("tolerant decoding", testTolerantDecoding),
            ("newer schema protection", testNewerSchemaProtection),
            ("corrupt file backup", testCorruptBackup),
            ("rename adoption", testRenameAdoption)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try test()
                print("PASS: \(name)")
            } catch {
                failures += 1
                fputs("FAIL: \(name): \(error)\n", stderr)
            }
        }
        if failures > 0 {
            fputs("\(failures) test group(s) failed\n", stderr)
            exit(1)
        }
        print("All tests passed")
    }
}
