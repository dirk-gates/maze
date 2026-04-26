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
        HStack(spacing: 16) {
            buttons
            Spacer()
            speedControl.frame(width: 200)
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

        if viewModel.isGenerating || viewModel.isSolving {
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
        }
    }

    private var speedControl: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise")
                .foregroundStyle(.secondary)
            Slider(value: $viewModel.animationSpeed, in: 0...1)
            Image(systemName: "hare")
                .foregroundStyle(.secondary)
        }
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
