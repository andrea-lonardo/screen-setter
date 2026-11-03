import CoreGraphics
import Foundation

// Pure arrangement geometry used by the layout editor. No UI dependencies, so it
// can be unit tested. Coordinates are desktop points: y grows downward and the
// main display's origin is 0,0. Every mutating operation leaves the arrangement
// connected (each unmirrored display shares an edge of positive length with the
// rest), free of overlaps, on integer coordinates, and normalized.

extension LayoutSnapshot {
    enum NudgeDirection: Sendable {
        case left, right, up, down

        var vector: (x: Int, y: Int) {
            switch self {
            case .left: return (-1, 0)
            case .right: return (1, 0)
            case .up: return (0, -1)
            case .down: return (0, 1)
            }
        }
    }

    // MARK: Queries

    func displayIndex(of id: String) -> Int? {
        displays.firstIndex { ArrangementGeometry.sameID($0.id, id) }
    }

    func display(withID id: String) -> DisplaySpec? {
        displayIndex(of: id).map { displays[$0] }
    }

    var unmirroredDisplays: [DisplaySpec] {
        displays.filter { $0.mirrorSourceID == nil }
    }

    /// The unmirrored display at 0,0, or the first unmirrored display.
    var mainDisplayID: String? {
        let candidates = unmirroredDisplays
        return (candidates.first { $0.x == 0 && $0.y == 0 } ?? candidates.first)?.id
    }

    func isMain(_ id: String) -> Bool {
        mainDisplayID.map { ArrangementGeometry.sameID($0, id) } ?? false
    }

    /// Displays that mirror the given display.
    func mirrors(of id: String) -> [DisplaySpec] {
        displays.filter { $0.mirrorSourceID.map { ArrangementGeometry.sameID($0, id) } ?? false }
    }

    /// True when every display other than the main one mirrors the main display.
    var isMirroringAll: Bool {
        guard displays.count > 1, let main = mainDisplayID else { return false }
        return displays.allSatisfy { display in
            ArrangementGeometry.sameID(display.id, main)
                || display.mirrorSourceID.map { ArrangementGeometry.sameID($0, main) } ?? false
        }
    }

    var isExtendingAll: Bool {
        displays.allSatisfy { $0.mirrorSourceID == nil }
    }

    /// The bounding box of all unmirrored display frames.
    var arrangementBounds: CGRect {
        unmirroredDisplays.map { frame(of: $0) }.reduce(CGRect.null) { $0.union($1) }
    }

    // MARK: Editing

    /// Moves an unmirrored display to `origin`, then snaps it against the other
    /// displays so it shares an edge with one of them and overlaps none. Edges
    /// within `snapThreshold` points of a neighbour's edge or centre are aligned.
    mutating func moveDisplay(_ id: String, to origin: CGPoint, snapThreshold: Double) {
        guard let index = displayIndex(of: id), displays[index].mirrorSourceID == nil,
              let main = mainDisplayID else { return }
        setOrigin(of: index, x: Int(origin.x.rounded()), y: Int(origin.y.rounded()))

        let others = unmirroredDisplays.filter { !ArrangementGeometry.sameID($0.id, id) }.map { frame(of: $0) }
        if !others.isEmpty,
           let offset = ArrangementGeometry.snapOffset(moving: frame(of: displays[index]), fixed: others, threshold: snapThreshold) {
            translate(index, by: offset)
        }
        settle(anchor: displays[index].id)
        normalize(mainID: main)
    }

    /// Moves a display one step in a direction (for keyboard and VoiceOver users).
    /// Returns false when there is no valid position further in that direction.
    @discardableResult
    mutating func nudgeDisplay(_ id: String, _ direction: NudgeDirection) -> Bool {
        guard let index = displayIndex(of: id), displays[index].mirrorSourceID == nil else { return false }
        let start = frame(of: displays[index])
        let others = unmirroredDisplays.filter { !ArrangementGeometry.sameID($0.id, id) }
        guard !others.isEmpty else { return false }

        let vector = direction.vector
        let dimension = vector.x != 0 ? start.width : start.height
        let step = max(16, Int(dimension / 8))
        // Measure movement relative to another display, since normalization may
        // translate everything when the main display itself moves.
        let referenceID = others[0].id
        let before = relativeOffset(of: id, to: referenceID)

        for multiple in 1...80 {
            var candidate = self
            let distance = step * multiple
            candidate.moveDisplay(
                id,
                to: CGPoint(x: start.minX + CGFloat(vector.x * distance), y: start.minY + CGFloat(vector.y * distance)),
                snapThreshold: 0
            )
            guard candidate != self,
                  let after = candidate.relativeOffset(of: id, to: referenceID) else { continue }
            let moved = (after.x - (before?.x ?? 0)) * vector.x + (after.y - (before?.y ?? 0)) * vector.y
            if moved > 0 {
                self = candidate
                return true
            }
        }
        return false
    }

    /// Makes a display the main display, translating the arrangement so it is at 0,0.
    mutating func makeMain(_ id: String) {
        guard let index = displayIndex(of: id) else { return }
        if displays[index].mirrorSourceID != nil {
            unmirror(id)
        }
        normalize(mainID: displays[index].id)
    }

    /// Makes a display an extended (unmirrored, non-main) display. Unmirrored
    /// displays are placed to the right of the arrangement, top-aligned. When the
    /// main display is extended, the next unmirrored display becomes main.
    mutating func makeExtended(_ id: String) {
        guard let index = displayIndex(of: id) else { return }
        if displays[index].mirrorSourceID != nil {
            unmirror(id)
        } else if isMain(id),
                  let next = unmirroredDisplays.first(where: { !ArrangementGeometry.sameID($0.id, id) }) {
            normalize(mainID: next.id)
        }
    }

    /// Makes `id` mirror `sourceID`. Displays that mirrored `id` mirror the new
    /// source instead; if `id` was main, the source becomes main.
    mutating func mirror(_ id: String, of sourceID: String) {
        guard let index = displayIndex(of: id), let sourceIndex = displayIndex(of: sourceID),
              index != sourceIndex, displays[sourceIndex].mirrorSourceID == nil else { return }
        let source = displays[sourceIndex].id
        let wasMain = isMain(id)
        let main = wasMain ? source : (mainDisplayID ?? source)

        displays[index].mirrorSourceID = source
        for other in displays.indices where displays[other].mirrorSourceID.map({ ArrangementGeometry.sameID($0, id) }) ?? false {
            displays[other].mirrorSourceID = source
        }
        settle(anchor: main)
        normalize(mainID: main)
    }

    /// Mirror for everything: every other display mirrors the main display.
    mutating func mirrorAll() {
        guard let main = mainDisplayID else { return }
        for index in displays.indices where !ArrangementGeometry.sameID(displays[index].id, main) {
            displays[index].mirrorSourceID = main
        }
        normalize(mainID: main)
    }

    /// Extend everything: unmirrors every display and lays them out in a row to
    /// the right of the main display.
    mutating func extendAll() {
        let main = mainDisplayID
        for index in displays.indices {
            displays[index].mirrorSourceID = nil
        }
        arrangeInRow(mainID: main)
    }

    /// Lays out the unmirrored displays in a row, top-aligned, with the main
    /// display first and the others in their current left-to-right order.
    mutating func arrangeInRow(mainID: String? = nil) {
        guard let main = mainID ?? mainDisplayID, let mainIndex = displayIndex(of: main) else { return }
        let others = displays.indices
            .filter { $0 != mainIndex && displays[$0].mirrorSourceID == nil }
            .sorted {
                let lhs = displays[$0], rhs = displays[$1]
                return lhs.x != rhs.x ? lhs.x < rhs.x : lhs.y < rhs.y
            }
        setOrigin(of: mainIndex, x: 0, y: 0)
        var cursor = Int(frame(of: displays[mainIndex]).width)
        for index in others {
            setOrigin(of: index, x: cursor, y: 0)
            cursor += Int(frame(of: displays[index]).width)
        }
        normalize(mainID: displays[mainIndex].id)
    }

    /// Changes a display's mode. Neighbours are re-snapped around the display so
    /// nothing overlaps or floats; its top-left corner stays put.
    mutating func setMode(_ mode: DisplayModeSpec, for id: String) {
        guard let index = displayIndex(of: id) else { return }
        let main = mainDisplayID
        let before = frame(of: displays[index])
        displays[index].mode = mode
        if displays[index].mirrorSourceID == nil {
            // Neighbours to the right of or below the display keep their side.
            let after = frame(of: displays[index])
            let dx = Int(after.width - before.width), dy = Int(after.height - before.height)
            for other in displays.indices where other != index && displays[other].mirrorSourceID == nil {
                let neighbour = frame(of: displays[other])
                let x = Int(displays[other].x) + (neighbour.minX >= before.maxX ? dx : 0)
                let y = Int(displays[other].y) + (neighbour.minY >= before.maxY ? dy : 0)
                setOrigin(of: other, x: x, y: y)
            }
            settle(anchor: displays[index].id)
        }
        normalize(mainID: main)
    }

    /// Translates the arrangement so the main display (or `mainID`) is at 0,0,
    /// keeps mirrored displays at their source's origin, and flattens mirror chains.
    mutating func normalize(mainID: String? = nil) {
        // Flatten chains: a display may only mirror an unmirrored display.
        for index in displays.indices {
            var source = displays[index].mirrorSourceID
            var hops = 0
            while let current = source, let sourceIndex = displayIndex(of: current),
                  let next = displays[sourceIndex].mirrorSourceID, hops < displays.count {
                source = next
                hops += 1
            }
            if let source, ArrangementGeometry.sameID(source, displays[index].id) || displayIndex(of: source) == nil {
                displays[index].mirrorSourceID = nil
            } else {
                displays[index].mirrorSourceID = source
            }
        }

        let candidate = mainID.flatMap { id in
            displayIndex(of: id).flatMap { displays[$0].mirrorSourceID == nil ? displays[$0].id : nil }
        } ?? mainDisplayID
        if let main = candidate, let mainIndex = displayIndex(of: main) {
            let dx = displays[mainIndex].x, dy = displays[mainIndex].y
            for index in displays.indices where displays[index].mirrorSourceID == nil {
                displays[index].x -= dx
                displays[index].y -= dy
            }
        }
        for index in displays.indices {
            if let source = displays[index].mirrorSourceID, let sourceIndex = displayIndex(of: source) {
                displays[index].x = displays[sourceIndex].x
                displays[index].y = displays[sourceIndex].y
            }
        }
    }

    // MARK: Private

    private mutating func setOrigin(of index: Int, x: Int, y: Int) {
        displays[index].x = Int32(clamping: x)
        displays[index].y = Int32(clamping: y)
    }

    private mutating func translate(_ index: Int, by offset: CGVector) {
        setOrigin(
            of: index,
            x: Int(displays[index].x) + Int(offset.dx.rounded()),
            y: Int(displays[index].y) + Int(offset.dy.rounded())
        )
    }

    private func relativeOffset(of id: String, to referenceID: String) -> (x: Int, y: Int)? {
        guard let moved = display(withID: id), let reference = display(withID: referenceID) else { return nil }
        return (Int(moved.x) - Int(reference.x), Int(moved.y) - Int(reference.y))
    }

    /// Unmirrors a display and places it to the right of the arrangement, top-aligned
    /// with the rightmost display.
    private mutating func unmirror(_ id: String) {
        guard let index = displayIndex(of: id) else { return }
        let main = mainDisplayID
        displays[index].mirrorSourceID = nil
        let others = displays.indices.filter { $0 != index && displays[$0].mirrorSourceID == nil }
        if let rightmost = others.max(by: {
            let lhs = frame(of: displays[$0]), rhs = frame(of: displays[$1])
            return lhs.maxX != rhs.maxX ? lhs.maxX < rhs.maxX : lhs.minY > rhs.minY
        }) {
            let neighbour = frame(of: displays[rightmost])
            setOrigin(of: index, x: Int(neighbour.maxX), y: Int(neighbour.minY))
        } else {
            setOrigin(of: index, x: 0, y: 0)
        }
        normalize(mainID: main)
    }

    /// Re-attaches displays around `anchor` so the arrangement is connected and
    /// free of overlaps. Displays that already touch the placed set without
    /// overlapping keep their positions; the others are snapped to the nearest
    /// valid position, nearest displays first.
    private mutating func settle(anchor: String) {
        guard let anchorIndex = displayIndex(of: anchor), displays[anchorIndex].mirrorSourceID == nil else { return }
        var placed = [anchorIndex]
        var remaining = displays.indices.filter { $0 != anchorIndex && displays[$0].mirrorSourceID == nil }

        while !remaining.isEmpty {
            let placedFrames = placed.map { frame(of: displays[$0]) }
            func gap(_ index: Int) -> CGFloat {
                let rect = frame(of: displays[index])
                return placedFrames.map { ArrangementGeometry.distance(rect, $0) }.min() ?? 0
            }
            let valid = remaining.filter { index in
                let rect = frame(of: displays[index])
                return !placedFrames.contains { ArrangementGeometry.overlaps($0, rect) }
                    && placedFrames.contains { ArrangementGeometry.sharesEdge($0, rect) }
            }
            let next: Int
            if let touching = valid.first {
                next = touching
            } else {
                next = remaining.min { gap($0) < gap($1) }!
                if let offset = ArrangementGeometry.snapOffset(moving: frame(of: displays[next]), fixed: placedFrames, threshold: 0) {
                    translate(next, by: offset)
                }
            }
            placed.append(next)
            remaining.removeAll { $0 == next }
        }
    }
}

/// Rectangle helpers for arrangement editing.
enum ArrangementGeometry {
    /// True when two rectangles overlap with positive area (touching edges do not count).
    static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// True when two rectangles share an edge segment of positive length.
    static func sharesEdge(_ a: CGRect, _ b: CGRect) -> Bool {
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        if (a.maxX == b.minX || b.maxX == a.minX) && verticalOverlap > 0 { return true }
        if (a.maxY == b.minY || b.maxY == a.minY) && horizontalOverlap > 0 { return true }
        return false
    }

    /// The smallest integer offset that places `moving` against a side of one of
    /// the `fixed` rectangles without overlapping any of them. Positions within
    /// `threshold` of edge or centre alignment with that neighbour are aligned.
    static func snapOffset(moving: CGRect, fixed: [CGRect], threshold: Double) -> CGVector? {
        var best: (offset: CGVector, distance: Double)?

        func consider(x: CGFloat, y: CGFloat) {
            let origin = CGPoint(x: x.rounded(), y: y.rounded())
            let candidate = CGRect(origin: origin, size: moving.size)
            guard !fixed.contains(where: { overlaps($0, candidate) }) else { return }
            let offset = CGVector(dx: origin.x - moving.minX, dy: origin.y - moving.minY)
            let distance = hypot(offset.dx, offset.dy)
            if best == nil || distance < best!.distance - 0.001 {
                best = (offset, distance)
            }
        }

        // Keeps `desired` within the range that leaves an overlap of at least
        // `minimumOverlap` with the neighbour, then applies alignment snapping.
        func slide(_ desired: CGFloat, length: CGFloat, neighbourMin: CGFloat, neighbourLength: CGFloat) -> CGFloat {
            let minimumOverlap = max(1, min(min(length, neighbourLength) / 4, 64))
            let lower = neighbourMin - length + minimumOverlap
            let upper = neighbourMin + neighbourLength - minimumOverlap
            var value = min(max(desired, lower), upper)
            if threshold > 0 {
                let alignments = [
                    neighbourMin,
                    neighbourMin + neighbourLength - length,
                    neighbourMin + (neighbourLength - length) / 2,
                ]
                if let nearest = alignments.min(by: { abs($0 - desired) < abs($1 - desired) }),
                   abs(nearest - desired) <= threshold {
                    value = nearest
                }
            }
            return value
        }

        for neighbour in fixed {
            let y = slide(moving.minY, length: moving.height, neighbourMin: neighbour.minY, neighbourLength: neighbour.height)
            let x = slide(moving.minX, length: moving.width, neighbourMin: neighbour.minX, neighbourLength: neighbour.width)
            consider(x: neighbour.maxX, y: y)                  // right of
            consider(x: neighbour.minX - moving.width, y: y)   // left of
            consider(x: x, y: neighbour.maxY)                  // below
            consider(x: x, y: neighbour.minY - moving.height)  // above
        }
        return best?.offset
    }

    static func sameID(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// The gap between two rectangles (0 when they touch or overlap).
    static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
        let dy = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
        return hypot(dx, dy)
    }
}
