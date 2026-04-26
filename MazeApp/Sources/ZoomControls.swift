// ZoomControls -- compact +/- pair overlaid on the maze canvas.
// Tapping changes the per-platform target unit pixels (cell size at
// fit-to-canvas) and regenerates so the new cell size takes effect
// immediately while the maze keeps filling the screen.

import SwiftUI

struct ZoomControls: View {
    @Bindable var viewModel: MazeViewModel

    /// Each tap multiplies the unit size by this factor (or 1/this).
    /// 1.2 = ~20% per tap, ~3 taps to roughly halve/double cell count.
    private let stepFactor = 1.2

    var body: some View {
        VStack(spacing: 1) {
            Button { viewModel.zoom(by: stepFactor) } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom in")

            Divider().frame(width: 24)

            Button { viewModel.zoom(by: 1.0 / stepFactor) } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Zoom out")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 0.5)
        )
        .disabled(viewModel.isGenerating)
    }
}
