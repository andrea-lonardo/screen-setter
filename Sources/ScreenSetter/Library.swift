import Foundation

/// A system-wide key combination. `keyCode` is a virtual key code (kVK_*), and
/// `modifiers` uses Carbon flags so it can be registered directly.
struct Hotkey: Codable, Hashable, Sendable {
    static let command: UInt32 = 1 << 8
    static let shift: UInt32 = 1 << 9
    static let option: UInt32 = 1 << 11
    static let control: UInt32 = 1 << 12

    var keyCode: UInt32
    var modifiers: UInt32
    /// The key's printable name captured at record time, such as "1" or "F5".
    var key: String

    var displayString: String {
        var result = ""
        if modifiers & Self.control != 0 { result += "⌃" }
        if modifiers & Self.option != 0 { result += "⌥" }
        if modifiers & Self.shift != 0 { result += "⇧" }
        if modifiers & Self.command != 0 { result += "⌘" }
        return result + key.uppercased()
    }

    /// Hotkeys are the same shortcut when key code and modifiers match; `key` is only a label.
    func isSameShortcut(as other: Hotkey) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

/// One user-defined arrangement of an exact set of displays.
struct Layout: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var snapshot: LayoutSnapshot
    var createdAt: Date
    var modifiedAt: Date
    var autoApply: Bool = false
    var hotkey: Hotkey?
    /// The 1.x preset identifier (for example "ipad-left"), kept so existing
    /// displaylayouts://apply/<id> and screensetter://apply/<id> actions continue to work after migration.
    var legacyID: String?

    /// Layouts are grouped by the exact set of displays they use.
    var groupID: String { snapshot.topologyKey }
    var isMirrored: Bool { snapshot.displays.contains { $0.mirrorSourceID != nil } }
}

/// A display set. Created automatically when a layout for new hardware is saved;
/// removed when its last layout is deleted.
struct DisplayGroup: Codable, Identifiable, Equatable, Sendable {
    /// `LayoutSnapshot.topologyKey` of the displays in this set.
    var id: String
    /// A user-chosen name; when nil the name is derived from the display names.
    var customName: String?
}

struct LayoutLibrary: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var schemaVersion = LayoutLibrary.currentSchemaVersion
    /// Ordered. The relative order of layouts that share a group is their order in that group.
    var layouts: [Layout] = []
    /// Ordered. Every group has at least one layout.
    var groups: [DisplayGroup] = []
    /// Last known human-readable name for each display UUID (uppercased). Mirrored
    /// displays are not always reported by macOS, so names are remembered.
    var displayNames: [String: String] = [:]
    var hasCompletedOnboarding = false
    /// 1.x preset identifiers already imported, so deleting a migrated layout does
    /// not import its legacy file again.
    var importedLegacyIDs: [String] = []
}

// Decoders live in extensions to keep the memberwise initializers. Every defaulted
// field is optional in JSON so older or hand-edited libraries still load.
extension Layout {
    private enum CodingKeys: String, CodingKey {
        case id, name, snapshot, createdAt, modifiedAt, autoApply, hotkey, legacyID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        snapshot = try container.decode(LayoutSnapshot.self, forKey: .snapshot)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        autoApply = try container.decodeIfPresent(Bool.self, forKey: .autoApply) ?? false
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        legacyID = try container.decodeIfPresent(String.self, forKey: .legacyID)
    }
}

extension LayoutLibrary {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, layouts, groups, displayNames, hasCompletedOnboarding, importedLegacyIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        layouts = try container.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        groups = try container.decodeIfPresent([DisplayGroup].self, forKey: .groups) ?? []
        displayNames = try container.decodeIfPresent([String: String].self, forKey: .displayNames) ?? [:]
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        importedLegacyIDs = try container.decodeIfPresent([String].self, forKey: .importedLegacyIDs) ?? []
    }
}
