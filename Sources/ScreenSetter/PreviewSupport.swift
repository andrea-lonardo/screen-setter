import Foundation

/// An in-memory display engine for `--preview-settings` and `--render-settings`.
/// It never talks to Core Graphics, so previews cannot change the real screens.
final class PreviewDisplayEngine: DisplayControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var current: LayoutSnapshot

    init(current: LayoutSnapshot) {
        self.current = current
    }

    func connect(_ snapshot: LayoutSnapshot) {
        lock.withLock { current = snapshot }
    }

    func capture() throws -> LayoutSnapshot {
        lock.withLock { current }
    }

    func validate(_ target: LayoutSnapshot) throws {
        guard target.isValid else { throw ProfileRepositoryError.invalidSnapshot }
        guard try capture().topologyKey == target.topologyKey else {
            throw DisplayEngineError.unavailable("Connect exactly the displays saved in this layout, then try again. Your current arrangement is unchanged.")
        }
    }

    func apply(_ target: LayoutSnapshot) throws {
        try validate(target)
        connect(target)
    }
}

/// Realistic sample data for previews and documentation renders.
enum PreviewLibrary {
    private static let builtInID = "4F1C2B7E-8A3D-4E61-B0C9-1D7E5A2F8C30"
    private static let studioID = "9C6B1E52-41F0-4C8A-A0D3-5E2F7B11C4A9"
    private static let ultraFineID = "E1A4F0C7-3B28-4D6E-9F15-2C8D7A60B3E4"

    private static let builtInModes = [
        DisplayModeSpec(width: 1147, height: 745, pixelWidth: 2294, pixelHeight: 1490, refreshRate: 120),
        DisplayModeSpec(width: 1352, height: 878, pixelWidth: 2704, pixelHeight: 1756, refreshRate: 120),
        DisplayModeSpec(width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120),
        DisplayModeSpec(width: 1728, height: 1117, pixelWidth: 3456, pixelHeight: 2234, refreshRate: 120)
    ]
    private static let studioModes = [
        DisplayModeSpec(width: 1600, height: 900, pixelWidth: 3200, pixelHeight: 1800, refreshRate: 60),
        DisplayModeSpec(width: 2048, height: 1152, pixelWidth: 4096, pixelHeight: 2304, refreshRate: 60),
        DisplayModeSpec(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60),
        DisplayModeSpec(width: 2880, height: 1620, pixelWidth: 5760, pixelHeight: 3240, refreshRate: 60)
    ]
    private static let ultraFineModes = [
        DisplayModeSpec(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 60),
        DisplayModeSpec(width: 2048, height: 1152, pixelWidth: 4096, pixelHeight: 2304, refreshRate: 60),
        DisplayModeSpec(width: 2304, height: 1296, pixelWidth: 4608, pixelHeight: 2592, refreshRate: 60)
    ]

    private static func builtIn(x: Int32 = 0, y: Int32 = 0) -> DisplaySpec {
        DisplaySpec(id: builtInID, name: "Built-in Display", vendor: 1552, model: 41_007, serial: 0,
                    builtIn: true, mode: builtInModes[2], x: x, y: y, rotation: 0, mirrorSourceID: nil,
                    availableModes: builtInModes)
    }

    private static func studio(x: Int32, y: Int32, mirroring: Bool = false) -> DisplaySpec {
        DisplaySpec(id: studioID, name: "Studio Display", vendor: 1552, model: 44_838, serial: 1_001,
                    builtIn: false, mode: studioModes[2], x: x, y: y, rotation: 0,
                    mirrorSourceID: mirroring ? builtInID : nil, availableModes: studioModes)
    }

    private static func ultraFine(x: Int32, y: Int32) -> DisplaySpec {
        DisplaySpec(id: ultraFineID, name: "LG UltraFine", vendor: 7789, model: 23_305, serial: 1_002,
                    builtIn: false, mode: ultraFineModes[1], x: x, y: y, rotation: 0, mirrorSourceID: nil,
                    availableModes: ultraFineModes)
    }

    static let studioAbove = LayoutSnapshot(displays: [builtIn(), studio(x: -524, y: -1440)])
    static let studioLeft = LayoutSnapshot(displays: [builtIn(), studio(x: -2560, y: -458)])
    static let studioMirrored = LayoutSnapshot(displays: [builtIn(), studio(x: 0, y: 0, mirroring: true)])
    static let ultraFineRight = LayoutSnapshot(displays: [builtIn(), ultraFine(x: 1512, y: -170)])

    /// A store in a fresh temporary directory, backed by `PreviewDisplayEngine`.
    /// With `empty`, the library has no layouts and onboarding is not completed.
    static func makeStore(empty: Bool = false) -> LayoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("screen-setter-preview-" + UUID().uuidString, isDirectory: true)
        let engine = PreviewDisplayEngine(current: studioAbove)
        let store = LayoutStore(directory: directory, engine: engine)

        // Display-queue store calls must not run on the main thread.
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer { done.signal() }
            do {
                _ = try store.refresh()
                guard !empty else { return }
                let above = try save(studioAbove, as: "Studio Display Above", store: store, engine: engine)
                _ = try save(studioLeft, as: "Studio Display Left", store: store, engine: engine)
                _ = try save(studioMirrored, as: "Mirror for Presenting", store: store, engine: engine)
                _ = try save(ultraFineRight, as: "Desk", store: store, engine: engine)
                engine.connect(studioAbove)
                _ = try store.refresh()

                try store.setHotkey(Hotkey(keyCode: 18, modifiers: Hotkey.control | Hotkey.option | Hotkey.command, key: "1"),
                                    for: above.id)
                try store.setAutomaticLayout(inGroup: above.groupID, layoutID: above.id)
                try store.setOnboardingCompleted()
            } catch {
                FileHandle.standardError.write(Data("Preview sample data is incomplete: \(error.localizedDescription)\n".utf8))
            }
        }
        done.wait()
        return store
    }

    private static func save(_ snapshot: LayoutSnapshot, as name: String,
                             store: LayoutStore, engine: PreviewDisplayEngine) throws -> Layout {
        engine.connect(snapshot)
        _ = try store.refresh()
        return try store.saveCurrent(named: name)
    }
}
