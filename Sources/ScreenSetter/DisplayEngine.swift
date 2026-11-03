import AppKit
import CoreGraphics
import ColorSync

enum DisplayEngineError: LocalizedError {
    case unavailable(String)
    case system(CGError)
    case verification

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .system(let code): return "macOS could not complete the display request (\(code.rawValue)). If a change was started, use Undo to restore the previous arrangement."
        case .verification: return "macOS did not restore every saved display setting. The current arrangement has been refreshed. Use Undo to restore the previous arrangement."
        }
    }
}

extension DisplaySpec {
    /// The name used when macOS reports none, which is common for mirrored displays.
    static func fallbackName(builtIn: Bool, model: UInt32) -> String {
        builtIn ? "Built-in Display" : "Display \(model)"
    }

    /// True for engine fallbacks and the generic names stored by 1.x.
    var hasFallbackName: Bool {
        name.isEmpty || name == Self.fallbackName(builtIn: builtIn, model: model)
            || name == "Built-in display" || name == "External display"
    }
}

/// All methods run on the app's serial display queue. No display mutation occurs at initialization.
protocol DisplayControlling {
    func capture() throws -> LayoutSnapshot
    func validate(_ target: LayoutSnapshot) throws
    func apply(_ target: LayoutSnapshot) throws
}

final class DisplayEngine: DisplayControlling {
    private func connected() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        try check(CGGetOnlineDisplayList(0, nil, &count))
        guard count > 0 else {
            throw DisplayEngineError.unavailable("No displays are available to this process. Run Screen Setter in your normal macOS desktop session.")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        try check(CGGetOnlineDisplayList(count, &ids, &count))
        return Array(ids.prefix(Int(count)))
    }

    private func identity(_ id: CGDirectDisplayID) throws -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else {
            throw DisplayEngineError.unavailable("A connected display has no stable identifier. No layout was changed.")
        }
        return (CFUUIDCreateString(nil, uuid) as String).uppercased()
    }

    private func spec(_ mode: CGDisplayMode) -> DisplayModeSpec {
        DisplayModeSpec(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                        pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
    }

    /// Mode list for editing: usable modes plus the current one, deduplicated and
    /// sorted by size (largest first), HiDPI before low resolution, then refresh rate.
    private func availableModes(_ id: CGDirectDisplayID, current: DisplayModeSpec) -> [DisplayModeSpec] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
            .filter { $0.isUsableForDesktopGUI() }.map(spec)
        var seen = Set<DisplayModeSpec>()
        return ([current] + all).filter { seen.insert($0).inserted }.sorted { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            let aHiDPI = a.pixelWidth > a.width, bHiDPI = b.pixelWidth > b.width
            if aHiDPI != bHiDPI { return aHiDPI }
            if a.pixelWidth != b.pixelWidth { return a.pixelWidth > b.pixelWidth }
            return a.refreshRate > b.refreshRate
        }
    }

    /// `NSScreen.localizedName` by display ID. NSScreen must be read on the main
    /// thread; from the display queue this blocks on the main queue. That cannot
    /// deadlock because the app's main thread never waits synchronously on the
    /// display queue — keep it that way.
    private func screenNames() -> [CGDirectDisplayID: String] {
        let read = {
            MainActor.assumeIsolated {
                var names: [CGDirectDisplayID: String] = [:]
                for screen in NSScreen.screens {
                    if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                        names[number.uint32Value] = screen.localizedName
                    }
                }
                return names
            }
        }
        return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
    }

    func capture() throws -> LayoutSnapshot {
        let ids = try connected()
        let names = screenNames()
        let identities = try Dictionary(uniqueKeysWithValues: ids.map { ($0, try identity($0)) })
        guard Set(identities.values).count == ids.count else {
            throw DisplayEngineError.unavailable("Two displays have the same identifier. Save the layout after connecting them individually.")
        }
        let displays = try ids.map { id -> DisplaySpec in
            guard let mode = CGDisplayCopyDisplayMode(id) else {
                throw DisplayEngineError.unavailable("A display is still connecting. Wait a moment and try again.")
            }
            let bounds = CGDisplayBounds(id)
            let mirror = CGDisplayMirrorsDisplay(id)
            let builtIn = CGDisplayIsBuiltin(id) != 0, model = CGDisplayModelNumber(id)
            let name = names[id].flatMap { $0.isEmpty ? nil : $0 } ?? DisplaySpec.fallbackName(builtIn: builtIn, model: model)
            return DisplaySpec(id: identities[id]!, name: name, vendor: CGDisplayVendorNumber(id), model: model,
                               serial: CGDisplaySerialNumber(id), builtIn: builtIn, mode: spec(mode),
                               x: Int32(bounds.minX), y: Int32(bounds.minY), rotation: CGDisplayRotation(id),
                               mirrorSourceID: mirror == kCGNullDirectDisplay ? nil : identities[mirror],
                               availableModes: availableModes(id, current: spec(mode)))
        }
        return LayoutSnapshot(displays: displays)
    }

    private func matchingMode(_ wanted: DisplayModeSpec, on id: CGDirectDisplayID) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        // Prefer the live mode when equivalent: duplicate modes can differ in driver flags.
        let modes = [CGDisplayCopyDisplayMode(id)].compactMap { $0 } + (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? [])
        return modes.first { mode in
            let candidate = spec(mode)
            return candidate.width == wanted.width && candidate.height == wanted.height &&
                candidate.pixelWidth == wanted.pixelWidth && candidate.pixelHeight == wanted.pixelHeight &&
                abs(candidate.refreshRate - wanted.refreshRate) <= 0.1 && mode.isUsableForDesktopGUI()
        }
    }

    /// Resolves the whole transaction before changing anything. Exact topology prevents partial restores.
    private func prepare(_ target: LayoutSnapshot) throws -> ([String: CGDirectDisplayID], [String: CGDisplayMode]) {
        guard target.isValid else { throw ProfileRepositoryError.invalidSnapshot }
        let current = try capture()
        guard current.topologyKey == target.topologyKey else {
            throw DisplayEngineError.unavailable("Connect exactly the displays saved in this layout, then try again. Your current arrangement is unchanged.")
        }
        let ids = try connected()
        let idMap = try Dictionary(uniqueKeysWithValues: ids.map { (try identity($0), $0) })
        var modes: [String: CGDisplayMode] = [:]
        for display in target.displays {
            guard let id = idMap[display.id.uppercased()],
                  let live = current.displays.first(where: { $0.id.uppercased() == display.id.uppercased() }) else {
                throw DisplayEngineError.unavailable("A saved display is no longer connected.")
            }
            guard abs(live.rotation - display.rotation) < 0.01 else {
                throw DisplayEngineError.unavailable("Set the saved display rotation in Display Settings first, then apply this layout. The native engine preserves rotation but cannot change it.")
            }
            guard let mode = matchingMode(display.mode, on: id) else {
                throw DisplayEngineError.unavailable("A saved resolution, scaling, or refresh rate is no longer available. Review the arrangement in Display Settings and save it again.")
            }
            modes[display.id.uppercased()] = mode
            if let source = display.mirrorSourceID {
                guard source.uppercased() != display.id.uppercased(),
                      target.displays.contains(where: { $0.id.uppercased() == source.uppercased() && $0.mirrorSourceID == nil }) else {
                    throw DisplayEngineError.unavailable("The saved mirroring configuration is invalid. Save this layout again.")
                }
            }
        }
        return (idMap, modes)
    }

    func validate(_ target: LayoutSnapshot) throws { _ = try prepare(target) }

    func apply(_ target: LayoutSnapshot) throws {
        if try capture().matches(target) { return }
        let (idMap, modes) = try prepare(target)
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config))
        var submitted = false
        defer { if !submitted { CGCancelDisplayConfiguration(config) } }
        // Explicitly clear old mirrors before creating the target mirror groups.
        for display in target.displays {
            try check(CGConfigureDisplayMirrorOfDisplay(config, idMap[display.id.uppercased()]!, kCGNullDirectDisplay))
        }
        for display in target.displays {
            let id = idMap[display.id.uppercased()]!
            try check(CGConfigureDisplayWithDisplayMode(config, id, modes[display.id.uppercased()]!, nil))
            if display.mirrorSourceID == nil {
                try check(CGConfigureDisplayOrigin(config, id, display.x, display.y))
            }
        }
        for display in target.displays {
            if let source = display.mirrorSourceID {
                try check(CGConfigureDisplayMirrorOfDisplay(config, idMap[display.id.uppercased()]!, idMap[source.uppercased()]!))
            }
        }
        submitted = true
        try check(CGCompleteDisplayConfiguration(config, .permanently))
        // Drivers can settle after the transaction returns. Bounded retries run off the main thread.
        for _ in 0..<10 {
            if let actual = try? capture(), actual.matches(target) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw DisplayEngineError.verification
    }

    private func check(_ result: CGError) throws {
        guard result == .success else { throw DisplayEngineError.system(result) }
    }
}
