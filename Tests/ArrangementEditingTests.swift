import CoreGraphics
import Foundation

private struct EditingTestFailure: Error, CustomStringConvertible {
    let description: String
}

private func requireEditing(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw EditingTestFailure(description: message) }
}

private func editingDisplay(_ number: Int, x: Int32 = 0, y: Int32 = 0,
                            width: Int = 100, height: Int = 80, rotation: Double = 0,
                            mirror: String? = nil) -> DisplaySpec {
    DisplaySpec(id: String(format: "00000000-0000-0000-0000-%012d", number),
                name: "Display \(number)", vendor: 1, model: 1, serial: UInt32(number),
                builtIn: number == 1,
                mode: DisplayModeSpec(width: width, height: height, pixelWidth: width * 2,
                                      pixelHeight: height * 2, refreshRate: 60),
                x: x, y: y, rotation: rotation, mirrorSourceID: mirror)
}

private func editingRow(_ count: Int = 3) -> LayoutSnapshot {
    LayoutSnapshot(displays: (1...count).map { editingDisplay($0, x: Int32(($0 - 1) * 100)) })
}

private func requireEditingInvariants(_ snapshot: LayoutSnapshot, topology: String, _ context: String) throws {
    try requireEditing(snapshot.topologyKey == topology, "\(context): display identities changed")
    try requireEditing(snapshot.isValid, "\(context): invalid display data or mirroring")
    try requireEditing(snapshot.arrangementIssue == nil,
                       "\(context): \(snapshot.arrangementIssue ?? "unknown arrangement issue")")
    let mainCount = snapshot.displays.filter { $0.mirrorSourceID == nil && $0.x == 0 && $0.y == 0 }.count
    try requireEditing(mainCount == 1, "\(context): exactly one unmirrored display must be main")
    for display in snapshot.displays {
        if let sourceID = display.mirrorSourceID,
           let source = snapshot.displays.first(where: { $0.id == sourceID }) {
            try requireEditing(display.x == source.x && display.y == source.y,
                               "\(context): mirror origin differs from its source")
        }
    }
}

func testEditorMovementAndSnapping() throws {
    let initial = editingRow(2)
    let moving = initial.displays[1].id
    let positions: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 110, y: 0), CGPoint(x: 100, y: 0)),
        (CGPoint(x: -110, y: 0), CGPoint(x: -100, y: 0)),
        (CGPoint(x: 0, y: -90), CGPoint(x: 0, y: -80)),
        (CGPoint(x: 0, y: 90), CGPoint(x: 0, y: 80)),
    ]
    for (requested, expected) in positions {
        var snapshot = initial
        snapshot.moveDisplay(moving, to: requested, snapThreshold: 8)
        try requireEditing(snapshot.frame(of: snapshot.displays[1]).origin == expected,
                           "drag must attach to the requested side")
        try requireEditingInvariants(snapshot, topology: initial.topologyKey, "side snapping")
    }

    var inside = initial
    inside.moveDisplay(moving, to: CGPoint(x: 105, y: 7), snapThreshold: 8)
    try requireEditing(inside.displays[1].y == 0, "nearby top edges must align inside the threshold")
    var outside = initial
    outside.moveDisplay(moving, to: CGPoint(x: 105, y: 9), snapThreshold: 8)
    try requireEditing(outside.displays[1].y == 9, "outside the threshold, preserve the requested offset")

    var centred = LayoutSnapshot(displays: [editingDisplay(1, width: 200, height: 160), editingDisplay(2, x: 200)])
    centred.moveDisplay(moving, to: CGPoint(x: 205, y: 35), snapThreshold: 8)
    try requireEditing(centred.displays[1].x == 200 && centred.displays[1].y == 40,
                       "nearby vertical centres must align")

    var corner = initial
    corner.moveDisplay(moving, to: CGPoint(x: 100, y: 80), snapThreshold: 0)
    try requireEditing(corner.displays[1].x != 100 || corner.displays[1].y != 80,
                       "corner-only contact must be replaced by a shared edge")
    try requireEditingInvariants(corner, topology: initial.topologyKey, "corner drop")

    var bridge = editingRow()
    let topology = bridge.topologyKey
    bridge.moveDisplay(bridge.displays[1].id, to: CGPoint(x: 0, y: 100), snapThreshold: 0)
    try requireEditing(bridge.displays[2].x != 200 || bridge.displays[2].y != 0,
                       "moving a bridge display must reattach the stranded neighbour")
    try requireEditingInvariants(bridge, topology: topology, "moving a bridge")
}

func testEditorMainDisplay() throws {
    var snapshot = LayoutSnapshot(displays: [editingDisplay(1), editingDisplay(2, x: -100),
                                            editingDisplay(3, x: -100, y: -80)])
    let topology = snapshot.topologyKey
    let before = snapshot.displays
    snapshot.makeMain(before[2].id)
    try requireEditing(snapshot.displays[2].x == 0 && snapshot.displays[2].y == 0,
                       "the chosen main display must be at the origin")
    for index in before.indices {
        try requireEditing(snapshot.displays[index].x == before[index].x - before[2].x
                           && snapshot.displays[index].y == before[index].y - before[2].y,
                           "changing main must translate all positions equally")
    }
    try requireEditingInvariants(snapshot, topology: topology, "main normalization")

    var mirrored = editingRow()
    mirrored.mirror(mirrored.displays[2].id, of: mirrored.displays[0].id)
    mirrored.makeMain(mirrored.displays[2].id)
    try requireEditing(mirrored.displays[2].mirrorSourceID == nil && mirrored.mainDisplayID == mirrored.displays[2].id,
                       "choosing a mirrored display as main must extend it")
    try requireEditingInvariants(mirrored, topology: topology, "mirrored display promoted to main")
}

func testEditorMirroring() throws {
    var snapshot = editingRow(4)
    let topology = snapshot.topologyKey
    let ids = snapshot.displays.map(\.id)
    snapshot.mirror(ids[2], of: ids[0])
    snapshot.mirror(ids[0], of: ids[1])
    try requireEditing(snapshot.mainDisplayID == ids[1], "mirroring the main display must promote its source")
    try requireEditing(snapshot.displays[0].mirrorSourceID == ids[1]
                       && snapshot.displays[2].mirrorSourceID == ids[1],
                       "followers must move to the new source rather than form a mirror chain")
    try requireEditing(snapshot.displays[3].mirrorSourceID == nil, "unrelated extended displays must stay extended")
    try requireEditingInvariants(snapshot, topology: topology, "mixed mirroring")

    snapshot.makeExtended(ids[2])
    try requireEditing(snapshot.displays[2].mirrorSourceID == nil, "unmirroring must extend the chosen display")
    try requireEditingInvariants(snapshot, topology: topology, "unmirror one display")
    snapshot.makeExtended(ids[1])
    try requireEditing(snapshot.mainDisplayID != ids[1], "extending main must choose another main display")
    try requireEditingInvariants(snapshot, topology: topology, "extend main")

    let main = snapshot.mainDisplayID
    snapshot.mirrorAll()
    try requireEditing(snapshot.unmirroredDisplays.count == 1 && snapshot.mainDisplayID == main,
                       "Mirror must keep only the existing main display unmirrored")
    try requireEditingInvariants(snapshot, topology: topology, "mirror all")
    snapshot.extendAll()
    try requireEditing(snapshot.displays.allSatisfy { $0.mirrorSourceID == nil } && snapshot.mainDisplayID == main,
                       "Extend must unmirror every display and retain the main display")
    try requireEditingInvariants(snapshot, topology: topology, "extend all")
}

func testEditorResolutionAndRotation() throws {
    var snapshot = editingRow()
    let topology = snapshot.topologyKey
    let selected = snapshot.displays[1].id
    let main = snapshot.mainDisplayID
    var larger = snapshot.displays[1].mode
    larger.width = 200
    larger.pixelWidth = 400
    snapshot.setMode(larger, for: selected)
    try requireEditing(snapshot.displays[1].x == 100 && snapshot.displays[2].x == 300,
                       "growing an interior display must move its right neighbour outward")
    try requireEditingInvariants(snapshot, topology: topology, "grow resolution")
    var smaller = larger
    smaller.width = 50
    smaller.pixelWidth = 100
    snapshot.setMode(smaller, for: selected)
    try requireEditing(snapshot.displays[1].x == 100 && snapshot.displays[2].x == 150,
                       "shrinking an interior display must close the gap")
    try requireEditing(snapshot.mainDisplayID == main, "resolution changes must retain main display")
    try requireEditingInvariants(snapshot, topology: topology, "shrink resolution")

    for rotation in [90.0, 270.0] {
        var rotated = LayoutSnapshot(displays: [editingDisplay(1, rotation: rotation), editingDisplay(2, x: 80)])
        try requireEditing(rotated.frame(of: rotated.displays[0]).size == CGSize(width: 80, height: 100),
                           "portrait frames must swap logical width and height")
        var mode = rotated.displays[0].mode
        mode.width = 140
        mode.height = 90
        mode.pixelWidth = 280
        mode.pixelHeight = 180
        rotated.setMode(mode, for: rotated.displays[0].id)
        try requireEditing(rotated.displays[1].x == 90 && rotated.displays[0].rotation == rotation,
                           "resizing a portrait display must use its rotated frame and preserve rotation")
        try requireEditingInvariants(rotated, topology: rotated.topologyKey, "portrait resolution change")
    }
}

func testEditorKeyboardMovement() throws {
    let directions: [LayoutSnapshot.NudgeDirection] = [.left, .right, .up, .down]
    for direction in directions {
        for movingIndex in 0...1 {
            var snapshot = editingRow(2)
            let initial = snapshot
            let otherIndex = 1 - movingIndex
            let vector = direction.vector
            let beforeX = Int(snapshot.displays[movingIndex].x) - Int(snapshot.displays[otherIndex].x)
            let beforeY = Int(snapshot.displays[movingIndex].y) - Int(snapshot.displays[otherIndex].y)
            let moved = snapshot.nudgeDisplay(snapshot.displays[movingIndex].id, direction)
            let afterX = Int(snapshot.displays[movingIndex].x) - Int(snapshot.displays[otherIndex].x)
            let afterY = Int(snapshot.displays[movingIndex].y) - Int(snapshot.displays[otherIndex].y)
            if moved {
                try requireEditing((afterX - beforeX) * vector.x + (afterY - beforeY) * vector.y > 0,
                                   "nudge must move in the requested direction relative to the other display")
            } else {
                try requireEditing(snapshot == initial, "an unavailable nudge must leave the arrangement unchanged")
            }
            try requireEditingInvariants(snapshot, topology: initial.topologyKey, "keyboard nudge")
        }
    }
    var upward = editingRow(2)
    try requireEditing(upward.nudgeDisplay(upward.displays[1].id, .up), "an extended display must be movable upward")
    try requireEditing(upward.displays[1].y < 0, "upward nudge must decrease the secondary display's y coordinate")

    var single = editingRow(1)
    let originalSingle = single
    try requireEditing(!single.nudgeDisplay(single.displays[0].id, .left) && single == originalSingle,
                       "one display cannot move relative to itself")
    var mirrored = editingRow(2)
    mirrored.mirrorAll()
    let originalMirror = mirrored
    for display in originalMirror.displays {
        try requireEditing(!mirrored.nudgeDisplay(display.id, .right) && mirrored == originalMirror,
                           "fully mirrored displays cannot be nudged")
    }
}

private struct EditingRandom {
    var state: UInt64 = 0x53435245454E
    mutating func next(_ count: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(count))
    }
}

func testEditorOperationSequences() throws {
    var random = EditingRandom()
    for count in 3...5 {
        var snapshot = editingRow(count)
        let topology = snapshot.topologyKey
        for step in 0..<100 {
            let selected = snapshot.displays[random.next(count)].id
            switch random.next(8) {
            case 0: snapshot.moveDisplay(selected, to: CGPoint(x: random.next(1000) - 500, y: random.next(1000) - 500), snapThreshold: 10)
            case 1: snapshot.makeMain(selected)
            case 2: snapshot.makeExtended(selected)
            case 3:
                let sources = snapshot.unmirroredDisplays.filter { $0.id != selected }
                if !sources.isEmpty { snapshot.mirror(selected, of: sources[random.next(sources.count)].id) }
            case 4: snapshot.mirrorAll()
            case 5: snapshot.extendAll()
            case 6:
                let width = [80, 100, 160][random.next(3)]
                let height = [60, 80, 120][random.next(3)]
                snapshot.setMode(DisplayModeSpec(width: width, height: height, pixelWidth: width * 2,
                                                 pixelHeight: height * 2, refreshRate: 60), for: selected)
            default: snapshot.nudgeDisplay(selected, [.left, .right, .up, .down][random.next(4)])
            }
            try requireEditingInvariants(snapshot, topology: topology, "\(count) displays, sequence step \(step)")
        }
    }
}
