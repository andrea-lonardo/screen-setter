// Draws the "switch layouts" animation used in the README as an animated GIF:
// Screen Setter's menu picks a layout and the displays glide into place,
// matching the website's demo (docs/assets/site.js).
//
//     swift Tools/make_demo_gif.swift docs/images/demo.gif

import AppKit
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images/demo.gif")
let size = CGSize(width: 960, height: 600)
let fps = 20.0
let barHeight: CGFloat = 44
let canvas = CGRect(x: 0, y: barHeight, width: size.width, height: size.height - barHeight)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let background = color(0x101218), floor = color(0x171A22), border = color(0x262A35)
let text = color(0xF3F4F7), text2 = color(0xA7ADBA), text3 = color(0x7E8596)
let accent = color(0x3D9BFF), onAccent = color(0x04060A), tile = color(0x3D8FF5)

struct Rect { var x, y, w, h: CGFloat }
struct Layout { let name: String; let studio: Rect; let builtin: Rect; let mirrored: Bool }

// Canvas units are 160 × 100, as on the website.
let studioSize = (w: CGFloat(46), h: CGFloat(25.9)), builtinSize = (w: CGFloat(31), h: CGFloat(20.2))
let layouts = [
    Layout(name: "Studio Display Above", studio: Rect(x: 21, y: 26, w: studioSize.w, h: studioSize.h),
           builtin: Rect(x: 28.5, y: 53.4, w: builtinSize.w, h: builtinSize.h), mirrored: false),
    Layout(name: "Side by Side", studio: Rect(x: 1, y: 40, w: studioSize.w, h: studioSize.h),
           builtin: Rect(x: 48.5, y: 45.7, w: builtinSize.w, h: builtinSize.h), mirrored: false),
    Layout(name: "Mirror for Presenting", studio: Rect(x: 21, y: 38, w: studioSize.w, h: studioSize.h),
           builtin: Rect(x: 24.5, y: 34.5, w: studioSize.w, h: studioSize.h), mirrored: true),
]

func ease(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
func mix(_ a: Rect, _ b: Rect, _ t: CGFloat) -> Rect {
    Rect(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, w: a.w + (b.w - a.w) * t, h: a.h + (b.h - a.h) * t)
}
func onCanvas(_ r: Rect) -> CGRect {
    let sx = canvas.width / 160, sy = canvas.height / 100
    return CGRect(x: canvas.minX + r.x * sx, y: canvas.minY + r.y * sy, width: r.w * sx, height: r.h * sy)
}

func draw(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor, centeredIn rect: CGRect? = nil) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    if let rect {
        let measured = attributed.size()
        attributed.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: point.y))
    } else {
        attributed.draw(at: point)
    }
}

func drawTile(_ rect: CGRect, title: String, detail: String, main: Bool, alpha: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
    tile.withAlphaComponent(alpha).setFill()
    path.fill()
    NSColor.white.withAlphaComponent(0.2 * alpha).setStroke()
    path.lineWidth = 1.5
    path.stroke()
    if main {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.white.withAlphaComponent(0.92 * alpha).setFill()
        CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(8, rect.height * 0.08)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    guard alpha > 0.9 else { return }
    let midY = rect.midY
    draw(title, at: CGPoint(x: 0, y: midY - 20), size: 19, weight: .semibold, color: .white, centeredIn: rect)
    draw(detail, at: CGPoint(x: 0, y: midY + 3), size: 16, weight: .regular, color: NSColor.white.withAlphaComponent(0.85), centeredIn: rect)
}

func frame(from: Int, to: Int, progress: CGFloat, highlighted: Int?, checked: Int) -> CGImage {
    let image = NSImage(size: size, flipped: true) { _ in
        background.setFill()
        CGRect(origin: .zero, size: size).fill()

        // Menu bar strip with the status item.
        color(0xFFFFFF, 0.05).setFill()
        CGRect(x: 0, y: 0, width: size.width, height: barHeight).fill()
        border.setFill()
        CGRect(x: 0, y: barHeight - 1, width: size.width, height: 1).fill()
        draw("Built-in Display + Studio Display", at: CGPoint(x: 22, y: 12), size: 17, weight: .medium, color: text2)
        let status = CGRect(x: size.width - 66, y: 8, width: 44, height: 28)
        color(0xFFFFFF, 0.14).setFill()
        NSBezierPath(roundedRect: status, xRadius: 8, yRadius: 8).fill()
        text.setStroke()
        for r in [CGRect(x: status.minX + 10, y: status.minY + 6, width: 15, height: 10),
                  CGRect(x: status.minX + 19, y: status.minY + 12, width: 15, height: 10)] {
            let p = NSBezierPath(roundedRect: r, xRadius: 2.5, yRadius: 2.5)
            p.lineWidth = 2
            p.stroke()
        }

        // Canvas floor with a dot grid.
        floor.setFill()
        canvas.fill()
        color(0xFFFFFF, 0.06).setFill()
        var gy = canvas.minY + 16
        while gy < canvas.maxY {
            var gx: CGFloat = 16
            while gx < size.width { CGRect(x: gx, y: gy, width: 2, height: 2).fill(); gx += 32 }
            gy += 32
        }

        // Displays.
        let t = ease(progress)
        let a = layouts[from], b = layouts[to]
        let studio = onCanvas(mix(a.studio, b.studio, t))
        let builtin = onCanvas(mix(a.builtin, b.builtin, t))
        let ghost = (a.mirrored ? 1 - t : 0) + (b.mirrored ? t : 0)
        drawTile(builtin, title: "Built-in", detail: "1512 × 982", main: false, alpha: 1 - 0.6 * ghost)
        drawTile(studio, title: "Studio Display", detail: "2560 × 1440", main: true, alpha: 1)

        // Screen Setter's menu.
        let menu = CGRect(x: size.width - 470, y: barHeight + 10, width: 450, height: 304)
        let menuPath = NSBezierPath(roundedRect: menu, xRadius: 16, yRadius: 16)
        color(0x1C1F28, 0.97).setFill()
        menuPath.fill()
        color(0xFFFFFF, 0.1).setStroke()
        menuPath.lineWidth = 1.5
        menuPath.stroke()
        draw("Built-in Display + Studio Display", at: CGPoint(x: menu.minX + 44, y: menu.minY + 14), size: 16, weight: .semibold, color: text3)
        let rows = layouts.map(\.name) + ["", "Undo", "Save Current Arrangement…"]
        var y = menu.minY + 46
        for (index, row) in rows.enumerated() {
            if row.isEmpty {
                color(0xFFFFFF, 0.1).setFill()
                CGRect(x: menu.minX + 14, y: y + 7, width: menu.width - 28, height: 1.5).fill()
                y += 16
                continue
            }
            let rowRect = CGRect(x: menu.minX + 8, y: y, width: menu.width - 16, height: 44)
            let isHighlighted = index == highlighted
            if isHighlighted {
                accent.setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 9, yRadius: 9).fill()
            }
            let isLayout = index < layouts.count
            let ink = isHighlighted ? onAccent : (isLayout ? text : text2)
            if index == checked { draw("✓", at: CGPoint(x: rowRect.minX + 12, y: y + 11), size: 18, weight: .bold, color: ink) }
            draw(row, at: CGPoint(x: rowRect.minX + 36, y: y + 11), size: 19, weight: .regular, color: ink)
            let key = isLayout ? "⌘\(index + 1)" : (row == "Undo" ? "⌘Z" : "")
            if !key.isEmpty {
                let keyColor = isHighlighted ? onAccent : text3
                let measured = NSAttributedString(string: key, attributes: [.font: NSFont.systemFont(ofSize: 17)]).size()
                draw(key, at: CGPoint(x: rowRect.maxX - 14 - measured.width, y: y + 12), size: 17, weight: .regular, color: keyColor)
            }
            y += 44
        }
        return true
    }
    var rect = CGRect(origin: .zero, size: size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

// Timeline per step: hold, highlight the next row, then glide.
var frames: [(CGImage, Double)] = []
for step in 0..<layouts.count {
    let from = step, to = (step + 1) % layouts.count
    frames.append((frame(from: from, to: from, progress: 1, highlighted: nil, checked: from), 1.4))
    frames.append((frame(from: from, to: from, progress: 1, highlighted: to, checked: from), 0.35))
    let glide = Int(0.55 * fps)
    for i in 1...glide {
        frames.append((frame(from: from, to: to, progress: CGFloat(i) / CGFloat(glide), highlighted: nil, checked: to), 1 / fps))
    }
}

guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    fatalError("Could not create \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (image, delay) in frames {
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output.path)") }
print("Wrote \(output.path) (\(frames.count) frames)")
