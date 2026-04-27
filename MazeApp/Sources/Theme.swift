// Theme -- runtime visual theme. For Phase 3a we ship a single
// "Classic" theme that adapts to the system's light/dark color
// scheme. Phase 3b will introduce additional themes (Blueprint,
// Glow, Hedge); their values plug into the same `Theme` struct.

import SwiftUI

struct Theme: Sendable {
    /// Color filling the area outside the maze (and visually merging
    /// with carved cells, since they're the same color).
    var background : Color

    /// Color of unrebreached "material" the maze is carved from. In
    /// dark mode this is white (creating a chalkboard effect); in
    /// light mode this is black (creating a printed-on-paper look).
    var material   : Color

    /// Color of carved cells and opened wall slots. Equal to
    /// `background` so the "carved" feels like an absence of material.
    var carved     : Color

    /// Color of the solution path stroke.
    var solution   : Color

    static func classic(_ scheme: ColorScheme) -> Theme {
        // Solution = blue, matching the 3D walk-view's cyan trail
        // so the same color reads as "the path" in both views.
        // Saturation tuned per scheme so it pops without buzzing.
        switch scheme {
        case .dark:
            return Theme(
                background : .black,
                material   : .white,
                carved     : .black,
                solution   : Color(red: 0.30, green: 0.75, blue: 1.00))
        default:
            return Theme(
                background : .white,
                material   : .black,
                carved     : .white,
                solution   : Color(red: 0.00, green: 0.45, blue: 0.95))
        }
    }
}
