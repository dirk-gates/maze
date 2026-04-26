// ControlsView -- bottom-of-window controls: Generate, Solve,
// settings, speed. Adaptive layout: single row on macOS / iPad;
// two rows on narrow iPhone widths so the slider doesn't crowd
// out the buttons.

import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: MazeViewModel
    @Binding var showingSettings: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow
            twoRows
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // ----- layouts -----

    private var singleRow: some View {
        // Slider gets all the slack the row can spare (between the
        // buttons on the left and stats/settings on the right) so it
        // stretches across iPhone landscape and iPad widths instead
        // of pinning to a stubby 200pt.
        HStack(spacing: 16) {
            buttons
            speedControl.frame(minWidth: 200, maxWidth: .infinity)
            stats
            settingsButton
        }
    }

    private var twoRows: some View {
        VStack(spacing: 10) {
            HStack {
                buttons
                Spacer()
                stats
                settingsButton
            }
            speedControl
        }
    }

    // ----- pieces -----

    @ViewBuilder
    private var buttons: some View {
        Button {
            viewModel.generate()
        } label: {
            Label("Generate", systemImage: "arrow.clockwise")
                .frame(minWidth: 110)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isGenerating)

        Button {
            viewModel.solve()
        } label: {
            Label("Solve", systemImage: "scope")
                .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.maze == nil || viewModel.isGenerating || viewModel.isSolving)
    }

    private var speedControl: some View {
        HStack(spacing: 8) {
            Button { nudgeSpeed(by: -speedStep) } label: {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Slower")

            Slider(value: $viewModel.animationSpeed, in: 0...1)

            Button { nudgeSpeed(by: speedStep) } label: {
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Faster")
        }
    }

    // 5% per tap -> 20 taps to traverse, ~13% perceptual speed change
    // per tap given the log curve in the view model.
    private let speedStep = 0.05

    private func nudgeSpeed(by delta: Double) {
        viewModel.animationSpeed = min(1.0, max(0.0, viewModel.animationSpeed + delta))
    }

    @ViewBuilder
    private var stats: some View {
        if !viewModel.statsLine.isEmpty {
            Text(viewModel.statsLine)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var settingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Settings")
    }
}
