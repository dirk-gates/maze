// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.
//
// Auto-fit policy: we hand the current canvas size and per-platform
// target unit pixel size to the view model. The view model uses
// these to refit width/height ONLY when a new generation is kicked
// off (initial launch, Generate button, ⌘N). Orientation flips and
// other geometry changes update the cached size but leave the
// existing maze and dimensions alone -- the user said rotation
// shouldn't auto-regenerate.
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
                    .onAppear {
                        viewModel.targetUnitPx = targetUnitPixels()
                        viewModel.canvasSize   = geo.size
                        if !didInitialLaunch {
                            didInitialLaunch = true
                            viewModel.generate()
                        }
                    }
                    .onChange(of: geo.size) { _, new in
                        // Cache the new size so the next user-driven
                        // generation fits the current orientation, but
                        // do NOT regenerate -- rotation shouldn't kick
                        // off a new maze.
                        viewModel.canvasSize = new
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            ControlsView(viewModel: viewModel, showingSettings: $showingSettings)
        }
        .background(theme.background)
        // NOTE: do not ignore horizontal safe area on iOS -- in
        // landscape the iPhone Dynamic Island sits inside the
        // horizontal safe area inset, and ignoring it would let the
        // maze render underneath the island. The default behavior
        // (respect safe area) leaves a small inset around the island
        // and the rounded display corners, which is what we want.
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
