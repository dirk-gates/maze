// Theme -- runtime visual theme. For Phase 3a we ship a single
// "Classic" theme that adapts to the system's light/dark color
// scheme. Phase 3b will introduce additional themes (Blueprint,
// Glow, Hedge); their values plug into the same `Theme` struct.

import SwiftUI

struct Theme: Sendable {
    var background : Color
    /// "Top" of the hedge wall -- the lit color the camera sees.
    var material   : Color
    /// "Shaded side" of the hedge -- a darker variant drawn offset
    /// down-right of the top to fake an extruded 3D wall in 2D.
    var wallShadow : Color
    var carved     : Color
    var solution   : Color

    static func classic(_ scheme: ColorScheme) -> Theme {
        // Walls = hedge green; wallShadow = a noticeably darker
        // green drawn shifted down-right to suggest the hedge has
        // height. Tuned per scheme so the shadow is visible against
        // both the white and black floor.
        switch scheme {
        case .dark:
            return Theme(
                background : .black,
                material   : Color(red: 0.30, green: 0.60, blue: 0.25),
                wallShadow : Color(red: 0.10, green: 0.25, blue: 0.08),
                carved     : .black,
                solution   : Color(red: 0.30, green: 0.75, blue: 1.00))
        default:
            return Theme(
                background : .white,
                material   : Color(red: 0.18, green: 0.45, blue: 0.18),
                wallShadow : Color(red: 0.07, green: 0.20, blue: 0.07),
                carved     : .white,
                solution   : Color(red: 0.00, green: 0.45, blue: 0.95))
        }
    }
}
