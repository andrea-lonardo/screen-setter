import Foundation

struct DisplayModeSpec: Codable, Hashable, Sendable {
    var width: Int
    var height: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var refreshRate: Double

    init(
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double
    ) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }
}

struct DisplaySpec: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var builtIn: Bool
    var mode: DisplayModeSpec
    var x: Int32
    var y: Int32
    var rotation: Double
    var mirrorSourceID: String?
    /// Modes the display offered when captured, for editing while disconnected.
    /// Nil in profiles saved before 2.0.
    var availableModes: [DisplayModeSpec]?

    init(
        id: String,
        name: String,
        vendor: UInt32,
        model: UInt32,
        serial: UInt32,
        builtIn: Bool,
        mode: DisplayModeSpec,
        x: Int32,
        y: Int32,
        rotation: Double,
        mirrorSourceID: String?,
        availableModes: [DisplayModeSpec]? = nil
    ) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.builtIn = builtIn
        self.mode = mode
        self.x = x
        self.y = y
        self.rotation = rotation
        self.mirrorSourceID = mirrorSourceID
        self.availableModes = availableModes
    }
}

struct LayoutSnapshot: Codable, Equatable, Sendable {
    var displays: [DisplaySpec]

    init(displays: [DisplaySpec]) {
        self.displays = displays
    }

    /// A stable identity for the set of attached displays, independent of order.
    var topologyKey: String {
        displays.map { Self.normalizedID($0.id) }.sorted().joined(separator: "+")
    }

    var isValid: Bool {
        let ids = Set(displays.map { $0.id.uppercased() })
        guard !displays.isEmpty, ids.count == displays.count else { return false }
        return displays.allSatisfy { display in
            guard UUID(uuidString: display.id) != nil,
                  display.mode.width > 0, display.mode.height > 0,
                  display.mode.pixelWidth > 0, display.mode.pixelHeight > 0,
                  display.mode.refreshRate.isFinite, display.mode.refreshRate >= 0,
                  [0.0, 90, 180, 270].contains(display.rotation) else { return false }
            if let source = display.mirrorSourceID {
                return source.uppercased() != display.id.uppercased() && displays.contains {
                    $0.id.uppercased() == source.uppercased() && $0.mirrorSourceID == nil
                }
            }
            return true
        }
    }

    /// Compares configuration state while deliberately ignoring descriptive hardware
    /// metadata. Refresh rates from macOS and displayplacer commonly differ by a small
    /// rounding amount (for example 59.94 and 60), so 0.1 Hz is treated as equal.
    func matches(_ other: LayoutSnapshot) -> Bool {
        guard displays.count == other.displays.count else { return false }

        let lhs = displays.sorted(by: Self.displayOrder)
        let rhs = other.displays.sorted(by: Self.displayOrder)

        return zip(lhs, rhs).allSatisfy { left, right in
            Self.normalizedID(left.id) == Self.normalizedID(right.id)
                && left.mode.width == right.mode.width
                && left.mode.height == right.mode.height
                && left.mode.pixelWidth == right.mode.pixelWidth
                && left.mode.pixelHeight == right.mode.pixelHeight
                && left.mode.refreshRate.isFinite
                && right.mode.refreshRate.isFinite
                && abs(left.mode.refreshRate - right.mode.refreshRate) <= 0.1
                && left.x == right.x
                && left.y == right.y
                && left.rotation == right.rotation
                && Self.normalizedOptionalID(left.mirrorSourceID)
                    == Self.normalizedOptionalID(right.mirrorSourceID)
        }
    }

    private static func normalizedID(_ id: String) -> String {
        id.uppercased()
    }

    private static func normalizedOptionalID(_ id: String?) -> String? {
        id.map(normalizedID)
    }

    private static func displayOrder(_ lhs: DisplaySpec, _ rhs: DisplaySpec) -> Bool {
        let leftID = normalizedID(lhs.id)
        let rightID = normalizedID(rhs.id)
        if leftID != rightID { return leftID < rightID }

        // Duplicate IDs are invalid configuration data, but deterministic secondary
        // ordering keeps matches symmetric even before validation rejects such a file.
        if lhs.x != rhs.x { return lhs.x < rhs.x }
        if lhs.y != rhs.y { return lhs.y < rhs.y }
        return lhs.mirrorSourceID ?? "" < rhs.mirrorSourceID ?? ""
    }
}

struct SavedLayout: Codable, Sendable {
    var schemaVersion: Int = 1
    var presetID: String
    var title: String
    var savedAt: Date
    var snapshot: LayoutSnapshot
    var autoApply: Bool = false

    init(
        schemaVersion: Int = 1,
        presetID: String,
        title: String,
        savedAt: Date,
        snapshot: LayoutSnapshot,
        autoApply: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.presetID = presetID
        self.title = title
        self.savedAt = savedAt
        self.snapshot = snapshot
        self.autoApply = autoApply
    }
}

enum ProfileRepositoryError: LocalizedError {
    case invalidPresetID(String)
    case unsupportedSchema(Int)
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidPresetID(let id):
            return "The preset identifier “\(id)” is not valid."
        case .unsupportedSchema(let version):
            return "Profile schema version \(version) is not supported."
        case .invalidSnapshot:
            return "The saved layout contains invalid display data. Save it again in Settings."
        }
    }
}

final class ProfileRepository {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private(set) var directory: URL

    init(directory: URL? = nil) {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("Display Layouts", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load(id: String) -> SavedLayout? {
        guard Self.isValidPresetID(id),
              let data = try? Data(contentsOf: profileURL(id: id)),
              let profile = try? decoder.decode(SavedLayout.self, from: data),
              profile.schemaVersion == 1,
              profile.snapshot.isValid,
              profile.presetID == id else {
            return nil
        }
        return profile
    }

    func save(_ profile: SavedLayout) throws {
        guard Self.isValidPresetID(profile.presetID) else {
            throw ProfileRepositoryError.invalidPresetID(profile.presetID)
        }
        guard profile.schemaVersion == 1 else {
            throw ProfileRepositoryError.unsupportedSchema(profile.schemaVersion)
        }
        guard profile.snapshot.isValid else { throw ProfileRepositoryError.invalidSnapshot }

        try ensureDirectory()

        // Only one preset may be automatic for a given connected-display topology.
        // Clear peers first so a failed target write never leaves two automatic rules.
        if profile.autoApply {
            for var existing in all()
            where existing.presetID != profile.presetID
                && existing.autoApply
                && existing.snapshot.topologyKey == profile.snapshot.topologyKey {
                existing.autoApply = false
                try write(existing)
            }
        }

        try write(profile)
    }

    func clear(id: String) throws {
        guard Self.isValidPresetID(id) else {
            throw ProfileRepositoryError.invalidPresetID(id)
        }

        let url = profileURL(id: id)
        if fileManager.fileExists(atPath: url.path) {
            try Data(contentsOf: url).write(to: backupURL(id: id), options: .atomic)
            try setOwnerOnlyPermissions(on: backupURL(id: id))
            try fileManager.removeItem(at: url)
        }
    }

    func all() -> [SavedLayout] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { url -> SavedLayout? in
            let filename = url.lastPathComponent
            guard filename.hasSuffix(".json"),
                  !filename.hasSuffix(".previous.json") else {
                return nil
            }
            let id = String(filename.dropLast(".json".count))
            return load(id: id)
        }
        .sorted {
            if $0.savedAt != $1.savedAt { return $0.savedAt > $1.savedAt }
            return $0.presetID < $1.presetID
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private func write(_ profile: SavedLayout) throws {
        let destination = profileURL(id: profile.presetID)
        let backup = backupURL(id: profile.presetID)

        if fileManager.fileExists(atPath: destination.path) {
            // Data.write(.atomic) replaces the backup only after the complete prior
            // profile has been written, so an interrupted save retains a valid copy.
            let previousData = try Data(contentsOf: destination)
            try previousData.write(to: backup, options: .atomic)
            try setOwnerOnlyPermissions(on: backup)
        }

        let data = try encoder.encode(profile)
        try data.write(to: destination, options: .atomic)
        try setOwnerOnlyPermissions(on: destination)
    }

    private func setOwnerOnlyPermissions(on url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func profileURL(id: String) -> URL {
        directory.appendingPathComponent(id + ".json", isDirectory: false)
    }

    private func backupURL(id: String) -> URL {
        directory.appendingPathComponent(id + ".previous.json", isDirectory: false)
    }

    private static func isValidPresetID(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 128 else { return false }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122: // -, 0-9, A-Z, _, a-z
                return true
            default:
                return false
            }
        }
    }
}

enum LegacyLayoutParserError: LocalizedError {
    case invalidCommand(String)
    case unknownDisplay(String)
    case topologyMismatch
    case modeMismatch(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let reason):
            return "The legacy display profile is invalid: \(reason)"
        case .unknownDisplay(let id):
            return "The display with identifier \(id) is not currently connected."
        case .topologyMismatch:
            return "Reconnect the same displays used by this profile before migrating it."
        case .modeMismatch(let name):
            return "Set “\(name)” to the saved resolution, scaling, and refresh rate, then migrate the profile again."
        case .unsupported(let reason):
            return "The legacy display profile cannot be migrated safely: \(reason)"
        }
    }
}

enum LegacyLayoutParser {
    /// Parses the single, quoted command format emitted by `displayplacer list`.
    /// This is a data parser only: it never invokes a shell or executes input.
    ///
    /// Pixel dimensions are not present in legacy commands. Migration therefore
    /// succeeds only when every saved logical mode, scaling state, and refresh rate
    /// matches the connected `current` snapshot, whose exact pixel dimensions are
    /// then retained. No 2x or other scaling factor is guessed.
    static func parse(
        _ command: String,
        presetID: String,
        title: String,
        current: LayoutSnapshot
    ) throws -> SavedLayout {
        let argumentStrings = try quotedArguments(in: command)
        guard !argumentStrings.isEmpty else {
            throw LegacyLayoutParserError.invalidCommand("no display arguments were found")
        }

        var currentByID: [String: DisplaySpec] = [:]
        for display in current.displays {
            guard let normalized = normalizedUUID(display.id) else {
                throw LegacyLayoutParserError.invalidCommand(
                    "the current display identifier \(display.id) is not a UUID"
                )
            }
            guard currentByID[normalized] == nil else {
                throw LegacyLayoutParserError.invalidCommand(
                    "the current display list contains duplicate identifiers"
                )
            }
            currentByID[normalized] = display
        }

        var migrated: [DisplaySpec] = []
        var seenIDs = Set<String>()

        for argument in argumentStrings {
            let legacy = try parseDisplayArgument(argument)
            let sourceID = legacy.ids[0]

            for (index, id) in legacy.ids.enumerated() {
                guard seenIDs.insert(id).inserted else {
                    throw LegacyLayoutParserError.invalidCommand(
                        "display identifier \(id) occurs more than once"
                    )
                }
                guard let connected = currentByID[id] else {
                    throw LegacyLayoutParserError.unknownDisplay(id)
                }
                guard connected.mode.width > 0,
                      connected.mode.height > 0,
                      connected.mode.pixelWidth > 0,
                      connected.mode.pixelHeight > 0,
                      connected.mode.refreshRate.isFinite,
                      connected.mode.width == legacy.width,
                      connected.mode.height == legacy.height,
                      abs(connected.mode.refreshRate - legacy.refreshRate) <= 0.1,
                      isScaled(connected.mode) == legacy.scaling else {
                    throw LegacyLayoutParserError.modeMismatch(connected.name)
                }

                migrated.append(DisplaySpec(
                    id: id,
                    name: connected.name,
                    vendor: connected.vendor,
                    model: connected.model,
                    serial: connected.serial,
                    builtIn: connected.builtIn,
                    mode: connected.mode,
                    x: legacy.x,
                    y: legacy.y,
                    rotation: legacy.rotation,
                    mirrorSourceID: index == 0 ? nil : sourceID
                ))
            }
        }

        guard seenIDs == Set(currentByID.keys) else {
            throw LegacyLayoutParserError.topologyMismatch
        }

        return SavedLayout(
            presetID: presetID,
            title: title,
            savedAt: Date(),
            snapshot: LayoutSnapshot(displays: migrated)
        )
    }

    private struct LegacyDisplayArgument {
        let ids: [String]
        let width: Int
        let height: Int
        let refreshRate: Double
        let scaling: Bool
        let x: Int32
        let y: Int32
        let rotation: Double
    }

    private static let expectedKeys: Set<String> = [
        "id", "res", "hz", "color_depth", "enabled", "scaling", "origin", "degree"
    ]

    private static func quotedArguments(in rawCommand: String) throws -> [String] {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw LegacyLayoutParserError.invalidCommand("the command is empty")
        }

        var index = command.startIndex
        let executableStart = index
        while index < command.endIndex, !command[index].isWhitespace {
            index = command.index(after: index)
        }
        let executable = String(command[executableStart..<index])
        guard !executable.contains("\"") && !executable.contains("\\"),
              URL(fileURLWithPath: executable).lastPathComponent == "displayplacer" else {
            throw LegacyLayoutParserError.invalidCommand("the executable is not displayplacer")
        }

        var arguments: [String] = []
        while true {
            while index < command.endIndex, command[index].isWhitespace {
                index = command.index(after: index)
            }
            guard index < command.endIndex else { break }
            guard command[index] == "\"" else {
                throw LegacyLayoutParserError.invalidCommand(
                    "each display argument must be enclosed in double quotes"
                )
            }
            index = command.index(after: index)
            let argumentStart = index
            while index < command.endIndex, command[index] != "\"" {
                let character = command[index]
                guard character != "\\", !character.isNewline else {
                    throw LegacyLayoutParserError.invalidCommand(
                        "escaped or multiline display arguments are not supported"
                    )
                }
                index = command.index(after: index)
            }
            guard index < command.endIndex else {
                throw LegacyLayoutParserError.invalidCommand("a display argument is unterminated")
            }
            let argument = String(command[argumentStart..<index])
            guard !argument.isEmpty else {
                throw LegacyLayoutParserError.invalidCommand("a display argument is empty")
            }
            arguments.append(argument)
            index = command.index(after: index)

            if index < command.endIndex, !command[index].isWhitespace {
                throw LegacyLayoutParserError.invalidCommand(
                    "unexpected text follows a display argument"
                )
            }
        }
        return arguments
    }

    private static func parseDisplayArgument(
        _ argument: String
    ) throws -> LegacyDisplayArgument {
        var fields: [String: String] = [:]
        for token in argument.split(whereSeparator: \.isWhitespace) {
            guard let separator = token.firstIndex(of: ":"), separator != token.startIndex else {
                throw LegacyLayoutParserError.invalidCommand("a display field is malformed")
            }
            let key = String(token[..<separator])
            let valueStart = token.index(after: separator)
            let value = String(token[valueStart...])
            guard expectedKeys.contains(key), !value.isEmpty else {
                throw LegacyLayoutParserError.invalidCommand("display field \(key) is not supported")
            }
            guard fields.updateValue(value, forKey: key) == nil else {
                throw LegacyLayoutParserError.invalidCommand("display field \(key) is duplicated")
            }
        }
        guard Set(fields.keys) == expectedKeys else {
            throw LegacyLayoutParserError.invalidCommand("required display fields are missing")
        }

        let rawIDs = fields["id"]!.split(separator: "+", omittingEmptySubsequences: false)
        guard !rawIDs.isEmpty,
              !rawIDs.contains(where: \.isEmpty) else {
            throw LegacyLayoutParserError.invalidCommand("the display identifier is malformed")
        }
        let ids = try rawIDs.map { rawID -> String in
            guard let id = normalizedUUID(String(rawID)) else {
                throw LegacyLayoutParserError.invalidCommand(
                    "display identifier \(rawID) is not a persistent UUID"
                )
            }
            return id
        }
        guard Set(ids).count == ids.count else {
            throw LegacyLayoutParserError.invalidCommand(
                "a mirrored display group contains a duplicate identifier"
            )
        }

        let resolution = fields["res"]!.split(separator: "x", omittingEmptySubsequences: false)
        guard resolution.count == 2,
              let width = Int(resolution[0]), width > 0,
              let height = Int(resolution[1]), height > 0 else {
            throw LegacyLayoutParserError.invalidCommand("the resolution is malformed")
        }

        guard let refreshRate = Double(fields["hz"]!),
              refreshRate.isFinite,
              refreshRate >= 0 else {
            throw LegacyLayoutParserError.invalidCommand("the refresh rate is malformed")
        }

        // The semantic model intentionally leaves color depth to macOS. Eight-bit is
        // the legacy default; other explicit depths cannot be preserved by migration.
        guard fields["color_depth"] == "8" else {
            throw LegacyLayoutParserError.unsupported("non-default color depth")
        }
        guard fields["enabled"] == "true" else {
            if fields["enabled"] == "false" {
                throw LegacyLayoutParserError.unsupported("disabled displays")
            }
            throw LegacyLayoutParserError.invalidCommand("the enabled value is malformed")
        }

        let scaling: Bool
        switch fields["scaling"]! {
        case "on": scaling = true
        case "off": scaling = false
        default:
            throw LegacyLayoutParserError.invalidCommand("the scaling value is malformed")
        }

        let origin = fields["origin"]!
        guard origin.first == "(", origin.last == ")" else {
            throw LegacyLayoutParserError.invalidCommand("the display origin is malformed")
        }
        let coordinateText = origin.dropFirst().dropLast()
        let coordinates = coordinateText.split(separator: ",", omittingEmptySubsequences: false)
        guard coordinates.count == 2,
              let x = Int32(coordinates[0]),
              let y = Int32(coordinates[1]) else {
            throw LegacyLayoutParserError.invalidCommand("the display origin is malformed")
        }

        guard let rotation = Double(fields["degree"]!),
              rotation.isFinite,
              [0.0, 90, 180, 270].contains(rotation) else {
            throw LegacyLayoutParserError.invalidCommand("the display rotation is malformed")
        }

        return LegacyDisplayArgument(
            ids: ids,
            width: width,
            height: height,
            refreshRate: refreshRate,
            scaling: scaling,
            x: x,
            y: y,
            rotation: rotation
        )
    }

    private static func normalizedUUID(_ id: String) -> String? {
        UUID(uuidString: id)?.uuidString.uppercased()
    }

    private static func isScaled(_ mode: DisplayModeSpec) -> Bool {
        mode.width != mode.pixelWidth || mode.height != mode.pixelHeight
    }
}
