import SwiftUI

/// Primary action. Liquid Glass where the OS has it, and a genuinely solid
/// control where it does not — never a blurred imitation of glass, which reads
/// worse than an honest solid.
struct GlassButton: View {
    let title: String
    var prominent: Bool = true
    var enabled: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(label)
                .frame(maxWidth: .infinity)
                .frame(height: Palette.Size.blockControl)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .background { surface }
        .clipShape(.capsule)
        .overlay {
            Capsule().strokeBorder(Palette.hairline(scheme), lineWidth: 1)
        }
        .opacity(enabled ? 1 : 0.42)
        .scaleEffect(pressed ? Motion.pressScale : 1)
        .animation(Motion.spring, value: pressed)
        .onLongPressGesture(
            minimumDuration: 0,
            pressing: { pressed = $0 && enabled },
            perform: {}
        )
    }

    @ViewBuilder
    private var surface: some View {
        if #available(macOS 26.0, *) {
            // The prominent action is the one place a full brand colour is
            // allowed to sit on the glass. Everything else tints with a low
            // alpha of white, or the material turns opaque and the label dies.
            Capsule()
                .fill(.clear)
                .glassEffect(
                    .regular
                        .tint(prominent ? Palette.accent(scheme).opacity(0.72)
                                        : Color.white.opacity(0.18))
                        .interactive(),
                    in: .capsule
                )
        } else {
            Capsule()
                .fill(prominent ? Palette.accent(scheme) : Palette.glassFallback(scheme))
        }
    }

    private var label: Color {
        guard prominent else { return Palette.primaryText(scheme) }
        // Solid light-theme accent needs white on it; the dark accent is a
        // bright cyan and needs dark type instead.
        return scheme == .light ? .white : Color(hex: 0x04121F)
    }
}
