import SwiftUI

/// One physics for the whole app. Never `.linear`, never plain `.easeInOut`.
enum Motion {
    static let standard = UnitCurve.bezier(
        startControlPoint: .init(x: 0.2, y: 0.8),
        endControlPoint: .init(x: 0.2, y: 1)
    )

    static let inOut = UnitCurve.bezier(
        startControlPoint: .init(x: 0.6, y: 0),
        endControlPoint: .init(x: 0.35, y: 1)
    )

    /// Touch response — overshoots slightly on the way back.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.62)

    static let tap = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.15)
    static let item = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)
    static let panel = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    static let screen = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.40)

    /// Scale applied while a control is held.
    static let pressScale: CGFloat = 0.975
}
