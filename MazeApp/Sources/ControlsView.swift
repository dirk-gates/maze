// ControlsView -- bottom-of-window controls: Generate, Solve,
// settings, speed. Adaptive layout: single row on macOS / iPad;
// two rows on narrow iPhone widths so the slider doesn't crowd
// out the buttons.

import MazeKit
import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: MazeViewModel
    @Binding var showingSettings: Bool
    @Binding var showingLibrary : Bool
    @Binding var showing3D      : Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            singleRow
            twoRows
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Thick material gives the bar enough opacity that the
        // standard button styles read with proper contrast against
        // it -- regular material was making bordered buttons feel
        // washed out without needing any per-button decoration.
        .background(.thickMaterial)
    }

    // ----- layouts -----

    private var singleRow: some View {
        // Slider gets all the slack the row can spare (between the
        // buttons on the left and stats/settings on the right) so it
        // stretches across iPhone landscape and iPad widths instead
        // of pinning to a stubby 200pt.
        HStack(spacing: 12) {
            buttons
            speedControl.frame(minWidth: 200, maxWidth: .infinity)
            stats
            zoomControls
            iconColumn
        }
    }

    private var twoRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                buttons
                Spacer()
                stats
                iconColumn
            }
            // Density on the same row as the slider so each control
            // has a proper hit target. Putting density on the action
            // row was cramming everything into a strip that was hard
            // to tap.
            HStack(spacing: 8) {
                fewerCellsButton
                speedControl
                moreCellsButton
            }
        }
    }

    /// Walk / Share / History / Settings packed tight. The buttons
    /// still own their 44pt hit targets internally; the small
    /// outer spacing just keeps the whole strip from eating the
    /// row on iPhone widths.
    @ViewBuilder
    private var iconColumn: some View {
        HStack(spacing: 0) {
            walkButton
            shareButton
            libraryButton
            settingsButton
        }
    }

    // ----- pieces -----

    @ViewBuilder
    private var buttons: some View {
        // No explicit minWidth -- the Label sizes to its content
        // (~85 / ~65 pt) so the action row keeps headroom for the
        // icon column on the right.
        Button {
            viewModel.generate()
        } label: {
            Label("Generate", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isGenerating)

        Button {
            viewModel.solve()
        } label: {
            Label("Solve", systemImage: "scope")
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

    /// Each density tap multiplies targetUnitPx by this factor (or
    /// 1/this). 1.2 = ~20% per tap, ~3 taps to roughly halve/double
    /// cell count. + makes cells smaller (more rows/columns); - makes
    /// them bigger (fewer rows/columns).
    private let zoomStep = 1.2

    /// 44pt minimum hit target -- Apple HIG.
    private let tapTarget: CGFloat = 44

    @ViewBuilder
    private var zoomControls: some View {
        HStack(spacing: 8) {
            fewerCellsButton
            moreCellsButton
        }
    }

    /// "−" : fewer rows/columns (cells get bigger, fitting fewer).
    /// Stays active during generation -- a tap cancels the in-flight
    /// run and restarts at the new density.
    private var fewerCellsButton: some View {
        Button { viewModel.zoom(by: zoomStep) } label: {
            Image(systemName: "minus")
                .frame(width: tapTarget, height: tapTarget)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Fewer rows and columns")
    }

    /// "+" : more rows/columns (cells get smaller, fitting more).
    /// Stays active during generation -- see fewerCellsButton.
    private var moreCellsButton: some View {
        Button { viewModel.zoom(by: 1.0 / zoomStep) } label: {
            Image(systemName: "plus")
                .frame(width: tapTarget, height: tapTarget)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .accessibilityLabel("More rows and columns")
    }

    /// Build a maze:// share URL for whatever is currently on
    /// screen. Returns nil before the first generation lands -- the
    /// share button hides itself in that case.
    private var currentShareURL: URL? {
        guard viewModel.maze != nil else { return nil }
        let snapshot = SavedMaze(
            seed          : viewModel.currentSeed,
            width         : viewModel.width,
            height        : viewModel.height,
            lookAheadDepth: viewModel.lookAheadDepth
        )
        return snapshot.shareURL()
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = currentShareURL {
            ShareLink(item: url,
                      preview: SharePreview("Maze \(viewModel.width)×\(viewModel.height)")) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .frame(width: tapTarget, height: tapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share this maze")
        }
    }

    @ViewBuilder
    private var walkButton: some View {
        // Hide until the first generation lands -- there's nothing
        // to walk through before then.
        if viewModel.maze != nil {
            Button {
                showing3D = true
            } label: {
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .frame(width: tapTarget, height: tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Walk the maze in 3D")
        }
    }

    private var libraryButton: some View {
        Button {
            showingLibrary = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .frame(width: tapTarget, height: tapTarget)
                .contentShape(Rectangle())
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
                .frame(width: tapTarget, height: tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Settings")
    }
}

