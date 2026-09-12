import SwiftUI

/// The backdrop: a three-stop ramp, two faint light sources for the glass to
/// refract, a field of falling symbols, and a scrim that only closes at the
/// bottom.
///
/// The symbols are drawn here as plain geometry rather than copied from an
/// asset file. Visually it is the same motif; legally it keeps a public
/// repository free of artwork whose licence we cannot vouch for.
struct GradientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(
                stops: Palette.backdrop(scheme),
                startPoint: .top,
                endPoint: .bottom
            )

            // Two very faint light sources in different hues — this is what
            // the glass has to refract. Without them it sits on a flat fill
            // and reads as a frosted rectangle.
            RadialGradient(
                colors: [Palette.accent(scheme).opacity(scheme == .light ? 0.16 : 0.26), .clear],
                center: .init(x: 0.5, y: 0.02),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color(hex: 0x5A31C8).opacity(scheme == .light ? 0.08 : 0.20), .clear],
                center: .init(x: 0.82, y: 1.0),
                startRadius: 0,
                endRadius: 460
            )

            FallingSymbols(reduceMotion: reduceMotion)
                .blendMode(scheme == .light ? .multiply : .screen)
                .opacity(scheme == .light ? 0.12 : 0.22)

            LinearGradient(
                stops: Palette.scrim(scheme),
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Falling field

private struct FallingSymbols: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                for symbol in Symbol.field {
                    symbol.draw(in: &canvas, bounds: size, time: reduceMotion ? 0 : time)
                }
            }
        }
    }
}

private struct Symbol {
    enum Kind: CaseIterable {
        case triangle
        case circle
        case cross
        case square
    }

    let kind: Kind
    let column: CGFloat     // Horizontal position, as a fraction of the width.
    let extent: CGFloat     // Size, as a fraction of the smaller edge.
    let fallSeconds: Double // Time to cross the screen once.
    let phase: Double       // Where in that cycle it starts.
    let spinSeconds: Double // Time for a full turn. Negative spins the other way.
    let weight: CGFloat
    let alpha: CGFloat

    func draw(in canvas: inout GraphicsContext, bounds: CGSize, time: TimeInterval) {
        let unit = min(bounds.width, bounds.height)
        let side = extent * unit

        // Travel from just above the top edge to just past the bottom, then
        // wrap. Adding the phase inside the modulo is what keeps the loop
        // seamless instead of snapping when the cycle restarts.
        let progress = ((time / fallSeconds) + phase).truncatingRemainder(dividingBy: 1)
        let y = -0.12 * bounds.height + CGFloat(progress) * (bounds.height * 1.24)
        let x = column * bounds.width

        // A slow sway, so the field does not read as a rigid grid falling.
        let sway = CGFloat(sin(progress * .pi * 2 + phase * 6)) * side * 0.35

        let angle = Angle.radians(time * (.pi * 2 / spinSeconds) + phase * 4)

        canvas.drawLayer { layer in
            layer.translateBy(x: x + sway, y: y)
            layer.rotate(by: angle)
            layer.opacity = alpha

            let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
            let stroke = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(.white)

            layer.stroke(path(in: rect), with: ink, style: stroke)
        }
    }

    private func path(in rect: CGRect) -> Path {
        switch kind {
        case .triangle:
            var path = Path()
            // Slightly short of the corners so the round joins sit inside the
            // same optical box as the other three.
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.06))
            path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.maxY - rect.height * 0.10))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.maxY - rect.height * 0.10))
            path.closeSubpath()
            return path

        case .circle:
            return Path(ellipseIn: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06))

        case .cross:
            let inset = rect.width * 0.14
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            path.move(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
            return path

        case .square:
            let inset = rect.width * 0.10
            return Path(
                roundedRect: rect.insetBy(dx: inset, dy: inset),
                cornerRadius: rect.width * 0.06
            )
        }
    }

    /// Hand-placed rather than random. Two things a random field gets wrong:
    /// it clumps, and it wanders into the centre column where the copy and the
    /// buttons live. Columns here stay outside 0.18–0.82, and the few that come
    /// closer are the smallest and faintest of the set.
    static let field: [Symbol] = [
        Symbol(kind: .triangle, column: 0.06, extent: 0.085, fallSeconds: 38, phase: 0.00, spinSeconds: 46, weight: 2.0, alpha: 0.85),
        Symbol(kind: .circle,   column: 0.13, extent: 0.130, fallSeconds: 52, phase: 0.42, spinSeconds: -70, weight: 1.7, alpha: 0.65),
        Symbol(kind: .cross,    column: 0.02, extent: 0.070, fallSeconds: 44, phase: 0.71, spinSeconds: 38, weight: 2.2, alpha: 0.75),
        Symbol(kind: .square,   column: 0.17, extent: 0.055, fallSeconds: 33, phase: 0.18, spinSeconds: -52, weight: 1.8, alpha: 0.55),

        Symbol(kind: .square,   column: 0.94, extent: 0.100, fallSeconds: 48, phase: 0.11, spinSeconds: 60, weight: 1.9, alpha: 0.80),
        Symbol(kind: .cross,    column: 0.87, extent: 0.075, fallSeconds: 36, phase: 0.55, spinSeconds: -42, weight: 2.1, alpha: 0.70),
        Symbol(kind: .triangle, column: 0.98, extent: 0.060, fallSeconds: 41, phase: 0.86, spinSeconds: 55, weight: 1.8, alpha: 0.60),
        Symbol(kind: .circle,   column: 0.83, extent: 0.150, fallSeconds: 58, phase: 0.30, spinSeconds: -80, weight: 1.6, alpha: 0.50),

        // The far background: small, slow and faint enough to pass behind the
        // centre column without fighting the text.
        Symbol(kind: .triangle, column: 0.34, extent: 0.032, fallSeconds: 66, phase: 0.63, spinSeconds: 90, weight: 1.2, alpha: 0.30),
        Symbol(kind: .circle,   column: 0.66, extent: 0.028, fallSeconds: 74, phase: 0.24, spinSeconds: -96, weight: 1.2, alpha: 0.26),
        Symbol(kind: .cross,    column: 0.50, extent: 0.030, fallSeconds: 62, phase: 0.91, spinSeconds: 84, weight: 1.2, alpha: 0.24),
        Symbol(kind: .square,   column: 0.26, extent: 0.026, fallSeconds: 70, phase: 0.07, spinSeconds: -88, weight: 1.2, alpha: 0.28),
        Symbol(kind: .triangle, column: 0.74, extent: 0.024, fallSeconds: 80, phase: 0.48, spinSeconds: 100, weight: 1.1, alpha: 0.22),
    ]
}
