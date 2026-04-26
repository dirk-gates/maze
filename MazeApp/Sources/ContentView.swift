// ContentView -- top-level layout. Maze fills the bulk of the window;
// a Controls bar pinned to the bottom holds Generate / Solve / Settings.
//
// The view model is owned by MazeApp and injected here so the App
// scene itself can apply `.preferredColorScheme(viewModel.schemeOverride)`
// at the WindowGroup level. That's what makes the appearance picker
// reliably revert sheets and chrome back to the system scheme when
// the user picks "System" -- the modifier covers everything in the
// scene including sheet hierarchies, which a modifier applied
// further down inside the view tree does not.

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
            MazeCanvasView(viewModel: viewModel, theme: theme)
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
        .onAppear {
            // Gate to the first-ever appearance. On iOS, dismissing
            // the Settings sheet re-fires .onAppear on the host view,
            // and we don't want that to auto-regenerate -- the user
            // should have to press Generate explicitly.
            guard !didInitialLaunch else { return }
            didInitialLaunch = true
            applyPlatformDefaults()
            viewModel.generate()
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

    private func applyPlatformDefaults() {
        #if os(iOS)
        // iPad gets a denser default so the maze fills its larger
        // canvas; iPhone stays at portrait-friendly 20x30.
        if UIDevice.current.userInterfaceIdiom == .pad {
            viewModel.width  = 30
            viewModel.height = 40
        } else {
            viewModel.width  = 20
            viewModel.height = 30
        }
        #endif
    }
}
