import AppKit
import SwiftUI

/// Scales an arrangement into a small box for thumbnails and menu glyphs.
struct ThumbnailGeometry: Sendable {
    struct Tile: Sendable {
        var rect: CGRect
        var isMain: Bool
        /// The number of displays mirroring this one.
        var mirrorCount: Int
    }

    var tiles: [Tile]
    /// Offset of the "stack" drawn behind mirrored displays.
    var stackOffset: CGFloat

    /// - Parameters:
    ///   - inset: margin kept free on every side.
    ///   - stackOffset: room reserved (up and right) for mirror stacks.
    ///   - minimumSide: tiles are never drawn smaller than this.
    init(snapshot: LayoutSnapshot, size: CGSize, inset: CGFloat, stackOffset: CGFloat, minimumSide: CGFloat) {
        let unmirrored = snapshot.unmirroredDisplays
        let frames = unmirrored.map { snapshot.frame(of: $0) }
        let bounds = frames.reduce(CGRect.null) { $0.union($1) }
        let hasMirrors = snapshot.displays.contains { $0.mirrorSourceID != nil }
        let stack = hasMirrors ? stackOffset : 0
        self.stackOffset = stack

        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            tiles = []
            return
        }
        let available = CGSize(width: size.width - inset * 2 - stack, height: size.height - inset * 2 - stack)
        let scale = min(available.width / bounds.width, available.height / bounds.height)
        let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        // Centre the drawing, leaving the stack room above and to the right.
        let origin = CGPoint(
            x: inset + (available.width - drawn.width) / 2,
            y: inset + stack + (available.height - drawn.height) / 2
        )
        let main = snapshot.mainDisplayID
        tiles = zip(unmirrored, frames).map { display, frame in
            var rect = CGRect(
                x: origin.x + (frame.minX - bounds.minX) * scale,
                y: origin.y + (frame.minY - bounds.minY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            )
            if rect.width < minimumSide { rect = rect.insetBy(dx: (rect.width - minimumSide) / 2, dy: 0) }
            if rect.height < minimumSide { rect = rect.insetBy(dx: 0, dy: (rect.height - minimumSide) / 2) }
            return Tile(
                rect: rect,
                isMain: display.id == main,
                mirrorCount: snapshot.mirrors(of: display.id).count
            )
        }
    }
}

/// A small drawing of a layout's arrangement. Accent-coloured when active.
struct LayoutThumbnailView: View {
    let snapshot: LayoutSnapshot
    var isActive = false

    var body: some View {
        Canvas { context, size in
            let geometry = ThumbnailGeometry(
                snapshot: snapshot,
                size: size,
                inset: 1.5,
                stackOffset: max(2, min(size.width, size.height) * 0.08),
                minimumSide: 4
            )
            let ink: GraphicsContext.Shading = isActive ? .color(.accentColor) : .style(.secondary)
            let fill: GraphicsContext.Shading = isActive
                ? .color(.accentColor.opacity(0.18))
                : .style(.quaternary.opacity(0.6))
            let radius = max(1.5, min(size.width, size.height) * 0.07)

            for tile in geometry.tiles {
                let front = Path(roundedRect: tile.rect, cornerRadius: radius)
                if tile.mirrorCount > 0 {
                    let back = tile.rect.offsetBy(dx: geometry.stackOffset, dy: -geometry.stackOffset)
                    var clipped = context
                    var mask = Path(CGRect(origin: .zero, size: size))
                    mask.addPath(front)
                    clipped.clip(to: mask, style: FillStyle(eoFill: true))
                    clipped.stroke(Path(roundedRect: back, cornerRadius: radius), with: ink, lineWidth: 1)
                }
                context.fill(front, with: fill)
                context.stroke(front, with: ink, lineWidth: tile.isMain ? 1.5 : 1)
                if tile.isMain {
                    let bar = CGRect(
                        x: tile.rect.minX,
                        y: tile.rect.minY,
                        width: tile.rect.width,
                        height: max(2, tile.rect.height * 0.14)
                    )
                    var clipped = context
                    clipped.clip(to: front)
                    clipped.fill(Path(bar), with: ink)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

enum LayoutThumbnail {
    /// An 18×18 pt template image of the arrangement for NSMenu items.
    @MainActor static func menuImage(for snapshot: LayoutSnapshot) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let geometry = ThumbnailGeometry(
            snapshot: snapshot,
            size: size,
            inset: 1.25,
            stackOffset: 2,
            minimumSide: 4.5
        )
        let image = NSImage(size: size, flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let lineWidth: CGFloat = 1.25
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(lineWidth)

            for tile in geometry.tiles {
                let rect = tile.rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let radius = min(1.75, rect.width / 3, rect.height / 3)
                let front = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
                if tile.mirrorCount > 0 {
                    context.saveGState()
                    context.addRect(bounds)
                    context.addPath(CGPath(
                        roundedRect: tile.rect.insetBy(dx: -0.75, dy: -0.75),
                        cornerWidth: radius,
                        cornerHeight: radius,
                        transform: nil
                    ))
                    context.clip(using: .evenOdd)
                    let back = rect.offsetBy(dx: geometry.stackOffset, dy: -geometry.stackOffset)
                    context.addPath(CGPath(roundedRect: back, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    context.strokePath()
                    context.restoreGState()
                }
                context.addPath(front)
                context.strokePath()
                if tile.isMain, rect.height >= 5 {
                    // The menu bar: a filled strip along the top edge.
                    context.saveGState()
                    context.addPath(front)
                    context.clip()
                    context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 2.25))
                    context.restoreGState()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Layout arrangement"
        return image
    }
}
