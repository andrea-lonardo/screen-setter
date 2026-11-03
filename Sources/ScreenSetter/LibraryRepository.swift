import Foundation

/// Reads and writes `library.json`. Not thread-safe; `LayoutStore` serializes access.
final class LibraryRepository {
    enum LoadResult {
        case loaded(LayoutLibrary)
        /// library.json did not exist; the library holds whatever 1.x profiles were imported.
        case migrated(LayoutLibrary)
        /// library.json was unreadable and was moved to `backup`.
        case corrupt(backup: URL)
        /// library.json was written by a newer version and must not be overwritten.
        case newerVersion(Int)
        /// library.json could be neither read nor backed up; it is left untouched.
        case unreadable
    }

    static let legacyPresetTitles: [(id: String, title: String)] = [
        ("ipad-left", "iPad Left"),
        ("ipad-right", "iPad Right"),
        ("monitor-above", "Monitor Above"),
        ("monitor-right", "Monitor Right"),
        ("projector-mirror", "Projector Mirror")
    ]

    let directory: URL
    /// Where the app kept its data while it was called Display Layouts: 1.x
    /// profiles and pre-rename 2.0 libraries. Read, never written.
    let legacyDirectory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    var libraryURL: URL { directory.appendingPathComponent("library.json", isDirectory: false) }
    var previousURL: URL { directory.appendingPathComponent("library.previous.json", isDirectory: false) }
    private var legacyLibraryURL: URL { legacyDirectory.appendingPathComponent("library.json", isDirectory: false) }
    /// 1.x JSON profiles and displayplacer `.command` files.
    var profilesDirectory: URL { legacyDirectory.appendingPathComponent("Profiles", isDirectory: true) }

    /// With an explicit `directory` and no `legacyDirectory`, both are the same
    /// folder, so nothing is copied and 1.x profiles are read from its Profiles.
    init(directory: URL? = nil, legacyDirectory: URL? = nil) {
        if let directory {
            self.directory = directory
            self.legacyDirectory = legacyDirectory ?? directory
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = applicationSupport.appendingPathComponent("Screen Setter", isDirectory: true)
            self.legacyDirectory = legacyDirectory
                ?? applicationSupport.appendingPathComponent("Display Layouts", isDirectory: true)
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LoadResult {
        adoptLegacyLibrary()
        guard let data = try? Data(contentsOf: libraryURL) else {
            if fileManager.fileExists(atPath: libraryURL.path) {
                return backUpCorruptFile()
            }
            return .migrated(migrateVersion1())
        }
        struct Header: Decodable { var schemaVersion: Int? }
        if let version = (try? decoder.decode(Header.self, from: data))?.schemaVersion,
           version > LayoutLibrary.currentSchemaVersion {
            return .newerVersion(version)
        }
        guard let library = try? decoder.decode(LayoutLibrary.self, from: data) else {
            return backUpCorruptFile()
        }
        return .loaded(library)
    }

    /// Atomically replaces library.json, keeping the prior file as library.previous.json.
    func save(_ library: LayoutLibrary) throws {
        let data = try encoder.encode(library)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if let previous = try? Data(contentsOf: libraryURL) {
            try previous.write(to: previousURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previousURL.path)
        }
        try data.write(to: libraryURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: libraryURL.path)
    }

    /// The displayplacer command saved by 1.0 for a preset, if any. Files named
    /// `samsung-*` predate the `monitor-*` preset names.
    func legacyCommand(for presetID: String) -> String? {
        for id in [presetID, presetID.replacingOccurrences(of: "monitor-", with: "samsung-")] {
            let url = profilesDirectory.appendingPathComponent(id + ".command", isDirectory: false)
            if let command = try? String(contentsOf: url, encoding: .utf8) { return command }
        }
        return nil
    }

    /// Copies a library saved before the rename into the new folder, once. The
    /// original is left in place, so a failed copy only means starting fresh.
    private func adoptLegacyLibrary() {
        guard legacyDirectory.standardizedFileURL != directory.standardizedFileURL,
              !fileManager.fileExists(atPath: libraryURL.path),
              let data = try? Data(contentsOf: legacyLibraryURL) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: libraryURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: libraryURL.path)
        } catch {
            try? fileManager.removeItem(at: libraryURL)
        }
    }

    /// Converts 1.x JSON profiles to layouts. The 1.x files are left untouched.
    private func migrateVersion1() -> LayoutLibrary {
        let order = Self.legacyPresetTitles.map(\.id)
        let profiles = ProfileRepository(directory: profilesDirectory).all().sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.presetID) ?? order.count
            let right = order.firstIndex(of: rhs.presetID) ?? order.count
            return left != right ? left < right : lhs.presetID < rhs.presetID
        }
        var library = LayoutLibrary()
        library.layouts = profiles.map { profile in
            Layout(id: UUID(), name: profile.title, snapshot: profile.snapshot, createdAt: profile.savedAt,
                   modifiedAt: profile.savedAt, autoApply: profile.autoApply, legacyID: profile.presetID)
        }
        library.hasCompletedOnboarding = !library.layouts.isEmpty
        return library
    }

    private func backUpCorruptFile() -> LoadResult {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        var backup = directory.appendingPathComponent("library.corrupt-\(formatter.string(from: Date())).json")
        if fileManager.fileExists(atPath: backup.path) {
            backup = directory.appendingPathComponent("library.corrupt-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json")
        }
        do {
            try fileManager.moveItem(at: libraryURL, to: backup)
        } catch {
            return .unreadable
        }
        return .corrupt(backup: backup)
    }
}
