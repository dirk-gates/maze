// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.
//
// Cell counts (width / height) auto-fit the actual canvas geometry on
// every appearance and orientation change, so the maze fills the
// screen on both iPhone and iPad in either orientation. Manual
// settings overrides are still respected for one generation, but the
// next orientation change re-fits.
//
// The view model is owned by MazeApp and injected here so the App
// scene can apply `.preferredColorScheme(viewModel.schemeOverride)`
// at WindowGroup scope -- which is what makes the appearance picker
// reach sheets and reliably revert to the system scheme.

import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: MazeViewModel
    @State private var showingSettings  = false
    @State private var didInitialLaunch = false
    @Environment(\.colorScheme) private var systemScheme

    private var theme: Theme {
        Theme.classic(systemScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                MazeCanvasView(viewModel: viewModel, theme: theme)
                    .onAppear { fitMaze(to: geo.size, regenerate: !didInitialLaunch) }
                    .onChange(of: geo.size) { _, new in fitMaze(to: new, regenerate: true) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel, showingSettings: $showingSettings)
        }
        .background(theme.background)
        #if os(iOS)
        .ignoresSafeArea(.container, edges: .horizontal)
        #endif
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .mazeGenerate)) { _ in
            viewModel.generate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mazeSolve)) { _ in
            viewModel.solve()
        }
        #endif
    }

    /// Compute the largest (cells_wide, cells_tall) pair whose rendered
    /// maze fully fills `size` at the per-platform target unit pixel
    /// size, then update the view model and (optionally) regenerate.
    /// Skips the regenerate if the cell counts haven't changed -- avoids
    /// spurious regens on no-op layout passes.
    private func fitMaze(to size: CGSize, regenerate: Bool) {
        guard size.width > 0, size.height > 0 else { return }

        let targetUnit = targetUnitPixels()
        // Maze grid in "units": w cells take 3*w cell-units + (w+1) wall-units = 4w+1.
        // Solving 4w + 1 ≤ size.width / targetUnit → w = floor((size.width / targetUnit - 1) / 4)
        let w = max(4, Int((size.width  / targetUnit - 1) / 4))
        let h = max(4, Int((size.height / targetUnit - 1) / 4))

        let changed = (w != viewModel.width) || (h != viewModel.height)
        viewModel.width  = w
        viewModel.height = h

        if regenerate && changed {
            viewModel.generate()
        }
        didInitialLaunch = true
    }

    /// Target pixel size for one "unit" (= one wall thickness). Cell
    /// edge is 3x this. Larger value → fewer, chunkier cells; smaller
    /// → finer maze. Tuned so phone cells stay finger-sized and iPad
    /// cells stay readable from arm's length.
    private func targetUnitPixels() -> CGFloat {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? 9 : 6
        #else
        return 8
        #endif
    }
}
