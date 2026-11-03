import CoreGraphics

extension LayoutSnapshot {
    /// The display's desktop-space frame in logical points (y grows downward, the
    /// main display's origin is 0,0). 90° and 270° rotations swap width and height.
    /// A mirrored display reports its source's frame.
    func frame(of display: DisplaySpec) -> CGRect {
        let positioned = display.mirrorSourceID.flatMap { source in
            displays.first { $0.id.uppercased() == source.uppercased() }
        } ?? display
        let rotated = positioned.rotation == 90 || positioned.rotation == 270
        let width = rotated ? positioned.mode.height : positioned.mode.width
        let height = rotated ? positioned.mode.width : positioned.mode.height
        return CGRect(x: Int(positioned.x), y: Int(positioned.y), width: width, height: height)
    }

    /// A user-facing reason the arrangement cannot be applied, or nil when valid.
    /// Checks: exactly one unmirrored display at 0,0; unmirrored frames do not
    /// overlap; every unmirrored display shares an edge segment of positive length
    /// with the rest (one connected arrangement); mirroring is one level deep.
    var arrangementIssue: String? {
        guard !displays.isEmpty else { return "A layout needs at least one display." }
        for display in displays {
            guard let source = display.mirrorSourceID else { continue }
            guard source.uppercased() != display.id.uppercased(),
                  displays.contains(where: { $0.id.uppercased() == source.uppercased() && $0.mirrorSourceID == nil }) else {
                return "A display can only mirror a display that is not mirrored itself."
            }
        }
        let frames = displays.filter { $0.mirrorSourceID == nil }.map { frame(of: $0) }
        for (index, a) in frames.enumerated() {
            for b in frames[(index + 1)...] where a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY {
                return "Displays overlap."
            }
        }
        guard let main = frames.firstIndex(where: { $0.origin == .zero }) else {
            return "One display must be the main display."
        }
        // Flood-fill from the main display across shared edges.
        var reached: Set<Int> = [main]
        var pending = [main]
        while let next = pending.popLast() {
            for candidate in frames.indices where !reached.contains(candidate) && Self.touchesAlongEdge(frames[next], frames[candidate]) {
                reached.insert(candidate)
                pending.append(candidate)
            }
        }
        return reached.count == frames.count ? nil : "Every display must touch another display."
    }

    /// True when the frames touch along a segment of positive length (corners do not count).
    private static func touchesAlongEdge(_ a: CGRect, _ b: CGRect) -> Bool {
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        return ((a.maxX == b.minX || b.maxX == a.minX) && verticalOverlap > 0)
            || ((a.maxY == b.minY || b.maxY == a.minY) && horizontalOverlap > 0)
    }
}
