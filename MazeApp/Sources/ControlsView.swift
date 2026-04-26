// ControlsView -- bottom-of-window controls: Generate, Solve, speed.

import SwiftUI

struct ControlsView: View {
    @Bindable var viewModel: MazeViewModel

    var body: some View {
        HStack(spacing: 16) {
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

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "tortoise")
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.animationSpeed, in: 0...1)
                    .frame(width: 200)
                Image(systemName: "hare")
                    .foregroundStyle(.secondary)
            }

            if !viewModel.statsLine.isEmpty {
                Text(viewModel.statsLine)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}
