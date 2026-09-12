import SwiftUI

/// The app's one signature: the four symbols drawn as a single seal, and a
/// ring of light that closes around them while work is in flight.
///
/// The same four shapes that drift through the backdrop lock into one mark
/// here — which is the idea of the product: a small mark written onto a drive
/// is what gets it through the door.
struct SigilMark: View {
    var active: Bool = false
    var size: CGFloat = 84

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    var body: some View {
        ZStack {
            SealShape()
                .stroke(
                    Palette.primaryText(scheme).opacity(0.92),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                )

            Circle()
                .strokeBorder(
                    Palette.primaryText(scheme).opacity(0.18),
                    lineWidth: 1.4
                )

            if active {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(
                        Palette.accent(scheme),
                        style: StrokeStyle(lineWidth: 2.6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 0.4)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: active) { _, isActive in
            guard isActive, !reduceMotion else {
                sweep = 0
                return
            }
            sweep = 0
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// Triangle up, circle right, cross down, square left — arranged on a ring.
private struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let orbit = min(rect.width, rect.height) * 0.28
        let glyph = min(rect.width, rect.height) * 0.24

        var path = Path()

        func box(at angle: Double) -> CGRect {
            let radians = angle * .pi / 180
            let point = CGPoint(
                x: centre.x + CGFloat(cos(radians)) * orbit,
                y: centre.y + CGFloat(sin(radians)) * orbit
            )
            return CGRect(
                x: point.x - glyph / 2,
                y: point.y - glyph / 2,
                width: glyph,
                height: glyph
            )
        }

        // Triangle, top.
        let triangle = box(at: -90)
        path.move(to: CGPoint(x: triangle.midX, y: triangle.minY))
        path.addLine(to: CGPoint(x: triangle.maxX, y: triangle.maxY))
        path.addLine(to: CGPoint(x: triangle.minX, y: triangle.maxY))
        path.closeSubpath()

        // Circle, right.
        path.addEllipse(in: box(at: 0).insetBy(dx: glyph * 0.06, dy: glyph * 0.06))

        // Cross, bottom.
        let cross = box(at: 90).insetBy(dx: glyph * 0.12, dy: glyph * 0.12)
        path.move(to: CGPoint(x: cross.minX, y: cross.minY))
        path.addLine(to: CGPoint(x: cross.maxX, y: cross.maxY))
        path.move(to: CGPoint(x: cross.maxX, y: cross.minY))
        path.addLine(to: CGPoint(x: cross.minX, y: cross.maxY))

        // Square, left.
        path.addRoundedRect(
            in: box(at: 180).insetBy(dx: glyph * 0.10, dy: glyph * 0.10),
            cornerSize: CGSize(width: glyph * 0.08, height: glyph * 0.08)
        )

        return path
    }
}
