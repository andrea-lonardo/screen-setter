import SwiftUI

/// Maps desktop coordinates into the canvas: the arrangement is drawn to scale
/// and centred.
struct CanvasMapping {
    var bounds: CGRect
    var scale: CGFloat
    var offset: CGPoint

    init(bounds: CGRect, size: CGSize, padding: CGFloat, maximumScale: CGFloat = 0.12) {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            self.bounds = .zero
            scale = 0.1
            offset = CGPoint(x: size.width / 2, y: size.height / 2)
            return
        }
        self.bounds = bounds
        scale = max(0.005, min(
            (size.width - padding * 2) / bounds.width,
            (size.height - padding * 2) / bounds.height,
            maximumScale
        ))
        offset = CGPoint(
            x: (size.width - bounds.width * scale) / 2,
            y: (size.height - bounds.height * scale) / 2
        )
    }

    func rect(for frame: CGRect) -> CGRect {
        CGRect(
            x: offset.x + (frame.minX - bounds.minX) * scale,
            y: offset.y + (frame.minY - bounds.minY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
    }
}

/// An editable drawing of the arrangement in the style of System Settings ›
/// Displays. Click selects a display; dragging moves it and snaps it against
/// the others when released. Arrow keys move the selected display.
struct ArrangementCanvas: View {
    @Binding var snapshot: LayoutSnapshot
    @Binding var selectedID: String?
    let model: AppModel

    @State private var draggingID: String?
    @State private var dragTranslation: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    /// The canvas distance within which edges align while dragging.
    private let snapDistance: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let mapping = CanvasMapping(bounds: snapshot.arrangementBounds, size: proxy.size, padding: 30)
            let mainID = snapshot.mainDisplayID
            let selectedSource = selectedID
                .flatMap { snapshot.display(withID: $0) }
                .flatMap { $0.mirrorSourceID }

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(snapshot.unmirroredDisplays, id: \.id) { display in
                    let isDragging = draggingID == display.id
                    let base = mapping.rect(for: snapshot.frame(of: display))
                    let rect = isDragging
                        ? base.offsetBy(dx: dragTranslation.width, dy: dragTranslation.height)
                        : base
                    let mirrors = snapshot.mirrors(of: display.id)

                    DisplayTile(
                        name: model.displayLabel(for: display),
                        detail: display.mode.resolutionLabel,
                        isMain: display.id == mainID,
                        isSelected: selectedID == display.id,
                        isSourceOfSelection: selectedSource == display.id,
                        mirrorCount: mirrors.count
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .zIndex(isDragging ? 1 : 0)
                    .gesture(dragGesture(for: display, mapping: mapping))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(model.displayLabel(for: display))
                    .accessibilityValue(accessibilityValue(for: display, isMain: display.id == mainID, mirrors: mirrors))
                    .accessibilityAddTraits(selectedID == display.id ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selectedID = display.id }
                    .accessibilityAction(named: "Move Left") { nudge(display.id, .left) }
                    .accessibilityAction(named: "Move Right") { nudge(display.id, .right) }
                    .accessibilityAction(named: "Move Up") { nudge(display.id, .up) }
                    .accessibilityAction(named: "Move Down") { nudge(display.id, .down) }
                }
            }
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            guard let id = selectedMovableID else { return }
            switch direction {
            case .left: nudge(id, .left)
            case .right: nudge(id, .right)
            case .up: nudge(id, .up)
            case .down: nudge(id, .down)
            @unknown default: break
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Arrangement")
    }

    /// The selected display, or its source when a mirrored display is selected.
    private var selectedMovableID: String? {
        guard let selectedID, let display = snapshot.display(withID: selectedID) else { return nil }
        return display.mirrorSourceID ?? display.id
    }

    private func dragGesture(for display: DisplaySpec, mapping: CanvasMapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggingID != display.id {
                    draggingID = display.id
                    selectedID = display.id
                    isFocused = true
                }
                dragTranslation = value.translation
            }
            .onEnded { value in
                let moved = abs(value.translation.width) > 2 || abs(value.translation.height) > 2
                let frame = snapshot.frame(of: display)
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    if moved {
                        snapshot.moveDisplay(
                            display.id,
                            to: CGPoint(
                                x: frame.minX + value.translation.width / mapping.scale,
                                y: frame.minY + value.translation.height / mapping.scale
                            ),
                            snapThreshold: snapDistance / mapping.scale
                        )
                    }
                    draggingID = nil
                    dragTranslation = .zero
                }
            }
    }

    private func nudge(_ id: String, _ direction: LayoutSnapshot.NudgeDirection) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            if !snapshot.nudgeDisplay(id, direction) { NSSound.beep() }
        }
    }

    private func accessibilityValue(for display: DisplaySpec, isMain: Bool, mirrors: [DisplaySpec]) -> String {
        var parts = [display.mode.menuLabel]
        if isMain { parts.append("Main display") }
        if !mirrors.isEmpty {
            parts.append("Mirrored by " + mirrors.map { model.displayLabel(for: $0) }.formatted(.list(type: .and)))
        }
        return parts.joined(separator: ", ")
    }
}

/// One display on the canvas.
struct DisplayTile: View {
    let name: String
    let detail: String
    let isMain: Bool
    let isSelected: Bool
    /// True when a display mirroring this one is selected in the inspector.
    let isSourceOfSelection: Bool
    let mirrorCount: Int

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(8, max(3, min(size.width, size.height) * 0.06))
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let compact = size.height < 46 || size.width < 70
            let increasedContrast = contrast == .increased

            ZStack {
                if mirrorCount > 0 {
                    // A second sheet behind the display shows it is mirrored.
                    shape
                        .fill(reduceTransparency
                            ? Color.accentColor.mix(with: .gray, by: 0.55)
                            : Color.accentColor.opacity(0.35))
                        .overlay(shape.strokeBorder(.white.opacity(increasedContrast ? 0.8 : 0.35), lineWidth: 1))
                        .offset(x: 6, y: -6)
                }
                shape
                    .fill(Color.accentColor.gradient)
                    .overlay(shape.fill(.black.opacity(isSelected ? 0 : 0.18)))
                    .overlay(alignment: .top) {
                        if isMain {
                            Rectangle()
                                .fill(.white.opacity(0.92))
                                .frame(height: max(3, min(7, size.height * 0.07)))
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(
                        increasedContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.white.opacity(0.25)),
                        lineWidth: increasedContrast ? 1.5 : 1
                    ))

                VStack(spacing: 1) {
                    Text(name)
                        .font(compact ? .caption2.weight(.semibold) : .callout.weight(.semibold))
                    if !compact {
                        Text(detail)
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .padding(.top, isMain ? 4 : 0)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)

                if mirrorCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "rectangle.on.rectangle")
                        if mirrorCount > 1 { Text("\(mirrorCount)") }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(increasedContrast || reduceTransparency ? 0.6 : 0.28), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
                    .help("Mirrored")
                }
            }
            .overlay {
                if isSelected || isSourceOfSelection {
                    RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                        .inset(by: -3)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 2.5, dash: isSourceOfSelection && !isSelected ? [5, 3] : [])
                        )
                }
            }
        }
    }
}
