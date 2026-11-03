import Foundation

// Thread safety: every method may be called from any thread. Methods marked
// "display queue" talk to the display engine and must only be called from the
// app's serial display queue (never the main thread). Edits persist immediately
// to library.json and throw on failure, leaving the in-memory library unchanged.

final class LayoutStore: @unchecked Sendable {
    private let repository: LibraryRepository
    private let engine: any DisplayControlling
    private let lock = NSRecursiveLock()
    private var state = LayoutLibrary()
    /// Set when library.json must not be overwritten (newer version or unreadable).
    private var readOnlyError: LayoutError?
    private var undoSnapshot: LayoutSnapshot?
    private var undoTitle: String?

    /// A message for the user when the library could not be loaded normally, such
    /// as a newer-version file or a corrupt file that was backed up. Nil when fine.
    private(set) var loadIssue: String?

    init(directory: URL? = nil, legacyDirectory: URL? = nil, engine: any DisplayControlling = DisplayEngine()) {
        self.engine = engine
        repository = LibraryRepository(directory: directory, legacyDirectory: legacyDirectory)
        switch repository.load() {
        case .loaded(let library):
            state = Self.normalized(library)
        case .migrated(let library):
            state = Self.normalized(library)
            if !library.layouts.isEmpty { try? repository.save(state) }
        case .corrupt(let backup):
            try? repository.save(state)
            loadIssue = "Your saved layouts could not be read. The damaged file was kept as “\(backup.lastPathComponent)” and Screen Setter started with no layouts."
        case .newerVersion:
            readOnlyError = .newerLibrary
            state.hasCompletedOnboarding = true
            loadIssue = LayoutError.newerLibrary.errorDescription
        case .unreadable:
            readOnlyError = .libraryUnreadable
            state.hasCompletedOnboarding = true
            loadIssue = LayoutError.libraryUnreadable.errorDescription
        }
    }

    private func locked<T>(_ work: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try work()
    }

    /// Applies `change` to a copy, normalizes it, persists it, and only then publishes it.
    private func commit(_ change: (inout LayoutLibrary) throws -> Void) throws {
        try locked {
            if let readOnlyError { throw readOnlyError }
            var library = state
            try change(&library)
            library = Self.normalized(library)
            guard library != state else { return }
            try repository.save(library)
            state = library
        }
    }

    /// Restores invariants: one group per display set in use (new sets appended,
    /// empty ones removed), at most one automatic layout per group, unique hotkeys,
    /// and every legacy ID in use recorded as imported.
    private static func normalized(_ input: LayoutLibrary) -> LayoutLibrary {
        var library = input
        library.schemaVersion = LayoutLibrary.currentSchemaVersion
        var seenIDs = Set<UUID>()
        library.layouts = library.layouts.filter { seenIDs.insert($0.id).inserted }

        let used = Set(library.layouts.map(\.groupID))
        var groupIDs = Set<String>()
        library.groups = library.groups.filter { used.contains($0.id) && groupIDs.insert($0.id).inserted }
        for layout in library.layouts where groupIDs.insert(layout.groupID).inserted {
            library.groups.append(DisplayGroup(id: layout.groupID))
        }

        var automaticGroups = Set<String>()
        var hotkeys: [Hotkey] = []
        for index in library.layouts.indices {
            if library.layouts[index].autoApply, !automaticGroups.insert(library.layouts[index].groupID).inserted {
                library.layouts[index].autoApply = false
            }
            if let hotkey = library.layouts[index].hotkey {
                if hotkeys.contains(where: { $0.isSameShortcut(as: hotkey) }) {
                    library.layouts[index].hotkey = nil
                } else {
                    hotkeys.append(hotkey)
                }
            }
        }

        var imported = Set(library.importedLegacyIDs.map { $0.lowercased() })
        imported.formUnion(library.layouts.compactMap { $0.legacyID?.lowercased() })
        library.importedLegacyIDs = imported.sorted()
        return library
    }

    private static func index(of id: UUID, in library: LayoutLibrary) throws -> Int {
        guard let index = library.layouts.firstIndex(where: { $0.id == id }) else { throw LayoutError.layoutNotFound }
        return index
    }

    private static func trimmedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LayoutError.emptyName }
        return trimmed
    }

    /// Records real display names, and fallbacks only for displays never named before.
    private static func rememberNames(in snapshot: LayoutSnapshot, library: inout LayoutLibrary) {
        for display in snapshot.displays {
            let key = display.id.uppercased()
            if !display.hasFallbackName || (library.displayNames[key] == nil && !display.name.isEmpty
                && display.name != "Built-in display" && display.name != "External display") {
                library.displayNames[key] = display.name
            }
        }
    }

    /// Moves elements with SwiftUI `onMove` semantics.
    private static func moved<T>(_ items: [T], from source: IndexSet, to destination: Int) -> [T] {
        let source = source.filteredIndexSet { items.indices.contains($0) }
        let destination = min(max(destination, 0), items.count)
        let moving = source.map { items[$0] }
        var result = items.indices.filter { !source.contains($0) }.map { items[$0] }
        result.insert(contentsOf: moving, at: destination - source.count(in: 0..<destination))
        return result
    }

    // MARK: Reads

    /// A consistent copy of the whole library.
    var library: LayoutLibrary { locked { state } }

    func layout(id: UUID) -> Layout? {
        locked { state.layouts.first { $0.id == id } }
    }

    /// Layouts of one display set, in user order.
    func layouts(inGroup groupID: String) -> [Layout] {
        locked { state.layouts.filter { $0.groupID == groupID } }
    }

    /// Resolves a URL/Shortcuts identifier: a layout UUID, a 1.x legacy ID, or a
    /// case-insensitive exact layout name (nil when ambiguous).
    func layout(matchingIdentifier identifier: String) -> Layout? {
        let wanted = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        return locked {
            if let id = UUID(uuidString: wanted), let layout = state.layouts.first(where: { $0.id == id }) {
                return layout
            }
            if let layout = state.layouts.first(where: { $0.legacyID?.caseInsensitiveCompare(wanted) == .orderedSame }) {
                return layout
            }
            let named = state.layouts.filter {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(wanted) == .orderedSame
            }
            return named.count == 1 ? named[0] : nil
        }
    }

    /// The custom name, or the display names joined with " + " (built-in first).
    func name(of group: DisplayGroup) -> String {
        if let custom = group.customName?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return locked {
            let displays: [(builtIn: Bool, name: String)]
            if let snapshot = state.layouts.first(where: { $0.groupID == group.id })?.snapshot {
                displays = snapshot.displays.map { ($0.builtIn, displayName(for: $0.id, builtIn: $0.builtIn)) }
            } else {
                displays = group.id.split(separator: "+").map { (false, displayName(for: String($0), builtIn: false)) }
            }
            let ordered = displays.filter(\.builtIn) + displays.filter { !$0.builtIn }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            var seen = Set<String>()
            return ordered.map(\.name).filter { seen.insert($0).inserted }.joined(separator: " + ")
        }
    }

    /// The remembered name of a display, else a generic one.
    func displayName(for displayID: String, builtIn: Bool = false) -> String {
        locked { state.displayNames[displayID.uppercased()] } ?? (builtIn ? "Built-in Display" : "Display")
    }

    /// "2 displays · Extended" / "3 displays · Mirrored".
    func summary(for layout: Layout) -> String {
        let count = layout.snapshot.displays.count
        guard count > 1 else { return "1 display" }
        return "\(count) displays · \(layout.isMirrored ? "Mirrored" : "Extended")"
    }

    func activeLayoutID(in snapshot: LayoutSnapshot) -> UUID? {
        locked { state.layouts.first { $0.snapshot.matches(snapshot) }?.id }
    }

    func automaticLayoutID(inGroup groupID: String) -> UUID? {
        locked { state.layouts.first { $0.groupID == groupID && $0.autoApply }?.id }
    }

    func automaticLayout(for snapshot: LayoutSnapshot) -> Layout? {
        locked {
            let matching = state.layouts.filter { $0.autoApply && $0.groupID == snapshot.topologyKey }
            return matching.count == 1 ? matching[0] : nil
        }
    }

    func canAutomaticallyApply(_ layout: Layout, to current: LayoutSnapshot) -> Bool {
        let saved = layout.snapshot
        guard saved.topologyKey == current.topologyKey else { return false }
        // Automatic restoration only moves geometry; changed modes/mirroring/rotation need manual review.
        return saved.displays.allSatisfy { wanted in
            guard let live = current.displays.first(where: { $0.id.uppercased() == wanted.id.uppercased() }) else { return false }
            return wanted.mode == live.mode && wanted.rotation == live.rotation
                && wanted.mirrorSourceID?.uppercased() == live.mirrorSourceID?.uppercased()
        }
    }

    var undoActionTitle: String? { locked { undoTitle } }

    // MARK: Display operations (display queue)

    /// Captures the current displays, updates remembered display names, and
    /// imports compatible 1.x legacy profiles.
    func refresh() throws -> LayoutSnapshot {
        let current = try engine.capture()
        // Best effort: a failed write must not hide the current arrangement.
        try? commit { library in
            Self.rememberNames(in: current, library: &library)
            let imported = Set(library.importedLegacyIDs)
            for preset in LibraryRepository.legacyPresetTitles where !imported.contains(preset.id) {
                guard let command = repository.legacyCommand(for: preset.id),
                      let parsed = try? LegacyLayoutParser.parse(command, presetID: preset.id, title: preset.title, current: current)
                else { continue }
                let now = Date()
                library.layouts.append(Layout(id: UUID(), name: preset.title, snapshot: parsed.snapshot,
                                              createdAt: now, modifiedAt: now, legacyID: preset.id))
                library.hasCompletedOnboarding = true
            }
        }
        return current
    }

    /// Captures the current arrangement as a new layout at the end of its display
    /// set. A nil name produces a unique default such as "Layout 3".
    @discardableResult func saveCurrent(named name: String?) throws -> Layout {
        let snapshot = try engine.capture()
        guard snapshot.isValid else { throw LayoutError.invalidSnapshot }
        let explicitName = try name.map(Self.trimmedName)
        var layout: Layout?
        try commit { library in
            let now = Date()
            let used = Set(library.layouts.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            let name = explicitName ?? (1...).lazy.map { "Layout \($0)" }.first { !used.contains($0.lowercased()) }!
            let new = Layout(id: UUID(), name: name, snapshot: snapshot, createdAt: now, modifiedAt: now)
            library.layouts.append(new)
            Self.rememberNames(in: snapshot, library: &library)
            layout = new
        }
        return layout!
    }

    /// Replaces a layout's arrangement with the current one; the display set must match.
    func replaceWithCurrent(_ id: UUID) throws {
        let snapshot = try engine.capture()
        guard snapshot.isValid else { throw LayoutError.invalidSnapshot }
        try commit { library in
            let index = try Self.index(of: id, in: library)
            guard library.layouts[index].groupID == snapshot.topologyKey else { throw LayoutError.displaysChanged }
            library.layouts[index].snapshot = snapshot
            library.layouts[index].modifiedAt = Date()
            Self.rememberNames(in: snapshot, library: &library)
        }
    }

    func apply(_ id: UUID, automatic: Bool = false) throws {
        let current = try refresh()
        guard let layout = self.layout(id: id) else { throw LayoutError.layoutNotFound }
        if current.matches(layout.snapshot) { return }
        guard current.topologyKey == layout.groupID else { throw LayoutError.displayNotConnected(layout.name) }
        if automatic && !canAutomaticallyApply(layout, to: current) { throw LayoutError.automaticChanged }
        try engine.validate(layout.snapshot)
        locked { undoSnapshot = current; undoTitle = "Undo \(layout.name)" }
        try engine.apply(layout.snapshot)
    }

    func undo() throws {
        guard let previous = locked({ undoSnapshot }) else { return }
        try engine.apply(previous)
        locked { undoSnapshot = nil; undoTitle = nil }
    }

    // MARK: Edits

    func rename(_ id: UUID, to name: String) throws {
        let name = try Self.trimmedName(name)
        try commit { library in
            let index = try Self.index(of: id, in: library)
            library.layouts[index].name = name
            library.layouts[index].modifiedAt = Date()
        }
    }

    /// Saves an edited layout (name, snapshot, hotkey). The display set must not
    /// change, the snapshot must be valid, and every mode must be available.
    func update(_ layout: Layout) throws {
        let name = try Self.trimmedName(layout.name)
        guard layout.snapshot.isValid else { throw LayoutError.invalidSnapshot }
        if let issue = layout.snapshot.arrangementIssue { throw LayoutError.invalidArrangement(issue) }
        for display in layout.snapshot.displays {
            guard let modes = display.availableModes else { continue }
            let wanted = display.mode
            guard modes.contains(where: {
                $0.width == wanted.width && $0.height == wanted.height && $0.pixelWidth == wanted.pixelWidth
                    && $0.pixelHeight == wanted.pixelHeight && abs($0.refreshRate - wanted.refreshRate) <= 0.1
            }) else { throw LayoutError.modeUnavailable(display.name) }
        }
        try commit { library in
            let index = try Self.index(of: layout.id, in: library)
            let stored = library.layouts[index]
            guard stored.groupID == layout.groupID else { throw LayoutError.displaysChanged }
            var edited = layout
            edited.name = name
            edited.createdAt = stored.createdAt
            edited.modifiedAt = Date()
            edited.legacyID = stored.legacyID
            // Clear conflicts on the other layouts so normalization keeps the edited values.
            for other in library.layouts.indices where other != index {
                if edited.autoApply && library.layouts[other].groupID == edited.groupID {
                    library.layouts[other].autoApply = false
                }
                if let hotkey = edited.hotkey, library.layouts[other].hotkey?.isSameShortcut(as: hotkey) == true {
                    library.layouts[other].hotkey = nil
                }
            }
            library.layouts[index] = edited
        }
    }

    @discardableResult func duplicate(_ id: UUID) throws -> Layout {
        var copy: Layout?
        try commit { library in
            let index = try Self.index(of: id, in: library)
            let now = Date()
            let original = library.layouts[index]
            let new = Layout(id: UUID(), name: original.name + " copy", snapshot: original.snapshot, createdAt: now, modifiedAt: now)
            library.layouts.insert(new, at: index + 1)
            copy = new
        }
        return copy!
    }

    func delete(_ id: UUID) throws {
        try commit { library in
            library.layouts.remove(at: try Self.index(of: id, in: library))
        }
    }

    func moveLayouts(inGroup groupID: String, from source: IndexSet, to destination: Int) throws {
        try commit { library in
            let slots = library.layouts.indices.filter { library.layouts[$0].groupID == groupID }
            guard !slots.isEmpty else { throw LayoutError.groupNotFound }
            let reordered = Self.moved(slots.map { library.layouts[$0] }, from: source, to: destination)
            for (slot, layout) in zip(slots, reordered) { library.layouts[slot] = layout }
        }
    }

    func moveGroups(from source: IndexSet, to destination: Int) throws {
        try commit { library in
            library.groups = Self.moved(library.groups, from: source, to: destination)
        }
    }

    /// Empty or whitespace names restore the derived name.
    func renameGroup(_ groupID: String, to name: String?) throws {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        try commit { library in
            guard let index = library.groups.firstIndex(where: { $0.id == groupID }) else { throw LayoutError.groupNotFound }
            library.groups[index].customName = trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    func setAutomaticLayout(inGroup groupID: String, layoutID: UUID?) throws {
        try commit { library in
            guard library.groups.contains(where: { $0.id == groupID }) else { throw LayoutError.groupNotFound }
            if let layoutID, !library.layouts.contains(where: { $0.id == layoutID && $0.groupID == groupID }) {
                throw LayoutError.layoutNotFound
            }
            for index in library.layouts.indices where library.layouts[index].groupID == groupID {
                library.layouts[index].autoApply = library.layouts[index].id == layoutID
            }
        }
    }

    /// Assigning a hotkey already used by another layout removes it from that layout.
    func setHotkey(_ hotkey: Hotkey?, for id: UUID) throws {
        try commit { library in
            let index = try Self.index(of: id, in: library)
            if let hotkey {
                for other in library.layouts.indices where other != index
                    && library.layouts[other].hotkey?.isSameShortcut(as: hotkey) == true {
                    library.layouts[other].hotkey = nil
                }
            }
            library.layouts[index].hotkey = hotkey
        }
    }

    func setOnboardingCompleted() throws {
        try commit { $0.hasCompletedOnboarding = true }
    }
}
