import SwiftUI

/// Single source of truth for every colour, radius and duration in the app.
/// Nothing else in the codebase is allowed to hardcode a colour value.
enum Palette {
    // MARK: Backdrop ramp
    //
    // Three stops with the middle one pulled early, rather than the two-stop
    // ramp every design tool emits by default. The scrim below is what keeps
    // text legible over it.

    static func backdrop(_ scheme: ColorScheme) -> [Gradient.Stop] {
        scheme == .light
            ? [
                .init(color: Color(hex: 0x6EA8E8), location: 0.00),
                .init(color: Color(hex: 0xAFCEF0), location: 0.48),
                .init(color: Color(hex: 0xE4EEF9), location: 0.72),
                .init(color: Color(hex: 0xF2F6FB), location: 1.00),
            ]
            : [
                .init(color: Color(hex: 0x1F6FD0), location: 0.00),
                .init(color: Color(hex: 0x0A3A7A), location: 0.48),
                .init(color: Color(hex: 0x05172F), location: 0.72),
                .init(color: Color(hex: 0x02080F), location: 1.00),
            ]
    }

    /// Transparent across the top half so it does not seam with the ramp, and
    /// only closes past ~82%.
    static func scrim(_ scheme: ColorScheme) -> [Gradient.Stop] {
        let veil = scheme == .light ? Color.white : Color.black
        return [
            .init(color: veil.opacity(0.0), location: 0.00),
            .init(color: veil.opacity(0.0), location: 0.50),
            .init(color: veil.opacity(scheme == .light ? 0.10 : 0.22), location: 0.82),
            .init(color: veil.opacity(scheme == .light ? 0.22 : 0.55), location: 1.00),
        ]
    }

    // MARK: Accent — exactly one

    static func accent(_ scheme: ColorScheme) -> Color {
        // Measured against the ramp: the dark value fails AA over the light
        // backdrop, so the light theme steps down rather than reusing it.
        scheme == .light ? Color(hex: 0x0B4F86) : Color(hex: 0x6CC6FF)
    }

    // MARK: Text

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x0A1A2B) : .white
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x0A1A2B).opacity(0.62) : Color.white.opacity(0.64)
    }

    static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(hex: 0x0A1A2B).opacity(0.42) : Color.white.opacity(0.40)
    }

    // MARK: Surfaces

    /// Hairline that separates a surface from the backdrop. Never a drop shadow.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.10) : Color.white.opacity(0.10)
    }

    /// Fallback surface for builds without Liquid Glass.
    static func glassFallback(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.66) : Color(hex: 0x0B1B33).opacity(0.58)
    }

    // MARK: State lexicon — semantic, never decorative

    static let ok = Color(hex: 0x34D17F)
    static let warning = Color(hex: 0xE8B23A)
    static let danger = Color(hex: 0xFF5C5C)

    // MARK: Geometry

    enum Radius {
        static let pill: CGFloat = 999
        static let card: CGFloat = 22
        static let control: CGFloat = 16
    }

    enum Size {
        static let touch: CGFloat = 44
        static let blockControl: CGFloat = 52
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
