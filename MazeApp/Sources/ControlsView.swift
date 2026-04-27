// ControlsView -- bottom-of-window controls: Generate, Solve,
// settings, speed. Adaptive layout: single row on macOS / iPad;
// two rows on narrow iPhone widths so the slider doesn't crowd
// out the buttons.

import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: MazeViewModel
    @Binding var showingSettings: Bool
    @Binding var showingLibrary : Bool

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
            zoomControls
            libraryButton
            settingsButton
        }
    }

    private var twoRows: some View {
        VStack(spacing: 10) {
            HStack {
                buttons
                Spacer()
                stats
                zoomControls
                libraryButton
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

    // 2.5% per tap -> ~40 taps to traverse. Finer than the 5% step
    // so the transition between "very fast" and "instant" near the
    // top of the slider takes several taps instead of jumping.
    private let speedStep = 0.025

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

    /// Each zoom tap multiplies targetUnitPx by this factor (or 1/this).
    /// 1.2 = ~20% per tap, ~3 taps to roughly halve/double cell count.
    private let zoomStep = 1.2

    @ViewBuilder
    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { viewModel.zoom(by: 1.0 / zoomStep) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zoom out")

            Button { viewModel.zoom(by: zoomStep) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zoom in")
        }
        .disabled(viewModel.isGenerating)
    }

    private var libraryButton: some View {
        Button {
            showingLibrary = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("History")
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
